/// FriendState 测试：分页、30s 详情缓存、排序、5s 冷却、偷菜失败/成功后的刷新。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:hyb_farm_desktop/api/api_client.dart';
import 'package:hyb_farm_desktop/api/farm_api.dart';
import 'package:hyb_farm_desktop/api/models.dart';
import 'package:hyb_farm_desktop/core/operation_coordinator.dart';
import 'package:hyb_farm_desktop/state/friend_state.dart';

class _FakeApi extends FarmApi {
  _FakeApi(this.friends) : super(ApiClient());

  final List<FriendSummary> friends;

  /// 详情状态映射（seedId → FriendFarm）。
  Map<String, FriendFarm> farms = {};

  int listCalls = 0;
  int detailCalls = 0;
  int stealCalls = 0;
  Object? stealError;

  @override
  Future<List<FriendSummary>> fetchFriendsStealable() async {
    listCalls++;
    return friends;
  }

  @override
  Future<FriendFarm> fetchFriendFarm(String friendId) async {
    detailCalls++;
    return farms[friendId] ?? FriendFarm(id: friendId, username: friendId);
  }

  @override
  Future<StealResult> stealFriend(String friendId) async {
    stealCalls++;
    final err = stealError;
    if (err != null) throw err;
    return const StealResult(
      message: '偷菜成功',
      stolenCrops: [StolenCrop(seedId: 'p', quantity: 2)],
    );
  }
}

FriendSummary _friend(String id) => FriendSummary(id: id, username: '用户$id');

FriendFarm _farm(String id, {bool stealable = false}) => FriendFarm(
  id: id,
  username: '用户$id',
  isStealable: stealable,
  firstCrop: stealable
      ? const FriendFirstCrop(seedName: '南瓜', seedImage: '/p', remainingTime: 0)
      : const FriendFirstCrop(
          seedName: '南瓜',
          seedImage: '/p',
          remainingTime: 300,
        ),
);

void main() {
  test('refresh 拉取列表并加载详情，可偷好友排最前', () async {
    final api = _FakeApi([_friend('a'), _friend('b'), _friend('c')])
      ..farms = {
        'a': _farm('a'),
        'b': _farm('b', stealable: true),
        'c': _farm('c'),
      };
    final state = FriendState(api: api, coordinator: OperationCoordinator());

    await state.refresh();

    expect(api.listCalls, 1);
    expect(api.detailCalls, 3);
    expect(state.statuses.length, 3);
    expect(state.statuses.first.id, 'b'); // 可偷排最前
  });

  test('refresh 5min TTL 内复用列表缓存，2min 内复用详情缓存', () async {
    final api = _FakeApi([_friend('a')])..farms = {'a': _farm('a')};
    final state = FriendState(api: api, coordinator: OperationCoordinator());

    await state.refresh();
    final listAfterFirst = api.listCalls;
    final detailsAfterFirst = api.detailCalls;
    // 第二次 refresh 在列表 TTL（5min）与详情 TTL（2min）内：两者都复用缓存。
    await state.refresh();

    expect(api.listCalls, listAfterFirst); // 列表命中 5min TTL
    expect(api.detailCalls, detailsAfterFirst); // 详情命中 2min TTL
  });

  test('refresh(force:true) 绕过列表 TTL 重拉', () async {
    final api = _FakeApi([_friend('a')])..farms = {'a': _farm('a')};
    final state = FriendState(api: api, coordinator: OperationCoordinator());

    await state.refresh();
    final listAfterFirst = api.listCalls;
    await state.refresh(force: true);

    expect(api.listCalls, listAfterFirst + 1); // force 绕过 5min TTL
  });

  test('分页：pageSize=5，第二页只加载对应好友详情', () async {
    final friends = List.generate(7, (i) => _friend('f$i'));
    final api = _FakeApi(friends)
      ..farms = {for (final f in friends) f.id: _farm(f.id)};
    final state = FriendState(api: api, coordinator: OperationCoordinator());

    await state.refresh();
    expect(state.totalPages, 2);
    expect(state.statuses.length, 5);

    await state.setPage(2);
    expect(state.page, 2);
    expect(state.statuses.length, 2);
  });

  test('偷菜成功：调用接口、失效缓存并刷新列表', () async {
    final api = _FakeApi([_friend('a'), _friend('b')])
      ..farms = {'a': _farm('a', stealable: true), 'b': _farm('b')};
    final state = FriendState(api: api, coordinator: OperationCoordinator());
    await state.refresh();
    final listBefore = api.listCalls;
    final detailBefore = api.detailCalls;

    await state.steal('a');

    expect(api.stealCalls, 1);
    expect(state.stealNotice, contains('偷菜成功'));
    expect(state.stealNoticeType, StealNoticeType.success);
    // 偷菜成功后失效 a 的缓存并刷新：列表 + 详情都重拉。
    expect(api.listCalls, listBefore + 1);
    expect(api.detailCalls, greaterThan(detailBefore));
  });

  test('5s 冷却守卫：冷却期内再次偷菜不发请求', () async {
    final api = _FakeApi([_friend('a'), _friend('b')])
      ..farms = {
        'a': _farm('a', stealable: true),
        'b': _farm('b', stealable: true),
      };
    final state = FriendState(api: api, coordinator: OperationCoordinator());
    await state.refresh();

    await state.steal('a');
    final stealCallsAfterFirst = api.stealCalls;

    await state.steal('b');

    expect(api.stealCalls, stealCallsAfterFirst); // 冷却中未发请求
    expect(state.stealNotice, contains('冷却中'));
    expect(state.stealNoticeType, StealNoticeType.error);
  });

  test('业务失败（success:false）：失效缓存并刷新列表', () async {
    final api = _FakeApi([_friend('a')])
      ..farms = {'a': _farm('a', stealable: true)}
      ..stealError = const ApiBusinessException(1, '已被偷完');
    final state = FriendState(api: api, coordinator: OperationCoordinator());
    await state.refresh();
    final listBefore = api.listCalls;

    await state.steal('a');

    expect(state.stealNoticeType, StealNoticeType.error);
    expect(state.stealNotice, contains('已被偷完'));
    expect(api.listCalls, listBefore + 1);
  });

  test('网络失败：不刷新列表，仅提示', () async {
    final api = _FakeApi([_friend('a')])
      ..farms = {'a': _farm('a', stealable: true)}
      ..stealError = const ApiNetworkException('网络请求失败');
    final state = FriendState(api: api, coordinator: OperationCoordinator());
    await state.refresh();
    final listBefore = api.listCalls;

    await state.steal('a');

    expect(state.stealNoticeType, StealNoticeType.error);
    expect(api.listCalls, listBefore); // 未刷新
  });

  test('认证失效：外抛 AuthExpiredException', () async {
    final api = _FakeApi([_friend('a')])
      ..farms = {'a': _farm('a', stealable: true)}
      ..stealError = const AuthExpiredException();
    final state = FriendState(api: api, coordinator: OperationCoordinator());
    await state.refresh();

    expect(() => state.steal('a'), throwsA(isA<AuthExpiredException>()));
  });
}

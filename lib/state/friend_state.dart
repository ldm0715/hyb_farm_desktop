/// 好友农场状态：列表、分页、详情 30s 缓存、偷菜流程与冷却。
library;

import 'package:flutter/foundation.dart';
import 'package:hyb_farm_desktop/api/api_client.dart';
import 'package:hyb_farm_desktop/api/farm_api.dart';
import 'package:hyb_farm_desktop/api/models.dart';
import 'package:hyb_farm_desktop/core/constants.dart';
import 'package:hyb_farm_desktop/core/operation_coordinator.dart';

/// 偷菜结果提示类型。
enum StealNoticeType { success, error }

class FriendState extends ChangeNotifier {
  FriendState({required FarmApi api, required OperationCoordinator coordinator})
    : _api = api,
      _coordinator = coordinator;

  final FarmApi _api;
  final OperationCoordinator _coordinator;

  List<FriendSummary> _friends = const [];
  List<FriendFarm> _statuses = const [];
  int _page = 1;
  bool _loading = false;
  String? _stealingFriendId;
  DateTime? _stealCooldownUntil;
  String? _stealNotice;
  StealNoticeType? _stealNoticeType;
  final Map<String, ({FriendFarm status, DateTime fetchedAt})> _detailCache =
      {};

  List<FriendFarm> get statuses => _statuses;
  int get page => _page;
  int get totalPages =>
      _friends.isEmpty ? 1 : (_friends.length / kFriendsPageSize).ceil();
  bool get loading => _loading;
  String? get stealingFriendId => _stealingFriendId;
  String? get stealNotice => _stealNotice;
  StealNoticeType? get stealNoticeType => _stealNoticeType;

  /// 偷菜接口剩余冷却秒数（所有好友共用）。
  int get stealCooldownRemainingSeconds {
    final until = _stealCooldownUntil;
    if (until == null) return 0;
    final diff = until.difference(DateTime.now()).inSeconds;
    return diff > 0 ? diff : 0;
  }

  bool get isStealCoolingDown => stealCooldownRemainingSeconds > 0;

  /// 拉取好友列表并按当前页加载详情；列表失败/为空时清空状态。
  Future<void> refresh({bool forceDetails = false}) async {
    _loading = true;
    notifyListeners();
    try {
      final friends = await _api.fetchFriendsStealable();
      _friends = friends;

      final total = totalPages;
      if (_page > total) _page = total;

      final start = (_page - 1) * kFriendsPageSize;
      final pageFriends = friends.skip(start).take(kFriendsPageSize).toList();
      final statuses = await _fetchDetails(pageFriends, force: forceDetails);
      _statuses = _sort(statuses);
    } on AuthExpiredException {
      rethrow;
    } on Exception {
      _friends = const [];
      _statuses = const [];
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 并发（最多 3）拉取当前页好友详情，命中 30s 缓存则复用。
  Future<List<FriendFarm>> _fetchDetails(
    List<FriendSummary> friends, {
    bool force = false,
  }) async {
    final results = List<FriendFarm?>.filled(friends.length, null);
    var next = 0;

    Future<void> worker() async {
      while (true) {
        final index = next++;
        if (index >= friends.length) return;
        final friend = friends[index];

        final cached = force ? null : _detailCache[friend.id];
        if (cached != null &&
            DateTime.now().difference(cached.fetchedAt) < kFriendDetailCache) {
          results[index] = cached.status;
          continue;
        }

        final status = await _api.fetchFriendFarm(friend.id);
        _detailCache[friend.id] = (status: status, fetchedAt: DateTime.now());
        results[index] = status;
      }
    }

    final workers = friends.length < 3 ? friends.length : 3;
    await Future.wait(List.generate(workers, (_) => worker()));
    return results.whereType<FriendFarm>().toList();
  }

  List<FriendFarm> _sort(List<FriendFarm> statuses) {
    final list = [...statuses];
    list.sort((a, b) {
      if (a.isStealable != b.isStealable) return a.isStealable ? -1 : 1;
      final aTime = a.firstCrop?.maturesAt;
      final bTime = b.firstCrop?.maturesAt;
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return aTime.compareTo(bTime);
    });
    return list;
  }

  /// 偷菜流程，对齐脚本 handleStealFriend：5s 全局冷却、成功后失效缓存并刷新。
  Future<void> steal(String friendId) async {
    if (_stealingFriendId != null || friendId.isEmpty) return;

    if (isStealCoolingDown) {
      _stealNotice = '偷菜接口冷却中，请 $stealCooldownRemainingSeconds 秒后再试';
      _stealNoticeType = StealNoticeType.error;
      notifyListeners();
      return;
    }

    FriendFarm? friend;
    for (final f in _statuses) {
      if (f.id == friendId) {
        friend = f;
        break;
      }
    }
    if (friend == null || !friend.isStealable) return;

    _stealingFriendId = friendId;
    _stealCooldownUntil = DateTime.now().add(kStealCooldown);
    _stealNotice = null;
    _stealNoticeType = null;
    notifyListeners();

    try {
      final result = await _coordinator.run(() => _api.stealFriend(friendId));
      _detailCache.remove(friendId);
      try {
        await refresh();
      } on Exception {
        // 偷菜已成功，刷新失败不覆盖成功提示。
      }
      _stealNotice = result.displayMessage(friend.username);
      _stealNoticeType = StealNoticeType.success;
    } on AuthExpiredException {
      _stealingFriendId = null;
      notifyListeners();
      rethrow;
    } on ApiBusinessException catch (e) {
      _detailCache.remove(friendId);
      try {
        await refresh();
      } on Exception {
        // 业务失败提示优先，刷新失败不覆盖。
      }
      _stealNotice = '${friend.username}农场：${e.message}';
      _stealNoticeType = StealNoticeType.error;
    } on ApiNetworkException catch (e) {
      // 网络失败不刷新列表，仅提示。
      _stealNotice = '${friend.username}农场：${e.message}';
      _stealNoticeType = StealNoticeType.error;
    } on Exception {
      _stealNotice = '${friend.username}农场：偷菜失败';
      _stealNoticeType = StealNoticeType.error;
    } finally {
      _stealingFriendId = null;
      notifyListeners();
    }
  }

  /// 切换分页（clamp 到有效范围）并刷新。
  Future<void> setPage(int p) async {
    final total = totalPages;
    _page = p < 1 ? 1 : (p > total ? total : p);
    await refresh();
  }
}

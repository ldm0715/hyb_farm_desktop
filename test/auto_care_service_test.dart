/// AutoCareService 测试：快照刷新触发、无 debuff 不 care、刷新失败不 care、nextCareAt 调度。
library;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyb_farm_desktop/api/api_client.dart';
import 'package:hyb_farm_desktop/api/farm_api.dart';
import 'package:hyb_farm_desktop/api/models.dart';
import 'package:hyb_farm_desktop/core/operation_coordinator.dart';
import 'package:hyb_farm_desktop/services/auto_care_service.dart';
import 'package:hyb_farm_desktop/services/care_log.dart';
import 'package:hyb_farm_desktop/state/connection_state_store.dart';
import 'package:hyb_farm_desktop/state/farm_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

Crop _crop({String id = 'c', List<String> conditions = const []}) => Crop(
  id: id,
  seedId: 's',
  seedName: 'n',
  seedImage: 'img',
  plotIndex: 0,
  conditions: conditions,
);

/// 可编程 FarmApi 假实现：可控 debuff 与 care 计数。
class _FakeApi extends FarmApi {
  _FakeApi() : super(ApiClient());

  bool hasDebuff = false;
  bool failFetch = false;
  int careCalls = 0;

  @override
  Future<CropsResponse> fetchCrops() async {
    if (failFetch) throw const ApiNetworkException('网络请求失败');
    return CropsResponse(
      crops: [_crop(conditions: hasDebuff ? const ['weed'] : const [])],
      maxSlots: 4,
    );
  }

  @override
  Future<FarmPlots> fetchPlots() async =>
      const FarmPlots(totalSlots: 4, freeSlots: 3);

  @override
  Future<List<InventoryItem>> fetchInventory() async => const [];

  @override
  Future<CareAllResult> careAll() async {
    careCalls++;
    return const CareAllResult(
      processed: 1,
      skipped: 0,
      energySpent: 1,
      byKind: {'weed': 1},
    );
  }
}

/// 同步构造服务（供 fakeAsync 用），CareLog 由调用方预建。
AutoCareService _buildSync({
  required _FakeApi api,
  required FarmState farmState,
  required CareLog careLog,
  required DateTime Function() now,
}) {
  return AutoCareService(
    api: api,
    farmState: farmState,
    coordinator: OperationCoordinator(),
    careLog: careLog,
    connectionStore: ConnectionStateStore(),
    now: now,
  );
}

/// 异步构造服务（供非调度测试用），内部 mock 掉 prefs。
Future<(AutoCareService, _FakeApi, FarmState)> _build() async {
  SharedPreferences.setMockInitialValues({});
  final api = _FakeApi();
  final farmState = FarmState(api);
  final careLog = await CareLog.create();
  final service = _buildSync(
    api: api,
    farmState: farmState,
    careLog: careLog,
    now: DateTime.now,
  );
  return (service, api, farmState);
}

void main() {
  test('checkAndCare 先刷新，debuff 出现后触发 careAll', () async {
    final (service, api, farmState) = await _build();

    // 初始无 debuff，刷新后快照无 debuff。
    await farmState.refresh();
    expect(farmState.hasDebuff, isFalse);
    await service.checkAndCare();
    expect(api.careCalls, 0);

    // 服务端出现 debuff，检查时先刷新再判，触发 careAll。
    api.hasDebuff = true;
    await service.checkAndCare();
    expect(api.careCalls, 1);
  });

  test('无 debuff 时 checkAndCare 不触发 careAll', () async {
    final (service, api, farmState) = await _build();
    api.hasDebuff = false;
    await farmState.refresh();
    await service.checkAndCare();
    expect(api.careCalls, 0);
  });

  test('刷新失败时 checkAndCare 不触发 careAll 且不抛异常', () async {
    final (service, api, _) = await _build();
    api.failFetch = true;
    await service.checkAndCare();
    expect(api.careCalls, 0);
  });

  test('start 设定 nextCareAt，stop 清空，同间隔重复 start 不重置', () async {
    SharedPreferences.setMockInitialValues({});
    final careLog = await CareLog.create();
    final api = _FakeApi();
    final farmState = FarmState(api);

    fakeAsync((async) {
      final base = DateTime(2026, 1, 1, 12, 0, 0);
      final service = _buildSync(
        api: api,
        farmState: farmState,
        careLog: careLog,
        now: () => base.add(async.elapsed),
      );

      service.start(5);
      final first = service.nextCareAt!;
      expect(first, base.add(const Duration(minutes: 5)));

      // 同间隔重复 start 不重置倒计时。
      async.elapse(const Duration(minutes: 1));
      service.start(5);
      expect(service.nextCareAt, first);

      // 改间隔则重置。
      service.start(10);
      expect(service.nextCareAt, base.add(const Duration(minutes: 11)));

      service.stop();
      expect(service.nextCareAt, isNull);
      expect(service.running, isFalse);
    });
  });

  test('start 到点后触发一次检查并自动重排', () async {
    SharedPreferences.setMockInitialValues({});
    final careLog = await CareLog.create();
    final api = _FakeApi();
    final farmState = FarmState(api);
    api.hasDebuff = true;

    fakeAsync((async) {
      final base = DateTime(2026, 1, 1, 12, 0, 0);
      final service = _buildSync(
        api: api,
        farmState: farmState,
        careLog: careLog,
        now: () => base.add(async.elapsed),
      );

      service.start(5);
      final first = service.nextCareAt;

      async.elapse(const Duration(minutes: 5));
      async.flushMicrotasks();
      expect(api.careCalls, 1);
      // 到点后重排下一次。
      expect(service.nextCareAt, isNot(first));
      expect(service.nextCareAt, base.add(const Duration(minutes: 10)));
    });
  });
}

/// HarvestScheduler 假时钟测试：到点收菜、延迟补种、失败延迟确认、最小间隔守卫。
library;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyb_farm_desktop/api/api_client.dart';
import 'package:hyb_farm_desktop/api/farm_api.dart';
import 'package:hyb_farm_desktop/api/models.dart';
import 'package:hyb_farm_desktop/core/operation_coordinator.dart';
import 'package:hyb_farm_desktop/services/harvest_log.dart';
import 'package:hyb_farm_desktop/services/harvest_scheduler.dart';
import 'package:hyb_farm_desktop/services/notification_service.dart';
import 'package:hyb_farm_desktop/services/replant_service.dart';
import 'package:hyb_farm_desktop/state/farm_state.dart';
import 'package:hyb_farm_desktop/state/connection_state_store.dart';
import 'package:hyb_farm_desktop/state/settings_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 可编程的 FarmApi 假实现：用一个固定成熟作物 + 一个按 [matureAt] 成熟的作物。
class _RecordingApi extends FarmApi {
  _RecordingApi({required this.now}) : super(ApiClient());

  final DateTime Function() now;
  bool hasMatureCrop = false;
  DateTime? matureAt;
  FarmPlots plots = const FarmPlots(totalSlots: 4, freeSlots: 4);
  List<InventoryItem> inventory = const [];
  bool failHarvest = false;

  /// pending 作物第一次 fetch 时算出的剩余秒数快照，之后不再随墙钟自减，
  /// 模拟后端 `remainingTime` 是请求时刻静态快照的真实行为。
  int? _pendingRemainingSnapshot;

  int harvestCalls = 0;
  int plantCalls = 0;
  int fetchCropsCalls = 0;

  @override
  Future<CropsResponse> fetchCrops() async {
    fetchCropsCalls++;
    final crops = <Crop>[];
    if (hasMatureCrop) {
      crops.add(
        const Crop(
          id: 'mature',
          seedId: 'corn',
          seedName: '玉米',
          seedImage: '/c',
          plotIndex: 0,
          isMature: true,
          remainingTime: 0,
        ),
      );
    }
    final m = matureAt;
    if (m != null) {
      // 快照只在首次 fetch 计算一次，之后成熟与否只能靠 maturesAt 绝对时刻判定。
      _pendingRemainingSnapshot ??= m.difference(now()).inSeconds;
      crops.add(
        Crop(
          id: 'pending',
          seedId: 'pumpkin',
          seedName: '南瓜',
          seedImage: '/p',
          plotIndex: 1,
          maturesAt: m,
          remainingTime: _pendingRemainingSnapshot!,
        ),
      );
    }
    return CropsResponse(crops: crops, maxSlots: 4);
  }

  @override
  Future<FarmPlots> fetchPlots() async => plots;

  @override
  Future<List<InventoryItem>> fetchInventory() async => inventory;

  @override
  Future<void> harvestAll() async {
    harvestCalls++;
    if (failHarvest) {
      // 模拟服务端已收菜，但响应超时。
      hasMatureCrop = false;
      matureAt = null;
      throw const ApiNetworkException('timeout');
    }
  }

  @override
  Future<PlantBatchResult> plantBatch(String seedId, int quantity) async {
    plantCalls++;
    return PlantBatchResult(plantedCount: quantity);
  }
}

HarvestScheduler _build({
  required _RecordingApi api,
  required FarmState farmState,
  required SettingsState settings,
  required HarvestLog harvestLog,
  required DateTime Function() now,
}) => HarvestScheduler(
  api: api,
  farmState: farmState,
  settings: settings,
  coordinator: OperationCoordinator(),
  replant: ReplantService(api: api),
  notifications: NotificationService(),
  harvestLog: harvestLog,
  connectionStore: ConnectionStateStore(),
  now: now,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SettingsState settings;
  late HarvestLog harvestLog;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await SettingsState.create();
    harvestLog = await HarvestLog.create();
  });

  test('到点自动收菜', () {
    fakeAsync((async) {
      final base = DateTime(2026, 8, 14, 10, 0, 0);
      DateTime now() => base.add(async.elapsed);
      final api = _RecordingApi(now: now)
        ..matureAt = base.add(const Duration(seconds: 45));
      final farmState = FarmState(api, now: now);
      final scheduler = _build(
        api: api,
        farmState: farmState,
        settings: settings,
        harvestLog: harvestLog,
        now: now,
      );

      scheduler.start();
      async.flushMicrotasks();
      expect(api.fetchCropsCalls, greaterThan(0));
      expect(api.harvestCalls, 0);

      async.elapse(const Duration(seconds: 46));
      async.flushMicrotasks();
      expect(api.harvestCalls, 1);

      // 到点成熟的地块应被计入 24 小时收菜统计。
      final counts = harvestLog.countsWithin(const Duration(hours: 24));
      expect(counts['南瓜']?.count, 1);

      scheduler.stop();
    });
  });

  test('收菜成功后延迟 10s 补种', () {
    fakeAsync((async) {
      final base = DateTime(2026, 8, 14, 10, 0, 0);
      DateTime now() => base.add(async.elapsed);
      final api = _RecordingApi(now: now)
        ..matureAt = base.add(const Duration(seconds: 45))
        ..inventory = const [
          InventoryItem(
            seedId: 'pumpkin',
            seedName: '南瓜',
            seedImage: '/p',
            quantity: 2,
            recyclePrice: '100',
          ),
        ];
      final farmState = FarmState(api, now: now);
      settings.replantSeedId = 'pumpkin';
      final scheduler = _build(
        api: api,
        farmState: farmState,
        settings: settings,
        harvestLog: harvestLog,
        now: now,
      );

      scheduler.start();
      async.flushMicrotasks();

      async.elapse(const Duration(seconds: 46));
      async.flushMicrotasks();
      expect(api.harvestCalls, 1);
      expect(api.plantCalls, 0);

      async.elapse(const Duration(seconds: 10));
      async.flushMicrotasks();
      expect(api.plantCalls, 1);

      scheduler.stop();
    });
  });

  test('收菜失败但服务端已收菜 → 延迟确认成功', () {
    fakeAsync((async) {
      final base = DateTime(2026, 8, 14, 10, 0, 0);
      DateTime now() => base.add(async.elapsed);
      final api = _RecordingApi(now: now)
        ..hasMatureCrop = true
        ..matureAt = base.add(const Duration(seconds: 45))
        ..failHarvest = true;
      final farmState = FarmState(api, now: now);
      final scheduler = _build(
        api: api,
        farmState: farmState,
        settings: settings,
        harvestLog: harvestLog,
        now: now,
      );

      scheduler.start();
      async.flushMicrotasks();

      async.elapse(const Duration(seconds: 46));
      async.flushMicrotasks();

      expect(api.harvestCalls, 1);
      expect(farmState.lastResult, '收菜成功（延迟确认）');

      scheduler.stop();
    });
  });

  test('最小间隔守卫：30s 内重复成熟不重复收菜', () {
    fakeAsync((async) {
      final base = DateTime(2026, 8, 14, 10, 0, 0);
      DateTime now() => base.add(async.elapsed);
      // 一块从启动即成熟的作物；收菜成功后它仍保持成熟（harvestAll 不清理），
      // _reschedule 会再次看到成熟地块并尝试收菜，由 30s 守卫拦下。
      final api = _RecordingApi(now: now)..hasMatureCrop = true;
      final farmState = FarmState(api, now: now);
      final scheduler = _build(
        api: api,
        farmState: farmState,
        settings: settings,
        harvestLog: harvestLog,
        now: now,
      );

      scheduler.start();
      async.flushMicrotasks();
      expect(api.harvestCalls, 1);

      // 无新触发源（mature Timer 单次、fallback 5min），短时间内不再收菜。
      async.elapse(const Duration(seconds: 10));
      async.flushMicrotasks();
      expect(api.harvestCalls, 1);

      scheduler.stop();
    });
  });
}

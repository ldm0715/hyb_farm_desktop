/// HarvestScheduler 假时钟测试：到点收菜、延迟补种、失败延迟确认、最小间隔守卫。
library;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyb_farm_desktop/api/api_client.dart';
import 'package:hyb_farm_desktop/api/farm_api.dart';
import 'package:hyb_farm_desktop/api/models.dart';
import 'package:hyb_farm_desktop/core/constants.dart';
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

  /// 前 N 次 fetchCrops 抛 ApiNetworkException（模拟唤醒后短暂断网）。
  int failFetchN = 0;

  /// fetchCrops 抛 AuthExpiredException。
  bool failAuth = false;

  /// pending 作物第一次 fetch 时算出的剩余秒数快照，之后不再随墙钟自减，
  /// 模拟后端 `remainingTime` 是请求时刻静态快照的真实行为。
  int? _pendingRemainingSnapshot;

  int harvestCalls = 0;
  int plantCalls = 0;
  int fetchCropsCalls = 0;

  @override
  Future<CropsResponse> fetchCrops() async {
    fetchCropsCalls++;
    if (failAuth) throw const AuthExpiredException();
    if (failFetchN > 0) {
      failFetchN--;
      throw const ApiNetworkException('network down');
    }
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
  List<Duration>? recoveryRetryDelays,
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
  recoveryRetryDelays: recoveryRetryDelays,
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

  test('recoverAndReschedule 立即补收（系统唤醒）', () {
    fakeAsync((async) {
      var wallClock = DateTime(2026, 8, 14, 10, 0, 0);
      final api = _RecordingApi(now: () => wallClock)
        ..matureAt = wallClock.add(const Duration(seconds: 45));
      final farmState = FarmState(api, now: () => wallClock);
      final scheduler = _build(
        api: api,
        farmState: farmState,
        settings: settings,
        harvestLog: harvestLog,
        now: () => wallClock,
      );

      scheduler.start();
      async.flushMicrotasks();
      expect(api.harvestCalls, 0);

      // 模拟休眠：墙钟跳 10 分钟（作物已成熟），但 fake Timer 不触发。
      wallClock = wallClock.add(const Duration(minutes: 10));

      scheduler.recoverAndReschedule(RecoveryReason.powerResume);
      async.flushMicrotasks();
      expect(api.harvestCalls, 1);

      scheduler.stop();
    });
  });

  test('网络失败有限重试后成功恢复', () {
    fakeAsync((async) {
      var wallClock = DateTime(2026, 8, 14, 10, 0, 0);
      final api = _RecordingApi(now: () => wallClock)
        ..matureAt = wallClock.add(const Duration(seconds: 45));
      final farmState = FarmState(api, now: () => wallClock);
      final scheduler = _build(
        api: api,
        farmState: farmState,
        settings: settings,
        harvestLog: harvestLog,
        now: () => wallClock,
        recoveryRetryDelays: const [
          Duration(milliseconds: 10),
          Duration(milliseconds: 10),
        ],
      );

      scheduler.start();
      async.flushMicrotasks();
      expect(api.harvestCalls, 0);

      wallClock = wallClock.add(const Duration(minutes: 10));
      api.failFetchN = 2;

      scheduler.recoverAndReschedule(RecoveryReason.powerResume);
      async.flushMicrotasks();
      expect(api.harvestCalls, 0); // 第一次 fetch 失败，等待重试

      async.elapse(const Duration(milliseconds: 10));
      async.flushMicrotasks();
      expect(api.harvestCalls, 0); // 第二次 fetch 失败

      async.elapse(const Duration(milliseconds: 10));
      async.flushMicrotasks();
      expect(api.harvestCalls, 1); // 第三次 fetch 成功 → 补收
      expect(api.failFetchN, 0);

      scheduler.stop();
    });
  });

  test('认证失效不重试', () {
    fakeAsync((async) {
      var wallClock = DateTime(2026, 8, 14, 10, 0, 0);
      final api = _RecordingApi(now: () => wallClock)
        ..matureAt = wallClock.add(const Duration(hours: 1));
      final farmState = FarmState(api, now: () => wallClock);
      final scheduler = _build(
        api: api,
        farmState: farmState,
        settings: settings,
        harvestLog: harvestLog,
        now: () => wallClock,
        recoveryRetryDelays: const [
          Duration(milliseconds: 10),
          Duration(milliseconds: 10),
        ],
      );

      scheduler.start();
      async.flushMicrotasks();
      final callsBefore = api.fetchCropsCalls;

      wallClock = wallClock.add(const Duration(minutes: 10));
      api.failAuth = true;

      scheduler.recoverAndReschedule(RecoveryReason.powerResume);
      async.flushMicrotasks();
      expect(api.fetchCropsCalls, callsBefore + 1); // 只尝试一次，不重试
      expect(api.harvestCalls, 0);

      async.elapse(const Duration(seconds: 60));
      async.flushMicrotasks();
      expect(api.fetchCropsCalls, callsBefore + 1);

      scheduler.stop();
    });
  });

  test('重试期间认证失效立即停止', () {
    fakeAsync((async) {
      var wallClock = DateTime(2026, 8, 14, 10, 0, 0);
      final api = _RecordingApi(now: () => wallClock)
        ..matureAt = wallClock.add(const Duration(hours: 1));
      final farmState = FarmState(api, now: () => wallClock);
      final scheduler = _build(
        api: api,
        farmState: farmState,
        settings: settings,
        harvestLog: harvestLog,
        now: () => wallClock,
        recoveryRetryDelays: const [
          Duration(milliseconds: 10),
          Duration(milliseconds: 10),
        ],
      );

      scheduler.start();
      async.flushMicrotasks();

      wallClock = wallClock.add(const Duration(minutes: 10));
      api.failFetchN = 1;

      scheduler.recoverAndReschedule(RecoveryReason.powerResume);
      async.flushMicrotasks();
      expect(api.fetchCropsCalls, 2); // start 1 次 + 第一次网络失败

      api.failAuth = true; // 重试时认证失效

      async.elapse(const Duration(milliseconds: 10));
      async.flushMicrotasks();
      expect(api.fetchCropsCalls, 3); // 只到第二次尝试
      expect(api.harvestCalls, 0);

      async.elapse(const Duration(seconds: 60));
      async.flushMicrotasks();
      expect(api.fetchCropsCalls, 3); // 不再重试

      scheduler.stop();
    });
  });

  test('timer-gap 检测触发恢复（系统休眠，独立墙钟）', () {
    fakeAsync((async) {
      var wallClock = DateTime(2026, 8, 14, 10, 0, 0);
      final api = _RecordingApi(now: () => wallClock)
        ..matureAt = wallClock.add(const Duration(hours: 1));
      final farmState = FarmState(api, now: () => wallClock);
      final scheduler = _build(
        api: api,
        farmState: farmState,
        settings: settings,
        harvestLog: harvestLog,
        now: () => wallClock,
      );

      scheduler.start();
      async.flushMicrotasks();
      expect(api.harvestCalls, 0);

      // 模拟休眠：墙钟跳 10 小时，但 fallback Timer 只恢复执行一次。
      wallClock = wallClock.add(const Duration(hours: 10));

      // 只推进 5 分钟 fake 时间：成熟 Timer（1h）不触发，fallback tick 检测到 gap。
      async.elapse(kHarvestFallbackInterval);
      async.flushMicrotasks();
      expect(api.harvestCalls, 1);

      scheduler.stop();
    });
  });

  test('并发恢复入口 single-flight：只执行一轮', () {
    fakeAsync((async) {
      var wallClock = DateTime(2026, 8, 14, 10, 0, 0);
      final api = _RecordingApi(now: () => wallClock)
        ..matureAt = wallClock.add(const Duration(hours: 1));
      final farmState = FarmState(api, now: () => wallClock);
      final scheduler = _build(
        api: api,
        farmState: farmState,
        settings: settings,
        harvestLog: harvestLog,
        now: () => wallClock,
      );

      scheduler.start();
      async.flushMicrotasks();

      wallClock = wallClock.add(const Duration(hours: 10));

      // 三个入口同时触发：合并为至多一个补跑，30s 守卫 + single-flight 兜底。
      scheduler.recoverAndReschedule(RecoveryReason.powerResume);
      scheduler.recoverAndReschedule(RecoveryReason.foreground);
      scheduler.recoverAndReschedule(RecoveryReason.timerGap);
      async.flushMicrotasks();

      expect(api.harvestCalls, 1);

      scheduler.stop();
    });
  });
}

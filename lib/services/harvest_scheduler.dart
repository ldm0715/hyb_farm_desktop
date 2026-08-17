/// 收菜调度器：识别最近成熟作物，到点触发收菜，成功后延迟补种。
library;

import 'dart:async';

import 'package:hyb_farm_desktop/api/api_client.dart';
import 'package:hyb_farm_desktop/api/farm_api.dart';
import 'package:hyb_farm_desktop/core/constants.dart';
import 'package:hyb_farm_desktop/core/log/app_logger.dart';
import 'package:hyb_farm_desktop/core/operation_coordinator.dart';
import 'package:hyb_farm_desktop/core/request_backoff.dart';
import 'package:hyb_farm_desktop/services/harvest_log.dart';
import 'package:hyb_farm_desktop/services/notification_service.dart';
import 'package:hyb_farm_desktop/services/replant_service.dart';
import 'package:hyb_farm_desktop/state/farm_state.dart';
import 'package:hyb_farm_desktop/state/connection_state_store.dart';
import 'package:hyb_farm_desktop/state/settings_state.dart';

/// 触发一次「恢复 + 重排」的来源。
///
/// 所有入口共用同一个 single-flight 协调器（[HarvestScheduler.recoverAndReschedule]）。
enum RecoveryReason {
  /// 应用进入前台（window_manager 的 show/restore）。
  foreground,

  /// Windows 从睡眠/休眠恢复（原生 WM_POWERBROADCAST）。
  powerResume,

  /// 网络从瞬时错误恢复（networkError/serverError → healthy）。
  networkRecovered,

  /// fallback 定时器检测到异常时间间隔（系统休眠导致 Timer 滞后）。
  timerGap,

  /// 完成人机验证、状态从 challengeRequired 恢复 healthy。
  challengeCleared,
}

class HarvestScheduler {
  HarvestScheduler({
    required FarmApi api,
    required FarmState farmState,
    required SettingsState settings,
    required OperationCoordinator coordinator,
    required ReplantService replant,
    required NotificationService notifications,
    required HarvestLog harvestLog,
    required ConnectionStateStore connectionStore,
    RequestBackoff? backoff,
    List<Duration>? recoveryRetryDelays,
    DateTime Function() now = DateTime.now,
  }) : _api = api,
       _farmState = farmState,
       _settings = settings,
       _coordinator = coordinator,
       _replant = replant,
       _notifications = notifications,
       _harvestLog = harvestLog,
       _connectionStore = connectionStore,
       _backoff = backoff ?? RequestBackoff(),
       _recoveryRetryDelays = recoveryRetryDelays ?? kRecoveryRetryDelays,
       _now = now;

  final FarmApi _api;
  final FarmState _farmState;
  final SettingsState _settings;
  final OperationCoordinator _coordinator;
  final ReplantService _replant;
  final NotificationService _notifications;
  final HarvestLog _harvestLog;
  final ConnectionStateStore _connectionStore;
  final RequestBackoff _backoff;
  final DateTime Function() _now;
  final List<Duration> _recoveryRetryDelays;

  /// crops 资源的退避/门控键。
  static const _cropsKey = '/api/farm/crops';
  static const _harvestKey = '/api/farm/harvest-all';

  Timer? _matureTimer;
  Timer? _fallbackTimer;
  DateTime? _lastHarvestAt;
  DateTime? _lastFallbackTickAt;
  bool _running = false;

  // —— 恢复流程 single-flight / coalescing ——
  bool _recoveryRunning = false;
  RecoveryReason? _pendingRecoveryReason;
  Completer<void>? _recoveryCompleter;

  /// 最小收菜间隔守卫，避免多个触发源叠加请求（仅作 cooldown，不替代 single-flight）。
  static const _minInterval = Duration(seconds: 30);

  void start() {
    if (_running) return;
    _running = true;
    _farmState.setAutomation(AutomationStatus.running);
    _lastFallbackTickAt = _now();
    _fallbackTimer = Timer.periodic(
      kHarvestFallbackInterval,
      (_) => _onFallbackTick(),
    );
    _reschedule();
  }

  void stop() {
    _running = false;
    _matureTimer?.cancel();
    _fallbackTimer?.cancel();
    _lastFallbackTickAt = null;
    _farmState.setAutomation(AutomationStatus.paused);
  }

  /// 进入后台（隐藏到托盘 / 最小化 / 退出）。仅由 windowManager 事件驱动，
  /// 前台失焦（inactive）不调用此方法。
  ///
  /// [allowAutoHarvest] 取 settings.autoHarvest：
  ///  - false：完全停止，取消 mature + fallback Timer，不发任何农场请求；
  ///  - true：保留单次 mature Timer + 5min fallback crops 检查，到点仍完整收菜。
  void onAppBackgrounded({required bool allowAutoHarvest}) {
    if (!_running) return;
    if (!allowAutoHarvest) {
      _matureTimer?.cancel();
      _fallbackTimer?.cancel();
      _farmState.setAutomation(AutomationStatus.paused);
      return;
    }
    // 自动收菜开启：保留现有 mature Timer 与 fallback Timer，不做额外动作。
  }

  /// 统一恢复协调器：所有恢复入口（前台 / 系统唤醒 / 网络恢复 / timer-gap）共用。
  ///
  /// single-flight + coalescing：任意时刻至多一个恢复流程；执行期间新事件合并为
  /// 至多一个补跑。返回的 Future 在刷新、补收与重排真正完成后才 complete。
  Future<void> recoverAndReschedule(RecoveryReason reason) {
    if (!_running) return Future<void>.value();
    if (_recoveryRunning) {
      _pendingRecoveryReason ??= reason;
      AppLog.i('Recovery', 'coalesced', {'reason': reason.name});
      return _recoveryCompleter!.future;
    }
    _recoveryRunning = true;
    final completer = Completer<void>();
    _recoveryCompleter = completer;
    // _runRecoveryLoop 内部吞掉所有异常、从不抛，故 then 后无未处理异步错误。
    _runRecoveryLoop(reason).then((_) => completer.complete());
    return completer.future;
  }

  Future<void> _runRecoveryLoop(RecoveryReason first) async {
    try {
      var reason = first;
      while (true) {
        await _doRecovery(reason);
        final next = _pendingRecoveryReason;
        _pendingRecoveryReason = null;
        if (next == null) break;
        reason = next;
      }
    } finally {
      _recoveryRunning = false;
      _recoveryCompleter = null;
    }
  }

  /// 单轮恢复：force 刷新 → 有成熟则完整补收（await 到完成）→ 否则重排成熟 Timer。
  /// 网络失败按注入退避有限重试；认证失效/业务错误/限流等不重试。
  Future<void> _doRecovery(RecoveryReason reason) async {
    AppLog.i('Recovery', 'start', {'reason': reason.name});
    for (var attempt = 0; ; attempt++) {
      try {
        await _farmState.refreshCrops(force: true);
        // 用绝对成熟时刻 matureAt(now) 判定：休眠期间 remainingTime 是静态快照不自减，
        // 必须用墙钟重算是否有已成熟作物需要补收（matureCount 走 c.mature 会漏判）。
        final now = _now();
        final hasMature = _farmState.crops?.crops
                .any((c) => !c.isEmpty && c.matureAt(now)) ??
            false;
        if (hasMature) {
          // 走同一 coordinator，完整收菜+补种+重排，await 到真正完成。
          await _coordinator.run(_harvestFlow);
        } else {
          await _reschedule();
        }
        AppLog.i('Recovery', 'success', {'reason': reason.name});
        return;
      } on AuthExpiredException {
        _handleExpired();
        AppLog.i('Recovery', 'failed',
            {'reason': reason.name, 'attempt': attempt + 1, 'error': 'auth'});
        return;
      } on ApiNetworkException {
        AppLog.i('Recovery', 'failed',
            {'reason': reason.name, 'attempt': attempt + 1});
        if (attempt >= _recoveryRetryDelays.length) return;
        await Future.delayed(_recoveryRetryDelays[attempt]);
      } on Exception {
        // challenge / rateLimited / business / unknown：不重试，交由各自机制处理。
        AppLog.i('Recovery', 'failed',
            {'reason': reason.name, 'attempt': attempt + 1});
        return;
      }
    }
  }

  /// fallback 兜底 tick：检测 timer-gap（系统休眠导致 Timer 滞后）并触发恢复，
  /// 否则走常规 _reschedule。
  void _onFallbackTick() {
    final now = _now();
    final gap = _lastFallbackTickAt == null
        ? Duration.zero
        : now.difference(_lastFallbackTickAt!);
    _lastFallbackTickAt = now;
    if (gap > kHarvestFallbackInterval + kBackgroundResumeThreshold) {
      AppLog.i('Scheduler', 'timer gap detected', {'duration': gap.inSeconds});
      recoverAndReschedule(RecoveryReason.timerGap);
      return;
    }
    _reschedule();
  }

  /// 拉取作物并安排下一次成熟任务；失败交由兜底定时器重试。
  Future<void> _reschedule() async {
    _matureTimer?.cancel();
    if (!_running) return;
    if (!_connectionStore.canRunAutomation) return;
    if (!_backoff.allowedAt(_cropsKey, _now())) return;
    try {
      await _farmState.refreshCrops();
    } on AuthExpiredException {
      _handleExpired();
      return;
    } on Exception {
      return;
    }

    // 已有成熟作物：直接收，避免「全成熟、无未成熟」时 nextMatureAt==null 漏收。
    if (_farmState.matureCount > 0) {
      _onMature();
      return;
    }

    final nextAt = _farmState.nextMatureAt;
    if (nextAt == null) return;
    final delay = nextAt.difference(_now()) + kHarvestTriggerDelay;
    if (delay <= Duration.zero) {
      _onMature();
      return;
    }
    _matureTimer = Timer(delay, _onMature);
  }

  void _onMature() {
    if (!_running) return;
    _coordinator.run(_harvestFlow);
  }

  Future<void> _harvestFlow() async {
    if (!_running || !_connectionStore.canRunAutomation) return;
    if (!_guardInterval()) return;
    // 收菜写请求纳入退避：退避期内不重试，等待 fallback tick 或下一成熟点。
    if (!_backoff.allowedAt(_harvestKey, _now())) return;

    // 收菜前刷新一次，确保成熟地块快照是最新的。内存里的 remainingTime/isMature
    // 是上次 fetch 的静态快照、到点不会自减，直接快照会把刚成熟的作物漏记。
    try {
      await _farmState.refreshCrops(force: true);
    } on AuthExpiredException {
      _handleExpired();
      return;
    } on Exception {
      // 刷新失败用旧数据兜底，继续尝试收菜。
    }

    // 收菜前快照成熟地块，用于成功后的类型次数统计。
    // 用 matureAt(_now()) 而非 c.mature：remainingTime/isMature 是上次 fetch 的
    // 静态快照、到点不自减，直接快照会把刚成熟的作物漏记；maturesAt 是绝对时刻，
    // 用当前时间重算才准。
    final now = _now();
    final matureBefore =
        _farmState.crops?.crops
            .where((c) => !c.isEmpty && c.matureAt(now))
            .toList() ??
        [];
    var success = false;

    try {
      await _api.harvestAll();
      _lastHarvestAt = _now();
      _farmState.setLastResult('收菜成功');
      success = true;
      if (_settings.notifyHarvest) {
        await _notifications.show('收菜成功', '已完成一次自动收菜');
      }
    } on AuthExpiredException {
      _handleExpired();
      return;
    } on Exception {
      // 超时/失败：重新拉取判断服务端是否已完成收菜。
      try {
        final before = _farmState.matureCount;
        await _farmState.refreshCrops(force: true);
        if (_farmState.matureCount < before) {
          _lastHarvestAt = _now();
          _farmState.setLastResult('收菜成功（延迟确认）');
          success = true;
        } else {
          _farmState.setLastResult('收菜失败，稍后重试');
          return;
        }
      } on Exception {
        _farmState.setLastResult('收菜失败，稍后重试');
        return;
      }
    }

    if (success) {
      try {
        await _harvestLog.record(matureBefore);
      } on Exception {
        // 统计记录失败不影响后续。
      }
      // 收菜改变了 crops 与 inventory，均 force 拿写后最新（约束修订 #1）：
      // 否则 _reschedule 的 refreshCrops() 会命中 15s 最小间隔返回收菜前旧快照，
      // 把刚收掉的地块仍判为成熟。
      try {
        await _farmState.refreshCrops(force: true);
      } on Exception {
        // 刷新失败不影响后续，交由 fallback 兜底。
      }
      try {
        await _farmState.refreshInventory(force: true);
      } on Exception {
        // 库存刷新失败不影响后续。
      }
    }

    // 收菜成功后延迟补种。
    final seedId = _settings.replantSeedId;
    if (seedId != null) {
      await Future.delayed(kReplantDelay);
      try {
        final count = await _replant.replant(seedId);
        if (count > 0) _farmState.setLastResult('补种 $count 个');
      } on AuthExpiredException {
        _handleExpired();
        return;
      } on Exception {
        // 补种失败不影响后续。
      }
    }

    await _reschedule();
  }

  bool _guardInterval() {
    final now = _now();
    if (_lastHarvestAt != null &&
        now.difference(_lastHarvestAt!) < _minInterval) {
      return false;
    }
    return true;
  }

  void _handleExpired() {
    if (_settings.notifyAuthExpired) {
      _notifications.show('登录已失效', '自动化已停止，请重新登录');
    }
  }
}

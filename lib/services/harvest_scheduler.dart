/// 收菜调度器：识别最近成熟作物，到点触发收菜，成功后延迟补种。
library;

import 'dart:async';

import 'package:hyb_farm_desktop/api/api_client.dart';
import 'package:hyb_farm_desktop/api/farm_api.dart';
import 'package:hyb_farm_desktop/core/constants.dart';
import 'package:hyb_farm_desktop/core/operation_coordinator.dart';
import 'package:hyb_farm_desktop/services/harvest_log.dart';
import 'package:hyb_farm_desktop/services/notification_service.dart';
import 'package:hyb_farm_desktop/services/replant_service.dart';
import 'package:hyb_farm_desktop/state/farm_state.dart';
import 'package:hyb_farm_desktop/state/connection_state_store.dart';
import 'package:hyb_farm_desktop/state/settings_state.dart';

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
    DateTime Function() now = DateTime.now,
  }) : _api = api,
       _farmState = farmState,
       _settings = settings,
       _coordinator = coordinator,
       _replant = replant,
       _notifications = notifications,
       _harvestLog = harvestLog,
       _connectionStore = connectionStore,
       _now = now;

  final FarmApi _api;
  final FarmState _farmState;
  final SettingsState _settings;
  final OperationCoordinator _coordinator;
  final ReplantService _replant;
  final NotificationService _notifications;
  final HarvestLog _harvestLog;
  final ConnectionStateStore _connectionStore;
  final DateTime Function() _now;

  Timer? _matureTimer;
  Timer? _fallbackTimer;
  DateTime? _lastHarvestAt;
  bool _running = false;

  /// 最小收菜间隔守卫，避免多个触发源叠加请求。
  static const _minInterval = Duration(seconds: 30);

  void start() {
    if (_running) return;
    _running = true;
    _farmState.setAutomation(AutomationStatus.running);
    _fallbackTimer = Timer.periodic(
      kFallbackPollInterval,
      (_) => _reschedule(),
    );
    _reschedule();
  }

  void stop() {
    _running = false;
    _matureTimer?.cancel();
    _fallbackTimer?.cancel();
    _farmState.setAutomation(AutomationStatus.paused);
  }

  /// 拉取作物并安排下一次成熟任务；失败交由兜底定时器重试。
  Future<void> _reschedule() async {
    _matureTimer?.cancel();
    if (!_running) return;
    if (!_connectionStore.canRunAutomation) return;
    try {
      await _farmState.refresh();
    } on AuthExpiredException {
      _handleExpired();
      return;
    } on Exception {
      return;
    }

    final next = _farmState.nextMatureIn;
    if (next == null || next <= 0) return;
    _matureTimer = Timer(Duration(seconds: next), _onMature);
  }

  void _onMature() {
    if (!_running) return;
    _coordinator.run(_harvestFlow);
  }

  Future<void> _harvestFlow() async {
    if (!_running || !_connectionStore.canRunAutomation) return;
    if (!_guardInterval()) return;

    // 收菜前刷新一次，确保成熟地块快照是最新的。内存里的 remainingTime/isMature
    // 是上次 fetch 的静态快照、到点不会自减，直接快照会把刚成熟的作物漏记。
    try {
      await _farmState.refresh();
    } on AuthExpiredException {
      _handleExpired();
      return;
    } on Exception {
      // 刷新失败用旧数据兜底，继续尝试收菜。
    }

    // 收菜前快照成熟地块，用于成功后的类型次数统计。
    final matureBefore =
        _farmState.crops?.crops.where((c) => c.mature && !c.isEmpty).toList() ??
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
        await _farmState.refresh();
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

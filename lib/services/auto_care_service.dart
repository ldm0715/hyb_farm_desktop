/// 自动务农服务：低频检查 debuff，存在则调用 care/all。
///
/// 同时是务农调度的唯一来源：持有定时器，暴露 [nextCareAt] 供 UI 展示倒计时。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hyb_farm_desktop/api/api_client.dart';
import 'package:hyb_farm_desktop/api/farm_api.dart';
import 'package:hyb_farm_desktop/core/operation_coordinator.dart';
import 'package:hyb_farm_desktop/core/request_backoff.dart';
import 'package:hyb_farm_desktop/services/care_log.dart';
import 'package:hyb_farm_desktop/state/connection_state_store.dart';
import 'package:hyb_farm_desktop/state/farm_state.dart';

class AutoCareService extends ChangeNotifier {
  AutoCareService({
    required FarmApi api,
    required FarmState farmState,
    required OperationCoordinator coordinator,
    required CareLog careLog,
    required ConnectionStateStore connectionStore,
    RequestBackoff? backoff,
    DateTime Function() now = DateTime.now,
  }) : _api = api,
       _farmState = farmState,
       _coordinator = coordinator,
       _careLog = careLog,
       _connectionStore = connectionStore,
       _backoff = backoff ?? RequestBackoff(),
       _now = now;

  final FarmApi _api;
  final FarmState _farmState;
  final OperationCoordinator _coordinator;
  final CareLog _careLog;
  final ConnectionStateStore _connectionStore;
  final RequestBackoff _backoff;
  final DateTime Function() _now;

  /// 务农写请求的退避门控键。
  static const _careKey = '/api/farm/care/all';

  Timer? _timer;
  int? _intervalMinutes;
  DateTime? _nextCareAt;

  /// 下一次务农检查的绝对时刻；未运行时为 null。
  DateTime? get nextCareAt => _nextCareAt;

  /// 是否正在按间隔运行。
  bool get running => _timer != null;

  /// 启动务农调度。间隔未变且已在运行时直接返回，避免重置倒计时。
  void start(int intervalMinutes) {
    if (running && _intervalMinutes == intervalMinutes) return;
    stop();
    _intervalMinutes = intervalMinutes;
    _scheduleNext();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _nextCareAt = null;
    notifyListeners();
  }

  void _scheduleNext() {
    _nextCareAt = _now().add(Duration(minutes: _intervalMinutes!));
    notifyListeners();
    _timer = Timer(Duration(minutes: _intervalMinutes!), _onTick);
  }

  Future<void> _onTick() async {
    _nextCareAt = null;
    notifyListeners();
    await checkAndCare();
    // 检查期间可能被 stop()（连接失效/用户关闭开关），仅在仍运行时重排。
    if (running) _scheduleNext();
  }

  /// 检查并处理 debuff；无 debuff 时不做任何事。
  Future<void> checkAndCare() async {
    if (!_connectionStore.canRunAutomation) return;

    // 先刷新拿最新快照再判 debuff：内存里的 crops 是上次 fetch 的静态快照，
    // 若只有自动务农、没有自动收菜的轮询去喂数据，debuff 会永远不被「看见」。
    try {
      await _farmState.refreshCrops(force: true);
    } on AuthExpiredException {
      _farmState.setLastResult('登录已失效');
      return;
    } on Exception {
      // 刷新失败（网络等）：连接状态已由 ApiClient 上报，跳过本次。
      return;
    }

    if (!_farmState.hasDebuff) return;
    // 务农写请求纳入退避：退避期内不重试，等待下一次务农 tick。
    if (!_backoff.allowedAt(_careKey, _now())) return;

    await _coordinator.run(() async {
      try {
        final result = await _api.careAll();
        _farmState.setLastResult(
          '务农：处理 ${result.processed} 块地，消耗 ${result.energySpent} 精力',
        );
        try {
          await _careLog.record(result.byKind);
        } on Exception {
          // 统计记录失败不影响主流程。
        }
        await _farmState.refreshCrops(force: true);
      } on AuthExpiredException {
        _farmState.setLastResult('登录已失效');
      } on Exception catch (e) {
        _farmState.setLastResult('务农失败：$e');
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

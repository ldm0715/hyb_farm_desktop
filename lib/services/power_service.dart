/// 电源通道桥 + 睡眠阻止状态机。
///
/// 通道 `hyb_farm/power`（双向 MethodChannel）：
///  - 原生 → Dart：`suspend` / `resume`（带 event type）推送，resume 已按 [kResumeDebounce] 去抖。
///  - Dart → 原生：`setSleepPrevention(bool)` 调用 `SetThreadExecutionState`。
///
/// 睡眠阻止是异步串行状态机：`_desiredState` 为最新目标、`_appliedState` 为已确认
/// 应用的平台状态，`_syncTail` 串行化底层平台调用。快速切换（true→false→true）最终
/// 收敛到最新目标；平台调用失败不标记为 held，且吞异常记日志不产生未处理异常。
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:hyb_farm_desktop/core/constants.dart';
import 'package:hyb_farm_desktop/core/log/app_logger.dart';

/// 原生 → Dart 的电源事件类型。
enum PowerEvent { suspend, resume }

class PowerService {
  PowerService({MethodChannel? channel, DateTime Function() now = DateTime.now})
      : _channel = channel ?? const MethodChannel('hyb_farm/power'),
        _now = now;

  final MethodChannel _channel;
  final DateTime Function() _now;

  final StreamController<PowerEvent> _events =
      StreamController<PowerEvent>.broadcast();

  DateTime? _lastResumeAt;

  // —— 睡眠阻止异步串行状态机 ——
  bool _desiredState = false;
  bool _appliedState = false;
  Future<void>? _syncTail;
  String? _releaseReason;

  bool _disposed = false;

  /// 原生 → Dart 电源事件（resume 已按 [kResumeDebounce] 去抖）。
  Stream<PowerEvent> get events => _events.stream;

  /// 注册原生回调（幂等）。在 `main()` 中 `await`。
  Future<void> init() async {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  /// 释放睡眠阻止、清理 handler 与事件流（幂等）。
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await releaseSleepPrevention(reason: 'dispose');
    _channel.setMethodCallHandler(null);
    await _events.close();
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    if (_disposed) return;
    if (call.method == 'suspend') {
      // 仅 best-effort 日志：挂起前未必能送达 Dart，不依赖它做关键逻辑。
      AppLog.i('Power', 'suspend');
      if (!_events.isClosed) _events.add(PowerEvent.suspend);
      return;
    }
    if (call.method == 'resume') {
      final type =
          call.arguments is String ? call.arguments as String : 'unknown';
      AppLog.i('Power', 'resume', {'event': type});
      // 去抖：短时间多条 resume（PBT_APMRESUMEAUTOMATIC/PBT_APMRESUMESUSPEND
      // 可能重复到达）只保留一次。
      final now = _now();
      if (_lastResumeAt != null &&
          now.difference(_lastResumeAt!) < kResumeDebounce) {
        return;
      }
      _lastResumeAt = now;
      if (!_events.isClosed) _events.add(PowerEvent.resume);
    }
  }

  /// 更新睡眠阻止目标。
  ///
  /// [automationRunning] 语义由调用方保证为 `automationDesired && sessionValid`，
  /// 即不因瞬时网络错误（networkError/serverError）而释放。
  Future<void> syncSleepPrevention({
    required bool enabled,
    required bool automationRunning,
  }) {
    _desiredState = enabled && automationRunning;
    return _drain();
  }

  /// 强制释放（退出登录 / dispose / 应用退出）。幂等。
  Future<void> releaseSleepPrevention({required String reason}) {
    _releaseReason = reason;
    _desiredState = false;
    return _drain();
  }

  Future<void> _drain() {
    final tail = _syncTail ?? Future<void>.value();
    final next = tail.then((_) => _applyToDesired());
    // 兜底：吞掉任何意外错误，防止 tail 断裂；_applyToDesired 自身已吞异常。
    _syncTail = next.catchError((_) {});
    return next;
  }

  Future<void> _applyToDesired() async {
    while (_appliedState != _desiredState) {
      final ok = await _tryApply(_desiredState);
      if (!ok) return; // 失败停止本轮，等下次 sync/release 重试。
    }
  }

  Future<bool> _tryApply(bool target) async {
    try {
      await _channel.invokeMethod('setSleepPrevention', target);
      _appliedState = target;
      AppLog.i(
        'SleepPrevention',
        target ? 'acquired' : 'released',
        target ? null : {'reason': _releaseReason ?? 'automation_changed'},
      );
      _releaseReason = null;
      return true;
    } on MissingPluginException {
      // 非 Windows：安全 no-op，标记已应用避免反复调用。
      _appliedState = target;
      return true;
    } on PlatformException catch (e) {
      AppLog.e('SleepPrevention', 'set failed', error: e);
      return false;
    } on Exception catch (e) {
      AppLog.e('SleepPrevention', 'set failed', error: e);
      return false;
    }
  }
}

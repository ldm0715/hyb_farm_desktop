/// 连接状态 Store：持有当前连接/会话状态与最近一次诊断，供 UI 与自动化门控消费。
library;

import 'package:flutter/foundation.dart';
import 'package:hyb_farm_desktop/core/farm_connection_state.dart';
import 'package:hyb_farm_desktop/core/request_failure_classifier.dart';

/// 统一的连接状态单一数据源。ApiClient 每次请求分类后经回调写入这里。
class ConnectionStateStore extends ChangeNotifier {
  FarmConnectionState _state = FarmConnectionState.healthy;
  ConnectionDiagnostics? _diagnostics;
  DateTime? _lastCheckedAt;
  DateTime? _retryAfterUntil;

  FarmConnectionState get state => _state;
  ConnectionDiagnostics? get diagnostics => _diagnostics;

  /// 最近一次请求分类时刻（healthy 状态下点击 chip 展示）。
  DateTime? get lastCheckedAt => _lastCheckedAt;

  /// 限流恢复时刻（rateLimited 时展示「将于 xx:xx 自动重试」）。
  DateTime? get retryAfterUntil => _retryAfterUntil;

  /// 自动化任务是否可运行（仅 healthy 允许）。
  bool get canRunAutomation => _state == FarmConnectionState.healthy;

  /// 是否处于需要人工处理的状态（challenge/auth/rateLimit）。
  bool get needsAttention =>
      _state == FarmConnectionState.challengeRequired ||
      _state == FarmConnectionState.authRequired ||
      _state == FarmConnectionState.rateLimited;

  /// 应用一次分类结果。rateLimited 时若带 retryAfter 则记录恢复时刻。
  void apply(ClassificationResult result) {
    _state = result.state;
    _diagnostics = result.diagnostics;
    _lastCheckedAt = DateTime.now();
    if (result.state == FarmConnectionState.rateLimited &&
        result.diagnostics.retryAfter != null) {
      _retryAfterUntil = result.diagnostics.retryAfter;
    } else if (result.state != FarmConnectionState.rateLimited) {
      _retryAfterUntil = null;
    }
    notifyListeners();
  }

  /// 标记为需要人机验证（验证流程/UI 主动触发）。
  void markChallenge() {
    _state = FarmConnectionState.challengeRequired;
    _lastCheckedAt = DateTime.now();
    notifyListeners();
  }

  /// 标记为健康（验证成功或健康检查通过）。
  void markHealthy() {
    _state = FarmConnectionState.healthy;
    _diagnostics = null;
    _retryAfterUntil = null;
    _lastCheckedAt = DateTime.now();
    notifyListeners();
  }

  /// 限流恢复展示文案；非 rateLimited 返回空串。
  String get retryAfterLabel {
    final until = _retryAfterUntil;
    if (_state != FarmConnectionState.rateLimited || until == null) return '';
    final diff = until.difference(DateTime.now());
    if (diff.isNegative) return '';
    final hh = until.hour.toString().padLeft(2, '0');
    final mm = until.minute.toString().padLeft(2, '0');
    return '将于 $hh:$mm 自动重试';
  }
}

/// 分作用域请求退避：全局（网络）/ 限流（429）/ 单资源（5xx）。
///
/// 纯 Dart、可注入 [now]，与 [ConnectionStateStore] 解耦。由 main.dart 在
/// `ApiClient.onClassified` 里一并驱动，供自动化路径（HarvestScheduler /
/// AutoCareService）在发请求前用 [allowedAt] 门控。
///
/// 作用域（约束 #3）：
///  - 网络错误（networkError）→ 全局退避（一次网络失败影响所有目标站请求）；
///  - 429 → 采用分类器已解析的 Retry-After，默认全局；
///  - 5xx → 按 resource/endpoint 键退避（crops 5xx 只退避 crops）；
///  - 成功只重置对应作用域：某 endpoint 成功清该 endpoint 退避，全局网络成功清全局。
///
/// 退避只门控自动化路径；用户主动操作（登录/手动刷新/写操作/challenge 验证）
/// 不经此退避——门控放在自动化层而非 ApiClient，天然隔离。
library;

import 'package:hyb_farm_desktop/core/constants.dart';
import 'package:hyb_farm_desktop/core/farm_connection_state.dart';
import 'package:hyb_farm_desktop/core/request_failure_classifier.dart';

/// 单资源退避状态。
class _ScopeBackoff {
  int failures = 0;
  DateTime? nextAllowAt;
}

class RequestBackoff {
  RequestBackoff({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  int _networkFailures = 0;
  DateTime? _networkNextAllowAt;
  DateTime? _rateLimitNextAllowAt;
  final Map<String, _ScopeBackoff> _serverBackoff = {};

  /// 记录一次分类结果，按状态与作用域更新退避。resourceKey 为资源/endpoint 键
  /// （如 `/api/farm/crops`），5xx 退避按此隔离；缺省时从诊断 URL 提取 path。
  void record(ClassificationResult r, {String? resourceKey}) {
    final key = resourceKey ?? _pathOf(r.diagnostics.url);
    switch (r.state) {
      case FarmConnectionState.healthy:
        _networkFailures = 0;
        _networkNextAllowAt = null;
        _rateLimitNextAllowAt = null;
        if (key.isNotEmpty) _serverBackoff.remove(key);
      case FarmConnectionState.networkError:
        _networkFailures++;
        _networkNextAllowAt = _now().add(_delay(_networkFailures));
      case FarmConnectionState.rateLimited:
        _rateLimitNextAllowAt =
            r.diagnostics.retryAfter ?? _now().add(_delay(1));
      case FarmConnectionState.serverError:
        if (key.isNotEmpty) {
          final entry = _serverBackoff[key] ?? _ScopeBackoff();
          entry.failures++;
          entry.nextAllowAt = _now().add(_delay(entry.failures));
          _serverBackoff[key] = entry;
        }
      case FarmConnectionState.authRequired:
      case FarmConnectionState.challengeRequired:
      case FarmConnectionState.unknownError:
        break;
    }
  }

  /// 从诊断 URL（scheme://host/path）提取 path 作为资源键。
  static String _pathOf(String? url) {
    if (url == null || url.isEmpty) return '';
    final uri = Uri.tryParse(url);
    if (uri == null) return '';
    return uri.path.isEmpty ? '/' : uri.path;
  }

  /// 该资源此刻是否可发出自动化请求。
  bool allowedAt(String resourceKey, DateTime now) {
    final network = _networkNextAllowAt;
    if (network != null && now.isBefore(network)) return false;
    final rate = _rateLimitNextAllowAt;
    if (rate != null && now.isBefore(rate)) return false;
    final server = _serverBackoff[resourceKey];
    if (server != null &&
        server.nextAllowAt != null &&
        now.isBefore(server.nextAllowAt!)) {
      return false;
    }
    return true;
  }

  /// 距下一次可发出请求的剩余时长（已到期返回 Duration.zero）。
  Duration retryIn(String resourceKey, DateTime now) {
    var remaining = Duration.zero;
    Duration max(Duration a, Duration b) => a > b ? a : b;

    final network = _networkNextAllowAt;
    if (network != null && now.isBefore(network)) {
      remaining = max(remaining, network.difference(now));
    }
    final rate = _rateLimitNextAllowAt;
    if (rate != null && now.isBefore(rate)) {
      remaining = max(remaining, rate.difference(now));
    }
    final server = _serverBackoff[resourceKey];
    if (server != null &&
        server.nextAllowAt != null &&
        now.isBefore(server.nextAllowAt!)) {
      remaining = max(remaining, server.nextAllowAt!.difference(now));
    }
    return remaining;
  }

  /// 指数退避：base × 2^(failures-1)，上限 [kBackoffMaxDelay]。
  Duration _delay(int failures) {
    var d = kBackoffBaseDelay;
    for (var i = 1; i < failures; i++) {
      d = d * 2;
      if (d >= kBackoffMaxDelay) return kBackoffMaxDelay;
    }
    return d;
  }
}

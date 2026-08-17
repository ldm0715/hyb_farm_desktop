/// 连接/会话状态模型：统一的接口健康状态，取代单一 isLoggedIn/needLogin 布尔。
///
/// 由 [ConnectionStateStore] 持有运行时状态，分类器 [request_failure_classifier.dart]
/// 决定每个请求应落入哪个状态。
library;

/// 连接/会话状态。
enum FarmConnectionState {
  /// 请求正常、会话有效。
  healthy,

  /// 明确需要重新登录 / Cookie 失效（后端 401）。
  authRequired,

  /// 检测到 Cloudflare 人机验证。
  challengeRequired,

  /// 频率限制 / 暂时受限。
  rateLimited,

  /// 网络连接、超时、DNS 等错误。
  networkError,

  /// 5xx 或目标站服务异常。
  serverError,

  /// 无法分类的错误。
  unknownError,
}

/// 每个状态的用户可读中文标题。
extension FarmConnectionStateTitle on FarmConnectionState {
  String get title => switch (this) {
    FarmConnectionState.healthy => '正常',
    FarmConnectionState.authRequired => '需要登录',
    FarmConnectionState.challengeRequired => '需验证',
    FarmConnectionState.rateLimited => '请求受限',
    FarmConnectionState.networkError => '网络异常',
    FarmConnectionState.serverError => '服务异常',
    FarmConnectionState.unknownError => '未知错误',
  };

  /// 用户可读中文说明。
  String get description => switch (this) {
    FarmConnectionState.healthy => '请求正常，会话有效',
    FarmConnectionState.authRequired => '登录 Cookie 已失效，请重新登录',
    FarmConnectionState.challengeRequired => '访问受到 Cloudflare 安全验证保护',
    FarmConnectionState.rateLimited => '请求过于频繁，已暂时受限',
    FarmConnectionState.networkError => '网络连接失败或超时',
    FarmConnectionState.serverError => '目标服务异常，请稍后再试',
    FarmConnectionState.unknownError => '发生无法分类的错误',
  };

  /// 是否暂停会产生目标站请求的自动化任务。
  bool get pausesAutomation => switch (this) {
    FarmConnectionState.healthy => false,
    FarmConnectionState.authRequired => true,
    FarmConnectionState.challengeRequired => true,
    FarmConnectionState.rateLimited => true,
    FarmConnectionState.networkError => true,
    FarmConnectionState.serverError => true,
    FarmConnectionState.unknownError => false,
  };

  /// 账户状态卡副标题（真实连接状态的可读中文，颜色由 UI 层映射）。
  String get accountSubtitle => switch (this) {
    FarmConnectionState.healthy => '登录状态正常',
    FarmConnectionState.authRequired => '需要重新登录',
    FarmConnectionState.challengeRequired => '需验证',
    FarmConnectionState.rateLimited => '请求受限，请稍后重试',
    FarmConnectionState.networkError => '无法检查账户状态',
    FarmConnectionState.serverError => '服务异常，请稍后重试',
    FarmConnectionState.unknownError => '无法检查账户状态',
  };

  /// 推荐操作（简短中文）。
  String get recommendedAction => switch (this) {
    FarmConnectionState.healthy => '',
    FarmConnectionState.authRequired => '重新登录',
    FarmConnectionState.challengeRequired => '完成人机验证',
    FarmConnectionState.rateLimited => '稍后重试',
    FarmConnectionState.networkError => '重试',
    FarmConnectionState.serverError => '稍后重试',
    FarmConnectionState.unknownError => '查看诊断',
  };
}

/// 分类诊断信息（脱敏、截断后）。
class ConnectionDiagnostics {
  const ConnectionDiagnostics({
    this.statusCode,
    this.url,
    this.contentType,
    this.hasCfMitigated = false,
    this.hasCfRay = false,
    this.bodyHits = const [],
    this.retryAfter,
    this.reason = '',
    this.confidence = 0.0,
  });

  /// HTTP 状态码；网络错误时为 0。
  final int? statusCode;

  /// 脱敏后的 URL（仅 host + path，query 参数打码）。
  final String? url;

  /// 响应 content-type。
  final String? contentType;

  /// 是否存在 `cf-mitigated` 响应头。
  final bool hasCfMitigated;

  /// 是否存在 `cf-ray` 响应头。
  final bool hasCfRay;

  /// body 命中的特征列表（脱敏后的特征名，非原文）。
  final List<String> bodyHits;

  /// 限流重试时刻（解析自 Retry-After）；非限流时为 null。
  final DateTime? retryAfter;

  /// 分类原因（脱敏描述）。
  final String reason;

  /// 分类置信度（0.0~1.0）。
  final double confidence;
}

/// 将 URL 脱敏为 `scheme://host/path`，丢弃 query 参数。
String sanitizeUrl(String? url) {
  if (url == null || url.isEmpty) return '';
  final uri = Uri.tryParse(url);
  if (uri == null) return '';
  final host = uri.host;
  if (host.isEmpty) return '';
  final scheme = uri.scheme.isEmpty ? 'https' : uri.scheme;
  final path = uri.path.isEmpty ? '/' : uri.path;
  return '$scheme://$host$path';
}

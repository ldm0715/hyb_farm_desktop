/// 请求失败分类器：把 HTTP 状态码 / 响应头 / 响应体分类为统一的连接状态。
///
/// 纯函数、无状态，便于单元测试。分类优先级严格递减：
/// challenge → auth → rateLimit → serverError → networkError → unknownError。
library;

import 'dart:convert';

import 'package:hyb_farm_desktop/core/farm_connection_state.dart';

/// body 检测的最大字符数，防止大响应造成内存问题。
const int kBodyInspectLimit = 32 * 1024;

/// 分类结果。
class ClassificationResult {
  const ClassificationResult({
    required this.state,
    required this.reason,
    required this.confidence,
    required this.diagnostics,
  });

  final FarmConnectionState state;
  final String reason;
  final double confidence;
  final ConnectionDiagnostics diagnostics;
}

/// Cloudflare challenge 强信号 body 标记（小写）。
const Set<String> _challengeStrongMarkers = {
  '/cdn-cgi/challenge-platform/',
  'cf-turnstile',
  'cf_chl_',
};

/// Cloudflare challenge 弱信号文本特征（小写）。
const Set<String> _challengeTextMarkers = {
  'just a moment...',
  'checking your browser',
  'performing security verification',
  'attention required! | cloudflare',
};

/// 登录失效关键词（用于 message/code 匹配，小写 + 去空白后比较）。
const Set<String> _authKeywords = {
  '未登录',
  'token失效',
  'token过期',
  '登录失效',
  '登录已过期',
  '会话失效',
  '会话过期',
  'unauthorized',
  'notloggedin',
  'loginrequired',
  'sessionexpired',
};

/// 限流关键词（小写 + 去空白后比较）。
const Set<String> _rateLimitKeywords = {
  '请求过快',
  '请求过于频繁',
  '过于频繁',
  '稍后再试',
  '请稍后重试',
  'ratelimit',
  'ratelimited',
  'toomanyrequests',
  'throttled',
};

/// 对字符串做小写 + 去空白归一化，用于中文/英文关键词模糊匹配。
String _normalize(String? s) => (s ?? '').toLowerCase().replaceAll(' ', '');

/// 大小写不敏感地取 header 首个值；缺失返回 null。
String? _header(Map<String, List<String>>? headers, String name) {
  if (headers == null) return null;
  final target = name.toLowerCase();
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == target) {
      final values = entry.value;
      if (values.isNotEmpty) return values.first;
    }
  }
  return null;
}

/// 大小写不敏感地判断 header 是否存在。
bool _hasHeader(Map<String, List<String>>? headers, String name) =>
    _header(headers, name) != null;

/// 把响应体转换为可检测的字符串（截断到 [kBodyInspectLimit]）。
String _bodyText(Object? body) {
  String text;
  if (body == null) {
    text = '';
  } else if (body is String) {
    text = body;
  } else if (body is Map || body is List) {
    try {
      text = jsonEncode(body);
    } catch (_) {
      text = body.toString();
    }
  } else {
    text = body.toString();
  }
  if (text.length > kBodyInspectLimit) {
    text = text.substring(0, kBodyInspectLimit);
  }
  return text;
}

/// 从 `{success:false, error:{code,message}}` 结构提取业务码/消息。
(int?, String?) _extractBusiness(Object? body) {
  if (body is! Map) return (null, null);
  final success = body['success'];
  if (success != false) return (null, null);
  final err = body['error'];
  if (err is! Map) return (null, null);
  final code = err['code'] is num ? (err['code'] as num).toInt() : null;
  final message = err['message'] is String ? err['message'] as String : null;
  return (code, message);
}

/// 解析 Retry-After：纯数字当秒数，HTTP 日期用 [DateTime.parse]。
DateTime? _parseRetryAfter(String? value, DateTime now) {
  if (value == null || value.isEmpty) return null;
  final v = value.trim();
  final seconds = int.tryParse(v);
  if (seconds != null) return now.add(Duration(seconds: seconds));
  final parsed = DateTime.tryParse(v);
  return parsed;
}

/// 分类单个请求。各字段均可空，由调用方按实际响应填充。
ClassificationResult classifyRequest({
  int? statusCode,
  Map<String, List<String>>? headers,
  Object? body,
  String? contentType,
  String? finalUrl,
  int? businessCode,
  String? businessMessage,
  DateTime? now,
}) {
  final clock = now ?? DateTime.now();
  final status = statusCode ?? 0;
  final bodyRaw = _bodyText(body);
  final bodyLower = bodyRaw.toLowerCase();
  final ctype = (contentType ?? '').toLowerCase();
  final url = sanitizeUrl(finalUrl);

  // 从 body 结构补充业务码/消息（若调用方未显式传入）。
  var bCode = businessCode;
  var bMessage = businessMessage;
  if (bMessage == null) {
    final (c, m) = _extractBusiness(body);
    bCode ??= c;
    bMessage = m;
  }

  final cfMitigated = _header(headers, 'cf-mitigated');
  final hasCfMitigatedChallenge =
      cfMitigated != null && cfMitigated.toLowerCase().contains('challenge');
  final hasCfRay = _hasHeader(headers, 'cf-ray');
  final serverIsCloudflare =
      (_header(headers, 'server') ?? '').toLowerCase() == 'cloudflare';

  final List<String> bodyHits = [];

  // —— 优先级 1：Cloudflare Challenge ——
  final urlHasChallenge =
      finalUrl?.contains('/cdn-cgi/challenge-platform/') ?? false;
  final strongMarkerHit = _challengeStrongMarkers.any(bodyLower.contains);
  final strongChallenge =
      hasCfMitigatedChallenge || urlHasChallenge || strongMarkerHit;

  if (strongChallenge) {
    for (final m in _challengeStrongMarkers) {
      if (bodyLower.contains(m)) bodyHits.add(m);
    }
    if (urlHasChallenge) bodyHits.add('url:/cdn-cgi/challenge-platform/');
    if (hasCfMitigatedChallenge) bodyHits.add('cf-mitigated:challenge');
    return ClassificationResult(
      state: FarmConnectionState.challengeRequired,
      reason: '命中 Cloudflare challenge 强信号',
      confidence: 0.95,
      diagnostics: ConnectionDiagnostics(
        statusCode: status,
        url: url,
        contentType: contentType,
        hasCfMitigated: hasCfMitigatedChallenge,
        hasCfRay: hasCfRay,
        bodyHits: bodyHits,
        reason: '命中 Cloudflare challenge 强信号',
        confidence: 0.95,
      ),
    );
  }

  final textFeatureHit = _challengeTextMarkers.any(bodyLower.contains);
  final isHtmlStatus =
      (status == 403 || status == 429 || status == 503) &&
      ctype.contains('text/html');
  final cloudflareServed = serverIsCloudflare || hasCfRay;

  // 弱信号需组合：`server: cloudflare` / `cf-ray` 单独出现不能判 challenge，
  // 至少两个弱信号（文本特征 / Cloudflare 标识 / 403|429|503+text/html）才判定。
  var weakSignals = 0;
  if (textFeatureHit) weakSignals++;
  if (cloudflareServed) weakSignals++;
  if (isHtmlStatus) weakSignals++;
  final weakChallenge = weakSignals >= 2;

  if (weakChallenge) {
    for (final m in _challengeTextMarkers) {
      if (bodyLower.contains(m)) bodyHits.add(m);
    }
    if (serverIsCloudflare) bodyHits.add('server:cloudflare');
    if (hasCfRay) bodyHits.add('cf-ray');
    return ClassificationResult(
      state: FarmConnectionState.challengeRequired,
      reason: '命中 Cloudflare challenge 弱信号组合',
      confidence: 0.7,
      diagnostics: ConnectionDiagnostics(
        statusCode: status,
        url: url,
        contentType: contentType,
        hasCfMitigated: hasCfMitigatedChallenge,
        hasCfRay: hasCfRay,
        bodyHits: bodyHits,
        reason: '命中 Cloudflare challenge 弱信号组合',
        confidence: 0.7,
      ),
    );
  }

  // —— 优先级 2：登录失效 ——
  final messageNorm = _normalize(bMessage);
  final codeNorm = _normalize(bCode?.toString());
  final messageIsAuth = _authKeywords.any(messageNorm.contains);
  final codeIsAuth = _authKeywords.any(codeNorm.contains);
  final urlIsLogin =
      finalUrl != null &&
      finalUrl.toLowerCase().contains('/login') &&
      !urlHasChallenge;
  final bodyIsAuth = _authKeywords.any(bodyLower.contains);

  if (status == 401) {
    return _authResult(status, url, contentType, 'HTTP 401 Unauthorized', 0.99);
  }
  if (messageIsAuth || codeIsAuth) {
    return _authResult(status, url, contentType, '业务错误明确表示未登录/失效', 0.9);
  }
  if (urlIsLogin) {
    return _authResult(status, url, contentType, '跳转到登录页', 0.85);
  }
  if (status == 403 && bodyIsAuth) {
    return _authResult(status, url, contentType, '403 且 body 明确认证失败', 0.6);
  }

  // —— 优先级 3：Rate Limit ——
  final retryAfterHeader = _header(headers, 'retry-after');
  final bodyIsRateLimited = _rateLimitKeywords.any(bodyLower.contains);
  if (status == 429 || retryAfterHeader != null || bodyIsRateLimited) {
    final retryAfter = _parseRetryAfter(retryAfterHeader, clock);
    return ClassificationResult(
      state: FarmConnectionState.rateLimited,
      reason: status == 429
          ? 'HTTP 429 频率限制'
          : (retryAfterHeader != null ? 'Retry-After 限流' : 'body 明确限流'),
      confidence: 0.9,
      diagnostics: ConnectionDiagnostics(
        statusCode: status,
        url: url,
        contentType: contentType,
        retryAfter: retryAfter,
        reason: '请求过于频繁',
        confidence: 0.9,
      ),
    );
  }

  // —— 403 兜底：未命中 challenge/auth/rateLimit 分类的 403 默认判为疑似 Cloudflare 验证 ——
  // 其他无法识别的 403 仍需用户介入，保守视为疑似验证，防止自动化继续重试。
  if (status == 403) {
    return ClassificationResult(
      state: FarmConnectionState.challengeRequired,
      reason: 'HTTP 403（疑似 Cloudflare 验证）',
      confidence: 0.5,
      diagnostics: ConnectionDiagnostics(
        statusCode: status,
        url: url,
        contentType: contentType,
        reason: 'HTTP 403（疑似 Cloudflare 验证）',
        confidence: 0.5,
      ),
    );
  }

  // —— 优先级 4：服务端错误 ——
  if (status >= 500 && status <= 599) {
    return ClassificationResult(
      state: FarmConnectionState.serverError,
      reason: 'HTTP $status 服务端错误',
      confidence: 0.95,
      diagnostics: ConnectionDiagnostics(
        statusCode: status,
        url: url,
        contentType: contentType,
        reason: 'HTTP $status',
        confidence: 0.95,
      ),
    );
  }

  // —— 优先级 5：网络错误 ——
  if (status == 0) {
    return ClassificationResult(
      state: FarmConnectionState.networkError,
      reason: '网络连接失败/超时/DNS 错误',
      confidence: 0.9,
      diagnostics: ConnectionDiagnostics(
        statusCode: status,
        url: url,
        contentType: contentType,
        reason: '网络连接失败/超时/DNS 错误',
        confidence: 0.9,
      ),
    );
  }

  // —— 优先级 6：健康 / 未知 ——
  if (status >= 200 && status < 300) {
    return ClassificationResult(
      state: FarmConnectionState.healthy,
      reason: 'HTTP $status 正常',
      confidence: 1.0,
      diagnostics: ConnectionDiagnostics(
        statusCode: status,
        url: url,
        contentType: contentType,
        reason: 'HTTP $status',
        confidence: 1.0,
      ),
    );
  }

  return ClassificationResult(
    state: FarmConnectionState.unknownError,
    reason: '无法分类（HTTP $status）',
    confidence: 0.3,
    diagnostics: ConnectionDiagnostics(
      statusCode: status,
      url: url,
      contentType: contentType,
      reason: '无法分类（HTTP $status）',
      confidence: 0.3,
    ),
  );
}

ClassificationResult _authResult(
  int status,
  String? url,
  String? contentType,
  String reason,
  double confidence,
) => ClassificationResult(
  state: FarmConnectionState.authRequired,
  reason: reason,
  confidence: confidence,
  diagnostics: ConnectionDiagnostics(
    statusCode: status,
    url: url,
    contentType: contentType,
    reason: reason,
    confidence: confidence,
  ),
);

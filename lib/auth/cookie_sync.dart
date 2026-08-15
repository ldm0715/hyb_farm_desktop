/// Cookie 双向同步：在 HTTP 客户端（单字符串 header）与 WebView Cookie Store 之间迁移。
///
/// HTTP 侧 Cookie 是纯字符串 `name=value; name=value`，存于 flutter_secure_storage；
/// WebView 侧是 flutter_inappwebview 的 CookieManager。两者不共享存储，故需手动同步。
///
/// 降级策略：HTTP 侧持久化格式是纯字符串，无法保留 expires/path/secure/httpOnly/sameSite，
/// 导出回 header 时只保留 name=value；导入 WebView 时按默认 domain/path 设置。
library;

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:hyb_farm_desktop/core/constants.dart';

/// 目标 Cookie 域（kBaseUrl 为 https://cdk.hybgzs.com）。
const String kCookieDomain = '.hybgzs.com';

/// 把 HTTP Cookie header 字符串逐个导入 WebView Cookie Store。
///
/// 日志只记录 name/domain，不记录 value。返回成功导入的条数。
Future<int> importToWebview(String? cookieHeader) async {
  if (cookieHeader == null || cookieHeader.trim().isEmpty) return 0;
  final manager = CookieManager.instance();
  var imported = 0;
  for (final raw in cookieHeader.split(';')) {
    final pair = raw.trim();
    final eq = pair.indexOf('=');
    if (eq <= 0) continue;
    final name = pair.substring(0, eq).trim();
    final value = pair.substring(eq + 1).trim();
    if (name.isEmpty) continue;
    final ok = await manager.setCookie(
      url: WebUri(kBaseUrl),
      name: name,
      value: value,
      domain: kCookieDomain,
      path: '/',
    );
    if (ok) imported++;
  }
  return imported;
}

/// 从 WebView Cookie Store 导出目标域 Cookie，序列化回 header 字符串。
///
/// 保留 cf_clearance 与登录 Cookie；只返回 name=value，属性无法保留（见文件头注释）。
Future<String?> exportFromWebview() async {
  final manager = CookieManager.instance();
  var cookies = await manager.getCookies(url: WebUri(kBaseUrl));
  if (cookies.isEmpty) {
    cookies = await manager.getAllCookies();
  }
  final relevant = cookies.where(_isTargetDomain).toList();
  if (relevant.isEmpty) return null;
  return relevant.map((c) => '${c.name}=${_cookieValue(c)}').join('; ');
}

bool _isTargetDomain(Cookie c) {
  final d = c.domain?.toLowerCase() ?? '';
  return d.isEmpty || d == kCookieDomain || d.endsWith('hybgzs.com');
}

String _cookieValue(Cookie c) {
  final v = c.value;
  return v == null ? '' : v.toString();
}

/// 脱敏日志：只输出 name/domain/expires，绝不输出 value。
String sanitizeCookieLog(List<Cookie> cookies) => cookies
    .map(
      (c) =>
          '${c.name}@${c.domain ?? '-'}'
          '${c.expiresDate != null ? '(expires=${c.expiresDate})' : ''}',
    )
    .join(', ');

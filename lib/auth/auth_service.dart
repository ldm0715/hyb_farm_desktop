/// 认证服务：Cookie 校验、测活、失效判定与安全存储持久化。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hyb_farm_desktop/api/api_client.dart';
import 'package:hyb_farm_desktop/api/farm_api.dart';
import 'package:hyb_farm_desktop/api/models.dart';

/// 认证状态。
enum AuthStatus { unknown, checking, authenticated, expired }

/// 管理会话 Cookie：测活、持久化到系统安全存储、失效判定。
class AuthService extends ChangeNotifier {
  AuthService({
    required ApiClient client,
    FarmApi? api,
    FlutterSecureStorage? storage,
  }) : _client = client,
       _api = api,
       _storage = storage ?? const FlutterSecureStorage();

  static const _cookieKey = 'hyb_farm_cookie';

  final ApiClient _client;
  final FarmApi? _api;
  final FlutterSecureStorage _storage;

  AuthStatus _status = AuthStatus.unknown;
  AuthStatus get status => _status;

  /// 最近一次成功登录时间（ISO8601，仅用于展示）。
  String? _lastLoginAt;
  String? get lastLoginAt => _lastLoginAt;

  /// 当前内存中的 Cookie（用于设置页查看/修改）。
  String? get currentCookie => _client.cookie;

  /// 最近一次成功加载的登录用户信息。
  UserInfo? _userInfo;
  UserInfo? get userInfo => _userInfo;
  String get username => _userInfo?.username ?? '';
  String get avatar => _userInfo?.avatar ?? '';

  /// 校验 Cookie 格式：非空、含 key=value、不含换行等控制字符。
  static String? validateCookie(String? cookie) {
    final c = cookie?.trim() ?? '';
    if (c.isEmpty) return 'Cookie 不能为空';
    if (!c.contains('=')) return '格式错误：应为 key=value 形式';
    if (c.contains('\n') || c.contains('\r')) return '格式错误：含非法换行';
    return null;
  }

  /// 用给定 Cookie 测活：设置到客户端并调轻量受保护接口。
  ///
  /// 仅 `AuthExpiredException`（401/403）判定为失效；网络等临时错误返回
  /// false 但不判失效、不触发清除或反复登录提示。
  Future<bool> testCookie(String cookie) async {
    _status = AuthStatus.checking;
    notifyListeners();
    _client.setCookie(cookie);
    try {
      await _client.get('/api/farm/crops');
      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } on AuthExpiredException {
      _status = AuthStatus.expired;
      notifyListeners();
      return false;
    } on Exception {
      _status = AuthStatus.unknown;
      notifyListeners();
      return false;
    }
  }

  /// 保存 Cookie 到安全存储（仅在测活通过后调用）。
  Future<void> saveCookie(String cookie) async {
    await _storage.write(key: _cookieKey, value: cookie);
    _client.setCookie(cookie);
    _status = AuthStatus.authenticated;
    _lastLoginAt = DateTime.now().toIso8601String();
    notifyListeners();
    unawaited(loadUserInfo());
  }

  /// 拉取当前登录用户信息（用户名/头像）。失败静默，不改变认证状态。
  Future<void> loadUserInfo() async {
    final api = _api;
    if (api == null) return;
    try {
      _userInfo = await api.fetchUserInfo();
      notifyListeners();
    } on Exception {
      // 网络/未登录等失败均忽略，保持上一次的值或空。
    }
  }

  /// 测活并保存新 Cookie；测活通过才保存，失败不覆盖旧值。返回是否成功。
  Future<bool> updateCookie(String cookie) async {
    final ok = await testCookie(cookie);
    if (ok) {
      await saveCookie(cookie);
    }
    return ok;
  }

  /// 合并 WebView 导出的 Cookie 到现有会话：WebView 同名键覆盖，其余保留现有值，
  /// 确保 cf_clearance 与登录 Cookie 都被保留。合并后测活，通过才持久化。
  Future<bool> mergeCookie(String webviewCookie) async {
    final existing = currentCookie;
    final merged = _mergeCookieHeaders(existing, webviewCookie);
    final ok = await testCookie(merged);
    if (ok) {
      await saveCookie(merged);
    }
    return ok;
  }

  /// 把两个 `name=value; ...` 字符串合并为一个，后者同名键覆盖前者。
  static String _mergeCookieHeaders(String? base, String overlay) {
    final map = <String, String>{};
    void absorb(String? header) {
      if (header == null) return;
      for (final raw in header.split(';')) {
        final pair = raw.trim();
        final eq = pair.indexOf('=');
        if (eq <= 0) continue;
        final name = pair.substring(0, eq).trim();
        final value = pair.substring(eq + 1).trim();
        if (name.isNotEmpty) map[name] = value;
      }
    }

    absorb(base);
    absorb(overlay);
    return map.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  /// 启动时恢复：读取存储 Cookie 并测活。
  Future<bool> tryRestore() async {
    final cookie = await _storage.read(key: _cookieKey);
    if (cookie == null || cookie.isEmpty) {
      _status = AuthStatus.expired;
      notifyListeners();
      return false;
    }
    final ok = await testCookie(cookie);
    if (ok) {
      unawaited(loadUserInfo());
    }
    return ok;
  }

  /// 认证失效回调：清除内存 Cookie，但保留安全存储中的值供用户手动替换/清除。
  void onExpired() {
    _client.setCookie(null);
    _status = AuthStatus.expired;
    notifyListeners();
  }

  /// 用户主动清除 Cookie：删除存储值并清内存。
  Future<void> clearCookie() async {
    await _storage.delete(key: _cookieKey);
    _client.setCookie(null);
    _status = AuthStatus.expired;
    _lastLoginAt = null;
    _userInfo = null;
    notifyListeners();
  }
}

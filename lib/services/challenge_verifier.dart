/// Cloudflare 人机验证协调器：验证窗口的防抖、Cookie 导出 + 健康检查、状态恢复。
///
/// 不实现 CAPTCHA 自动识别、自动点击、浏览器自动化绕过、指纹伪造或代理轮换。
library;

import 'package:hyb_farm_desktop/api/api_client.dart';
import 'package:hyb_farm_desktop/api/farm_api.dart';
import 'package:hyb_farm_desktop/auth/auth_service.dart';
import 'package:hyb_farm_desktop/auth/cookie_sync.dart';
import 'package:hyb_farm_desktop/core/farm_connection_state.dart';
import 'package:hyb_farm_desktop/state/connection_state_store.dart';

/// 验证结果：供验证窗口据此提示或关闭。
enum ChallengeCheckResult {
  /// 验证成功，可恢复自动化。
  success,

  /// 仍命中 challenge，验证尚未完成或已失效。
  stillChallenged,

  /// 变成需要重新登录。
  authRequired,

  /// 网络/其他错误，未能确认。
  inconclusive,
}

/// 协调验证流程：防抖打开、导出 Cookie、健康检查、更新状态。
class ChallengeVerifier {
  ChallengeVerifier({
    required ConnectionStateStore store,
    required AuthService auth,
    required FarmApi api,
  }) : _store = store,
       _auth = auth,
       _api = api;

  final ConnectionStateStore _store;
  final AuthService _auth;
  final FarmApi _api;

  bool _checking = false;
  DateTime? _lastAutoCheck;

  /// 是否正在做健康检查。
  bool get checking => _checking;

  /// 健康检查：导出 WebView Cookie → 合并写回 → 轻量无副作用请求探测。
  ///
  /// 判定：不再命中 challenge 且非 auth 失效 → success；仍 challenge → stillChallenged；
  /// auth 失效 → authRequired；网络/其他 → inconclusive。
  Future<ChallengeCheckResult> checkNow() async {
    if (_checking) return ChallengeCheckResult.inconclusive;
    _checking = true;
    try {
      final cookie = await exportFromWebview();
      if (cookie != null && cookie.isNotEmpty) {
        await _auth.mergeCookie(cookie);
      }
      // 用 fetchCrops 做一次轻量健康检查。分类结果已经 ApiClient 上报到 store，
      // 这里按是否抛异常 + store 最终状态综合判定。
      try {
        await _api.fetchCrops();
      } on AuthExpiredException {
        return ChallengeCheckResult.authRequired;
      } catch (_) {
        // challenge/rateLimit/network 等：不在此判定成功，交给下方 store 状态。
      }

      final state = _store.state;
      if (state == FarmConnectionState.healthy) {
        return ChallengeCheckResult.success;
      }
      if (state == FarmConnectionState.challengeRequired) {
        return ChallengeCheckResult.stillChallenged;
      }
      if (state == FarmConnectionState.authRequired) {
        return ChallengeCheckResult.authRequired;
      }
      return ChallengeCheckResult.inconclusive;
    } finally {
      _checking = false;
    }
  }

  /// 辅助自动检查（URL 变化 / load finished 时调用），带 ≥3s 节流。
  Future<void> maybeAutoCheck() async {
    final now = DateTime.now();
    if (_lastAutoCheck != null &&
        now.difference(_lastAutoCheck!) < const Duration(seconds: 3)) {
      return;
    }
    _lastAutoCheck = now;
    await checkNow();
  }
}

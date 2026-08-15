/// Cloudflare 人工验证窗口：对话框内嵌 WebView，用户手动完成验证后点击检查。
///
/// 复用 webview_login.dart 的 showDialog + InAppWebView 模式。关闭不假定成功；
/// 只有「我已完成验证，立即检查」触发健康检查通过才判定成功。
library;

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:hyb_farm_desktop/auth/auth_service.dart';
import 'package:hyb_farm_desktop/auth/cookie_sync.dart';
import 'package:hyb_farm_desktop/core/constants.dart';
import 'package:hyb_farm_desktop/services/challenge_verifier.dart';
import 'package:hyb_farm_desktop/theme/farm_theme.dart';

/// 打开验证窗口，返回是否验证成功。
Future<bool> showChallengeDialog(
  BuildContext context, {
  required ChallengeVerifier verifier,
  required AuthService auth,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ChallengeDialog(verifier: verifier, auth: auth),
  ).then((v) => v ?? false);
}

class _ChallengeDialog extends StatefulWidget {
  const _ChallengeDialog({required this.verifier, required this.auth});

  final ChallengeVerifier verifier;
  final AuthService auth;

  @override
  State<_ChallengeDialog> createState() => _ChallengeDialogState();
}

class _ChallengeDialogState extends State<_ChallengeDialog> {
  bool _checking = false;
  String? _hint;
  bool _imported = false;

  @override
  void initState() {
    super.initState();
    _importCookies();
  }

  Future<void> _importCookies() async {
    final cookie = widget.auth.currentCookie;
    await importToWebview(cookie);
    _imported = true;
  }

  Future<void> _check() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _hint = null;
    });
    final result = await widget.verifier.checkNow();
    if (!mounted) return;
    switch (result) {
      case ChallengeCheckResult.success:
        Navigator.of(context).pop(true);
      case ChallengeCheckResult.stillChallenged:
        setState(() {
          _checking = false;
          _hint = '验证尚未完成或已失效，请重试';
        });
      case ChallengeCheckResult.authRequired:
        setState(() {
          _checking = false;
          _hint = '登录已失效，请重新登录';
        });
      case ChallengeCheckResult.inconclusive:
        setState(() {
          _checking = false;
          _hint = '无法确认验证状态，请稍后重试';
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('完成安全验证'),
      content: SizedBox(
        width: 480,
        height: 600,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                '请在此窗口中手动完成网站安全验证。'
                '验证完成后将自动恢复农场任务。'
                '本应用不会自动绕过或破解验证码。',
                style: FarmTextStyles.settingDescription,
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: InAppWebView(
                  initialUrlRequest: URLRequest(url: WebUri(kBaseUrl)),
                  onLoadStop: (_, url) =>
                      widget.verifier.maybeAutoCheck().ignore(),
                  onUpdateVisitedHistory: (_, url, isReload) =>
                      widget.verifier.maybeAutoCheck().ignore(),
                ),
              ),
            ),
            if (_hint != null) ...[
              const SizedBox(height: 8),
              Text(
                _hint!,
                style: FarmTextStyles.bodySecondary.copyWith(
                  color: FarmColorScheme.of(context).error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _checking || !_imported ? null : _check,
          child: Text(_checking ? '检查中…' : '我已完成验证，立即检查'),
        ),
      ],
    );
  }
}

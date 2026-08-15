/// 内置 WebView2 登录：展示登录页，完成后读取 Cookie 并返回 header 字符串。
library;

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:hyb_farm_desktop/core/constants.dart';
import 'package:hyb_farm_desktop/theme/farm_theme.dart';

/// 打开内置 WebView2 登录对话框，返回读到的 Cookie header；取消或失败返回 null。
Future<String?> showWebviewLogin(BuildContext context) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _WebviewLoginDialog(),
  );
}

class _WebviewLoginDialog extends StatefulWidget {
  const _WebviewLoginDialog();

  @override
  State<_WebviewLoginDialog> createState() => _WebviewLoginDialogState();
}

class _WebviewLoginDialogState extends State<_WebviewLoginDialog> {
  bool _reading = false;

  Future<void> _readCookie() async {
    setState(() => _reading = true);
    try {
      var cookies = await CookieManager.instance().getCookies(
        url: WebUri(kBaseUrl),
      );
      // getCookies 按 domain 过滤，可能漏掉某些 cookie；空时退化为读全部。
      if (cookies.isEmpty) {
        cookies = await CookieManager.instance().getAllCookies();
      }
      final header = cookies
          .where((c) => c.name.isNotEmpty)
          .map((c) => '${c.name}=${c.value}')
          .join('; ');
      if (mounted) Navigator.of(context).pop(header.isEmpty ? null : header);
    } catch (_) {
      if (mounted) Navigator.of(context).pop(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('登录 HYB Farm'),
      content: SizedBox(
        width: 480,
        height: 600,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                '请在弹出的网页中完成登录，然后点击「完成登录」。'
                'App 只读取登录 Cookie，不会保存你的账号密码。',
                style: FarmTextStyles.settingDescription,
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: InAppWebView(
                  initialUrlRequest: URLRequest(url: WebUri(kBaseUrl)),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _reading ? null : _readCookie,
          child: const Text('完成登录'),
        ),
      ],
    );
  }
}

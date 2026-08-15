/// 登录页：内置 WebView2 登录为主，手动粘贴 Cookie 兜底。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hyb_farm_desktop/auth/auth_service.dart';
import 'package:hyb_farm_desktop/auth/webview_login.dart';
import 'package:hyb_farm_desktop/theme/farm_theme.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _cookieController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _cookieController.dispose();
    super.dispose();
  }

  Future<void> _loginViaWebview() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final cookie = await showWebviewLogin(context);
    if (cookie == null || cookie.isEmpty) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    await _applyCookie(cookie);
  }

  Future<void> _loginViaManual() async {
    final cookie = _cookieController.text.trim();
    final err = AuthService.validateCookie(cookie);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    await _applyCookie(cookie);
  }

  Future<void> _applyCookie(String cookie) async {
    final auth = context.read<AuthService>();
    final ok = await auth.testCookie(cookie);
    if (!mounted) return;
    if (ok) {
      await auth.saveCookie(cookie);
    } else {
      setState(() {
        _busy = false;
        _error = '登录失效或无法连接，请重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final colors = FarmColorScheme.of(context);
    final lastLogin = auth.lastLoginAt;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'HYB Farm',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '后台自动收菜 / 补种 / 务农',
                    textAlign: TextAlign.center,
                    style: FarmTextStyles.pageDescription.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _busy ? null : _loginViaWebview,
                    icon: const Icon(Icons.language),
                    label: const Text('登录 HYB Farm'),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '登录成功后自动读取 Cookie，不会保存你的密码',
                    textAlign: TextAlign.center,
                    style: FarmTextStyles.bodySecondary.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ExpansionTile(
                    title: const Text('手动导入 Cookie'),
                    children: [
                      TextField(
                        controller: _cookieController,
                        maxLines: 3,
                        style: FarmTextStyles.monoText,
                        decoration: const InputDecoration(
                          hintText: '粘贴浏览器中的 Cookie（key=value; ...）',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: _busy ? null : _loginViaManual,
                        child: const Text('验证并保存'),
                      ),
                    ],
                  ),
                  if (lastLogin != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      '上次登录：$lastLogin',
                      textAlign: TextAlign.center,
                      style: FarmTextStyles.bodySecondary.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                  if (_busy) ...[
                    const SizedBox(height: 16),
                    const Center(child: CircularProgressIndicator()),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.error),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

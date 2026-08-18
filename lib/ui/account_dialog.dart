/// 账户与安全详情对话框：展示当前账号状态，提供 Cookie 填写登录与退出登录。
///
/// 复用 [showChallengeDialog] 的 `showDialog + AlertDialog` 模式，不引入 push 路由。
/// 账户/验证状态由 [ConnectionStateStore] 驱动；登录态与用户信息由 [AuthService] 提供。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hyb_farm_desktop/auth/auth_service.dart';
import 'package:hyb_farm_desktop/core/farm_connection_state.dart';
import 'package:hyb_farm_desktop/services/challenge_verifier.dart';
import 'package:hyb_farm_desktop/state/connection_state_store.dart';
import 'package:hyb_farm_desktop/theme/farm_theme.dart';
import 'package:hyb_farm_desktop/ui/challenge_dialog.dart';
import 'package:hyb_farm_desktop/ui/widgets/vip_avatar.dart';

/// 打开账户与安全详情对话框。
Future<void> showAccountDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _AccountDialog(),
  );
}

/// 账户状态语义色映射：颜色只作辅助，必须伴随文字（见 [FarmConnectionState.accountSubtitle]）。
Color accountStatusColor(FarmColorScheme colors, FarmConnectionState state) =>
    switch (state) {
      FarmConnectionState.healthy => colors.success,
      FarmConnectionState.challengeRequired ||
      FarmConnectionState.rateLimited => colors.warning,
      FarmConnectionState.authRequired => colors.error,
      FarmConnectionState.networkError ||
      FarmConnectionState.serverError ||
      FarmConnectionState.unknownError => colors.textTertiary,
    };

class _AccountDialog extends StatefulWidget {
  const _AccountDialog();

  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  final _cookieController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cookieController.text = context.read<AuthService>().currentCookie ?? '';
  }

  @override
  void dispose() {
    _cookieController.dispose();
    super.dispose();
  }

  Future<void> _cookieLogin() async {
    final auth = context.read<AuthService>();
    final messenger = ScaffoldMessenger.of(context);
    final cookie = _cookieController.text.trim();
    final err = AuthService.validateCookie(cookie);
    if (err != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    final ok = await auth.updateCookie(cookie);
    if (!mounted) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(ok ? 'Cookie 已登录' : 'Cookie 无效或无法连接')),
      );
  }

  Future<void> _logout() async {
    final auth = context.read<AuthService>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('退出后需重新登录才能继续使用自动收菜等功能，确定退出吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('退出登录'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    Navigator.of(context).pop();
    await auth.clearCookie();
  }

  Future<void> _verify() async {
    final verifier = context.read<ChallengeVerifier>();
    final auth = context.read<AuthService>();
    await showChallengeDialog(context, verifier: verifier, auth: auth);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final connection = context.watch<ConnectionStateStore>();
    final colors = FarmColorScheme.of(context);
    final state = connection.state;
    final statusColor = accountStatusColor(colors, state);

    return AlertDialog(
      title: const Text('账户与安全'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StatusHeader(
                username: auth.username,
                avatar: auth.avatar,
                isVip: auth.isVip,
                statusColor: statusColor,
                statusText: state.accountSubtitle,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _cookieController,
                maxLines: 3,
                style: FarmTextStyles.monoText,
                decoration: const InputDecoration(
                  hintText: '粘贴 Cookie（key=value; ...）',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              if (state == FarmConnectionState.challengeRequired) ...[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _verify,
                    child: const Text('完成人机验证'),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: _cookieLogin,
                      child: const Text('Cookie 登录'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _logout,
                    style: TextButton.styleFrom(foregroundColor: colors.error),
                    child: const Text('退出登录'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({
    required this.username,
    required this.avatar,
    required this.isVip,
    required this.statusColor,
    required this.statusText,
  });

  final String username;
  final String avatar;
  final bool isVip;
  final Color statusColor;
  final String statusText;

  @override
  Widget build(BuildContext context) {
    final colors = FarmColorScheme.of(context);
    return Row(
      children: [
        VipAvatar(
          avatar: avatar,
          size: 44,
          isVip: isVip,
          iconSize: 28,
        ),
        const SizedBox(width: FarmSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                username.isEmpty ? '尚未登录' : username,
                style: FarmTextStyles.listTitle.copyWith(
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                statusText,
                style: FarmTextStyles.settingDescription.copyWith(
                  color: statusColor,
                ),
              ),
            ],
          ),
        ),
        Container(
          width: FarmSpacing.xs,
          height: FarmSpacing.xs,
          decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
        ),
      ],
    );
  }
}

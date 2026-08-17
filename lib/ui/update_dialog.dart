/// 检查更新结果对话框：发现新版本展示版本号与更新说明，提供「前往查看」跳转到发布页。
library;

import 'package:flutter/material.dart';
import 'package:hyb_farm_desktop/core/desktop_shell.dart';
import 'package:hyb_farm_desktop/services/update_service.dart';
import 'package:hyb_farm_desktop/theme/farm_theme.dart';

/// 发现新版本。
Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) {
  return showDialog<void>(
    context: context,
    builder: (_) => _UpdateDialog(info: info),
  );
}

/// 已是最新版本。
Future<void> showUpToDateDialog(BuildContext context, String current) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('检查更新'),
      content: Text('当前已是最新版本 v$current。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('好的'),
        ),
      ],
    ),
  );
}

class _UpdateDialog extends StatelessWidget {
  const _UpdateDialog({required this.info});

  final UpdateInfo info;

  @override
  Widget build(BuildContext context) {
    final colors = FarmColorScheme.of(context);
    final body = info.body.trim();

    return AlertDialog(
      title: const Text('发现新版本'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '最新版本 v${info.version}',
              style: FarmTextStyles.bodyEmphasis.copyWith(color: colors.primary),
            ),
            const SizedBox(height: FarmSpacing.sm),
            if (body.isNotEmpty) ...[
              Text(
                '更新说明',
                style: FarmTextStyles.metricLabel.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: FarmSpacing.xs),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: SingleChildScrollView(
                  child: SelectableText(
                    body,
                    style: FarmTextStyles.bodySecondary.copyWith(
                      color: colors.textPrimary,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop();
            if (info.htmlUrl.isNotEmpty) openUrl(info.htmlUrl);
          },
          child: const Text('前往查看'),
        ),
      ],
    );
  }
}
/// 设置日志目录对话框：用系统目录选择器挑选根目录，日志写入其下 `logs/` 子目录。
///
/// 「保存」调用 [AppLogger.setLogsDirectory] 立即生效并写入 [SettingsState] 持久化；
/// 「还原默认」回到 `getApplicationSupportDirectory()` 并清空自定义设置。
library;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:hyb_farm_desktop/core/desktop_shell.dart';
import 'package:hyb_farm_desktop/core/log/app_logger.dart';
import 'package:hyb_farm_desktop/state/settings_state.dart';
import 'package:hyb_farm_desktop/theme/farm_theme.dart';

Future<void> showLogDirectoryDialog(
  BuildContext context,
  SettingsState settings,
) {
  return showDialog<void>(
    context: context,
    builder: (_) => _LogDirectoryDialog(settings: settings),
  );
}

class _LogDirectoryDialog extends StatefulWidget {
  const _LogDirectoryDialog({required this.settings});

  final SettingsState settings;

  @override
  State<_LogDirectoryDialog> createState() => _LogDirectoryDialogState();
}

class _LogDirectoryDialogState extends State<_LogDirectoryDialog> {
  /// 用户本次已选但尚未保存的新根目录；null 表示未选择。
  String? _pendingRoot;

  String? get _currentRoot =>
      _pendingRoot ?? widget.settings.logDirectory ?? AppLogger.instance.logsRoot;

  Future<void> _pick() async {
    final dir = await getDirectoryPath();
    if (dir == null) return;
    if (!mounted) return;
    setState(() => _pendingRoot = dir);
  }

  Future<void> _save() async {
    final root = _pendingRoot;
    if (root == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await AppLogger.instance.setLogsDirectory(root);
    } catch (_) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('目录不可写，设置失败')));
      return;
    }
    widget.settings.logDirectory = root;
    if (mounted) navigator.pop();
  }

  Future<void> _resetDefault() async {
    final navigator = Navigator.of(context);
    final supportDir = await getApplicationSupportDirectory();
    await AppLogger.instance.setLogsDirectory(supportDir.path);
    widget.settings.logDirectory = null;
    if (mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = FarmColorScheme.of(context);
    final root = _currentRoot;
    final logsDir = root == null ? '' : logsDirFor(root);

    return AlertDialog(
      title: const Text('设置日志目录'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '日志文件将写入所选目录下的 logs 子文件夹。',
              style: FarmTextStyles.bodySecondary.copyWith(
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: FarmSpacing.sm),
            Container(
              padding: const EdgeInsets.all(FarmSpacing.sm),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(FarmRadii.control),
                border: Border.all(color: colors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '当前日志目录',
                    style: FarmTextStyles.metricLabel.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: FarmSpacing.xs),
                  Text(
                    logsDir.isEmpty ? '（默认目录）' : logsDir,
                    style: FarmTextStyles.monoText.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: FarmSpacing.sm),
            FilledButton.icon(
              onPressed: _pick,
              icon: const Icon(Icons.folder_open, size: 18),
              label: const Text('选择目录…'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: _resetDefault,
          child: const Text('还原默认'),
        ),
        FilledButton(
          onPressed: _pendingRoot == null ? null : _save,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
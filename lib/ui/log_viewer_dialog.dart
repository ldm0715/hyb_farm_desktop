/// 查看日志对话框：列出日志目录下的 `app_*.log`（倒序），展示所选文件内容。
///
/// 正文用 `SelectableText` + `FarmTextStyles.monoText`（JetBrainsMono）渲染，支持选中复制；
/// 顶部放「打开日志文件夹」按钮，直接调起资源管理器定位到日志目录。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:hyb_farm_desktop/core/desktop_shell.dart';
import 'package:hyb_farm_desktop/core/log/app_logger.dart';
import 'package:hyb_farm_desktop/theme/farm_theme.dart';
import 'widgets/empty_state.dart';

Future<void> showLogViewerDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _LogViewerDialog(),
  );
}

class _LogViewerDialog extends StatefulWidget {
  const _LogViewerDialog();

  @override
  State<_LogViewerDialog> createState() => _LogViewerDialogState();
}

class _LogViewerDialogState extends State<_LogViewerDialog> {
  List<File> _files = const [];
  String? _selectedName;
  String? _content;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  static String _fileName(File f) =>
      f.uri.pathSegments.last;

  static bool _isLogFile(File f) {
    final name = _fileName(f);
    return name.startsWith('app_') && name.endsWith('.log');
  }

  Future<String> _resolveLogsDir() async {
    final root = AppLogger.instance.logsRoot;
    final base = root ?? (await getApplicationSupportDirectory()).path;
    return logsDirFor(base);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final logsDir = Directory(await _resolveLogsDir());
      var files = const <File>[];
      if (logsDir.existsSync()) {
        files = logsDir
            .listSync()
            .whereType<File>()
            .where(_isLogFile)
            .toList()
          ..sort((a, b) => _fileName(b).compareTo(_fileName(a)));
      }
      if (!mounted) return;
      if (files.isEmpty) {
        setState(() {
          _files = const [];
          _selectedName = null;
          _content = null;
          _loading = false;
        });
        return;
      }
      final first = files.first;
      final content = await first.readAsString();
      if (!mounted) return;
      setState(() {
        _files = files;
        _selectedName = _fileName(first);
        _content = content;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _select(File file) async {
    setState(() {
      _loading = true;
      _selectedName = _fileName(file);
    });
    try {
      final content = await file.readAsString();
      if (!mounted) return;
      setState(() {
        _content = content;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _openFolder() {
    final root = AppLogger.instance.logsRoot;
    if (root == null || root.isEmpty) return;
    openDirectory(logsDirFor(root));
  }

  @override
  Widget build(BuildContext context) {
    final colors = FarmColorScheme.of(context);

    Widget body;
    if (_error != null) {
      body = Text(
        '读取日志失败：$_error',
        style: FarmTextStyles.bodySecondary.copyWith(color: colors.error),
      );
    } else if (_loading && _content == null) {
      body = const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: CircularProgressIndicator(),
        ),
      );
    } else if (_files.isEmpty) {
      body = const EmptyState(
        icon: Icons.article_outlined,
        title: '暂无日志',
        subtitle: '应用尚未产生日志文件',
      );
    } else {
      final files = _files;
      final selectedName = _selectedName ?? _fileName(files.first);
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: FarmSpacing.sm,
              vertical: FarmSpacing.xs,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(FarmRadii.control),
              border: Border.all(color: colors.border),
            ),
            child: DropdownButton<String>(
              value: selectedName,
              isExpanded: true,
              isDense: true,
              underline: const SizedBox.shrink(),
              items: [
                for (final f in files)
                  DropdownMenuItem(
                    value: _fileName(f),
                    child: Text(
                      _fileName(f),
                      style: FarmTextStyles.monoText.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
              ],
              onChanged: (name) {
                if (name == null) return;
                final file = files.firstWhere((f) => _fileName(f) == name);
                _select(file);
              },
            ),
          ),
          const SizedBox(height: FarmSpacing.sm),
          Flexible(
            child: _loading
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: CircularProgressIndicator(),
                    ),
                  )
                : SingleChildScrollView(
                    child: SelectableText(
                      _content ?? '',
                      style: FarmTextStyles.monoText.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
          ),
        ],
      );
    }

    return AlertDialog(
      title: const Text('应用日志'),
      content: SizedBox(
        width: 440,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _openFolder,
                icon: const Icon(Icons.folder_open, size: 18),
                label: const Text('打开日志文件夹'),
              ),
            ),
            const SizedBox(height: FarmSpacing.xs),
            Expanded(child: body),
          ],
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
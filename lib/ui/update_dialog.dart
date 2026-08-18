/// 检查更新结果对话框：发现新版本展示版本号与更新说明，提供「前往查看」「下载并安装」。
///
/// 下载与安装确认在同一对话框内完成（单模态，避免叠两层 barrier）：下载中显示进度条、
/// 可取消；下载完成后展示安装包路径并询问是否立即安装；立即安装启动安装器后退出应用
/// （Inno Setup 无法覆盖运行中的 exe），安装包由下次启动的 `cleanupStaleInstallers` 清理。
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import 'package:hyb_farm_desktop/core/desktop_shell.dart';
import 'package:hyb_farm_desktop/core/formatters.dart';
import 'package:hyb_farm_desktop/core/log/app_logger.dart';
import 'package:hyb_farm_desktop/services/update_service.dart';
import 'package:hyb_farm_desktop/theme/farm_theme.dart';
import 'package:hyb_farm_desktop/tray/tray_manager.dart';

/// 发现新版本。
///
/// `barrierDismissible: false`：禁止 Escape/点空白静默关掉对话框而留下未处理的安装包。
Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) {
  return showDialog<void>(
    context: context,
    builder: (_) => _UpdateDialog(info: info),
    barrierDismissible: false,
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

enum _Phase { idle, downloading, ready, failed }

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.info});

  final UpdateInfo info;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  _Phase _phase = _Phase.idle;
  int _received = 0;
  int _total = 0;
  String? _savePath;
  String? _error;
  CancelToken? _cancel;
  bool _installing = false;

  Future<void> _startDownload() async {
    setState(() {
      _phase = _Phase.downloading;
      _received = 0;
      _total = 0;
      _error = null;
    });
    final token = CancelToken();
    _cancel = token;
    var lastShown = 0;
    try {
      final path = await context.read<UpdateService>().downloadInstaller(
            widget.info,
            cancelToken: token,
            onProgress: (received, total) {
              _total = total;
              _received = received;
              // 节流 setState：到点或每推进 256KB 才重建一次。
              if (!mounted) return;
              if (received == total || received - lastShown >= 256 * 1024) {
                lastShown = received;
                setState(() {});
              }
            },
          );
      if (!mounted) return;
      setState(() {
        _phase = _Phase.ready;
        _savePath = path;
      });
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        // 用户主动取消下载：静默关闭，不弹错误提示。
        if (mounted) Navigator.of(context).pop();
        return;
      }
      _fail('下载失败：${e.message ?? e.type}');
    } catch (e) {
      _fail('下载失败：$e');
    } finally {
      _cancel = null;
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.failed;
      _error = message;
    });
  }

  void _cancelDownload() => _cancel?.cancel();

  Future<void> _installNow() async {
    setState(() => _installing = true);
    final tray = context.read<TrayManager>();
    try {
      await launchInstaller(_savePath!);
    } catch (e) {
      AppLog.e('Update', '启动安装器失败', error: e);
      if (!mounted) return;
      setState(() => _installing = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('启动安装器失败，请稍后重试')),
        );
      return;
    }
    if (!mounted) return;
    // 先收对话框再退出应用，让 Inno 向导接管。
    Navigator.of(context).pop();
    await tray.quit();
  }

  Future<void> _discardAndClose() async {
    final path = _savePath;
    if (path != null && path.isNotEmpty) {
      try {
        final f = File(path);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {
        // 删除失败不影响关闭；下次启动 cleanupStaleInstallers 兜底。
      }
    }
    if (mounted) Navigator.of(context).pop();
  }

  /// 用语义色/排版令牌构造 Markdown 样式表；亮/暗自适应由 colors 保证。
  /// 标题/加粗只用 w600（NotoSansSC 只注册 400/600，避免引擎合成粗体）。
  MarkdownStyleSheet _markdownStyleSheet(FarmColorScheme colors) {
    final body = FarmTextStyles.bodySecondary.copyWith(
      color: colors.textPrimary,
      height: 1.5,
    );
    final h = body.copyWith(fontWeight: FontWeight.w600);
    return MarkdownStyleSheet(
      a: body.copyWith(
        color: colors.primary,
        decoration: TextDecoration.underline,
        decorationColor: colors.primary,
      ),
      p: body,
      pPadding: EdgeInsets.zero,
      em: const TextStyle(fontStyle: FontStyle.italic),
      strong: const TextStyle(fontWeight: FontWeight.w600),
      del: const TextStyle(decoration: TextDecoration.lineThrough),
      h1: h.copyWith(fontSize: 16),
      h2: h.copyWith(fontSize: 15),
      h3: h.copyWith(fontSize: 14),
      h4: h.copyWith(fontSize: 13),
      h5: h.copyWith(fontSize: 12),
      h6: h.copyWith(fontSize: 12, color: colors.textTertiary),
      h1Padding: EdgeInsets.zero,
      h2Padding: EdgeInsets.zero,
      h3Padding: EdgeInsets.zero,
      h4Padding: EdgeInsets.zero,
      h5Padding: EdgeInsets.zero,
      h6Padding: EdgeInsets.zero,
      code: FarmTextStyles.monoText.copyWith(color: colors.textPrimary),
      codeblockPadding: const EdgeInsets.all(FarmSpacing.xs),
      codeblockDecoration: BoxDecoration(
        color: colors.surfaceSubtle,
        borderRadius: BorderRadius.circular(FarmRadii.small),
      ),
      blockquote: FarmTextStyles.bodySecondary.copyWith(
        color: colors.textSecondary,
        height: 1.5,
      ),
      blockquotePadding: const EdgeInsets.only(left: FarmSpacing.xs),
      blockquoteDecoration: BoxDecoration(
        border: Border(left: BorderSide(color: colors.borderStrong, width: 3)),
      ),
      blockSpacing: FarmSpacing.sm,
      listBullet: FarmTextStyles.bodySecondary.copyWith(
        color: colors.textSecondary,
        height: 1.5,
      ),
      listBulletPadding: const EdgeInsets.only(right: FarmSpacing.xs),
      listIndent: FarmSpacing.md,
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.border, width: 1)),
      ),
      tableHead: body.copyWith(fontWeight: FontWeight.w600),
      tableBody: FarmTextStyles.bodySecondary.copyWith(
        color: colors.textSecondary,
      ),
      tableBorder: TableBorder.all(color: colors.border),
      tableCellsPadding: const EdgeInsets.all(FarmSpacing.xs),
    );
  }

  Widget _releaseInfo(FarmColorScheme colors) {
    final body = widget.info.body.trim();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '最新版本 v${widget.info.version}',
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
              child: MarkdownBody(
                data: body,
                selectable: true, // 保留可选中复制（内部 SelectableText.rich）。
                styleSheet: _markdownStyleSheet(colors),
                onTapLink: (text, href, title) {
                  final url = href;
                  if (url == null || url.isEmpty) return; // href 可空。
                  openUrl(url);
                },
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDownloading(FarmColorScheme colors) {
    final value = _total > 0
        ? (_received / _total).clamp(0.0, 1.0).toDouble()
        : null;
    final label = _total > 0
        ? '${formatBytes(_received)} / ${formatBytes(_total)}'
        : '已下载 ${formatBytes(_received)}';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '正在下载安装包…',
          style: FarmTextStyles.bodyEmphasis.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: FarmSpacing.md),
        LinearProgressIndicator(value: value),
        const SizedBox(height: FarmSpacing.sm),
        Text(
          label,
          style: FarmTextStyles.numericText.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildReady(FarmColorScheme colors) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '安装包已下载',
          style: FarmTextStyles.bodyEmphasis.copyWith(color: colors.primary),
        ),
        const SizedBox(height: FarmSpacing.sm),
        SelectableText(
          _savePath ?? '',
          style: FarmTextStyles.monoText.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: FarmSpacing.md),
        Text(
          '是否立即安装？',
          style: FarmTextStyles.bodySecondary.copyWith(color: colors.textPrimary),
        ),
      ],
    );
  }

  Widget _buildFailed(FarmColorScheme colors) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _error ?? '下载失败',
          style: FarmTextStyles.bodySecondary.copyWith(color: colors.error),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = FarmColorScheme.of(context);
    return AlertDialog(
      title: const Text('发现新版本'),
      content: SizedBox(
        width: 420,
        child: switch (_phase) {
          _Phase.idle => _releaseInfo(colors),
          _Phase.downloading => _buildDownloading(colors),
          _Phase.ready => _buildReady(colors),
          _Phase.failed => _buildFailed(colors),
        },
      ),
      actions: switch (_phase) {
        _Phase.idle => [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            if (widget.info.htmlUrl.isNotEmpty)
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  openUrl(widget.info.htmlUrl);
                },
                child: const Text('前往查看'),
              ),
            if (widget.info.hasInstaller)
              FilledButton(
                onPressed: _startDownload,
                child: const Text('下载并安装'),
              ),
          ],
        _Phase.downloading => [
            TextButton(
              onPressed: _cancelDownload,
              child: const Text('取消下载'),
            ),
          ],
        _Phase.ready => [
            TextButton(
              onPressed: _discardAndClose,
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: _installing ? null : _installNow,
              child: const Text('立即安装'),
            ),
          ],
        _Phase.failed => [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: _startDownload,
              child: const Text('重试'),
            ),
          ],
      },
    );
  }
}

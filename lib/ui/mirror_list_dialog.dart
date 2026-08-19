/// 第三方下载镜像：风险确认对话框 + 镜像列表管理对话框（增删改/启停/排序）。
///
/// 镜像由第三方提供，项目不保证其安全性、下载速度与长期可用性。内置镜像只能停用
/// 不能删除；自定义镜像可编辑删除。所有改动立即写回 [SettingsState] 持久化。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hyb_farm_desktop/core/download_sources.dart';
import 'package:hyb_farm_desktop/state/settings_state.dart';
import 'package:hyb_farm_desktop/theme/farm_theme.dart';

/// 风险确认对话框：返回是否接受。
Future<bool> showMirrorRiskDialog(BuildContext context) {
  final colors = FarmColorScheme.of(context);
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('第三方下载镜像风险提示'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '下载安装包将经由第三方镜像服务器转发。镜像由第三方提供，'
            '项目不保证其安全性、下载速度与长期可用性，下载内容可能被第三方记录。',
            style: FarmTextStyles.bodySecondary.copyWith(
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: FarmSpacing.sm),
          Text(
            '本应用会使用官方 SHA256 校验下载结果，但仍无法保证绝对安全。',
            style: FarmTextStyles.bodySecondary.copyWith(color: colors.error),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('继续使用'),
        ),
      ],
    ),
  ).then((v) => v ?? false);
}

/// 确保用户已接受当前版本的风险说明；未接受则弹窗。返回是否可继续使用第三方镜像。
Future<bool> ensureMirrorRiskAccepted(
  BuildContext context,
  SettingsState settings,
) async {
  if (settings.downloadMirrorRiskAcceptedVersion >= kDownloadMirrorRiskVersion) {
    return true;
  }
  final ok = await showMirrorRiskDialog(context);
  if (ok) {
    settings.downloadMirrorRiskAcceptedVersion = kDownloadMirrorRiskVersion;
  }
  return ok;
}

/// 打开镜像列表管理对话框。
Future<void> showDownloadMirrorsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _MirrorListDialog(),
  );
}

class _MirrorListDialog extends StatefulWidget {
  const _MirrorListDialog();

  @override
  State<_MirrorListDialog> createState() => _MirrorListDialogState();
}

class _MirrorListDialogState extends State<_MirrorListDialog> {
  late final List<DownloadMirror> _mirrors;

  @override
  void initState() {
    super.initState();
    _mirrors = List.of(context.read<SettingsState>().downloadMirrors);
  }

  void _writeBack() {
    context.read<SettingsState>().downloadMirrors = _mirrors;
  }

  void _toggle(int index, bool value) {
    setState(() => _mirrors[index] = _mirrors[index].copyWith(enabled: value));
    final settings = context.read<SettingsState>();
    // 停用当前选中源时回落官方，避免残留指向已停用镜像的 source。
    if (!value && settings.downloadSource == mirrorSource(_mirrors[index].id)) {
      settings.downloadSource = kDownloadSourceOfficial;
    }
    _writeBack();
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final m = _mirrors.removeAt(oldIndex);
      _mirrors.insert(newIndex, m);
    });
    _writeBack();
  }

  Future<void> _add() async {
    final result = await _showMirrorForm(null);
    if (result == null) return;
    setState(() => _mirrors.add(result));
    _writeBack();
  }

  Future<void> _edit(DownloadMirror m) async {
    final result = await _showMirrorForm(m);
    if (result == null) return;
    setState(() {
      final i = _mirrors.indexWhere((e) => e.id == m.id);
      if (i >= 0) _mirrors[i] = result;
    });
    _writeBack();
  }

  Future<void> _delete(DownloadMirror m) async {
    final settings = context.read<SettingsState>();
    setState(() => _mirrors.removeWhere((e) => e.id == m.id));
    if (settings.downloadSource == mirrorSource(m.id)) {
      settings.downloadSource = kDownloadSourceOfficial;
    }
    _writeBack();
  }

  Future<void> _resetDefaults() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复默认镜像'),
        content: const Text('将移除所有自定义镜像并恢复内置默认列表，确定吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _mirrors
        ..clear()
        ..addAll(kDefaultDownloadMirrors);
    });
    _writeBack();
  }

  Future<DownloadMirror?> _showMirrorForm(DownloadMirror? existing) {
    return showDialog<DownloadMirror>(
      context: context,
      builder: (ctx) => _MirrorFormDialog(
        existing: existing,
        mirrors: _mirrors,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = FarmColorScheme.of(context);
    return AlertDialog(
      title: const Text('第三方下载镜像'),
      content: SizedBox(
        width: 440,
        height: 380,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '镜像由第三方提供，项目不保证其安全性、下载速度与长期可用性。',
              style: FarmTextStyles.settingDescription.copyWith(
                color: colors.textTertiary,
              ),
            ),
            const SizedBox(height: FarmSpacing.sm),
            Expanded(
              child: _mirrors.isEmpty
                  ? Center(
                      child: Text(
                        '暂无镜像',
                        style: FarmTextStyles.bodySecondary.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                    )
                  : ReorderableListView.builder(
                      buildDefaultDragHandles: false,
                      itemCount: _mirrors.length,
                      onReorder: _reorder,
                      itemBuilder: (context, i) {
                        final m = _mirrors[i];
                        return _MirrorRow(
                          key: ValueKey(m.id),
                          index: i,
                          mirror: m,
                          onToggle: (v) => _toggle(i, v),
                          onEdit: m.builtIn ? null : () => _edit(m),
                          onDelete: m.builtIn ? null : () => _delete(m),
                        );
                      },
                    ),
            ),
            const SizedBox(height: FarmSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _add,
                    child: const Text('添加镜像'),
                  ),
                ),
                const SizedBox(width: FarmSpacing.xs),
                TextButton(
                  onPressed: _resetDefaults,
                  child: const Text('恢复默认'),
                ),
              ],
            ),
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

class _MirrorRow extends StatelessWidget {
  const _MirrorRow({
    super.key,
    required this.index,
    required this.mirror,
    required this.onToggle,
    this.onEdit,
    this.onDelete,
  });

  final int index;
  final DownloadMirror mirror;
  final ValueChanged<bool> onToggle;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = FarmColorScheme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: ReorderableDragStartListener(
        index: index,
        child: Icon(Icons.drag_handle, color: colors.textTertiary),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              mirror.name,
              overflow: TextOverflow.ellipsis,
              style: FarmTextStyles.listTitle.copyWith(color: colors.textPrimary),
            ),
          ),
          if (mirror.builtIn) ...[
            const SizedBox(width: FarmSpacing.xs),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 1,
              ),
              decoration: BoxDecoration(
                color: colors.surfaceSubtle,
                borderRadius: BorderRadius.circular(FarmRadii.small),
              ),
              child: Text(
                '内置',
                style: FarmTextStyles.plotStatus.copyWith(
                  color: colors.textTertiary,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        mirror.prefix,
        overflow: TextOverflow.ellipsis,
        style: FarmTextStyles.monoText.copyWith(color: colors.textSecondary),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(value: mirror.enabled, onChanged: onToggle),
          if (onEdit != null)
            IconButton(
              icon: Icon(Icons.edit_outlined, color: colors.textSecondary),
              onPressed: onEdit,
              tooltip: '编辑',
            ),
          if (onDelete != null)
            IconButton(
              icon: Icon(Icons.delete_outline, color: colors.error),
              onPressed: onDelete,
              tooltip: '删除',
            ),
        ],
      ),
    );
  }
}

class _MirrorFormDialog extends StatefulWidget {
  const _MirrorFormDialog({this.existing, required this.mirrors});

  final DownloadMirror? existing;
  final List<DownloadMirror> mirrors;

  @override
  State<_MirrorFormDialog> createState() => _MirrorFormDialogState();
}

class _MirrorFormDialogState extends State<_MirrorFormDialog> {
  late final TextEditingController _name;
  late final TextEditingController _prefix;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _prefix = TextEditingController(text: widget.existing?.prefix ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _prefix.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '名称不能为空');
      return;
    }
    final prefixErr = validateMirrorPrefix(_prefix.text);
    if (prefixErr != null) {
      setState(() => _error = prefixErr);
      return;
    }
    var prefix = _prefix.text.trim();
    while (prefix.endsWith('/')) {
      prefix = prefix.substring(0, prefix.length - 1);
    }
    prefix = '$prefix/';
    if (hasDuplicatePrefix(
      widget.mirrors,
      prefix,
      excludeId: widget.existing?.id,
    )) {
      setState(() => _error = '该前缀已存在');
      return;
    }
    final existing = widget.existing;
    final result = existing == null
        ? DownloadMirror(
            id: newCustomMirrorId(),
            name: name,
            prefix: prefix,
            builtIn: false,
            enabled: true,
          )
        : existing.copyWith(name: name, prefix: prefix);
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final colors = FarmColorScheme.of(context);
    return AlertDialog(
      title: Text(widget.existing == null ? '添加镜像' : '编辑镜像'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: '名称',
                hintText: '如 my-mirror',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: FarmSpacing.sm),
            TextField(
              controller: _prefix,
              style: FarmTextStyles.monoText,
              decoration: const InputDecoration(
                labelText: '前缀 URL（https）',
                hintText: 'https://example.com/',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: FarmSpacing.sm),
              Text(
                _error!,
                style: FarmTextStyles.bodySecondary.copyWith(color: colors.error),
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
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }
}

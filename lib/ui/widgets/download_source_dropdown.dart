/// 下载源选择下拉：设置页（长期默认）与更新对话框（临时切换）共用，样式统一。
///
/// - 视觉与设置页 `_settingControl` 等价：定高圆角带边框容器 + 紧凑下拉。
/// - 内置值守卫（`official`/`auto`/启用镜像），选中源被停用/删除时回落官方，
///   避免 `DropdownButton.value` 不在 items 里。
/// - 切换经 `ensureMirrorRiskAccepted` 风险门控（仅在会实际使用第三方下载时弹确认）。
/// - 镜像项只显示名称（延迟信息由镜像列表与下载页的 `MirrorLatencyBadge` 展示，下拉空间小不塞）。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hyb_farm_desktop/core/download_sources.dart';
import 'package:hyb_farm_desktop/state/settings_state.dart';
import 'package:hyb_farm_desktop/theme/farm_theme.dart';
import 'package:hyb_farm_desktop/ui/mirror_list_dialog.dart';

/// 下载源下拉。`value` 为当前选中源（守卫后展示）；`onChanged` 在通过风险门控后回调。
class DownloadSourceDropdown extends StatefulWidget {
  const DownloadSourceDropdown({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<DownloadSourceDropdown> createState() => _DownloadSourceDropdownState();
}

class _DownloadSourceDropdownState extends State<DownloadSourceDropdown> {
  /// 非法/已停用 source 回落官方，避免 DropdownButton value 不在 items 里。
  String _guard(String source, SettingsState settings) {
    if (source == kDownloadSourceOfficial || source == kDownloadSourceAuto) {
      return source;
    }
    if (isMirrorSource(source)) {
      final id = source.substring('mirror:'.length);
      if (settings.downloadMirrors.any((m) => m.id == id && m.enabled)) {
        return source;
      }
    }
    return kDownloadSourceOfficial;
  }

  List<DropdownMenuItem<String>> _items(SettingsState settings) {
    return [
      const DropdownMenuItem(
        value: kDownloadSourceOfficial,
        child: Text('官方源'),
      ),
      const DropdownMenuItem(
        value: kDownloadSourceAuto,
        child: Text('自动（逐个尝试）'),
      ),
      for (final m in settings.downloadMirrors)
        if (m.enabled)
          DropdownMenuItem(value: mirrorSource(m.id), child: Text(m.name)),
    ];
  }

  Future<void> _change(String value) async {
    if (value == widget.value) return;
    final settings = context.read<SettingsState>();
    // 仅在会实际使用第三方下载时提示风险确认。
    if (sourceUsesThirdParty(value, settings.downloadMirrors)) {
      final ok = await ensureMirrorRiskAccepted(context, settings);
      if (!ok || !mounted) return;
    }
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = FarmColorScheme.of(context);
    final settings = context.read<SettingsState>();
    return Container(
      height: FarmSizes.button,
      padding: const EdgeInsets.symmetric(horizontal: FarmSpacing.sm),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(FarmRadii.control),
        border: Border.all(color: colors.border),
      ),
      child: Center(
        child: DropdownButton<String>(
          value: _guard(widget.value, settings),
          isExpanded: true,
          isDense: true,
          underline: const SizedBox.shrink(),
          items: _items(settings),
          onChanged: (v) {
            if (v != null) _change(v);
          },
        ),
      ),
    );
  }
}

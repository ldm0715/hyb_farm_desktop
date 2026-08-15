/// 仓库页二级分段控件：库存 / 收益排行 二选一切换。
///
/// 自绘实现，不依赖 Flutter 内置 SegmentedButton / TabBar 的 indicator 绘制，
/// 避免其内部 Material 绘制与自定义圆角背景叠加产生白色矩形方块。
/// 外层容器单一负责背景 + 边框 + 圆角裁切，内部 Row 两个 Expanded 严格 50% 等宽。
library;

import 'package:flutter/material.dart';

import '../theme/farm_color_scheme.dart';
import '../theme/farm_radii.dart';
import '../theme/farm_sizes.dart';
import '../theme/farm_text_styles.dart';

/// 二选一分段控件。
///
/// [selected] 为 true 时选中「收益排行」，false 时选中「库存」。
class WarehouseSegmentedControl extends StatelessWidget {
  const WarehouseSegmentedControl({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = FarmColorScheme.of(context);
    return SizedBox(
      width: FarmSizes.segmentedWidth,
      height: FarmSizes.segmented,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(FarmRadii.segmented),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: _Segment(
                label: '库存',
                selected: !selected,
                onTap: () => onChanged(false),
              ),
            ),
            Expanded(
              child: _Segment(
                label: '收益排行',
                selected: selected,
                onTap: () => onChanged(true),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 单个 segment：Material + InkWell 居中文字，选中态浅绿圆角由 InkWell 裁切。
class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = FarmColorScheme.of(context);
    final textStyle = selected
        ? FarmTextStyles.tabLabelSelected.copyWith(color: colors.primary)
        : FarmTextStyles.tabLabel.copyWith(color: colors.textSecondary);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(FarmRadii.segmented),
        overlayColor: WidgetStateProperty.all(
          selected ? colors.surfaceSelected : colors.surfaceHover,
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: selected ? colors.surfaceSelected : Colors.transparent,
            borderRadius: BorderRadius.circular(FarmRadii.segmented),
          ),
          alignment: Alignment.center,
          child: Text(label, style: textStyle),
        ),
      ),
    );
  }
}

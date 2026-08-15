/// 作物图标：统一固定尺寸、圆角与对齐，含网络失败兜底。
///
/// 所有页面/列表的主体作物 icon 统一走此组件，保证尺寸与对齐一致。
/// chip/菜单内联缩略图（自动化活动摘要、设置下拉）是缩略图而非 icon 主体，
/// 显式传小 `size`（16/18），避免撑高 chip/菜单。
library;

import 'package:flutter/material.dart';

import '../../theme/farm_theme.dart';

class FarmIcon extends StatelessWidget {
  const FarmIcon({
    required this.iconUrl,
    this.size = FarmSizes.farmIcon,
    this.radius = FarmRadii.small,
    super.key,
  });

  /// 图标完整地址（`cropIconUrl(seedImage)`）。
  final String iconUrl;

  /// 固定占位尺寸（宽高一致）。
  final double size;

  /// 图标圆角。
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(
        iconUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Icon(Icons.grass, size: size),
      ),
    );
  }
}

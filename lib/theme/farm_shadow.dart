/// 层级阴影抽象：消费 [FarmColorScheme.shadow]（中性深绿灰/黑、低透明度），
/// 派生出 3 级 [BoxShadow]，供 surface 层级（S1/S2/S3）使用。
///
/// 结构常量（blur/offset）不随主题变化；颜色取当前语义色板的 `shadow`，
/// 天然亮暗自适应。阴影不走 Material `elevation`（其阴影色固定为 colorScheme.shadow 黑基，
/// 无法命中语义色），统一由 `Container(BoxDecoration(boxShadow:))` 承担。
library;

import 'package:flutter/material.dart';

import 'farm_color_scheme.dart';

abstract final class FarmShadow {
  // 结构常量（blur / offset）。
  static const double _blurL1 = 3;
  static const double _blurL2 = 8;
  static const double _blurL3 = 18;
  static const Offset _offL1 = Offset(0, 1);
  static const Offset _offL2 = Offset(0, 2);
  static const Offset _offL3 = Offset(0, 5);

  /// 乘算 [base] 的 alpha（base 本身已带 10%/30% alpha）。
  static Color _tint(Color base, double factor) =>
      base.withValues(alpha: (base.a * factor).clamp(0.0, 1.0));

  /// S1 常规分组面（列表容器 / 设置分组）：极轻，与背景差区分即可。
  static List<BoxShadow> level1(FarmColorScheme c) => [
    BoxShadow(color: _tint(c.shadow, 0.4), blurRadius: _blurL1, offset: _offL1),
  ];

  /// S2 强调 / 可操作面（收获总览、排行 hero）：轻环境阴影。
  static List<BoxShadow> level2(FarmColorScheme c) => [
    BoxShadow(color: _tint(c.shadow, 0.8), blurRadius: _blurL2, offset: _offL2),
  ];

  /// S3 浮层（仅弹窗 / 菜单）：柔和双层阴影。
  static List<BoxShadow> level3(FarmColorScheme c) => [
    BoxShadow(color: _tint(c.shadow, 1.0), blurRadius: _blurL3, offset: _offL3),
    BoxShadow(color: _tint(c.shadow, 0.5), blurRadius: _blurL1, offset: _offL1),
  ];
}

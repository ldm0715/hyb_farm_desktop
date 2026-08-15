/// 语义颜色扩展：承载全项目颜色令牌，亮/暗两套实例通过 [ThemeData.extensions] 注入。
///
/// 页面与组件统一从 `FarmColorScheme.of(context)` 取色，禁止散落 magic 色值。
/// 名称表达用途（背景/表面/文字/边框/品牌/状态），不叫 green/white/gray。
library;

import 'package:flutter/material.dart';

/// 农场语义色板。
///
/// 亮/暗两套完整实例见 [FarmColorScheme.light] / [FarmColorScheme.dark]。
class FarmColorScheme extends ThemeExtension<FarmColorScheme> {
  const FarmColorScheme({
    required this.pageBackground,
    required this.headerBackground,
    required this.surface,
    required this.surfaceSubtle,
    required this.surfaceHover,
    required this.surfaceSelected,
    required this.surfaceDisabled,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textDisabled,
    required this.border,
    required this.borderStrong,
    required this.primary,
    required this.primaryHover,
    required this.primaryPressed,
    required this.onPrimary,
    required this.success,
    required this.warning,
    required this.error,
    required this.gold,
    required this.silver,
    required this.bronze,
    required this.readySurface,
    required this.readyBorder,
    required this.errorSurface,
    required this.errorBorder,
    required this.overlay,
    required this.shadow,
  });

  /// 页面背景。
  final Color pageBackground;

  /// Header / 顶部栏背景。
  final Color headerBackground;

  /// 卡片 / 弹层表面。
  final Color surface;

  /// 次级表面（列表分区、图标底、进度条轨道等）。
  final Color surfaceSubtle;

  /// hover 悬停表面。
  final Color surfaceHover;

  /// 选中表面（一级 Tab 选中背景、分段控件选中块）。
  final Color surfaceSelected;

  /// 禁用表面。
  final Color surfaceDisabled;

  /// 主文字。
  final Color textPrimary;

  /// 次级文字。
  final Color textSecondary;

  /// 弱提示文字。
  final Color textTertiary;

  /// 禁用文字。
  final Color textDisabled;

  /// 普通边框。
  final Color border;

  /// 强调边框。
  final Color borderStrong;

  /// 品牌主色（按钮、可点击主操作）。
  final Color primary;

  /// 品牌主色 hover。
  final Color primaryHover;

  /// 品牌主色 pressed。
  final Color primaryPressed;

  /// 主色之上的前景（按钮文字、品牌图标）。
  final Color onPrimary;

  /// 成功 / 生长中语义色。
  final Color success;

  /// 警示语义色。
  final Color warning;

  /// 错误 / 异常语义色。
  final Color error;

  /// 排行第 1 名金色徽章。
  final Color gold;

  /// 排行第 2 名银色徽章。
  final Color silver;

  /// 排行第 3 名铜色徽章。
  final Color bronze;

  /// 成熟/可收获地块背景。
  final Color readySurface;

  /// 成熟/可收获地块边框。
  final Color readyBorder;

  /// 异常地块背景。
  final Color errorSurface;

  /// 异常地块边框。
  final Color errorBorder;

  /// 遮罩/蒙层色（含透明度）。
  final Color overlay;

  /// 阴影色（含透明度）。
  final Color shadow;

  /// 从上下文取当前亮/暗语义色板。
  static FarmColorScheme of(BuildContext context) =>
      Theme.of(context).extension<FarmColorScheme>()!;

  @override
  FarmColorScheme copyWith({
    Color? pageBackground,
    Color? headerBackground,
    Color? surface,
    Color? surfaceSubtle,
    Color? surfaceHover,
    Color? surfaceSelected,
    Color? surfaceDisabled,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? textDisabled,
    Color? border,
    Color? borderStrong,
    Color? primary,
    Color? primaryHover,
    Color? primaryPressed,
    Color? onPrimary,
    Color? success,
    Color? warning,
    Color? error,
    Color? gold,
    Color? silver,
    Color? bronze,
    Color? readySurface,
    Color? readyBorder,
    Color? errorSurface,
    Color? errorBorder,
    Color? overlay,
    Color? shadow,
  }) {
    return FarmColorScheme(
      pageBackground: pageBackground ?? this.pageBackground,
      headerBackground: headerBackground ?? this.headerBackground,
      surface: surface ?? this.surface,
      surfaceSubtle: surfaceSubtle ?? this.surfaceSubtle,
      surfaceHover: surfaceHover ?? this.surfaceHover,
      surfaceSelected: surfaceSelected ?? this.surfaceSelected,
      surfaceDisabled: surfaceDisabled ?? this.surfaceDisabled,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      textDisabled: textDisabled ?? this.textDisabled,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      primary: primary ?? this.primary,
      primaryHover: primaryHover ?? this.primaryHover,
      primaryPressed: primaryPressed ?? this.primaryPressed,
      onPrimary: onPrimary ?? this.onPrimary,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      gold: gold ?? this.gold,
      silver: silver ?? this.silver,
      bronze: bronze ?? this.bronze,
      readySurface: readySurface ?? this.readySurface,
      readyBorder: readyBorder ?? this.readyBorder,
      errorSurface: errorSurface ?? this.errorSurface,
      errorBorder: errorBorder ?? this.errorBorder,
      overlay: overlay ?? this.overlay,
      shadow: shadow ?? this.shadow,
    );
  }

  @override
  FarmColorScheme lerp(ThemeExtension<FarmColorScheme>? other, double t) {
    if (other is! FarmColorScheme) return this;
    return FarmColorScheme(
      pageBackground: Color.lerp(pageBackground, other.pageBackground, t)!,
      headerBackground: Color.lerp(
        headerBackground,
        other.headerBackground,
        t,
      )!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceSubtle: Color.lerp(surfaceSubtle, other.surfaceSubtle, t)!,
      surfaceHover: Color.lerp(surfaceHover, other.surfaceHover, t)!,
      surfaceSelected: Color.lerp(surfaceSelected, other.surfaceSelected, t)!,
      surfaceDisabled: Color.lerp(surfaceDisabled, other.surfaceDisabled, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      textDisabled: Color.lerp(textDisabled, other.textDisabled, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primaryHover: Color.lerp(primaryHover, other.primaryHover, t)!,
      primaryPressed: Color.lerp(primaryPressed, other.primaryPressed, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
      gold: Color.lerp(gold, other.gold, t)!,
      silver: Color.lerp(silver, other.silver, t)!,
      bronze: Color.lerp(bronze, other.bronze, t)!,
      readySurface: Color.lerp(readySurface, other.readySurface, t)!,
      readyBorder: Color.lerp(readyBorder, other.readyBorder, t)!,
      errorSurface: Color.lerp(errorSurface, other.errorSurface, t)!,
      errorBorder: Color.lerp(errorBorder, other.errorBorder, t)!,
      overlay: Color.lerp(overlay, other.overlay, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
    );
  }

  /// 浅色语义色板。
  static const FarmColorScheme light = FarmColorScheme(
    pageBackground: Color(0xFFF6F8F4),
    headerBackground: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    surfaceSubtle: Color(0xFFF0F3EE),
    surfaceHover: Color(0xFFEAF1E9),
    surfaceSelected: Color(0xFFE2F1E4),
    surfaceDisabled: Color(0xFFE7ECE6),
    textPrimary: Color(0xFF1B2920),
    textSecondary: Color(0xFF4F5F53),
    textTertiary: Color(0xFF718074),
    textDisabled: Color(0xFF8A968C),
    border: Color(0xFFD3DED2),
    borderStrong: Color(0xFFB9C9BA),
    primary: Color(0xFF276C43),
    primaryHover: Color(0xFF205C39),
    primaryPressed: Color(0xFF18472C),
    onPrimary: Color(0xFFFFFFFF),
    success: Color(0xFF287C48),
    warning: Color(0xFFA76D0A),
    error: Color(0xFFB83F43),
    gold: Color(0xFFB8860B),
    silver: Color(0xFF8A939B),
    bronze: Color(0xFFA0602A),
    readySurface: Color(0xFFFFF8E6),
    readyBorder: Color(0xFFD6A52E),
    errorSurface: Color(0xFFFFF0F0),
    errorBorder: Color(0xFFD25A5A),
    // #000000 8%
    overlay: Color(0x14000000),
    // #16341E 10%
    shadow: Color(0x1A16341E),
  );

  /// 深色语义色板。
  static const FarmColorScheme dark = FarmColorScheme(
    pageBackground: Color(0xFF121A15),
    headerBackground: Color(0xFF18231C),
    surface: Color(0xFF1B271F),
    surfaceSubtle: Color(0xFF243128),
    surfaceHover: Color(0xFF2A3A2E),
    surfaceSelected: Color(0xFF234C31),
    surfaceDisabled: Color(0xFF26332A),
    textPrimary: Color(0xFFE6EFE7),
    textSecondary: Color(0xFFB4C1B6),
    textTertiary: Color(0xFF89998D),
    textDisabled: Color(0xFF7D8C80),
    border: Color(0xFF344438),
    borderStrong: Color(0xFF516454),
    primary: Color(0xFF72C98C),
    primaryHover: Color(0xFF8CDBA3),
    primaryPressed: Color(0xFF58B875),
    onPrimary: Color(0xFF102016),
    success: Color(0xFF78CF91),
    warning: Color(0xFFE8BF58),
    error: Color(0xFFF18D8F),
    gold: Color(0xFFE3B341),
    silver: Color(0xFFB9C3C9),
    bronze: Color(0xFFC98A52),
    readySurface: Color(0xFF423817),
    readyBorder: Color(0xFFCDAA42),
    errorSurface: Color(0xFF47292A),
    errorBorder: Color(0xFFE37C7D),
    // #000000 32%
    overlay: Color(0x52000000),
    // #000000 30%
    shadow: Color(0x4D000000),
  );
}

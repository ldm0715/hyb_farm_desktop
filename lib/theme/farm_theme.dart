/// 主题与统一入口：组合语义色板 / 间距 / 尺寸 / 圆角 / 文字令牌，产出 ThemeData。
library;

import 'package:flutter/material.dart';

import 'farm_color_scheme.dart';
import 'farm_radii.dart';
import 'farm_sizes.dart';
import 'farm_spacing.dart';
import 'farm_text_styles.dart';

export 'farm_color_scheme.dart';
export 'farm_radii.dart';
export 'farm_shadow.dart';
export 'farm_sizes.dart';
export 'farm_spacing.dart';
export 'farm_text_styles.dart';

/// 页面统一左右 padding（左右 16px）。
const EdgeInsets kPagePadding = EdgeInsets.fromLTRB(
  FarmSpacing.md,
  FarmSpacing.sm,
  FarmSpacing.md,
  FarmSpacing.md,
);

/// 浅色主题。
ThemeData buildLightTheme() => _lightTheme;

/// 深色主题。
ThemeData buildDarkTheme() => _darkTheme;

// 缓存两套 ThemeData：ColorScheme.fromSeed 是昂贵操作（HCT 色彩空间计算），
// 主题无可变状态，避免每次重建（如切换 themeMode）都重新生成。
final ThemeData _lightTheme = _build(FarmColorScheme.light);
final ThemeData _darkTheme = _build(FarmColorScheme.dark);

/// 给排版 token 叠加语义色（文字颜色由 FarmColorScheme 注入，保证亮/暗自适应）。
TextStyle _t(Color color, TextStyle base) => base.copyWith(color: color);

ThemeData _build(FarmColorScheme c) {
  final brightness = c == FarmColorScheme.dark
      ? Brightness.dark
      : Brightness.light;

  final scheme =
      ColorScheme.fromSeed(
        seedColor: c.primary,
        brightness: brightness,
      ).copyWith(
        primary: c.primary,
        onPrimary: c.onPrimary,
        surface: c.surface,
        onSurface: c.textPrimary,
        onSurfaceVariant: c.textSecondary,
        surfaceContainerHighest: c.surfaceSubtle,
        surfaceContainerHigh: c.surfaceSubtle,
        surfaceContainer: c.surfaceSubtle,
        surfaceContainerLow: c.surfaceSubtle,
        surfaceContainerLowest: c.surface,
        outline: c.border,
        outlineVariant: c.border,
        error: c.error,
      );

  final cardShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(FarmRadii.card),
    side: BorderSide(color: c.border),
  );

  // 与 FarmTextStyles 对齐的 textTheme：语义化映射，避免踩到组件默认引用。
  // 注意 DropdownButton 默认引用 titleMedium、ListTile title/subtitle 引用 bodyLarge/bodyMedium。
  final textTheme = TextTheme(
    titleLarge: _t(c.textPrimary, FarmTextStyles.pageTitle),
    titleMedium: _t(c.textPrimary, FarmTextStyles.settingValue),
    titleSmall: _t(c.textPrimary, FarmTextStyles.sectionTitle),
    bodyLarge: _t(c.textPrimary, FarmTextStyles.settingTitle),
    bodyMedium: _t(c.textSecondary, FarmTextStyles.listMeta),
    bodySmall: _t(c.textSecondary, FarmTextStyles.bodySecondary),
    labelLarge: FarmTextStyles.button,
    labelMedium: _t(c.textSecondary, FarmTextStyles.metricLabel),
    labelSmall: _t(c.primary, FarmTextStyles.statusText),
  );

  final outlineBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(FarmRadii.control),
    borderSide: BorderSide(color: c.border),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: kFontFamilyCjk,
    fontFamilyFallback: const [
      'NotoSansSC',
      'Microsoft YaHei UI',
      'Microsoft YaHei',
      'PingFang SC',
      'Segoe UI',
      'sans-serif',
    ],
    scaffoldBackgroundColor: c.pageBackground,
    extensions: [c],
    textTheme: textTheme,

    appBarTheme: AppBarTheme(
      backgroundColor: c.headerBackground,
      foregroundColor: c.textPrimary,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: c.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: cardShape,
    ),
    dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
    iconTheme: IconThemeData(color: c.textSecondary),
    tabBarTheme: TabBarThemeData(
      labelStyle: _t(c.textPrimary, FarmTextStyles.tabLabelSelected),
      unselectedLabelStyle: _t(c.textSecondary, FarmTextStyles.tabLabel),
      dividerColor: Colors.transparent,
    ),
    navigationBarTheme: NavigationBarThemeData(
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? _t(c.textPrimary, FarmTextStyles.tabLabelSelected)
            : _t(c.textSecondary, FarmTextStyles.tabLabel),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: c.surfaceSubtle,
      labelStyle: _t(c.textSecondary, FarmTextStyles.bodySecondary),
      side: BorderSide(color: c.border),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FarmRadii.small),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStatePropertyAll(c.surface),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? c.primary
              : c.textSecondary,
        ),
        side: WidgetStatePropertyAll(BorderSide(color: c.border)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, FarmSizes.button),
        textStyle: FarmTextStyles.button,
        backgroundColor: c.primary,
        foregroundColor: c.onPrimary,
        disabledBackgroundColor: c.surfaceDisabled,
        disabledForegroundColor: c.textDisabled,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FarmRadii.control),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, FarmSizes.button),
        textStyle: FarmTextStyles.button,
        foregroundColor: c.primary,
        disabledForegroundColor: c.textDisabled,
        side: BorderSide(color: c.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FarmRadii.control),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        textStyle: FarmTextStyles.buttonSecondary,
        foregroundColor: c.primary,
        disabledForegroundColor: c.textDisabled,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: c.textSecondary,
        disabledForegroundColor: c.textDisabled,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      labelStyle: _t(c.textSecondary, FarmTextStyles.bodySecondary),
      hintStyle: _t(c.textTertiary, FarmTextStyles.bodySecondary),
      border: outlineBorder,
      enabledBorder: outlineBorder,
      disabledBorder: outlineBorder.copyWith(
        borderSide: BorderSide(color: c.surfaceDisabled),
      ),
      focusedBorder: outlineBorder.copyWith(
        borderSide: BorderSide(color: c.primary),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return c.textDisabled;
        if (states.contains(WidgetState.selected)) return c.primary;
        return c.textSecondary;
      }),
      checkColor: WidgetStatePropertyAll(c.onPrimary),
      side: BorderSide(color: c.border),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return c.textDisabled;
        if (states.contains(WidgetState.selected)) return c.primary;
        return c.textSecondary;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return c.surfaceDisabled;
        if (states.contains(WidgetState.selected)) return c.surfaceSelected;
        return c.surfaceSubtle;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Colors.transparent
            : c.border,
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: c.primary,
      linearTrackColor: c.surfaceSubtle,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      titleTextStyle: _t(c.textPrimary, FarmTextStyles.sectionTitle),
      contentTextStyle: _t(c.textSecondary, FarmTextStyles.bodySecondary),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FarmRadii.container),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.surface,
      contentTextStyle: _t(c.textPrimary, FarmTextStyles.bodyEmphasis),
      actionTextColor: c.primary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FarmRadii.control),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.surface,
      textStyle: _t(c.textPrimary, FarmTextStyles.settingValue),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FarmRadii.control),
      ),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(backgroundColor: WidgetStatePropertyAll(c.surface)),
    ),
    tooltipTheme: TooltipThemeData(
      textStyle: _t(c.surface, FarmTextStyles.bodySecondary),
      decoration: BoxDecoration(
        color: c.textPrimary,
        borderRadius: BorderRadius.circular(FarmRadii.small),
      ),
    ),
    listTileTheme: ListTileThemeData(
      titleTextStyle: _t(c.textPrimary, FarmTextStyles.settingTitle),
      subtitleTextStyle: _t(c.textSecondary, FarmTextStyles.settingDescription),
      iconColor: c.textSecondary,
      textColor: c.textPrimary,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(c.borderStrong),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(FarmRadii.container),
        ),
      ),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: MenuStyle(backgroundColor: WidgetStatePropertyAll(c.surface)),
    ),
  );
}

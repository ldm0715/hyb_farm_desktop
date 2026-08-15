/// 字体与文字样式令牌（仅排版，不含颜色）。
///
/// 颜色不再内联进样式——由 `FarmColorScheme`（ThemeExtension）与 ThemeData.textTheme
/// 注入，保证亮/暗模式自适应。页面取带色文字请用：
/// - 标准角色走 `Theme.of(context).textTheme.<role>`；
/// - 页面专属样式走 `FarmTextStyles.xxx.copyWith(color: FarmColorScheme.of(context).<语义>)`。
///
/// 全局字体：中文用 Noto Sans SC（随包打包，见 pubspec.yaml）。
/// Inter 不含中文，仅用于独立的纯数字/金额/倒计时文本，禁止用于中文或中英混排。
/// 字重约束：中文只允许 w400/w600；Inter 纯数字允许 w400/w600/w700。
/// 禁用 w500（对应 Medium 文件已删除，避免引擎模拟粗体）与 w100/w200/w300。
/// 金额/数量/倒计时等跳动数值统一叠加 [kTabularFigures]（并切 Inter），
/// 避免每秒刷新时布局横向抖动。
library;

import 'package:flutter/material.dart';

/// 等宽数字（tabular figures）：金额/数量/倒计时统一使用，避免跳动错位。
List<FontFeature> get kTabularFigures => const [FontFeature.tabularFigures()];

/// 中文主字体族（全局默认，见 ThemeData.fontFamily）。
const String kFontFamilyCjk = 'NotoSansSC';

/// 英文/数字字体族（纯数字与金额文本局部切到 Inter）。
const String kFontFamilyLatin = 'Inter';

/// 等宽字体族（Cookie/token/URL/命令等技术文本）。
const String kFontFamilyMono = 'JetBrainsMono';

/// 纯数字/金额文本的样式叠加：切 Inter + 等宽数字。
/// 用法：`FarmTextStyles.metricValue.copyWith(fontFamily: kFontFamilyLatin, fontFeatures: kTabularFigures)`。
TextStyle _numeric(TextStyle base) =>
    base.copyWith(fontFamily: kFontFamilyLatin, fontFeatures: kTabularFigures);

/// 统一文字样式：全项目只从这里取字体，禁止在页面内散落 magic 字号/字重。
/// 注意：此处样式均无颜色，颜色由 ThemeData.textTheme / FarmColorScheme 注入。
abstract final class FarmTextStyles {
  // ── 全局 Header / 品牌栏 ───────────────────────────────

  /// 品牌名「HYB Farm」。
  static const TextStyle brand = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
  );

  /// 品牌副标题「自动化农场助手」。
  static const TextStyle brandSubtitle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
  );

  /// 运行状态文字（如「正常」）。
  static const TextStyle statusText = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
  );

  // ── 一级 TabBar ────────────────────────────────────────

  /// Tab 文案（选中/未选中只改字重，字号固定 13）。
  static const TextStyle tabLabel = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle tabLabelSelected = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
  );

  // ── 页面标题区 ─────────────────────────────────────────

  /// 页面标题（农场/仓库/好友/设置）。
  static const TextStyle pageTitle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  /// 页面描述 / 辅助统计（如「20 块地 · 0 块空闲」）。
  static const TextStyle pageDescription = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.45,
  );

  // ── 指标卡片 ───────────────────────────────────────────

  /// 指标卡标签（可收获/下次收获…）。
  static const TextStyle metricLabel = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
  );

  /// 指标卡数量（可收获/空闲地块）。22px，纯数字可叠加 [_numeric]。
  static const TextStyle metricValue = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
  );

  /// 指标卡金额/倒计时。20px，纯数字可叠加 [_numeric]。
  static const TextStyle metricValueCompact = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
  );

  // ── 列表 / 地块卡片 ────────────────────────────────────

  /// 列表主标题 / 作物名称。
  static const TextStyle listTitle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
  );

  /// 列表辅助说明（库存/单价等）。
  static const TextStyle listMeta = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );

  /// 地块编号「#01」。
  static const TextStyle plotNumber = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w400,
  );

  /// 地块状态文本（生长中）。
  static const TextStyle plotStatus = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
  );

  /// 成熟态强调（已成熟，可收获）。
  static const TextStyle plotStatusMature = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
  );

  // ── 设置页 ─────────────────────────────────────────────

  /// 设置分组标题（自动化/通知/外观…）。
  static const TextStyle settingGroupTitle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
  );

  /// 设置项标题（自动收菜…）。
  static const TextStyle settingTitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
  );

  /// 设置项描述。
  static const TextStyle settingDescription = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.45,
  );

  /// 下拉/输入值（跟随系统、5 分钟…）。数字叠加 [_numeric]。
  static const TextStyle settingValue = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
  );

  // ── 按钮 ───────────────────────────────────────────────

  /// 主按钮文字。
  static const TextStyle button = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
  );

  /// 次级按钮 / TextButton 文字。
  static const TextStyle buttonSecondary = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
  );

  // ── 通用层级 ───────────────────────────────────────────

  /// 正文强调（普通强调信息、次要数值）。
  static const TextStyle bodyEmphasis = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
  );

  /// 正文次级（说明、辅助信息）。
  static const TextStyle bodySecondary = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );

  /// 分区标题（田地状态、自动化活动）。
  static const TextStyle sectionTitle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
  );

  /// 分区标题旁说明（过去 24 小时…）。
  static const TextStyle sectionHint = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
  );

  // ── 纯数字/金额快捷样式（已切 Inter + 等宽数字）────────────

  static TextStyle numericValue(TextStyle base) => _numeric(base);

  /// 中文/混排基础样式：整行统一 NotoSansSC（含中英混排文本，禁止拆分成 fallback + Inter）。
  /// 用法：`FarmTextStyles.chineseText.merge(其他字号/字重/颜色)`。
  static const TextStyle chineseText = TextStyle(fontFamily: kFontFamilyCjk);

  /// 纯数字/金额/倒计时基础样式：切 Inter + 等宽数字。
  /// 只用于独立纯数字 Text（如 865.98、08:18:18、0、¥2,072.34），不含任何中文。
  static TextStyle get numericText => _numeric(const TextStyle());

  /// 技术文本（Cookie/token/URL/命令）：等宽字体，12/18。
  /// 只用于技术内容展示/输入，不用于中文 UI 正文。
  static const TextStyle monoText = TextStyle(
    fontFamily: kFontFamilyMono,
    fontSize: 12,
    height: 1.5,
  );
}

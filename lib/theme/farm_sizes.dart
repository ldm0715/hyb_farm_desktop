/// 尺寸令牌：统一控件与区块高度/点击区域。
library;

abstract final class FarmSizes {
  /// Header 高度。
  static const double header = 72;

  /// 一级 TabBar 总高度。
  static const double tabBar = 52;

  /// Tab 可交互区域高度。
  static const double tabInteractive = 36;

  /// IconButton 点击区域。
  static const double iconButton = 32;

  /// 普通按钮高度。
  static const double button = 36;

  /// Segmented Control 高度。
  static const double segmented = 40;

  /// Segmented Control 宽度（二级分段控件固定宽）。
  static const double segmentedWidth = 160;

  /// 指标卡高度（历史 token，收获概览卡取代后保留，避免遗留引用报错）。
  static const double metricCard = 80;

  /// 作物 icon 统一固定尺寸。
  static const double farmIcon = 28;

  /// 次级双列信息块高度（空闲地块 / 仓库估值）。
  static const double compactStat = 56;

  /// 设置页下拉控件固定宽度（避免内容过宽撑满整行）。
  static const double settingDropdown = 150;

  /// 地块卡高度。
  static const double plotCard = 96;

  /// 列表项最小高度。
  static const double listItemMin = 72;

  /// 底部出售栏高度。
  static const double sellBar = 64;

  /// 品牌图标尺寸。
  static const double brandIcon = 38;
}

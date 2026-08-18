/// 展示格式化纯函数，可脱离 UI 测试。
library;

import 'package:hyb_farm_desktop/core/constants.dart';

/// 接口价格整数 → 展示金额字符串（固定 2 位小数，带 $ 前缀）。
String formatMoney(int rawPrice) {
  return '\$${(rawPrice / kPriceDivisor).toStringAsFixed(2)}';
}

/// 接口价格整数 → 展示金额字符串（固定 2 位小数，千分位分隔，带 $ 前缀）。
String formatMoneyGrouped(int rawPrice) {
  final fixed = (rawPrice / kPriceDivisor).toStringAsFixed(2);
  final parts = fixed.split('.');
  final negative = parts[0].startsWith('-');
  final digits = negative ? parts[0].substring(1) : parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  return '\$${negative ? '-' : ''}$buf.${parts[1]}';
}

/// 秒 → "H:MM:SS"（不足一小时为 "MM:SS"）。
String formatCountdown(int seconds) {
  if (seconds <= 0) return '00:00';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

/// 时刻 → 人性化相对时间（"刚刚" / "N 分钟前" / "N 小时前" / "N 天前"）。
///
/// [now] 可注入固定当前时间（测试用），默认 `DateTime.now()`。
/// 未来时刻或系统时钟回拨时统一按「刚刚」处理，杜绝负时长。
/// 注意：本函数只负责格式化，不做 24h 过期判定（过期由 StealHistory 负责）；
/// 因此恰好 24 小时前仍输出「1 天前」。
String formatRelativeTime(DateTime? value, {DateTime? now}) {
  if (value == null) return '暂无';
  final ref = now ?? DateTime.now();
  if (!value.isBefore(ref)) return '刚刚'; // 未来/同一时刻 → 刚刚
  final diff = ref.difference(value);
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
  if (diff.inHours < 24) return '${diff.inHours} 小时前';
  return '${diff.inDays} 天前';
}

/// 秒 → 人性化剩余时长（"2小时13分" / "5分" / "已成熟"）。
String formatRemaining(int seconds) {
  if (seconds <= 0) return '已成熟';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  return h > 0 ? '$h小时$m分' : '$m分';
}

/// 作物固定成熟耗时 → "10小时0分钟" / "30分钟"（收益排行展示用）。
String formatGrowthTime(int seconds) {
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  if (hours > 0) return '$hours小时$minutes分钟';
  return '$minutes分钟';
}

/// 美元数值 → 带 $ 前缀、千分位、固定 2 位小数的展示文本。
String formatUsd(double value) {
  final fixed = value.toStringAsFixed(2);
  final parts = fixed.split('.');
  final negative = parts[0].startsWith('-');
  final digits = negative ? parts[0].substring(1) : parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  return '\$${negative ? '-' : ''}$buf.${parts[1]}';
}

/// 每小时收益金额 → 最多 4 位小数、带 $ 前缀的展示文本（对齐脚本 formatNumber）。
String formatPerHour(double value) {
  final s = value.toStringAsFixed(4);
  // 去掉末尾多余的 0 与可能残留的小数点。
  var trimmed = s.replaceFirst(RegExp(r'0+$'), '');
  if (trimmed.endsWith('.')) trimmed = trimmed.substring(0, trimmed.length - 1);
  return '\$$trimmed';
}

/// 涨跌百分比归一化到 2 位小数（方向/文案判定的基准，杜绝 ↓0.00%/↑0.00%）。
double normalizeTrendPercent(double percent) => (percent * 100).round() / 100;

/// 涨跌百分比 → 绝对值百分比文本（如 "0.09%"），方向由 UI 箭头/文案表达。
/// 入参应为已归一化（[normalizeTrendPercent]）的值。
String formatTrendPercent(double percent) =>
    '${percent.abs().toStringAsFixed(2)}%';

/// 字节数 → B/KB/MB/GB 人性化文本（下载进度 / 安装包大小展示用）。
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  var value = bytes.toDouble();
  const units = ['KB', 'MB', 'GB', 'TB'];
  var unitIndex = -1;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }
  return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} ${units[unitIndex]}';
}

/// Cookie header 脱敏：保留 key、遮蔽 value，绝不回显明文。
String maskCookie(String cookie) {
  final masked = cookie
      .split(';')
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .map((p) {
        final i = p.indexOf('=');
        if (i < 0) return '$p=•••';
        return '${p.substring(0, i + 1)}•••';
      });
  return masked.isEmpty ? '' : masked.join('; ');
}

/// 收益排行纯函数：由种子图鉴 + 实时价格构建每小时收益排行，并附带「昨日涨跌」趋势。
library;

import 'package:hyb_farm_desktop/api/models.dart';
import 'package:hyb_farm_desktop/core/constants.dart';

/// UTC 日历日（服务器自然日网格：趋势桶按 UTC 零点对齐）。
DateTime utcDay(DateTime value) {
  final utc = value.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day);
}

/// 收益排行行数据（纯数据类，由 [buildRanking] 构造）。
class RankingRow {
  const RankingRow({
    required this.seedId,
    required this.name,
    required this.iconUrl,
    required this.growthTimeSeconds,
    required this.harvestQuantity,
    required this.isVipOnly,
    required this.unitPrice,
    required this.harvestRevenue,
    required this.revenuePerHour,
    this.trendPercent,
  });

  final String seedId;
  final String name;
  final String iconUrl;
  final int growthTimeSeconds;
  final int harvestQuantity;
  final bool isVipOnly;

  /// 美元单价（接口整数 / kPriceDivisor）。
  final double unitPrice;

  /// 单次收获收益（单价 × 产量）。
  final double harvestRevenue;

  /// 每小时收益（排序指标）。
  final double revenuePerHour;

  /// 最近两个完整日（昨日 vs 前日）日均价涨跌百分比（%）；趋势数据不足时为 null。
  final double? trendPercent;
}

/// 最近两个完整日（通常是昨日 vs 前日）日均价涨跌百分比（%）。
///
/// - `serverRefreshedAt` 缺失 → null（**不回退**末桶日期）；
/// - 只保留日期严格早于「服务器今天」（`utcDay(serverRefreshedAt)`）的桶，
///   以排除今天（样本少/可能为空、不稳定）与任何未来桶；
/// - 按 UTC 日期排序（不信任接口顺序），同日重复桶去重（优先样本数更多者，
///   其次保留列表中最后出现的有效桶）；
/// - 末两桶必须连续自然日，否则 null；前一日均价 <= 0 或末价 < 0 → null。
double? priceTrendChange(List<TrendPoint> trend, DateTime? serverRefreshedAt) {
  if (serverRefreshedAt == null) return null;

  final serverToday = utcDay(serverRefreshedAt);

  final points = trend
      .where((point) => point.bucketStartedAt != null)
      .where((point) => utcDay(point.bucketStartedAt!).isBefore(serverToday))
      .toList()
    ..sort((a, b) => a.bucketStartedAt!.compareTo(b.bucketStartedAt!));

  // 按 UTC 日期去重：保留样本数更多者；相同时保留列表最后者。
  final deduped = <TrendPoint>[];
  for (final point in points) {
    if (deduped.isNotEmpty &&
        utcDay(deduped.last.bucketStartedAt!) == utcDay(point.bucketStartedAt!)) {
      if (point.sampleCount >= deduped.last.sampleCount) {
        deduped[deduped.length - 1] = point;
      }
    } else {
      deduped.add(point);
    }
  }

  if (deduped.length < 2) return null;

  final previous = deduped[deduped.length - 2];
  final latest = deduped.last;

  final previousDay = utcDay(previous.bucketStartedAt!);
  final latestDay = utcDay(latest.bucketStartedAt!);
  if (latestDay.difference(previousDay).inDays != 1) return null;

  final previousPrice = previous.avgUnitPriceInt;
  final latestPrice = latest.avgUnitPriceInt;
  if (previousPrice <= 0 || latestPrice < 0) return null;

  return (latestPrice - previousPrice) / previousPrice * 100;
}

/// 根据种子与实时单价构建收益排行，按每小时收益降序。
///
/// 对齐脚本 `buildRanking`：`revenuePerHour = unitPrice × harvestQuantity /
/// growthTimeSeconds × 3600`。价格缺失、成长时间为 0 或产量非法的种子被过滤。
/// `trends`/`serverRefreshedAt` 可选：提供时每行附带「昨日涨跌」百分比。
List<RankingRow> buildRanking(
  List<Seed> seeds,
  Map<String, int> unitPrices, {
  Map<String, List<TrendPoint>> trends = const {},
  DateTime? serverRefreshedAt,
}) {
  final rows = <RankingRow>[];

  for (final seed in seeds) {
    final raw = unitPrices[seed.id];
    if (raw == null || seed.growthTime <= 0 || seed.harvestQuantity <= 0) {
      continue;
    }

    final unitPrice = raw / kPriceDivisor;
    final harvestRevenue = unitPrice * seed.harvestQuantity;
    final revenuePerHour = harvestRevenue / seed.growthTime * 3600;

    rows.add(
      RankingRow(
        seedId: seed.id,
        name: seed.name,
        iconUrl: cropIconUrl(seed.image),
        growthTimeSeconds: seed.growthTime,
        harvestQuantity: seed.harvestQuantity,
        isVipOnly: seed.isVipOnly,
        unitPrice: unitPrice,
        harvestRevenue: harvestRevenue,
        revenuePerHour: revenuePerHour,
        trendPercent: priceTrendChange(
          trends[seed.id] ?? const [],
          serverRefreshedAt,
        ),
      ),
    );
  }

  rows.sort((a, b) => b.revenuePerHour.compareTo(a.revenuePerHour));
  return rows;
}

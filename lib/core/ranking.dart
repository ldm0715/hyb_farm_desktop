/// 收益排行纯函数：由种子图鉴 + 实时价格构建每小时收益排行。
library;

import 'package:hyb_farm_desktop/api/models.dart';
import 'package:hyb_farm_desktop/core/constants.dart';

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
}

/// 根据种子与实时单价构建收益排行，按每小时收益降序。
///
/// 对齐脚本 `buildRanking`：`revenuePerHour = unitPrice × harvestQuantity /
/// growthTimeSeconds × 3600`。价格缺失、成长时间为 0 或产量非法的种子被过滤。
List<RankingRow> buildRanking(List<Seed> seeds, Map<String, int> unitPrices) {
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
      ),
    );
  }

  rows.sort((a, b) => b.revenuePerHour.compareTo(a.revenuePerHour));
  return rows;
}

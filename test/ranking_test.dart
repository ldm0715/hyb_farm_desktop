/// buildRanking 收益排行纯函数测试：公式、排序、过滤。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:hyb_farm_desktop/api/models.dart';
import 'package:hyb_farm_desktop/core/constants.dart';
import 'package:hyb_farm_desktop/core/ranking.dart';

void main() {
  Seed seed({
    required String id,
    int growthTime = 3600,
    int harvestQuantity = 1,
    bool isVipOnly = false,
  }) => Seed(
    id: id,
    name: id,
    image: '/farm/crops/$id',
    growthTime: growthTime,
    harvestQuantity: harvestQuantity,
    isVipOnly: isVipOnly,
  );

  test('公式：revenuePerHour = 单价×产量/成长时间×3600', () {
    final seeds = [seed(id: 'a', growthTime: 3600, harvestQuantity: 2)];
    final prices = {'a': kPriceDivisor}; // 单价 = $1.00

    final rows = buildRanking(seeds, prices);

    expect(rows.length, 1);
    final r = rows.single;
    expect(r.unitPrice, 1.0);
    expect(r.harvestRevenue, 2.0);
    // 2.0 / 3600 * 3600 = 2.0
    expect(r.revenuePerHour, 2.0);
  });

  test('按每小时收益降序排列', () {
    final seeds = [
      seed(id: 'slow', growthTime: 7200, harvestQuantity: 1), // 0.5/h
      seed(id: 'fast', growthTime: 1800, harvestQuantity: 2), // 4.0/h
      seed(id: 'mid', growthTime: 3600, harvestQuantity: 1), // 1.0/h
    ];
    final prices = {
      'slow': kPriceDivisor,
      'fast': kPriceDivisor,
      'mid': kPriceDivisor,
    };

    final rows = buildRanking(seeds, prices);

    expect(rows.map((r) => r.seedId).toList(), ['fast', 'mid', 'slow']);
  });

  test('过滤缺失价格 / 成长时间为 0 / 产量为 0 的种子', () {
    final seeds = [
      seed(id: 'noPrice'),
      seed(id: 'zeroGrowth', growthTime: 0),
      seed(id: 'zeroYield', harvestQuantity: 0),
      seed(id: 'ok'),
    ];
    final prices = {'ok': kPriceDivisor};

    final rows = buildRanking(seeds, prices);

    expect(rows.length, 1);
    expect(rows.single.seedId, 'ok');
  });

  test('空输入返回空列表', () {
    expect(buildRanking(const [], const {}), isEmpty);
  });
}

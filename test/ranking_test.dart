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

  // ---- 昨日涨跌（最近两个完整日）趋势 ----

  TrendPoint point(
    String day, {
    int price = 0,
    int samples = 1,
  }) => TrendPoint(
    bucketStartedAt: DateTime.utc(2026, 8, int.parse(day)),
    avgUnitPrice: price.toString(),
    avgTotalSupply: 0,
    sampleCount: samples,
  );

  final refreshedAt = DateTime.utc(2026, 8, 18, 4, 17); // 服务器今天 = 8/18

  group('priceTrendChange', () {
    test('示例：剔除今天(8/18)后取 8/17 vs 8/16 → +0.09%', () {
      final trend = [
        point('16', price: 21639),
        point('17', price: 21659),
        point('18', price: 21571), // 今天的桶：不稳定，应剔除
      ];
      expect(priceTrendChange(trend, refreshedAt), closeTo(0.09, 0.01));
    });

    test('serverRefreshedAt 缺失 → null（不回退末桶日期）', () {
      final trend = [point('16', price: 100), point('17', price: 110)];
      expect(priceTrendChange(trend, null), isNull);
    });

    test('仅今天的桶 → null', () {
      final trend = [point('18', price: 100)];
      expect(priceTrendChange(trend, refreshedAt), isNull);
    });

    test('剔除今天后仅剩 1 个桶 → null', () {
      final trend = [point('17', price: 100), point('18', price: 110)];
      expect(priceTrendChange(trend, refreshedAt), isNull);
    });

    test('剔除今天后剩 2 个桶 → 正确差值', () {
      final trend = [
        point('16', price: 200),
        point('17', price: 210),
        point('18', price: 220),
      ];
      expect(priceTrendChange(trend, refreshedAt), closeTo(5.0, 0.001));
    });

    test('排除未来桶（今天 8/18，含 8/19 → 排除）', () {
      final trend = [
        point('16', price: 100),
        point('17', price: 110),
        point('18', price: 120),
        point('19', price: 130), // 未来桶：必须排除
      ];
      expect(priceTrendChange(trend, refreshedAt), closeTo(10.0, 0.001));
    });

    test('输入乱序 → 按 UTC 日期排序后取最近两个完整日', () {
      final trend = [
        point('18', price: 120),
        point('16', price: 100),
        point('17', price: 110),
      ];
      expect(priceTrendChange(trend, refreshedAt), closeTo(10.0, 0.001));
    });

    test('剔除今天后剩余桶不连续（8/14, 8/16）→ null', () {
      final trend = [
        point('14', price: 100),
        point('16', price: 110),
        point('18', price: 120),
      ];
      expect(priceTrendChange(trend, refreshedAt), isNull);
    });

    test('同日重复桶按 UTC 日去重：保留样本数更多者', () {
      final trend = [
        point('16', price: 100, samples: 1),
        point('17', price: 105, samples: 2),
        point('17', price: 110, samples: 10), // 同一天：样本更多者胜
        point('18', price: 120),
      ];
      expect(priceTrendChange(trend, refreshedAt), closeTo(10.0, 0.001));
    });

    test('前一日均价 <= 0 → null', () {
      final trend = [
        point('16', price: 0),
        point('17', price: 110),
        point('18', price: 120),
      ];
      expect(priceTrendChange(trend, refreshedAt), isNull);
    });

    test('末价 < 0 → null', () {
      final trend = [
        point('16', price: 100),
        point('17', price: -1),
        point('18', price: 120),
      ];
      expect(priceTrendChange(trend, refreshedAt), isNull);
    });

    test('末两桶均价相等 → 0', () {
      final trend = [
        point('16', price: 100),
        point('17', price: 100),
        point('18', price: 100),
      ];
      expect(priceTrendChange(trend, refreshedAt), 0);
    });

    test('空趋势 / 日期缺失桶 → null', () {
      expect(priceTrendChange(const [], refreshedAt), isNull);
      final bad = [TrendPoint(avgUnitPrice: '100')];
      expect(priceTrendChange(bad, refreshedAt), isNull);
    });
  });

  group('buildRanking 附带趋势', () {
    test('提供 trends 时填入 trendPercent', () {
      final seeds = [seed(id: 'a')];
      final prices = {'a': kPriceDivisor};
      final trends = {
        'a': [
          point('16', price: 100),
          point('17', price: 110),
          point('18', price: 120),
        ],
      };
      final rows = buildRanking(
        seeds,
        prices,
        trends: trends,
        serverRefreshedAt: refreshedAt,
      );
      expect(rows.single.trendPercent, closeTo(10.0, 0.001));
    });

    test('缺趋势 / 无 serverRefreshedAt → trendPercent 为 null', () {
      final seeds = [seed(id: 'a')];
      final prices = {'a': kPriceDivisor};
      final noTrend = buildRanking(seeds, prices);
      expect(noTrend.single.trendPercent, isNull);

      final withTrend = buildRanking(
        seeds,
        prices,
        trends: {
          'a': [
            point('16', price: 100),
            point('17', price: 110),
            point('18', price: 120),
          ],
        },
      );
      expect(withTrend.single.trendPercent, isNull); // 无 serverRefreshedAt
    });
  });
}

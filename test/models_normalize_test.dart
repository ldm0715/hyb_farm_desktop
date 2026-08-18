/// 数据模型归一化测试：手写 fromJson 对接口字段的解析、兜底与派生属性。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyb_farm_desktop/api/models.dart';

Map<String, dynamic> _loadFixture(String name) {
  final raw = File('test/fixtures/$name').readAsStringSync();
  return jsonDecode(raw) as Map<String, dynamic>;
}

void main() {
  group('Crop', () {
    test('fromJson 解析字段与日期', () {
      final crop = Crop.fromJson({
        'id': 'crop-1',
        'seedId': 'pumpkin',
        'seedName': '南瓜',
        'seedImage': '/farm/crops/pumpkin',
        'plotIndex': 2,
        'plantedAt': '2026-08-14T02:00:00.000Z',
        'maturesAt': '2026-08-14T04:00:00.000Z',
        'isMature': false,
        'remainingTime': 1800,
        'conditions': [
          {'kind': 'thirsty'},
        ],
      });

      expect(crop.id, 'crop-1');
      expect(crop.seedId, 'pumpkin');
      expect(crop.plotIndex, 2);
      expect(crop.plantedAt, DateTime.parse('2026-08-14T02:00:00.000Z'));
      expect(crop.maturesAt, DateTime.parse('2026-08-14T04:00:00.000Z'));
      expect(crop.mature, isFalse);
      expect(crop.hasDebuff, isTrue);
      expect(crop.isEmpty, isFalse);
    });

    test('成熟判定：isMature 或 remainingTime<=0', () {
      const matureByFlag = Crop(
        id: 'a',
        seedId: 's',
        seedName: 'n',
        seedImage: 'img',
        plotIndex: 0,
        isMature: true,
        remainingTime: 999,
      );
      expect(matureByFlag.mature, isTrue);

      const matureByTime = Crop(
        id: 'a',
        seedId: 's',
        seedName: 'n',
        seedImage: 'img',
        plotIndex: 0,
        isMature: false,
        remainingTime: 0,
      );
      expect(matureByTime.mature, isTrue);
    });

    test('conditions 过滤非法项与空 kind', () {
      final crop = Crop.fromJson({
        'id': 'a',
        'seedId': 's',
        'seedName': 'n',
        'seedImage': 'img',
        'plotIndex': 0,
        'conditions': [
          {'kind': 'thirsty'},
          {'kind': ''},
          'not-a-map',
          {'other': 'x'},
        ],
      });
      expect(crop.conditions, ['thirsty']);
      expect(crop.hasDebuff, isTrue);
    });

    test('iconUrl 拼接 baseUrl + seedImage + 后缀', () {
      const crop = Crop(
        id: 'a',
        seedId: 's',
        seedName: 'n',
        seedImage: '/farm/crops/pumpkin',
        plotIndex: 0,
      );
      expect(crop.iconUrl, 'https://cdk.hybgzs.com/farm/crops/pumpkin_s4.png');
    });
  });

  group('CropsResponse', () {
    test('从 fixture 解析 crops 字段与 maxSlots', () {
      final resp = CropsResponse.fromJson(_loadFixture('crops.json'));
      expect(resp.crops.length, 2);
      expect(resp.totalSlots, 6);
      expect(resp.plantedCount, 2);
      expect(resp.freeSlots, 4);
      expect(resp.crops.first.seedName, '南瓜');
      expect(resp.crops.first.hasDebuff, isTrue);
    });

    test('data 字段为数组时不丢失外层 maxSlots', () {
      final resp = CropsResponse.fromJson({
        'success': true,
        'data': [
          {
            'id': 'a',
            'seedId': 's',
            'seedName': 'n',
            'seedImage': 'img',
            'plotIndex': 0,
          },
        ],
        'maxSlots': 6,
      });
      expect(resp.crops.length, 1);
      expect(resp.totalSlots, 6);
    });

    test('maxSlots 缺失时用 plotLevels 最大 plotIndex+1 兜底', () {
      final resp = CropsResponse.fromJson({
        'crops': [],
        'plotLevels': [
          {'plotIndex': 0, 'level': 1, 'theme': 'a'},
          {'plotIndex': 3, 'level': 2, 'theme': 'b'},
        ],
      });
      expect(resp.totalSlots, 4);
    });

    test('无作物且无 plotLevels 时 totalSlots 为 0', () {
      const resp = CropsResponse(crops: []);
      expect(resp.totalSlots, 0);
      expect(resp.freeSlots, 0);
    });
  });

  group('FarmPlots', () {
    test('从 fixture 的 data 对象解析', () {
      final data = _loadFixture('plots.json')['data'] as Map<String, dynamic>;
      final plots = FarmPlots.fromJson(data);
      expect(plots.totalSlots, 6);
      expect(plots.freeSlots, 3);
    });
  });

  group('InventoryItem', () {
    test('从 fixture 解析数组并归一化 recyclePriceInt', () {
      final data = _loadFixture('inventory.json')['data'] as List<dynamic>;
      final items = data
          .whereType<Map<String, dynamic>>()
          .map(InventoryItem.fromJson)
          .toList();

      expect(items.length, 3);
      expect(items.first.seedId, 'pumpkin');
      expect(items.first.quantity, 12);
      expect(items.first.recyclePriceInt, 612581);
      expect(
        items.first.iconUrl,
        'https://cdk.hybgzs.com/farm/crops/pumpkin_s4.png',
      );
    });

    test('recyclePrice 非数字时回退为 0', () {
      final item = InventoryItem.fromJson({
        'seedId': 'x',
        'seedName': 'x',
        'seedImage': '/x',
        'quantity': 1,
        'recyclePrice': 'oops',
      });
      expect(item.recyclePriceInt, 0);
    });
  });

  group('Seed', () {
    test('从 fixture 解析 data.seeds', () {
      final data = _loadFixture('seeds.json')['data'] as Map<String, dynamic>;
      final seeds = (data['seeds'] as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map(Seed.fromJson)
          .toList();

      expect(seeds.length, 2);
      expect(seeds.first.id, 'pumpkin');
      expect(seeds.first.growthTime, 7200);
      expect(seeds.last.isVipOnly, isTrue);
    });
  });

  group('CareAllResult', () {
    test('读外层字段并按类型解析 byKind', () {
      final result = CareAllResult.fromJson(_loadFixture('care_all.json'));
      expect(result.processed, 3);
      expect(result.skipped, 4);
      expect(result.energySpent, 15);
      expect(result.byKind, {'thirsty': 2, 'weed': 1, 'pest': 0});
    });

    test('byKind 仅保留数值类型', () {
      final result = CareAllResult.fromJson({
        'processed': 1,
        'skipped': 0,
        'energySpent': 5,
        'byKind': {'thirsty': 2, 'weed': 'x', 'pest': 1},
      });
      expect(result.byKind, {'thirsty': 2, 'pest': 1});
    });
  });

  group('PlantBatchResult', () {
    test('从 fixture 的 data 对象解析', () {
      final data =
          _loadFixture('plant_batch.json')['data'] as Map<String, dynamic>;
      final result = PlantBatchResult.fromJson(data);
      expect(result.plantedCount, 2);
      expect(result.totalCost, '5000');
    });
  });

  group('RecyclePrice', () {
    test('从 fixture 解析数组并归一化 recyclePriceInt', () {
      final data = _loadFixture('recycle_prices.json')['data'] as List<dynamic>;
      final prices = data
          .whereType<Map<String, dynamic>>()
          .map(RecyclePrice.fromJson)
          .toList();

      expect(prices.length, 3);
      expect(prices.first.seedId, 'pumpkin');
      expect(prices.first.recyclePriceInt, 612581);
    });
  });

  group('MarketItem / TrendPoint', () {
    test('从 fixture 解析 trend 桶与 lastRefreshedAt', () {
      final market = _loadFixture('price_trends.json')['market']
          as Map<String, dynamic>;
      final items = market['items'] as List<dynamic>;
      final corn = MarketItem.fromJson(items[0] as Map<String, dynamic>);

      expect(corn.seedId, 'corn');
      expect(corn.unitPriceInt, 21570);
      expect(corn.lastRefreshedAt, DateTime.parse('2026-08-18T04:17:06.664Z'));
      expect(corn.trend.length, 3);

      final first = corn.trend[0];
      expect(first.bucketStartedAt, DateTime.utc(2026, 8, 16));
      expect(first.avgUnitPriceInt, 21639);
      expect(first.avgTotalSupply, 95649);
      expect(first.sampleCount, 6);
    });

    test('trend 缺失 / 空数组 → 空列表', () {
      final market = _loadFixture('price_trends.json')['market']
          as Map<String, dynamic>;
      final items = market['items'] as List<dynamic>;
      final wheat = MarketItem.fromJson(items[1] as Map<String, dynamic>);
      final barley = MarketItem.fromJson(items[2] as Map<String, dynamic>);

      expect(wheat.trend, isEmpty);
      expect(barley.trend, isEmpty);
      expect(barley.lastRefreshedAt, isNull);
    });

    test('TrendPoint toJson/fromJson 往返', () {
      const point = TrendPoint(
        bucketStartedAt: null,
        avgUnitPrice: '21659',
        avgTotalSupply: 93290,
        sampleCount: 10,
      );
      final restored = TrendPoint.fromJson(point.toJson());
      expect(restored.avgUnitPriceInt, 21659);
      expect(restored.avgTotalSupply, 93290);
      expect(restored.sampleCount, 10);
      expect(restored.bucketStartedAt, isNull);
    });
  });

  group('RecycleQuote', () {
    test('从 fixture 的 data 对象解析', () {
      final data =
          _loadFixture('recycle_quote.json')['data'] as Map<String, dynamic>;
      final q = RecycleQuote.fromJson(data);

      expect(q.seedId, 'pumpkin');
      expect(q.quantity, 2);
      expect(q.unitPrice, '612581');
      expect(q.totalQuota, '1225162');
      expect(q.quotedAt, DateTime.parse('2026-08-14T10:00:00.000Z'));
    });
  });

  group('RecycleResult', () {
    test('从 fixture 的 data 对象解析并归一化 totalQuotaInt', () {
      final data = _loadFixture('recycle.json')['data'] as Map<String, dynamic>;
      final r = RecycleResult.fromJson(data);

      expect(r.seedId, 'pumpkin');
      expect(r.quantity, 2);
      expect(r.totalQuotaInt, 1225162);
      expect(r.slippageBps, 0);
    });
  });

  group('UserInfo', () {
    test('fromJson 解析 username 与 avatar', () {
      final info = UserInfo.fromJson({
        'username': 'Alice',
        'avatar': 'https://cdn.example.com/a.png',
      });
      expect(info.username, 'Alice');
      expect(info.avatar, 'https://cdn.example.com/a.png');
    });

    test('缺失字段回退空串', () {
      const info = UserInfo();
      expect(info.username, '');
      expect(info.avatar, '');
    });
  });
}

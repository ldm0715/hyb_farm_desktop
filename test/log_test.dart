/// HarvestLog / CareLog 滚动 24 小时窗口统计测试。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyb_farm_desktop/api/models.dart';
import 'package:hyb_farm_desktop/services/care_log.dart';
import 'package:hyb_farm_desktop/services/harvest_log.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HarvestLog', () {
    test('record 后按 seedName 聚合次数', () async {
      SharedPreferences.setMockInitialValues({});
      final log = await HarvestLog.create();

      await log.record([
        const Crop(
          id: 'a',
          seedId: 'p',
          seedName: '南瓜',
          seedImage: '/p',
          plotIndex: 0,
        ),
        const Crop(
          id: 'b',
          seedId: 'p',
          seedName: '南瓜',
          seedImage: '/p',
          plotIndex: 1,
        ),
        const Crop(
          id: 'c',
          seedId: 'c',
          seedName: '玉米',
          seedImage: '/c',
          plotIndex: 2,
        ),
      ]);

      final counts = log.countsWithin(const Duration(hours: 24));
      expect(counts['南瓜']!.count, 2);
      expect(counts['玉米']!.count, 1);
      expect(log.totalWithin(const Duration(hours: 24)), 3);
    });

    test('record 跳过空地（id 为空）', () async {
      SharedPreferences.setMockInitialValues({});
      final log = await HarvestLog.create();

      await log.record([
        const Crop(
          id: '',
          seedId: '',
          seedName: '',
          seedImage: '',
          plotIndex: 0,
        ),
        const Crop(
          id: 'a',
          seedId: 'p',
          seedName: '南瓜',
          seedImage: '/p',
          plotIndex: 1,
        ),
      ]);

      expect(log.totalWithin(const Duration(hours: 24)), 1);
    });

    test('过滤 24h 窗口外的旧记录', () async {
      final old = DateTime.now().millisecondsSinceEpoch - 25 * 3600 * 1000;
      SharedPreferences.setMockInitialValues({
        'hyb-farm-harvest-log': jsonEncode([
          {'seedId': 'old', 'seedName': '旧作物', 'seedImage': '/old', 'at': old},
        ]),
      });
      final log = await HarvestLog.create();

      expect(log.totalWithin(const Duration(hours: 24)), 0);
    });
  });

  group('CareLog', () {
    test('record 后按 debuff 类型聚合', () async {
      SharedPreferences.setMockInitialValues({});
      final log = await CareLog.create();

      await log.record({'thirsty': 2, 'weed': 1, 'pest': 0});

      final counts = log.countsWithin(const Duration(hours: 24));
      expect(counts['thirsty'], 2);
      expect(counts['weed'], 1);
      expect(counts['pest'], isNull); // 0 不产生记录
      expect(log.totalWithin(const Duration(hours: 24)), 3);
    });

    test('过滤 24h 窗口外的旧记录', () async {
      final old = DateTime.now().millisecondsSinceEpoch - 25 * 3600 * 1000;
      SharedPreferences.setMockInitialValues({
        'hyb-farm-care-log': jsonEncode([
          {'kind': 'thirsty', 'at': old},
        ]),
      });
      final log = await CareLog.create();

      expect(log.totalWithin(const Duration(hours: 24)), 0);
    });
  });
}

/// PriceTrendStore 测试：服务器 UTC 自然日一天一次（成败同计、重启不重置）、
/// 时钟偏移容忍 / 回拨防御、schema 版本与命名空间隔离。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hyb_farm_desktop/api/farm_api.dart';
import 'package:hyb_farm_desktop/api/models.dart';
import 'package:hyb_farm_desktop/services/price_trend_store.dart';

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  PriceTrendStore store() => PriceTrendStore(prefs, PriceTrendStore.keyFor(null));

  // 服务器 8/18 04:00Z 刷新的一份趋势快照。
  PriceTrends result8_18({bool withData = true}) => PriceTrends(
    bySeedId: withData
        ? {
            'corn': [
              TrendPoint(
                bucketStartedAt: DateTime.utc(2026, 8, 17),
                avgUnitPrice: '21659',
                sampleCount: 10,
              ),
              TrendPoint(
                bucketStartedAt: DateTime.utc(2026, 8, 16),
                avgUnitPrice: '21639',
                sampleCount: 8,
              ),
            ],
          }
        : const {},
    serverObservedAt: DateTime.utc(2026, 8, 18, 4),
    dataRefreshedAt: DateTime.utc(2026, 8, 18, 4),
  );

  test('首次无记录 → shouldAttempt 为 true', () {
    expect(store().shouldAttempt(DateTime.utc(2026, 8, 18, 12)), isTrue);
  });

  test('recordAttempt 后同服务器日 → false（成功/失败同判）', () async {
    final s = store();
    // 先成功建立服务器锚点（服务器 8/18，本地同刻 8/18 12:00）。
    await s.recordSuccess(
      result: result8_18(),
      localReceivedAt: DateTime.utc(2026, 8, 18, 12),
    );
    // 同日失败尝试：只 recordAttempt，不 recordSuccess。
    await s.recordAttempt(s.createAttempt(DateTime.utc(2026, 8, 18, 20)));
    expect(s.shouldAttempt(DateTime.utc(2026, 8, 18, 23)), isFalse);
  });

  test('服务器自然日变化 → 允许重新尝试（不要求严格 24h 间隔）', () async {
    final s = store();
    await s.recordSuccess(
      result: result8_18(),
      localReceivedAt: DateTime.utc(2026, 8, 18, 12),
    );
    // 本地推进 24h+ → 估算服务器已跨入 8/19。
    expect(s.shouldAttempt(DateTime.utc(2026, 8, 19, 12)), isTrue);
  });

  test('无锚点（从未成功）时 24h 本地流逝兜底', () async {
    final s = store();
    // 首次尝试失败（无锚点）→ 本地时刻记下。
    await s.recordAttempt(s.createAttempt(DateTime.utc(2026, 8, 18, 4)));
    expect(s.shouldAttempt(DateTime.utc(2026, 8, 18, 5)), isFalse); // 1h
    expect(s.shouldAttempt(DateTime.utc(2026, 8, 19, 5)), isTrue); // 25h
  });

  test('陈旧不能突破当日上限：当天已尝试 + 时间推进 → 仍 false', () async {
    final s = store();
    await s.recordSuccess(
      result: result8_18(),
      localReceivedAt: DateTime.utc(2026, 8, 18, 12),
    );
    await s.recordAttempt(s.createAttempt(DateTime.utc(2026, 8, 18, 20)));
    // 同日多时段再查：即使本地流逝已接近 24h，当日上限依然挡住。
    expect(s.shouldAttempt(DateTime.utc(2026, 8, 18, 22)), isFalse);
    expect(s.shouldAttempt(DateTime.utc(2026, 8, 18, 23, 59)), isFalse);
  });

  test('客户端时间领先（固定偏移）：不产生重复请求循环', () async {
    final s = store();
    // 客户端时钟比服务器快 2 天：服务器 8/18，本地 8/20。
    await s.recordSuccess(
      result: result8_18(),
      localReceivedAt: DateTime.utc(2026, 8, 20, 12),
    );
    await s.recordAttempt(s.createAttempt(DateTime.utc(2026, 8, 20, 13)));
    // 本地再推进数小时：估算服务器仍为 8/18 → 当天已尝试 → 不再请求。
    expect(s.shouldAttempt(DateTime.utc(2026, 8, 20, 15)), isFalse);
    expect(s.shouldAttempt(DateTime.utc(2026, 8, 20, 20)), isFalse);
  });

  test('客户端时间回拨：负流逝按 0 处理、不抛异常、不绕过门控', () async {
    final s = store();
    await s.recordSuccess(
      result: result8_18(),
      localReceivedAt: DateTime.utc(2026, 8, 18, 12),
    );
    await s.recordAttempt(s.createAttempt(DateTime.utc(2026, 8, 18, 20)));
    // 回拨：now 早于 localObservedAt。
    expect(
      () => s.shouldAttempt(DateTime.utc(2026, 8, 18, 6)),
      returnsNormally,
    );
    expect(s.shouldAttempt(DateTime.utc(2026, 8, 18, 6)), isFalse);
  });

  test('重启（同 prefs 新建实例）：同日不重试、跨日重试', () async {
    final s1 = store();
    await s1.recordSuccess(
      result: result8_18(),
      localReceivedAt: DateTime.utc(2026, 8, 18, 12),
    );
    await s1.recordAttempt(s1.createAttempt(DateTime.utc(2026, 8, 18, 20)));

    final s2 = store(); // 「重启」：同一 prefs 的新实例
    expect(s2.shouldAttempt(DateTime.utc(2026, 8, 18, 23)), isFalse);
    expect(s2.shouldAttempt(DateTime.utc(2026, 8, 19, 12)), isTrue);
  });

  test('recordSuccess 仅成功后替换 data；失败尝试保留旧 data', () async {
    final s = store();
    await s.recordSuccess(
      result: result8_18(),
      localReceivedAt: DateTime.utc(2026, 8, 18, 12),
    );
    expect(s.loadData()?.bySeedId.keys, contains('corn'));

    // 失败尝试：只 recordAttempt，不 recordSuccess。
    await s.recordAttempt(s.createAttempt(DateTime.utc(2026, 8, 18, 20)));
    expect(s.loadData()?.bySeedId.keys, contains('corn')); // 旧数据保留
  });

  test('无数据 + 未尝试 → 尝试；无数据 + 当天已尝试 → 不尝试', () async {
    final s = store();
    expect(s.shouldAttempt(DateTime.utc(2026, 8, 18, 12)), isTrue);

    await s.recordAttempt(s.createAttempt(DateTime.utc(2026, 8, 18, 12)));
    expect(s.shouldAttempt(DateTime.utc(2026, 8, 18, 12)), isFalse);
  });

  test('未知 schemaVersion → 丢弃返回空', () async {
    await prefs.setString(
      PriceTrendStore.keyFor(null),
      jsonEncode({'schemaVersion': 99, 'lastAttemptedLocalAt': '2026-08-18T12:00:00Z'}),
    );
    final s = store();
    expect(s.loadData(), isNull);
    expect(s.shouldAttempt(DateTime.utc(2026, 8, 18, 12)), isTrue); // 视为首次
  });

  test('JSON 损坏 → 空状态且不抛', () async {
    await prefs.setString(PriceTrendStore.keyFor(null), 'not-json{{{');
    final s = store();
    expect(() => s.shouldAttempt(DateTime.utc(2026, 8, 18, 12)), returnsNormally);
    expect(s.loadData(), isNull);
  });

  test('命名空间隔离：不同 accountId 互不影响', () async {
    final sA = PriceTrendStore(prefs, PriceTrendStore.keyFor('accountA'));
    final sB = PriceTrendStore(prefs, PriceTrendStore.keyFor('accountB'));
    await sA.recordAttempt(sA.createAttempt(DateTime.utc(2026, 8, 18, 12)));
    expect(sA.shouldAttempt(DateTime.utc(2026, 8, 18, 12)), isFalse);
    expect(sB.shouldAttempt(DateTime.utc(2026, 8, 18, 12)), isTrue);
  });

  test('持久化往返：recordSuccess 后重启能恢复完整状态', () async {
    final s1 = store();
    await s1.recordSuccess(
      result: result8_18(),
      localReceivedAt: DateTime.utc(2026, 8, 18, 12),
    );
    final s2 = store();
    final data = s2.loadData();
    expect(data, isNotNull);
    expect(data!.bySeedId['corn']!.length, 2);
    expect(data.bySeedId['corn']!.first.avgUnitPriceInt, 21659);
    expect(data.serverObservedAt, DateTime.utc(2026, 8, 18, 4));
    expect(data.dataRefreshedAt, DateTime.utc(2026, 8, 18, 4));
  });
}

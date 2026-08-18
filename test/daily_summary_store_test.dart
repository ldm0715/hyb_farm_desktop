/// DailySummaryStore 测试：服务器 UTC 自然日一天成功一次（失败可重试、重启不重置）、
/// schema 版本与命名空间隔离。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hyb_farm_desktop/api/models.dart';
import 'package:hyb_farm_desktop/services/daily_summary_store.dart';

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  DailySummaryStore store() =>
      DailySummaryStore(prefs, DailySummaryStore.keyFor(null));

  // 服务器 8/18 生成的前一天（8/17）日报快照。
  DailySummary result8_18() => const DailySummary(
    summary: DailySummaryData(
      date: '2026-08-17',
      stolen: StolenSummary(
        totalQuantity: 47,
        cropsReturned: 0,
        quotaPenalty: '0.00',
        stealerCount: 1,
        topStealers: [StealerEntry(userId: 'u1', username: 'yanzexi', quantity: 47)],
      ),
      helped: HelpedSummary(),
      hasContent: true,
    ),
    shouldAutoShow: false,
    periodDate: '2026-08-18',
  );

  test('首次无记录 → shouldAttempt 为 true', () {
    expect(store().shouldAttempt(DateTime.utc(2026, 8, 18, 12)), isTrue);
  });

  test('recordSuccess 后同日 → false（成功门控）', () async {
    final s = store();
    await s.recordSuccess(
      result: result8_18(),
      localReceivedAt: DateTime.utc(2026, 8, 18, 12),
    );
    expect(s.shouldAttempt(DateTime.utc(2026, 8, 18, 23)), isFalse);
  });

  test('成功后跨日 → 允许重新请求', () async {
    final s = store();
    await s.recordSuccess(
      result: result8_18(),
      localReceivedAt: DateTime.utc(2026, 8, 18, 12),
    );
    expect(s.shouldAttempt(DateTime.utc(2026, 8, 19, 12)), isTrue);
  });

  test('失败后最小间隔内不重试、满间隔可重试', () async {
    final s = store();
    // 失败尝试（无成功记录）：只 recordAttempt。
    await s.recordAttempt(s.createAttempt(DateTime.utc(2026, 8, 18, 4)));
    expect(s.shouldAttempt(DateTime.utc(2026, 8, 18, 4, 29)), isFalse); // 29min
    expect(s.shouldAttempt(DateTime.utc(2026, 8, 18, 4, 30)), isTrue); // 满 30min
  });

  test('失败后跨日（无成功）仍可请求', () async {
    final s = store();
    await s.recordAttempt(s.createAttempt(DateTime.utc(2026, 8, 18, 4)));
    expect(s.shouldAttempt(DateTime.utc(2026, 8, 19, 12)), isTrue);
  });

  test('重启（同 prefs 新建实例）：同日不重试、跨日重试', () async {
    final s1 = store();
    await s1.recordSuccess(
      result: result8_18(),
      localReceivedAt: DateTime.utc(2026, 8, 18, 12),
    );

    final s2 = store(); // 「重启」：同一 prefs 的新实例
    expect(s2.shouldAttempt(DateTime.utc(2026, 8, 18, 23)), isFalse);
    expect(s2.shouldAttempt(DateTime.utc(2026, 8, 19, 12)), isTrue);
  });

  test('recordSuccess 仅成功后替换 data；失败尝试保留旧 data', () async {
    final s = store();
    // 仅失败尝试 → 无缓存数据。
    await s.recordAttempt(s.createAttempt(DateTime.utc(2026, 8, 18, 12)));
    expect(s.loadData(), isNull);

    await s.recordSuccess(
      result: result8_18(),
      localReceivedAt: DateTime.utc(2026, 8, 18, 12),
    );
    expect(s.loadData()?.periodDate, '2026-08-18');
  });

  test('未知 schemaVersion → 丢弃返回空（视为首次）', () async {
    await prefs.setString(
      DailySummaryStore.keyFor(null),
      jsonEncode({'schemaVersion': 99, 'periodDate': '2026-08-18'}),
    );
    final s = store();
    expect(s.loadData(), isNull);
    expect(s.shouldAttempt(DateTime.utc(2026, 8, 18, 12)), isTrue);
  });

  test('JSON 损坏 → 空状态且不抛', () async {
    await prefs.setString(DailySummaryStore.keyFor(null), 'not-json{{{');
    final s = store();
    expect(
      () => s.shouldAttempt(DateTime.utc(2026, 8, 18, 12)),
      returnsNormally,
    );
    expect(s.loadData(), isNull);
  });

  test('命名空间隔离：不同 accountId 互不影响', () async {
    final sA = DailySummaryStore(prefs, DailySummaryStore.keyFor('accountA'));
    final sB = DailySummaryStore(prefs, DailySummaryStore.keyFor('accountB'));
    await sA.recordSuccess(
      result: result8_18(),
      localReceivedAt: DateTime.utc(2026, 8, 18, 12),
    );
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
    expect(data!.periodDate, '2026-08-18');
    expect(data.summary.date, '2026-08-17');
    expect(data.summary.stolen.totalQuantity, 47);
    expect(data.summary.stolen.stealerCount, 1);
    expect(data.summary.stolen.topStealers.single.username, 'yanzexi');
    expect(data.summary.stolen.topStealers.single.quantity, 47);
  });
}

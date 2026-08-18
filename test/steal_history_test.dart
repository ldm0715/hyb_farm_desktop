/// StealHistory 测试：24h 保留期、健壮解码、prune、未来时间策略、持久化往返。
///
/// 边界测试全部注入固定 now，不依赖测试执行时的真实时间。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyb_farm_desktop/services/steal_history.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fixedNow = DateTime(2026, 1, 1, 12, 0, 0);

  // 创建全新实例（每次重置 mock prefs）。
  Future<StealHistory> make() async {
    SharedPreferences.setMockInitialValues({});
    return StealHistory.create(now: () => fixedNow);
  }

  test('无记录时 lastStealAt 返回 null', () async {
    final h = await make();
    expect(h.lastStealAt('a'), isNull);
  });

  test('record 后当前实例可读取', () async {
    final h = await make();
    await h.record('a', fixedNow);
    expect(h.lastStealAt('a'), fixedNow);
  });

  test('record 后重新 create 仍可读回（持久化往返）', () async {
    SharedPreferences.setMockInitialValues({});
    final h = await StealHistory.create(now: () => fixedNow);
    await h.record('a', fixedNow);
    // 不重置 mock prefs，验证跨实例持久化。
    final h2 = await StealHistory.create(now: () => fixedNow);
    expect(h2.lastStealAt('a'), fixedNow);
  });

  test('同一个好友重复 record 保留最新时间', () async {
    final h = await make();
    final old = fixedNow.subtract(const Duration(hours: 1));
    await h.record('a', old);
    await h.record('a', fixedNow);
    expect(h.lastStealAt('a'), fixedNow);
  });

  test('不同好友互不覆盖', () async {
    final h = await make();
    final other = fixedNow.subtract(const Duration(hours: 2));
    await h.record('a', fixedNow);
    await h.record('b', other);
    expect(h.lastStealAt('a'), fixedNow);
    expect(h.lastStealAt('b'), other);
  });

  test('空 friendId 不记录且不抛异常', () async {
    final h = await make();
    await h.record('', fixedNow);
    expect(h.lastStealAt(''), isNull);
  });

  test('非法/异型 JSON 根节点返回空', () async {
    for (final raw in <String>[
      'not json',
      '[1,2]',
      '42',
      '"hi"',
      'true',
      'null',
    ]) {
      SharedPreferences.setMockInitialValues({
        'hyb-farm-steal-history': raw,
      });
      final h = await StealHistory.create(now: () => fixedNow);
      expect(h.lastStealAt('a'), isNull, reason: 'raw=$raw');
    }
  });

  test('value 为字符串/布尔/null/数组/对象时忽略，保留合法项', () async {
    final good = fixedNow
        .subtract(const Duration(hours: 1))
        .millisecondsSinceEpoch;
    SharedPreferences.setMockInitialValues({
      'hyb-farm-steal-history': jsonEncode({
        'str': '123',
        'bool': true,
        'nil': null,
        'arr': [1],
        'obj': {'b': 1},
        'ok': good,
      }),
    });
    final h = await StealHistory.create(now: () => fixedNow);
    expect(h.lastStealAt('str'), isNull);
    expect(h.lastStealAt('bool'), isNull);
    expect(h.lastStealAt('nil'), isNull);
    expect(h.lastStealAt('arr'), isNull);
    expect(h.lastStealAt('obj'), isNull);
    expect(h.lastStealAt('ok'), isNotNull);
  });

  test('非正数/超 DateTime 范围时间戳忽略', () async {
    final good = fixedNow
        .subtract(const Duration(hours: 1))
        .millisecondsSinceEpoch;
    SharedPreferences.setMockInitialValues({
      'hyb-farm-steal-history': jsonEncode({
        'zero': 0,
        'neg': -1,
        'huge': 9000000000000000, // > DateTime 合法上限
        'ok': good,
      }),
    });
    final h = await StealHistory.create(now: () => fixedNow);
    expect(h.lastStealAt('zero'), isNull);
    expect(h.lastStealAt('neg'), isNull);
    expect(h.lastStealAt('huge'), isNull);
    expect(h.lastStealAt('ok'), isNotNull);
  });

  test('23h59m59s 前记录仍有效', () async {
    final h = await make();
    await h.record(
      'a',
      fixedNow.subtract(const Duration(hours: 23, minutes: 59, seconds: 59)),
    );
    expect(h.lastStealAt('a'), isNotNull);
  });

  test('恰好 24h 前记录过期', () async {
    final h = await make();
    await h.record('a', fixedNow.subtract(const Duration(hours: 24)));
    expect(h.lastStealAt('a'), isNull);
  });

  test('24h+1ms 前记录过期', () async {
    final h = await make();
    await h.record(
      'a',
      fixedNow
          .subtract(const Duration(hours: 24))
          .subtract(const Duration(milliseconds: 1)),
    );
    expect(h.lastStealAt('a'), isNull);
  });

  test('轻微时钟回拨（未来 ≤5min）视为有效', () async {
    final h = await make();
    await h.record('a', fixedNow.add(const Duration(minutes: 1)));
    expect(h.lastStealAt('a'), isNotNull);
  });

  test('明显远未来记录被丢弃且不持久化（不悬挂不过期）', () async {
    SharedPreferences.setMockInitialValues({});
    final h = await StealHistory.create(now: () => fixedNow);
    await h.record('a', fixedNow.add(const Duration(hours: 1)));
    expect(h.lastStealAt('a'), isNull);
    // record 内 prune 已物理清除并写回：新实例读不到。
    final h2 = await StealHistory.create(now: () => fixedNow);
    expect(h2.lastStealAt('a'), isNull);
  });

  test('create 加载时清理过期条目并回写磁盘', () async {
    final good = fixedNow
        .subtract(const Duration(hours: 1))
        .millisecondsSinceEpoch;
    final expired = fixedNow
        .subtract(const Duration(hours: 25))
        .millisecondsSinceEpoch;
    SharedPreferences.setMockInitialValues({
      'hyb-farm-steal-history': jsonEncode({
        'good': good,
        'expired': expired,
      }),
    });
    final h = await StealHistory.create(now: () => fixedNow);
    expect(h.lastStealAt('good'), isNotNull);
    expect(h.lastStealAt('expired'), isNull);
    // prune 已回写：新实例同样只见 good。
    final h2 = await StealHistory.create(now: () => fixedNow);
    expect(h2.lastStealAt('good'), isNotNull);
    expect(h2.lastStealAt('expired'), isNull);
  });

  test('record 时清理其他好友的过期记录', () async {
    var current = DateTime(2026, 1, 1, 0, 0, 0);
    SharedPreferences.setMockInitialValues({});
    final h = await StealHistory.create(now: () => current);
    await h.record('b', current); // b 有效
    current = current.add(const Duration(hours: 25));
    await h.record('a', current); // record 触发 prune，清掉过期的 b
    expect(h.lastStealAt('b'), isNull);
    expect(h.lastStealAt('a'), isNotNull);
  });
}

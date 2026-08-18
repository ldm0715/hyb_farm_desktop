/// 好友偷菜历史：本机按好友记录最近一次成功偷菜时间（非服务端权威历史）。
///
/// 仅保留 24 小时；「已偷·x前」标签到期后自然消失，不代表从未偷过。
/// 单账号模型：`UserInfo` 无稳定 id、认证为单一 Cookie，故 key 不做账号隔离；
/// `accountId` 参数保留，未来若引入账号切换可加后缀。
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

typedef NowProvider = DateTime Function();

class StealHistory {
  /// 保留期：记录距当前不足 24h 有效，恰好/超过 24h 过期。
  static const Duration retention = Duration(hours: 24);

  /// 允许轻微系统时钟回拨（≤5min 视为有效，显示「刚刚」）；明显远未来视为损坏丢弃。
  static const Duration _futureTolerance = Duration(minutes: 5);

  static const _baseKey = 'hyb-farm-steal-history';

  /// DateTime.fromMillisecondsSinceEpoch 的合法毫秒上限（约 275760 年）。
  static const int _maxEpochMs = 8640000000000000;

  /// 公开构造（`create` 是便捷工厂）：测试可子类化注入失败（对齐 `_FakeApi` 惯例）。
  StealHistory(this._prefs, this._key, {required NowProvider now})
    : _now = now,
      _entries = _decode(_prefs.getString(_key));

  final SharedPreferences _prefs;
  final String _key;
  final NowProvider _now;
  final Map<String, int> _entries;

  /// 当前时间（可注入）。记录时刻与有效性判定共用同一时钟，保证语义一致。
  DateTime get now => _now();

  static String keyFor(String? accountId) =>
      (accountId == null || accountId.isEmpty)
      ? _baseKey
      : '$_baseKey:$accountId';

  static Future<StealHistory> create({String? accountId, NowProvider? now}) async {
    final prefs = await SharedPreferences.getInstance();
    final history = StealHistory(prefs, keyFor(accountId), now: now ?? DateTime.now);
    // 加载后物理清理过期/损坏项；有清理则 best-effort 回写磁盘。
    // 回写失败不阻止创建/应用启动（仅磁盘残留，下次启动再清）。
    if (history._prune()) {
      try {
        await history._save();
      } catch (_) {
        // 忽略：过期清理回写失败不影响创建/启动。catch (_) 覆盖 _save 抛出的
        // StateError（Error 而非 Exception）。
      }
    }
    return history;
  }

  /// 记录最近一次成功偷菜时间。
  ///
  /// 先更新内存再持久化：服务端偷菜已成功，持久化失败不回滚内存记录——
  /// 本会话仍显示「已偷·刚刚」，只是跨会话保留失效。
  /// 调用方（FriendState）对历史失败做 best-effort，不得掩盖偷菜成功。
  Future<void> record(String friendId, DateTime at) async {
    if (friendId.isEmpty) return;
    _entries[friendId] = at.millisecondsSinceEpoch;
    _prune();
    await _save(); // setString 返回 false 时抛异常，由调用方决定是否忽略。
  }

  /// 查询最近一次成功偷菜时间（同步 getter，不做任何持久化写操作）。
  ///
  /// 按当前时间判定 24h 有效性：过期/损坏/明显远未来的条目返回 null，标签到期立即消失。
  /// 注意：这里只做查询级判定，不删除内存/磁盘记录；
  /// 真正的清理由 [create]/[record] 的 prune 完成。
  DateTime? lastStealAt(String friendId) {
    final ts = _entries[friendId];
    if (ts == null) return null;
    final recordedAt = _safeFromEpoch(ts);
    if (recordedAt == null) return null; // 损坏时间戳 → 无效
    if (!recordedAt.isBefore(_now().add(_futureTolerance))) return null; // 明显远未来 → 无效
    if (!recordedAt.isAfter(_now().subtract(retention))) return null; // 恰好 24h → 过期
    return recordedAt;
  }

  /// 物理清理：移除过期（≤cutoff）、损坏、明显远未来的条目。返回是否移除了内容。
  bool _prune() {
    final now = _now();
    final cutoff = now.subtract(retention);
    final future = now.add(_futureTolerance);
    final before = _entries.length;
    _entries.removeWhere((_, ts) {
      final at = _safeFromEpoch(ts);
      return at == null || !at.isBefore(future) || !at.isAfter(cutoff);
    });
    return _entries.length != before;
  }

  /// 安全转换：拒绝非正数与超出 DateTime 范围的值，避免 RangeError。
  static DateTime? _safeFromEpoch(int ms) {
    if (ms <= 0 || ms > _maxEpochMs) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> _save() async {
    final saved = await _prefs.setString(_key, jsonEncode(_entries));
    if (!saved) throw StateError('Failed to persist steal history');
  }

  /// 健壮解码：非法/异型根、坏值逐条忽略，绝不抛。
  static Map<String, int> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return <String, int>{};
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return <String, int>{};
    }
    // 根节点为数组/数字/字符串/bool/null 时返回空。
    if (decoded is! Map) return <String, int>{};
    final entries = <String, int>{};
    for (final e in decoded.entries) {
      final k = e.key;
      final v = e.value;
      // 仅 String key + 正 num 且落在 DateTime 合法范围；坏条目忽略，保留合法项。
      if (k is String && v is num && _safeFromEpoch(v.toInt()) != null) {
        entries[k] = v.toInt();
      }
    }
    return entries;
  }
}

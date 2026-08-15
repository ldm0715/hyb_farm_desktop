/// 24 小时自动务农统计：持久化务农日志，按 debuff 类型聚合次数。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CareLog extends ChangeNotifier {
  CareLog._(this._prefs) : _entries = _decode(_prefs.getString(_kKey));

  static const _kKey = 'hyb-farm-care-log';
  static const _window = Duration(hours: 24);

  final SharedPreferences _prefs;
  final List<Map<String, dynamic>> _entries;

  static Future<CareLog> create() async {
    return CareLog._(await SharedPreferences.getInstance());
  }

  /// 记录一次务农处理的 debuff，按类型（thirsty/weed/pest）每块地一条。
  Future<void> record(Map<String, int> byKind) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    byKind.forEach((kind, count) {
      for (var i = 0; i < count; i++) {
        _entries.add({'kind': kind, 'at': now});
      }
    });
    _prune(now);
    await _save();
    notifyListeners();
  }

  /// 窗口内按 debuff 类型聚合的次数。
  Map<String, int> countsWithin(Duration window) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final cutoff = now - window.inMilliseconds;
    final map = <String, int>{};
    for (final e in _entries) {
      if ((e['at'] as num? ?? 0) < cutoff) continue;
      final kind = e['kind'] as String? ?? '';
      if (kind.isEmpty) continue;
      map[kind] = (map[kind] ?? 0) + 1;
    }
    return map;
  }

  /// 窗口内总次数。
  int totalWithin(Duration window) {
    final counts = countsWithin(window);
    return counts.values.fold(0, (a, b) => a + b);
  }

  /// 最近一次务农时刻（无记录返回 null）。
  DateTime? get lastRecordedAt {
    num max = -1;
    for (final e in _entries) {
      final at = e['at'] as num? ?? 0;
      if (at > max) max = at;
    }
    return max < 0 ? null : DateTime.fromMillisecondsSinceEpoch(max.toInt());
  }

  void _prune(int nowMs) {
    final cutoff = nowMs - _window.inMilliseconds;
    _entries.removeWhere((e) => (e['at'] as num? ?? 0) < cutoff);
  }

  Future<void> _save() async {
    await _prefs.setString(_kKey, jsonEncode(_entries));
  }

  static List<Map<String, dynamic>> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List)
          .whereType<Map<String, dynamic>>()
          .toList();
    } on FormatException {
      return [];
    }
  }
}

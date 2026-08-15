/// 24 小时自动收菜统计：持久化收菜日志，按滚动窗口按作物类型聚合次数。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hyb_farm_desktop/api/models.dart';
import 'package:hyb_farm_desktop/core/constants.dart';

/// 单个作物类型的聚合结果（图标 + 次数）。
class HarvestCount {
  HarvestCount(this.name, this.seedImage);

  final String name;
  final String seedImage;
  int count = 0;

  String get iconUrl => cropIconUrl(seedImage);
}

class HarvestLog extends ChangeNotifier {
  HarvestLog._(this._prefs) : _entries = _decode(_prefs.getString(_kKey));

  static const _kKey = 'hyb-farm-harvest-log';
  static const _window = Duration(hours: 24);

  final SharedPreferences _prefs;
  final List<Map<String, dynamic>> _entries;

  static Future<HarvestLog> create() async {
    return HarvestLog._(await SharedPreferences.getInstance());
  }

  /// 记录一次自动收菜涉及的地块，每块地计该类型 1 次。
  Future<void> record(List<Crop> harvested) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final c in harvested) {
      if (c.isEmpty) continue;
      _entries.add({
        'seedId': c.seedId,
        'seedName': c.seedName,
        'seedImage': c.seedImage,
        'at': now,
      });
    }
    _prune(now);
    await _save();
    notifyListeners();
  }

  /// 窗口内按 seedName 聚合的次数（含图标）。
  Map<String, HarvestCount> countsWithin(Duration window) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final cutoff = now - window.inMilliseconds;
    final map = <String, HarvestCount>{};
    for (final e in _entries) {
      if ((e['at'] as num? ?? 0) < cutoff) continue;
      final name = e['seedName'] as String? ?? '';
      if (name.isEmpty) continue;
      final cur = map.putIfAbsent(
        name,
        () => HarvestCount(name, e['seedImage'] as String? ?? ''),
      );
      cur.count++;
    }
    return map;
  }

  /// 窗口内总次数。
  int totalWithin(Duration window) {
    final counts = countsWithin(window);
    return counts.values.fold(0, (sum, c) => sum + c.count);
  }

  /// 最近一次收菜时刻（无记录返回 null）。
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
      final list = jsonDecode(raw) as List;
      return list.whereType<Map<String, dynamic>>().toList();
    } on FormatException {
      return [];
    }
  }
}

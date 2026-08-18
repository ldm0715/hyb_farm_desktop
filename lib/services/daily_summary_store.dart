/// 每日日报「服务器自然日一天成功一次」有界持久化存储。
///
/// 语义（见 docs/daily-summary.md）：
/// - 请求频率 = 服务器 UTC 自然日最多**成功**一次；失败按最小间隔（30min）重试，
///   直到当天成功一次（与价格趋势的「成败同计」不同——日报失败可补）；
/// - 「服务器自然日」用 `utcDay(now)`（UTC 零点 = 国内 8 点）判定；响应只有日期
///   字符串、无服务器时间戳，故无价格趋势那套 serverObservedAt 锚点估算；
/// - 数据与冷却记录一起持久化 → 应用重启同日不重拉、仍显示日报；次日自动重拉。
///
/// 单账号模型（同 `StealHistory`）：无稳定账号 id、认证为单一 Cookie，
/// key 默认不隔离账号；`accountId` 参数保留，未来若引入账号切换/多环境可加后缀。
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:hyb_farm_desktop/api/models.dart';
import 'package:hyb_farm_desktop/core/constants.dart';
import 'package:hyb_farm_desktop/core/ranking.dart';

/// 日报持久化状态（schemaVersion=1）。
///
/// `lastAttemptedLocalAt`/`lastSuccessfulAt` 为本地时刻；
/// `lastSuccessfulServerDay` 为上次成功所在服务器 UTC 日（`utcDay` 零点）。
/// `data` 仅在请求成功后替换，失败保留旧值但 attempt 生效（用于失败重试间隔）。
class CachedDailySummaryState {
  const CachedDailySummaryState({
    this.schemaVersion = kSchemaVersion,
    this.lastAttemptedLocalAt,
    this.lastSuccessfulAt,
    this.lastSuccessfulServerDay,
    this.periodDate,
    this.data,
  });

  static const int kSchemaVersion = 1;

  final int schemaVersion;

  /// 上次尝试（本地时刻）——失败重试最小间隔判定用；成功时清空。
  final DateTime? lastAttemptedLocalAt;

  /// 上次成功（本地时刻）。
  final DateTime? lastSuccessfulAt;

  /// 上次成功所在服务器 UTC 日（`utcDay` 零点），当天成功门控用。
  final DateTime? lastSuccessfulServerDay;

  /// 上次成功响应的 `periodDate`（如 "2026-08-18"），仅展示/参考。
  final String? periodDate;

  /// 缓存日报快照（仅成功后替换）。
  final DailySummary? data;

  CachedDailySummaryState copyWith({
    int? schemaVersion,
    DateTime? lastAttemptedLocalAt,
    DateTime? lastSuccessfulAt,
    DateTime? lastSuccessfulServerDay,
    String? periodDate,
    DailySummary? data,
    bool clearLastAttemptedLocalAt = false,
    bool clearLastSuccessfulAt = false,
    bool clearLastSuccessfulServerDay = false,
    bool clearPeriodDate = false,
    bool clearData = false,
  }) =>
      CachedDailySummaryState(
        schemaVersion: schemaVersion ?? this.schemaVersion,
        lastAttemptedLocalAt: clearLastAttemptedLocalAt
            ? null
            : lastAttemptedLocalAt ?? this.lastAttemptedLocalAt,
        lastSuccessfulAt: clearLastSuccessfulAt
            ? null
            : lastSuccessfulAt ?? this.lastSuccessfulAt,
        lastSuccessfulServerDay: clearLastSuccessfulServerDay
            ? null
            : lastSuccessfulServerDay ?? this.lastSuccessfulServerDay,
        periodDate: clearPeriodDate ? null : periodDate ?? this.periodDate,
        data: clearData ? null : data ?? this.data,
      );

  factory CachedDailySummaryState.fromJson(Map<String, dynamic> json) =>
      CachedDailySummaryState(
        schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? kSchemaVersion,
        lastAttemptedLocalAt: _parseDate(json['lastAttemptedLocalAt']),
        lastSuccessfulAt: _parseDate(json['lastSuccessfulAt']),
        lastSuccessfulServerDay: _parseDate(json['lastSuccessfulServerDay']),
        periodDate: json['periodDate'] as String?,
        data: json['data'] is Map<String, dynamic>
            ? DailySummary.fromJson(json['data'] as Map<String, dynamic>)
            : null,
      );

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'lastAttemptedLocalAt': _iso(lastAttemptedLocalAt),
    'lastSuccessfulAt': _iso(lastSuccessfulAt),
    'lastSuccessfulServerDay': _iso(lastSuccessfulServerDay),
    'periodDate': periodDate,
    'data': data?.toJson(),
  };

  static DateTime? _parseDate(dynamic value) =>
      value is String && value.isNotEmpty ? DateTime.tryParse(value) : null;

  static String? _iso(DateTime? d) => d?.toUtc().toIso8601String();
}

/// 日报持久化存储：统一读写冷却记录与缓存数据，杜绝状态不一致。
///
/// 时钟约定：所有门控/记录方法显式接收 `now`（调用方注入，测试可传假时钟），
/// 与 FarmState 的可注入 `now` 保持一致。
class DailySummaryStore {
  /// 公开构造（`create` 是便捷工厂）：测试可注入 mock prefs。
  DailySummaryStore(this._prefs, this._key);

  static const _baseKey = 'hyb-farm-daily-summary-v1';

  static String keyFor(String? accountId) =>
      (accountId == null || accountId.isEmpty)
      ? _baseKey
      : '$_baseKey:$accountId';

  static Future<DailySummaryStore> create({String? accountId}) async {
    final prefs = await SharedPreferences.getInstance();
    return DailySummaryStore(prefs, keyFor(accountId));
  }

  final SharedPreferences _prefs;
  final String _key;

  CachedDailySummaryState? _state;
  bool _loaded = false;

  /// 当前状态（懒加载，仅解码一次后内存缓存；无记录/损坏/未知版本 → null）。
  CachedDailySummaryState? get state {
    if (!_loaded) {
      _state = _decode(_prefs.getString(_key));
      _loaded = true;
    }
    return _state;
  }

  /// 是否需要拉取日报（服务器 UTC 自然日最多**成功**一次，失败可重试）：
  ///
  /// ① 成功门控：当天已成功 → false（最高优先级，跨日才允许）；
  /// ② 失败重试最小间隔：距上次尝试 < `kDailySummaryRetryInterval` → false（防刷）；
  /// ③ 否则 → true（首次 / 跨日 / 失败满间隔后重试）。
  bool shouldAttempt(DateTime now) {
    final s = state;
    if (s == null) return true; // 首次：无任何记录

    final today = utcDay(now);

    // ① 当天已成功 → 不再请求。
    if (s.lastSuccessfulServerDay != null &&
        today == s.lastSuccessfulServerDay) {
      return false;
    }

    // ② 失败重试最小间隔：距上次尝试不足间隔 → 不重试。
    if (s.lastAttemptedLocalAt != null) {
      final elapsed = _safeElapsed(now.difference(s.lastAttemptedLocalAt!));
      if (elapsed < kDailySummaryRetryInterval) return false;
    }

    return true;
  }

  /// 生成本次尝试状态（纯计算）：记本地尝试时刻，保留旧数据/成功记录。
  CachedDailySummaryState createAttempt(DateTime now) {
    final base = state ?? const CachedDailySummaryState();
    return base.copyWith(lastAttemptedLocalAt: now);
  }

  /// 持久化本次尝试。**必须在发网络请求前调用**（失败重试间隔据此判定）；
  /// 持久化失败抛异常 → 调用方不得发网络请求。
  Future<void> recordAttempt(CachedDailySummaryState s) => _persist(s);

  /// 持久化成功结果：更新成功日 + periodDate + 数据（仅成功后替换），
  /// 并清空 `lastAttemptedLocalAt`（成功后无需再按失败间隔重试）。
  Future<void> recordSuccess({
    required DailySummary result,
    required DateTime localReceivedAt,
  }) async {
    final base = state ?? const CachedDailySummaryState();
    final next = base.copyWith(
      lastSuccessfulAt: localReceivedAt,
      lastSuccessfulServerDay: utcDay(localReceivedAt),
      periodDate: result.periodDate,
      data: result,
      clearLastAttemptedLocalAt: true,
    );
    await _persist(next);
  }

  /// 恢复缓存日报（schema 校验后；无/损坏/版本不符 → null）。
  DailySummary? loadData() => state?.data;

  Future<void> _persist(CachedDailySummaryState s) async {
    final saved = await _prefs.setString(_key, jsonEncode(s.toJson()));
    // 抛 Exception（非 Error）以便 FarmState.loadDailySummary 的 `on Exception`
    // 拦截：持久化失败 → 本次不发网络请求。
    if (!saved) throw Exception('Failed to persist daily summary state');
    _state = s;
    _loaded = true;
  }

  /// 健壮解码：非法/异型根 → null；未知 schema 版本 → null（丢弃旧缓存）。
  static CachedDailySummaryState? _decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    final s = CachedDailySummaryState.fromJson(decoded);
    if (s.schemaVersion != CachedDailySummaryState.kSchemaVersion) return null;
    return s;
  }
}

/// 负流逝按零处理（本地时间回拨防御）。
Duration _safeElapsed(Duration d) => d.isNegative ? Duration.zero : d;

/// 价格趋势「服务器 UTC 自然日一天一次」有界持久化存储。
///
/// 语义（见 docs/price-trend-ranking.md）：
/// - 请求频率 = 服务器 UTC 自然日最多**尝试**一次（成功/失败同计），应用重启不重置；
/// - 「昨天/前天」按服务器时间戳推导（`dataRefreshedAt`/`serverObservedAt`），
///   本地时钟仅用于 24h 陈旧兜底，且对固定时钟偏移容忍、对本地回拨防御；
/// - 24h（`kPriceTrendStaleAfter`）只作缓存陈旧判断与服务器日估算失效时的兜底，
///   不能突破「当前服务器日已尝试过」的最高限制。
///
/// 单账号模型（同 `StealHistory`）：无稳定账号 id、认证为单一 Cookie，
/// key 默认不隔离账号；`accountId` 参数保留，未来若引入账号切换/多环境可加后缀。
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:hyb_farm_desktop/api/farm_api.dart';
import 'package:hyb_farm_desktop/core/constants.dart';
import 'package:hyb_farm_desktop/core/ranking.dart';

/// 价格趋势持久化状态（schemaVersion=1）。
///
/// `lastAttemptedLocalAt`/`lastSuccessfulAt`/`localObservedAt` 为本地时刻；
/// `lastAttemptedServerDay`/`serverObservedAt`/`dataRefreshedAt` 为服务器时刻
/// （UTC 日或 UTC 时刻）。`data` 仅在请求成功后替换，失败保留旧值但 attempt 生效。
class CachedPriceTrendState {
  const CachedPriceTrendState({
    this.schemaVersion = kSchemaVersion,
    this.lastAttemptedLocalAt,
    this.lastAttemptedServerDay,
    this.lastSuccessfulAt,
    this.serverObservedAt,
    this.localObservedAt,
    this.dataRefreshedAt,
    this.data,
  });

  static const int kSchemaVersion = 1;

  final int schemaVersion;

  /// 上次尝试（本地时刻）——成功失败同记，当天无论成败都不再尝试。
  final DateTime? lastAttemptedLocalAt;

  /// 上次尝试所在服务器 UTC 日（`utcDay`，UTC 零点）。
  final DateTime? lastAttemptedServerDay;

  /// 上次成功（本地时刻）。
  final DateTime? lastSuccessfulAt;

  /// 服务器时间锚点（估算服务器当前时间用；Date header 不可得时回退数据刷新时刻）。
  final DateTime? serverObservedAt;

  /// 与 [serverObservedAt] 对应的本地接收时刻。
  final DateTime? localObservedAt;

  /// 数据本身的更新时间（响应内 max `lastRefreshedAt`，趋势「服务器今天」判定用）。
  final DateTime? dataRefreshedAt;

  /// 缓存趋势快照（仅成功后替换）。
  final PriceTrends? data;

  CachedPriceTrendState copyWith({
    int? schemaVersion,
    DateTime? lastAttemptedLocalAt,
    DateTime? lastAttemptedServerDay,
    DateTime? lastSuccessfulAt,
    DateTime? serverObservedAt,
    DateTime? localObservedAt,
    DateTime? dataRefreshedAt,
    PriceTrends? data,
    bool clearLastAttemptedLocalAt = false,
    bool clearLastAttemptedServerDay = false,
    bool clearLastSuccessfulAt = false,
    bool clearServerObservedAt = false,
    bool clearLocalObservedAt = false,
    bool clearDataRefreshedAt = false,
    bool clearData = false,
  }) =>
      CachedPriceTrendState(
        schemaVersion: schemaVersion ?? this.schemaVersion,
        lastAttemptedLocalAt:
            clearLastAttemptedLocalAt ? null : lastAttemptedLocalAt ?? this.lastAttemptedLocalAt,
        lastAttemptedServerDay:
            clearLastAttemptedServerDay ? null : lastAttemptedServerDay ?? this.lastAttemptedServerDay,
        lastSuccessfulAt:
            clearLastSuccessfulAt ? null : lastSuccessfulAt ?? this.lastSuccessfulAt,
        serverObservedAt:
            clearServerObservedAt ? null : serverObservedAt ?? this.serverObservedAt,
        localObservedAt:
            clearLocalObservedAt ? null : localObservedAt ?? this.localObservedAt,
        dataRefreshedAt:
            clearDataRefreshedAt ? null : dataRefreshedAt ?? this.dataRefreshedAt,
        data: clearData ? null : data ?? this.data,
      );

  factory CachedPriceTrendState.fromJson(Map<String, dynamic> json) =>
      CachedPriceTrendState(
        schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? kSchemaVersion,
        lastAttemptedLocalAt: _parseDate(json['lastAttemptedLocalAt']),
        lastAttemptedServerDay: _parseDate(json['lastAttemptedServerDay']),
        lastSuccessfulAt: _parseDate(json['lastSuccessfulAt']),
        serverObservedAt: _parseDate(json['serverObservedAt']),
        localObservedAt: _parseDate(json['localObservedAt']),
        dataRefreshedAt: _parseDate(json['dataRefreshedAt']),
        data: json['data'] is Map<String, dynamic>
            ? PriceTrends.fromJson(json['data'] as Map<String, dynamic>)
            : null,
      );

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'lastAttemptedLocalAt': _iso(lastAttemptedLocalAt),
    'lastAttemptedServerDay': _iso(lastAttemptedServerDay),
    'lastSuccessfulAt': _iso(lastSuccessfulAt),
    'serverObservedAt': _iso(serverObservedAt),
    'localObservedAt': _iso(localObservedAt),
    'dataRefreshedAt': _iso(dataRefreshedAt),
    'data': data?.toJson(),
  };

  static DateTime? _parseDate(dynamic value) =>
      value is String && value.isNotEmpty ? DateTime.tryParse(value) : null;

  static String? _iso(DateTime? d) => d?.toUtc().toIso8601String();
}

/// 价格趋势持久化存储：统一读写冷却记录与缓存数据，杜绝状态不一致。
///
/// 时钟约定：所有门控/记录方法显式接收 `now`（调用方注入，测试可传假时钟），
/// 与 FarmState 的可注入 `now` 保持一致。
class PriceTrendStore {
  /// 公开构造（`create` 是便捷工厂）：测试可注入 mock prefs。
  PriceTrendStore(this._prefs, this._key);

  static const _baseKey = 'hyb-farm-price-trend-v1';

  static String keyFor(String? accountId) =>
      (accountId == null || accountId.isEmpty)
      ? _baseKey
      : '$_baseKey:$accountId';

  static Future<PriceTrendStore> create({String? accountId}) async {
    final prefs = await SharedPreferences.getInstance();
    return PriceTrendStore(prefs, keyFor(accountId));
  }

  final SharedPreferences _prefs;
  final String _key;

  CachedPriceTrendState? _state;
  bool _loaded = false;

  /// 当前状态（懒加载，仅解码一次后内存缓存；无记录/损坏/未知版本 → null）。
  CachedPriceTrendState? get state {
    if (!_loaded) {
      _state = _decode(_prefs.getString(_key));
      _loaded = true;
    }
    return _state;
  }

  /// 是否需要重新拉取趋势（严格按服务器 UTC 自然日门控）：
  ///
  /// ① 当前服务器日已尝试过（成功或失败）→ false（最高优先级，陈旧不能突破）；
  /// ② 服务器日估算可用 → 新自然日即尝试（不要求严格 24h 间隔）；
  /// ③ 估算失效兜底 → 距上次尝试 < 24h 则不尝试。
  bool shouldAttempt(DateTime now) {
    final s = state;
    if (s == null) return true; // 首次：无任何记录

    final estimatedNow = estimateServerNow(s, now);
    final today = estimatedNow == null ? null : utcDay(estimatedNow);

    // ① 最高优先级：当前服务器日已尝试过，无论上次成功还是失败都不再请求。
    if (today != null &&
        s.lastAttemptedServerDay != null &&
        today == s.lastAttemptedServerDay) {
      return false;
    }

    // ② 服务器日估算可用：主判定 = 无缓存数据 || 服务器自然日已变化。
    if (today != null && s.lastAttemptedServerDay != null) {
      return s.data == null || today != s.lastAttemptedServerDay;
    }

    // ③ 估算失效兜底：24h 本地流逝（safeElapsed：本地回拨按 Duration.zero）。
    if (s.lastAttemptedLocalAt != null) {
      final safeElapsed = safeElapsedOf(now.difference(s.lastAttemptedLocalAt!));
      if (safeElapsed < kPriceTrendStaleAfter) return false;
    }
    return true;
  }

  /// 估算服务器当前时刻 = 服务器时间锚点 + 本地流逝时间（常量偏移在差值中抵消）。
  ///
  /// 仅对固定客户端—服务器时钟偏移具备容忍性，并对本地时间回拨做防御；
  /// 若无独立服务器当前时间（如 Date header），不声称能严格抵抗手动改系统时间。
  /// 锚点缺失（从未成功）→ null，由调用方走 24h 兜底。
  DateTime? estimateServerNow(CachedPriceTrendState s, DateTime now) {
    final anchor = s.serverObservedAt;
    final observed = s.localObservedAt;
    if (anchor == null || observed == null) return null;
    final safeElapsed = safeElapsedOf(now.difference(observed));
    return anchor.toUtc().add(safeElapsed);
  }

  /// 生成本次尝试状态（纯计算）：记本地尝试时刻与服务器 UTC 日，保留旧数据/锚点。
  CachedPriceTrendState createAttempt(DateTime now) {
    final s = state;
    final estimatedNow = s == null ? null : estimateServerNow(s, now);
    final base = s ?? const CachedPriceTrendState();
    return base.copyWith(
      lastAttemptedLocalAt: now,
      lastAttemptedServerDay: estimatedNow == null ? null : utcDay(estimatedNow),
    );
  }

  /// 持久化本次尝试。**必须在发网络请求前调用**（失败也计入当天次数）；
  /// 持久化失败抛异常 → 调用方不得发网络请求，避免突破请求上限。
  Future<void> recordAttempt(CachedPriceTrendState s) => _persist(s);

  /// 持久化成功结果：更新服务器锚点 + 数据（仅成功后替换 data），
  /// 并在锚点就绪后回填 `lastAttemptedServerDay`（attempt 时因无锚点为 null 的情况）。
  Future<void> recordSuccess({
    required PriceTrends result,
    required DateTime localReceivedAt,
  }) async {
    final s = state;
    final base = s ?? const CachedPriceTrendState();
    final next = base.copyWith(
      lastSuccessfulAt: localReceivedAt,
      serverObservedAt: result.serverObservedAt,
      localObservedAt: localReceivedAt,
      dataRefreshedAt: result.dataRefreshedAt,
      data: result,
      lastAttemptedServerDay: base.lastAttemptedServerDay ??
          (result.dataRefreshedAt == null ? null : utcDay(result.dataRefreshedAt!)),
      lastAttemptedLocalAt: base.lastAttemptedLocalAt ?? localReceivedAt,
    );
    await _persist(next);
  }

  /// 恢复缓存趋势数据（schema 校验后；无/损坏/版本不符 → null）。
  PriceTrends? loadData() => state?.data;

  Future<void> _persist(CachedPriceTrendState s) async {
    final saved = await _prefs.setString(_key, jsonEncode(s.toJson()));
    // 抛 Exception（非 Error）以便 FarmState.loadPriceTrend 的 `on Exception`
    // 拦截：持久化失败 → 本次不发网络请求，避免突破当天请求上限。
    if (!saved) throw Exception('Failed to persist price trend state');
    _state = s;
    _loaded = true;
  }

  /// 健壮解码：非法/异型根 → null；未知 schema 版本 → null（丢弃旧缓存）。
  static CachedPriceTrendState? _decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    final s = CachedPriceTrendState.fromJson(decoded);
    if (s.schemaVersion != CachedPriceTrendState.kSchemaVersion) return null;
    return s;
  }
}

/// 负流逝按零处理（本地时间回拨防御）。
Duration safeElapsedOf(Duration d) => d.isNegative ? Duration.zero : d;

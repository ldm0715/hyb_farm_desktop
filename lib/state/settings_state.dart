/// 应用设置：开关、种子、主题、关闭行为、测活间隔、通知，持久化到 shared_preferences。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hyb_farm_desktop/core/download_sources.dart';

/// 关闭窗口时的行为。
enum CloseBehavior { minimizeToTray, exit }

class SettingsState extends ChangeNotifier {
  SettingsState._(this._prefs);

  static const _kAutoHarvest = 'hyb-farm-auto-harvest';
  static const _kReplantSeed = 'hyb-farm-replant-seed';
  static const _kAutoCare = 'hyb-farm-auto-care';
  static const _kAutoCareInterval = 'hyb-farm-auto-care-interval';
  static const _kTheme = 'hyb-farm-theme';
  static const _kCloseBehavior = 'hyb-farm-close-behavior';
  static const _kHideOnMouseLeave = 'hyb-farm-hide-on-mouse-leave';
  static const _kLivenessMinutes = 'hyb-farm-liveness-minutes';
  static const _kNotifyHarvest = 'hyb-farm-notify-harvest';
  static const _kNotifyAuth = 'hyb-farm-notify-auth';
  static const _kWindowX = 'hyb-farm-window-x';
  static const _kWindowY = 'hyb-farm-window-y';
  static const _kLogDirectory = 'hyb-farm-log-directory';
  static const _kPreventSleep = 'hyb-farm-prevent-sleep';
  static const _kDownloadSource = 'hyb-farm-download-source';
  static const _kDownloadMirrors = 'hyb-farm-download-mirrors';
  static const _kDownloadMirrorRiskAccepted =
      'hyb-farm-download-mirror-risk-accepted';

  final SharedPreferences _prefs;

  static Future<SettingsState> create() async {
    return SettingsState._(await SharedPreferences.getInstance()).._load();
  }

  /// 读取持久化的自定义日志根目录（null 表示用默认目录）。
  ///
  /// 供 `main()` 在 `AppLogger.init` 之前调用——此时 `SettingsState` 尚未创建，
  /// 但 `SharedPreferences.getInstance()` 是单例、可安全复用。
  static Future<String?> loadLogDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kLogDirectory);
  }

  bool _autoHarvest = false;
  bool get autoHarvest => _autoHarvest;
  set autoHarvest(bool v) {
    _autoHarvest = v;
    _prefs.setBool(_kAutoHarvest, v);
    notifyListeners();
  }

  String? _replantSeedId;
  String? get replantSeedId => _replantSeedId;
  set replantSeedId(String? v) {
    _replantSeedId = v;
    if (v == null) {
      _prefs.remove(_kReplantSeed);
    } else {
      _prefs.setString(_kReplantSeed, v);
    }
    notifyListeners();
  }

  bool _autoCare = false;
  bool get autoCare => _autoCare;
  set autoCare(bool v) {
    _autoCare = v;
    _prefs.setBool(_kAutoCare, v);
    notifyListeners();
  }

  int _autoCareIntervalMinutes = 5;
  int get autoCareIntervalMinutes => _autoCareIntervalMinutes;
  set autoCareIntervalMinutes(int v) {
    _autoCareIntervalMinutes = v;
    _prefs.setInt(_kAutoCareInterval, v);
    notifyListeners();
  }

  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;
  set themeMode(ThemeMode v) {
    _themeMode = v;
    _prefs.setInt(_kTheme, v.index);
    notifyListeners();
  }

  CloseBehavior _closeBehavior = CloseBehavior.minimizeToTray;
  CloseBehavior get closeBehavior => _closeBehavior;
  set closeBehavior(CloseBehavior v) {
    _closeBehavior = v;
    _prefs.setInt(_kCloseBehavior, v.index);
    notifyListeners();
  }

  bool _hideOnMouseLeave = true;
  bool get hideOnMouseLeave => _hideOnMouseLeave;
  set hideOnMouseLeave(bool v) {
    _hideOnMouseLeave = v;
    _prefs.setBool(_kHideOnMouseLeave, v);
    notifyListeners();
  }

  int _livenessMinutes = 5;
  int get livenessMinutes => _livenessMinutes;
  set livenessMinutes(int v) {
    _livenessMinutes = v;
    _prefs.setInt(_kLivenessMinutes, v);
    notifyListeners();
  }

  bool _notifyHarvest = true;
  bool get notifyHarvest => _notifyHarvest;
  set notifyHarvest(bool v) {
    _notifyHarvest = v;
    _prefs.setBool(_kNotifyHarvest, v);
    notifyListeners();
  }

  bool _notifyAuthExpired = true;
  bool get notifyAuthExpired => _notifyAuthExpired;
  set notifyAuthExpired(bool v) {
    _notifyAuthExpired = v;
    _prefs.setBool(_kNotifyAuth, v);
    notifyListeners();
  }

  /// 上次用户移动后的窗口位置（逻辑坐标）；无记录返回 null。
  Offset? _windowPosition;
  Offset? get windowPosition => _windowPosition;
  set windowPosition(Offset? v) {
    _windowPosition = v;
    if (v == null) {
      _prefs.remove(_kWindowX);
      _prefs.remove(_kWindowY);
    } else {
      _prefs.setDouble(_kWindowX, v.dx);
      _prefs.setDouble(_kWindowY, v.dy);
    }
    notifyListeners();
  }

  /// 自定义日志根目录（日志写入其下 `logs/` 子目录）；null 表示用默认目录。
  String? _logDirectory;
  String? get logDirectory => _logDirectory;
  set logDirectory(String? v) {
    _logDirectory = v;
    if (v == null) {
      _prefs.remove(_kLogDirectory);
    } else {
      _prefs.setString(_kLogDirectory, v);
    }
    notifyListeners();
  }

  /// 自动化运行期间阻止系统空闲自动睡眠（不含屏幕，屏幕仍可关）。默认关。
  bool _preventSleepDuringAutomation = false;
  bool get preventSleepDuringAutomation => _preventSleepDuringAutomation;
  set preventSleepDuringAutomation(bool v) {
    _preventSleepDuringAutomation = v;
    _prefs.setBool(_kPreventSleep, v);
    notifyListeners();
  }

  /// 更新安装包下载源：`official` / `auto` / `mirror:<id>`。默认官方源。
  String _downloadSource = kDownloadSourceOfficial;
  String get downloadSource => _downloadSource;
  set downloadSource(String v) {
    _downloadSource = v;
    _prefs.setString(_kDownloadSource, v);
    notifyListeners();
  }

  /// 第三方下载镜像列表（含内置与自定义，按用户排序）。载入时与内置定义合并。
  List<DownloadMirror> _downloadMirrors = List.of(kDefaultDownloadMirrors);
  List<DownloadMirror> get downloadMirrors => List.unmodifiable(_downloadMirrors);
  set downloadMirrors(List<DownloadMirror> v) {
    _downloadMirrors = List.of(v);
    _prefs.setString(
      _kDownloadMirrors,
      jsonEncode([for (final m in v) m.toJson()]),
    );
    notifyListeners();
  }

  /// 已确认的第三方镜像风险说明版本号（低于 [kDownloadMirrorRiskVersion] 需重新提示）。
  int _downloadMirrorRiskAcceptedVersion = 0;
  int get downloadMirrorRiskAcceptedVersion =>
      _downloadMirrorRiskAcceptedVersion;
  set downloadMirrorRiskAcceptedVersion(int v) {
    _downloadMirrorRiskAcceptedVersion = v;
    _prefs.setInt(_kDownloadMirrorRiskAccepted, v);
    notifyListeners();
  }

  /// 解析持久化的镜像列表；损坏/空值回落空列表（随后与内置合并补齐）。
  List<DownloadMirror> _readMirrors() {
    final raw = _prefs.getString(_kDownloadMirrors);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final list = <DownloadMirror>[];
      for (final e in decoded) {
        final m = DownloadMirror.fromJson(e);
        if (m != null) list.add(m);
      }
      return list;
    } catch (_) {
      return const [];
    }
  }

  void _load() {
    _autoHarvest = _prefs.getBool(_kAutoHarvest) ?? false;
    _replantSeedId = _prefs.getString(_kReplantSeed);
    _autoCare = _prefs.getBool(_kAutoCare) ?? false;
    _autoCareIntervalMinutes = _prefs.getInt(_kAutoCareInterval) ?? 5;
    _themeMode = ThemeMode.values[_prefs.getInt(_kTheme) ?? 0];
    _closeBehavior = CloseBehavior.values[_prefs.getInt(_kCloseBehavior) ?? 0];
    _hideOnMouseLeave = _prefs.getBool(_kHideOnMouseLeave) ?? true;
    _livenessMinutes = _prefs.getInt(_kLivenessMinutes) ?? 5;
    _notifyHarvest = _prefs.getBool(_kNotifyHarvest) ?? true;
    _notifyAuthExpired = _prefs.getBool(_kNotifyAuth) ?? true;
    _logDirectory = _prefs.getString(_kLogDirectory);
    _preventSleepDuringAutomation = _prefs.getBool(_kPreventSleep) ?? false;
    _downloadSource =
        _prefs.getString(_kDownloadSource) ?? kDownloadSourceOfficial;
    _downloadMirrorRiskAcceptedVersion =
        _prefs.getInt(_kDownloadMirrorRiskAccepted) ?? 0;
    _downloadMirrors = mergeDownloadMirrors(
      _readMirrors(),
      kDefaultDownloadMirrors,
    );
    final wx = _prefs.getDouble(_kWindowX);
    final wy = _prefs.getDouble(_kWindowY);
    if (wx != null && wy != null) _windowPosition = Offset(wx, wy);
  }
}

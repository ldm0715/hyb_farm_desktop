/// 应用设置：开关、种子、主题、关闭行为、测活间隔、通知，持久化到 shared_preferences。
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  final SharedPreferences _prefs;

  static Future<SettingsState> create() async {
    return SettingsState._(await SharedPreferences.getInstance()).._load();
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
    final wx = _prefs.getDouble(_kWindowX);
    final wy = _prefs.getDouble(_kWindowY);
    if (wx != null && wy != null) _windowPosition = Offset(wx, wy);
  }
}

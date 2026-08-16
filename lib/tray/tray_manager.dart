/// 托盘管理器：系统托盘图标 + 点击显示/隐藏窗口 + 右键菜单 + 退出。
library;

import 'dart:async';

import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';
import 'package:hyb_farm_desktop/core/farm_connection_state.dart';
import 'package:hyb_farm_desktop/core/formatters.dart';
import 'package:hyb_farm_desktop/core/log/app_logger.dart';
import 'package:hyb_farm_desktop/state/connection_state_store.dart';
import 'package:hyb_farm_desktop/state/farm_state.dart';
import 'package:hyb_farm_desktop/state/settings_state.dart';

class TrayManager extends WindowListener {
  TrayManager({
    required this.settings,
    required this.farmState,
    required this.connectionStore,
  });

  final SettingsState settings;
  final FarmState farmState;
  final ConnectionStateStore connectionStore;
  final SystemTray _tray = SystemTray();
  MenuItemCheckbox? _autoHarvestItem;
  MenuItemCheckbox? _autoCareItem;
  MenuItemLabel? _countdownItem;
  MenuItemLabel? _statusItem;
  Timer? _tickTimer;
  String? _lastCountdownLabel;
  String? _lastStatusLabel;

  Future<void> init() async {
    windowManager.addListener(this);
    await windowManager.setPreventClose(true);

    try {
      // iconPath 直接传 asset 路径，system_tray 会自动拼到 flutter_assets 下。
      await _tray.initSystemTray(
        title: 'HYB Farm',
        iconPath: 'assets/icon/app_icon.ico',
        toolTip: 'HYB Farm',
      );
      _tray.registerSystemTrayEventHandler(_onTrayEvent);
      await _buildMenu();
      settings.addListener(_syncMenu);
      _updateCountdown();
      _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        _updateCountdown();
        _updateStatus();
      });
    } catch (e) {
      AppLog.e('Tray', 'tray init failed', error: e);
    }
  }

  Future<void> _buildMenu() async {
    _autoHarvestItem = MenuItemCheckbox(
      label: '自动收菜',
      name: 'auto-harvest',
      checked: settings.autoHarvest,
      onClicked: (_) => settings.autoHarvest = !settings.autoHarvest,
    );
    _autoCareItem = MenuItemCheckbox(
      label: '自动务农',
      name: 'auto-care',
      checked: settings.autoCare,
      onClicked: (_) => settings.autoCare = !settings.autoCare,
    );
    _countdownItem = MenuItemLabel(label: '下次收菜：—', enabled: false);
    _statusItem = MenuItemLabel(label: '状态：正常', enabled: false);

    final menu = Menu();
    await menu.buildFrom([
      _statusItem!,
      _countdownItem!,
      MenuSeparator(),
      _autoHarvestItem!,
      _autoCareItem!,
      MenuSeparator(),
      MenuItemLabel(label: '显示主窗口', onClicked: (_) => _show()),
      MenuSeparator(),
      MenuItemLabel(label: '退出', onClicked: (_) => _exit()),
    ]);
    await _tray.setContextMenu(menu);
  }

  /// 同步两个开关的勾选态：托盘点或设置页改开关都会走到这里。
  void _syncMenu() {
    _autoHarvestItem?.setCheck(settings.autoHarvest).ignore();
    _autoCareItem?.setCheck(settings.autoCare).ignore();
  }

  /// 更新顶部倒计时文案；label 未变时跳过，避免无谓的原生调用。
  void _updateCountdown() {
    final nextAt = farmState.nextMatureAt;
    final String label;
    if (nextAt == null) {
      label = farmState.matureCount > 0 ? '下次收菜：已成熟' : '下次收菜：—';
    } else {
      final seconds = nextAt.difference(DateTime.now()).inSeconds;
      label = '下次收菜：${formatCountdown(seconds)}';
    }
    if (label == _lastCountdownLabel) return;
    _lastCountdownLabel = label;
    _countdownItem?.setLabel(label).ignore();
  }

  /// 更新顶部状态项；label 未变时跳过。
  void _updateStatus() {
    final state = connectionStore.state;
    final String label = state == FarmConnectionState.healthy
        ? '状态：正常'
        : '状态：${state.title}';
    if (label == _lastStatusLabel) return;
    _lastStatusLabel = label;
    _statusItem?.setLabel(label).ignore();
  }

  void _onTrayEvent(String eventName) {
    if (eventName == kSystemTrayEventClick ||
        eventName == kSystemTrayEventDoubleClick) {
      _toggle();
    } else if (eventName == kSystemTrayEventRightClick) {
      _tray.popUpContextMenu();
    }
  }

  Future<void> _toggle() async {
    if (await windowManager.isVisible()) {
      await windowManager.hide();
    } else {
      await _show();
    }
  }

  Future<void> _show() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _exit() async {
    _tickTimer?.cancel();
    await windowManager.setPreventClose(false);
    await _tray.destroy();
    await windowManager.destroy();
  }

  @override
  void onWindowClose() async {
    if (settings.closeBehavior == CloseBehavior.minimizeToTray) {
      await windowManager.hide();
    } else {
      await _exit();
    }
  }

  @override
  void onWindowMoved() async {
    final p = await windowManager.getPosition();
    settings.windowPosition = p;
  }
}

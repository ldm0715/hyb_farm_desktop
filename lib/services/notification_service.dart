/// 系统通知封装；不可用时静默降级。
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;

  /// 初始化 Windows 通知；AppUserModelID/图标等需 Phase 0 在发行形态实测。
  Future<void> init() async {
    const settings = InitializationSettings(
      windows: WindowsInitializationSettings(
        appName: 'HYB Farm',
        appUserModelId: 'com.hybfarm.desktop',
        guid: '8f6f0a4a-1d5b-4e6a-9c8e-2b3c4d5e6f70',
      ),
    );
    try {
      await _plugin.initialize(settings: settings);
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  Future<void> show(String title, String body) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        id: 0,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          windows: WindowsNotificationDetails(),
        ),
      );
    } catch (_) {
      // 通知不可用：静默降级，不影响自动化主流程。
    }
  }
}

import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'api/api_client.dart';
import 'api/farm_api.dart';
import 'app.dart';
import 'auth/auth_service.dart';
import 'core/constants.dart';
import 'core/farm_connection_state.dart';
import 'core/log/app_logger.dart';
import 'core/log/network_log_interceptor.dart';
import 'core/operation_coordinator.dart';
import 'core/request_backoff.dart';
import 'services/auto_care_service.dart';
import 'services/care_log.dart';
import 'services/challenge_verifier.dart';
import 'services/harvest_log.dart';
import 'services/harvest_scheduler.dart';
import 'services/notification_service.dart';
import 'services/recycle_service.dart';
import 'services/replant_service.dart';
import 'state/connection_state_store.dart';
import 'state/farm_state.dart';
import 'state/friend_state.dart';
import 'state/settings_state.dart';
import 'tray/tray_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 日志系统最先初始化（早于 windowManager），窗口初始化失败也能记录。
  final supportDir = await getApplicationSupportDirectory();
  await AppLogger.instance.init(directory: supportDir.path);

  // 全局未捕获异常：框架层与平台层（root isolate）都落入文件日志。
  FlutterError.onError = (details) {
    AppLog.e('Flutter', '未捕获的框架异常', error: details.exception, stackTrace: details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLog.e('Flutter', '未捕获的隔离区异常', error: error, stackTrace: stack);
    return true;
  };

  await windowManager.ensureInitialized();
  await windowManager.setAsFrameless();
  await windowManager.setSize(const Size(440, 580));
  await windowManager.setMinimumSize(const Size(420, 520));
  await windowManager.setMaximumSize(const Size(480, 650));
  await windowManager.setResizable(true);

  // 组装依赖。
  final connectionStore = ConnectionStateStore();
  final apiClient = ApiClient();
  apiClient.addInterceptor(NetworkLogInterceptor());
  final farmApi = FarmApi(apiClient);
  final auth = AuthService(client: apiClient, api: farmApi);
  // 每次请求分类后更新连接状态，同时驱动退避；authRequired 时顺带触发 AuthService 失效态。
  final backoff = RequestBackoff();
  apiClient.onClassified = (result) {
    connectionStore.apply(result);
    backoff.record(result);
    if (result.state == FarmConnectionState.authRequired) {
      auth.onExpired();
    }
  };
  final settings = await SettingsState.create();
  final savedPos = settings.windowPosition;
  if (savedPos != null) {
    await windowManager.setPosition(savedPos);
  }
  final farmState = FarmState(farmApi);
  final coordinator = OperationCoordinator();
  final replant = ReplantService(api: farmApi);
  final recycleService = RecycleService(api: farmApi, coordinator: coordinator);
  final notifications = NotificationService();
  final harvestLog = await HarvestLog.create();
  final careLog = await CareLog.create();
  final scheduler = HarvestScheduler(
    api: farmApi,
    farmState: farmState,
    settings: settings,
    coordinator: coordinator,
    replant: replant,
    notifications: notifications,
    harvestLog: harvestLog,
    connectionStore: connectionStore,
    backoff: backoff,
  );
  final autoCare = AutoCareService(
    api: farmApi,
    farmState: farmState,
    coordinator: coordinator,
    careLog: careLog,
    connectionStore: connectionStore,
    backoff: backoff,
  );
  final friendState = FriendState(api: farmApi, coordinator: coordinator);
  final challengeVerifier = ChallengeVerifier(
    store: connectionStore,
    auth: auth,
    api: farmApi,
  );
  final trayManager = TrayManager(
    settings: settings,
    farmState: farmState,
    connectionStore: connectionStore,
  );

  await notifications.init();
  await trayManager.init();
  await auth.tryRestore();

  AppLog.i('App', '应用启动', {'version': kAppVersion, 'baseUrl': kBaseUrl});

  runApp(
    HybFarmApp(
      api: farmApi,
      auth: auth,
      settings: settings,
      farmState: farmState,
      coordinator: coordinator,
      scheduler: scheduler,
      autoCare: autoCare,
      replant: replant,
      recycleService: recycleService,
      notifications: notifications,
      harvestLog: harvestLog,
      careLog: careLog,
      friendState: friendState,
      connectionStore: connectionStore,
      challengeVerifier: challengeVerifier,
    ),
  );
}

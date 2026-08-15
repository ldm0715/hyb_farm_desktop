import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'api/api_client.dart';
import 'api/farm_api.dart';
import 'app.dart';
import 'auth/auth_service.dart';
import 'core/farm_connection_state.dart';
import 'core/operation_coordinator.dart';
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
  await windowManager.ensureInitialized();
  await windowManager.setAsFrameless();
  await windowManager.setSize(const Size(440, 580));
  await windowManager.setMinimumSize(const Size(420, 520));
  await windowManager.setMaximumSize(const Size(480, 650));
  await windowManager.setResizable(true);

  // 组装依赖。
  final connectionStore = ConnectionStateStore();
  final apiClient = ApiClient();
  final farmApi = FarmApi(apiClient);
  final auth = AuthService(client: apiClient, api: farmApi);
  // 每次请求分类后更新连接状态；authRequired 时顺带触发 AuthService 失效态。
  apiClient.onClassified = (result) {
    connectionStore.apply(result);
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
  );
  final autoCare = AutoCareService(
    api: farmApi,
    farmState: farmState,
    coordinator: coordinator,
    careLog: careLog,
    connectionStore: connectionStore,
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

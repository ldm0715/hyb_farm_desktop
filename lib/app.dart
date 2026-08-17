/// 应用根组件：组装依赖、提供 Provider、按认证状态切换登录页/主界面。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hyb_farm_desktop/api/farm_api.dart';
import 'package:hyb_farm_desktop/auth/auth_service.dart';
import 'package:hyb_farm_desktop/core/operation_coordinator.dart';
import 'package:hyb_farm_desktop/services/auto_care_service.dart';
import 'package:hyb_farm_desktop/services/care_log.dart';
import 'package:hyb_farm_desktop/services/challenge_verifier.dart';
import 'package:hyb_farm_desktop/services/harvest_log.dart';
import 'package:hyb_farm_desktop/services/harvest_scheduler.dart';
import 'package:hyb_farm_desktop/services/notification_service.dart';
import 'package:hyb_farm_desktop/services/power_service.dart';
import 'package:hyb_farm_desktop/services/recycle_service.dart';
import 'package:hyb_farm_desktop/services/replant_service.dart';
import 'package:hyb_farm_desktop/state/connection_state_store.dart';
import 'package:hyb_farm_desktop/state/farm_state.dart';
import 'package:hyb_farm_desktop/state/friend_state.dart';
import 'package:hyb_farm_desktop/state/settings_state.dart';
import 'package:hyb_farm_desktop/ui/app_theme.dart';
import 'package:hyb_farm_desktop/ui/login_page.dart';
import 'package:hyb_farm_desktop/ui/root_shell.dart';

class HybFarmApp extends StatelessWidget {
  const HybFarmApp({
    super.key,
    required this.api,
    required this.auth,
    required this.settings,
    required this.farmState,
    required this.coordinator,
    required this.scheduler,
    required this.autoCare,
    required this.replant,
    required this.recycleService,
    required this.notifications,
    required this.harvestLog,
    required this.careLog,
    required this.friendState,
    required this.connectionStore,
    required this.challengeVerifier,
    required this.power,
  });

  final FarmApi api;
  final AuthService auth;
  final SettingsState settings;
  final FarmState farmState;
  final OperationCoordinator coordinator;
  final HarvestScheduler scheduler;
  final AutoCareService autoCare;
  final ReplantService replant;
  final RecycleService recycleService;
  final NotificationService notifications;
  final HarvestLog harvestLog;
  final CareLog careLog;
  final FriendState friendState;
  final ConnectionStateStore connectionStore;
  final ChallengeVerifier challengeVerifier;
  final PowerService power;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<FarmApi>.value(value: api),
        ChangeNotifierProvider<AuthService>.value(value: auth),
        ChangeNotifierProvider<SettingsState>.value(value: settings),
        ChangeNotifierProvider<FarmState>.value(value: farmState),
        Provider<OperationCoordinator>.value(value: coordinator),
        Provider<HarvestScheduler>.value(value: scheduler),
        ChangeNotifierProvider<AutoCareService>.value(value: autoCare),
        Provider<ReplantService>.value(value: replant),
        Provider<RecycleService>.value(value: recycleService),
        Provider<NotificationService>.value(value: notifications),
        ChangeNotifierProvider<HarvestLog>.value(value: harvestLog),
        ChangeNotifierProvider<CareLog>.value(value: careLog),
        ChangeNotifierProvider<FriendState>.value(value: friendState),
        ChangeNotifierProvider<ConnectionStateStore>.value(
          value: connectionStore,
        ),
        Provider<ChallengeVerifier>.value(value: challengeVerifier),
        Provider<PowerService>.value(value: power),
      ],
      child: const _MaterialApp(),
    );
  }
}

class _MaterialApp extends StatelessWidget {
  const _MaterialApp();

  @override
  Widget build(BuildContext context) {
    final themeMode = context.watch<SettingsState>().themeMode;
    return MaterialApp(
      title: 'HYB Farm',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: themeMode,
      home: const _Root(),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final status = context.watch<AuthService>().status;
    return status == AuthStatus.authenticated
        ? const RootShell()
        : const LoginPage();
  }
}

/// 主面板外壳：顶部 Header + 顶部一级 TabBar + 四页签内容，负责调度器启停与刷新。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:hyb_farm_desktop/auth/auth_service.dart';
import 'package:hyb_farm_desktop/core/farm_connection_state.dart';
import 'package:hyb_farm_desktop/services/auto_care_service.dart';
import 'package:hyb_farm_desktop/services/challenge_verifier.dart';
import 'package:hyb_farm_desktop/services/harvest_scheduler.dart';
import 'package:hyb_farm_desktop/services/power_service.dart';
import 'package:hyb_farm_desktop/state/connection_state_store.dart';
import 'package:hyb_farm_desktop/state/farm_state.dart';
import 'package:hyb_farm_desktop/state/friend_state.dart';
import 'package:hyb_farm_desktop/state/settings_state.dart';
import 'package:hyb_farm_desktop/theme/farm_theme.dart';
import 'package:hyb_farm_desktop/ui/account_dialog.dart';
import 'package:hyb_farm_desktop/ui/challenge_dialog.dart';
import 'package:hyb_farm_desktop/ui/farm_page.dart';
import 'package:hyb_farm_desktop/ui/friends_page.dart';
import 'package:hyb_farm_desktop/ui/settings_page.dart';
import 'package:hyb_farm_desktop/ui/warehouse_page.dart';

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell>
    with SingleTickerProviderStateMixin, WindowListener {
  Timer? _tickTimer;
  Timer? _mouseLeaveTimer;
  StreamSubscription<PowerEvent>? _powerSub;
  FarmConnectionState? _prevConnectionState;
  DateTime? _outsideSince;
  bool _checkingLeave = false;
  late final TabController _tabController;
  int _lastIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);
    context.read<SettingsState>().addListener(_syncAutomation);
    context.read<SettingsState>().addListener(_syncHideOnMouseLeave);
    context.read<ConnectionStateStore>().addListener(_onConnectionChanged);
    _prevConnectionState = context.read<ConnectionStateStore>().state;
    windowManager.addListener(this);
    // 原生电源事件：resume 触发统一恢复；suspend 仅日志（已在 PowerService 记录）。
    _powerSub = context.read<PowerService>().events.listen((event) {
      if (event == PowerEvent.resume) _onPowerResume();
    });
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncAutomation();
      _syncHideOnMouseLeave();
      _refresh();
    });
  }

  @override
  void dispose() {
    context.read<SettingsState>().removeListener(_syncAutomation);
    context.read<SettingsState>().removeListener(_syncHideOnMouseLeave);
    context.read<ConnectionStateStore>().removeListener(_onConnectionChanged);
    windowManager.removeListener(this);
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _tickTimer?.cancel();
    _mouseLeaveTimer?.cancel();
    _powerSub?.cancel();
    // 退出登录（RootShell 卸载）：主动释放睡眠阻止。
    unawaited(
      context.read<PowerService>().releaseSleepPrevention(reason: 'logout'),
    );
    super.dispose();
  }

  void _onTabChanged() {
    if (!mounted) return;
    final i = _tabController.index;
    if (i == _lastIndex) return;
    _lastIndex = i;
    if (i == 2) {
      context.read<FriendState>().refresh();
    }
  }

  void _syncAutomation() {
    final settings = context.read<SettingsState>();
    final scheduler = context.read<HarvestScheduler>();
    final autoCare = context.read<AutoCareService>();
    final connection = context.read<ConnectionStateStore>();
    final power = context.read<PowerService>();

    // 仅「需人工」状态停止自动化；瞬态（network/server/rateLimited）不 stop，
    // 交由 RequestBackoff 门控重试（定时器继续走，退避到期后下一次 tick 恢复）。
    if (connection.needsAttention) {
      scheduler.stop();
      autoCare.stop();
    } else {
      if (settings.autoHarvest) {
        scheduler.start();
      } else {
        scheduler.stop();
      }
      if (settings.autoCare) {
        autoCare.start(settings.autoCareIntervalMinutes);
      } else {
        autoCare.stop();
      }
    }

    // 睡眠阻止：依据用户意图 + 会话有效性，不因瞬时网络错误（networkError/serverError）释放。
    final automationDesired = settings.autoHarvest || settings.autoCare;
    final sessionValid = connection.state != FarmConnectionState.authRequired;
    unawaited(
      power.syncSleepPrevention(
        enabled: settings.preventSleepDuringAutomation,
        automationRunning: automationDesired && sessionValid,
      ),
    );
  }

  /// 连接状态变化：先同步自动化（确保 scheduler 已启动），再决定是否触发网络恢复。
  void _onConnectionChanged() {
    final connection = context.read<ConnectionStateStore>();
    final prev = _prevConnectionState;
    final curr = connection.state;
    _prevConnectionState = curr;
    _syncAutomation();
    if (curr == FarmConnectionState.healthy && prev != null && curr != prev) {
      if (_isTransient(prev)) {
        unawaited(
          context
              .read<HarvestScheduler>()
              .recoverAndReschedule(RecoveryReason.networkRecovered),
        );
      } else if (prev == FarmConnectionState.challengeRequired) {
        // 完成人机验证后恢复：立即补收 + 务农，重跑被 403 拦下的自动化写请求。
        unawaited(_recoverAfterChallenge());
      }
    }
  }

  Future<void> _recoverAfterChallenge() async {
    final settings = context.read<SettingsState>();
    final scheduler = context.read<HarvestScheduler>();
    final autoCare = context.read<AutoCareService>();
    await scheduler.recoverAndReschedule(RecoveryReason.challengeCleared);
    if (settings.autoCare) {
      await autoCare.checkAndCare();
    }
  }

  bool _isTransient(FarmConnectionState s) =>
      s == FarmConnectionState.networkError ||
      s == FarmConnectionState.serverError;

  /// 系统从睡眠恢复：先补收重排，再按需立即务农。两者写入均经共用 OperationCoordinator 串行。
  void _onPowerResume() {
    final settings = context.read<SettingsState>();
    final scheduler = context.read<HarvestScheduler>();
    final autoCare = context.read<AutoCareService>();
    unawaited(() async {
      await scheduler.recoverAndReschedule(RecoveryReason.powerResume);
      if (settings.autoCare) {
        await autoCare.checkAndCare();
      }
    }());
  }

  /// 按设置启停「鼠标移出自动隐藏」的轮询。
  void _syncHideOnMouseLeave() {
    final settings = context.read<SettingsState>();
    _mouseLeaveTimer?.cancel();
    _outsideSince = null;
    if (settings.hideOnMouseLeave) {
      _mouseLeaveTimer = Timer.periodic(
        const Duration(milliseconds: 300),
        (_) => _checkMouseLeave(),
      );
    }
  }

  /// 轮询光标坐标与窗口 bounds；光标离开约 0.5 秒后隐藏到托盘。
  Future<void> _checkMouseLeave() async {
    if (_checkingLeave) return;
    _checkingLeave = true;
    try {
      if (!await windowManager.isVisible()) {
        _outsideSince = null;
        return;
      }
      final bounds = await windowManager.getBounds();
      final cursor = await screenRetriever.getCursorScreenPoint();
      if (!bounds.inflate(1).contains(cursor)) {
        _outsideSince ??= DateTime.now();
        if (DateTime.now().difference(_outsideSince!) >=
            const Duration(milliseconds: 500)) {
          _outsideSince = null;
          await windowManager.hide();
        }
      } else {
        _outsideSince = null;
      }
    } finally {
      _checkingLeave = false;
    }
  }

  Future<void> _refresh() async {
    final farmState = context.read<FarmState>();
    final friendState = _tabController.index == 2
        ? context.read<FriendState>()
        : null;
    try {
      // 手动刷新按钮是唯一 force:true 全量刷新入口。
      await farmState.refresh(force: true);
      await farmState.loadSeeds(force: true);
      await farmState.loadPrices(force: true);
      if (friendState != null) {
        await friendState.refresh(force: true);
      }
    } catch (_) {
      // 连接状态已由 ApiClient 上报到 ConnectionStateStore；这里吞掉异常，
      // 避免启动时未捕获异步异常。UI 据 store 状态展示。
    }
  }

  // —— 托盘后台生命周期（仅由 windowManager 事件驱动，失焦 inactive 不改调度） ——

  @override
  void onWindowEvent(String eventName) {
    // window_manager 用 onWindowEvent 分发所有原生事件（含 show/hide）；
    // 前台失焦（blur/focus）不改调度，只有隐藏到托盘（hide）与恢复（show）才进入后台/前台。
    if (eventName == 'hide') {
      _enterBackground();
    } else if (eventName == 'show') {
      _leaveBackground();
    }
  }

  @override
  void onWindowMinimize() => _enterBackground();

  @override
  void onWindowRestore() => _leaveBackground();

  void _enterBackground() {
    final settings = context.read<SettingsState>();
    final scheduler = context.read<HarvestScheduler>();
    final autoCare = context.read<AutoCareService>();
    scheduler.onAppBackgrounded(allowAutoHarvest: settings.autoHarvest);
    // 后台不务农。
    autoCare.stop();
  }

  void _leaveBackground() {
    final scheduler = context.read<HarvestScheduler>();
    final settings = context.read<SettingsState>();
    unawaited(scheduler.recoverAndReschedule(RecoveryReason.foreground));
    // 回前台按需重排务农。
    if (settings.autoCare) {
      context.read<AutoCareService>().start(settings.autoCareIntervalMinutes);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = FarmColorScheme.of(context);
    return Scaffold(
      body: Column(
        children: [
          _HeaderBar(onRefresh: _refresh),
          _TopTabBar(controller: _tabController),
          Expanded(
            // S0 页面背景：顶部→底部极弱渐变，仅防大面积死白，不制造明显色带。
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    colors.pageBackground,
                    Color.lerp(
                      colors.pageBackground,
                      colors.surfaceSubtle,
                      0.5,
                    )!,
                  ],
                ),
              ),
              child: IndexedStack(
                index: _tabController.index,
                children: const [
                  FarmPage(),
                  WarehousePage(),
                  FriendsPage(),
                  SettingsPage(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 顶部 Header（64px）：无边框窗口的拖拽区 + 品牌信息 + 状态 + 窗口控制。
class _HeaderBar extends StatelessWidget {
  const _HeaderBar({required this.onRefresh});

  final VoidCallback onRefresh;

  Future<void> _onStatusChipTap(BuildContext context) async {
    final connection = context.read<ConnectionStateStore>();
    switch (connection.state) {
      case FarmConnectionState.challengeRequired:
        final verifier = context.read<ChallengeVerifier>();
        final auth = context.read<AuthService>();
        await showChallengeDialog(context, verifier: verifier, auth: auth);
      case FarmConnectionState.authRequired:
        // 触发 AuthService 失效态，切回登录页。
        context.read<AuthService>().onExpired();
      case FarmConnectionState.rateLimited:
        final label = connection.retryAfterLabel;
        _showSnack(context, label.isEmpty ? '请求过于频繁，请稍后重试' : '请求受限，$label');
      case FarmConnectionState.networkError:
      case FarmConnectionState.serverError:
      case FarmConnectionState.unknownError:
        final d = connection.diagnostics;
        _showSnack(
          context,
          '${connection.state.title}${d?.reason.isNotEmpty == true ? '：${d!.reason}' : ''}',
        );
      case FarmConnectionState.healthy:
        final at = connection.lastCheckedAt;
        _showSnack(
          context,
          at == null ? '连接正常' : '连接正常 · 上次检查 ${_timeLabel(at)}',
        );
    }
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _timeLabel(DateTime at) {
    final now = DateTime.now();
    final diff = now.difference(at);
    if (diff.inSeconds < 60) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    return '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final farmState = context.watch<FarmState>();
    final auth = context.watch<AuthService>();
    final connection = context.watch<ConnectionStateStore>();
    final colors = FarmColorScheme.of(context);

    // 连接状态优先；healthy 时回落显示自动化运行状态。
    final conn = connection.state;
    final (statusColor, statusLabel) = conn == FarmConnectionState.healthy
        ? switch (farmState.automation) {
            AutomationStatus.running => (colors.primary, '正常'),
            _ => (colors.textSecondary, '已暂停'),
          }
        : switch (conn) {
            FarmConnectionState.authRequired => (colors.error, '需要登录'),
            FarmConnectionState.challengeRequired => (colors.warning, '需验证'),
            FarmConnectionState.rateLimited => (colors.warning, '请求受限'),
            FarmConnectionState.networkError => (colors.error, '网络异常'),
            FarmConnectionState.serverError => (colors.error, '服务异常'),
            FarmConnectionState.unknownError => (colors.textSecondary, '未知错误'),
            FarmConnectionState.healthy => (colors.primary, '正常'),
          };

    return DragToMoveArea(
      child: Container(
        height: FarmSizes.header,
        padding: const EdgeInsets.symmetric(horizontal: FarmSpacing.md),
        decoration: BoxDecoration(
          color: colors.headerBackground,
          border: Border(bottom: BorderSide(color: colors.border)),
        ),
        child: Row(
          children: [
            InkWell(
              onTap: () => showAccountDialog(context),
              borderRadius: BorderRadius.circular(FarmSizes.brandIcon),
              child: ClipOval(
                child: SizedBox(
                  width: FarmSizes.brandIcon,
                  height: FarmSizes.brandIcon,
                  child: auth.avatar.isEmpty
                      ? Icon(
                          Icons.person,
                          color: colors.textSecondary,
                          size: 22,
                        )
                      : Image.network(
                          auth.avatar,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Icon(
                            Icons.person,
                            color: colors.textSecondary,
                            size: 22,
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(width: FarmSpacing.sm),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'HYB Farm',
                  style: FarmTextStyles.brand.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                Text(
                  '自动化农场助手',
                  style: FarmTextStyles.brandSubtitle.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
            const Spacer(),
            InkWell(
              onTap: () => _onStatusChipTap(context),
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: FarmSpacing.xs,
                  vertical: FarmSpacing.xxs,
                ),
                decoration: BoxDecoration(
                  color: colors.surfaceSubtle,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: FarmSpacing.xs,
                      height: FarmSpacing.xs,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: FarmSpacing.xxs),
                    Text(
                      statusLabel,
                      style: FarmTextStyles.statusText.copyWith(
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: FarmSpacing.xs),
            _HeaderIconButton(
              icon: Icons.refresh,
              tooltip: '刷新',
              onPressed: onRefresh,
            ),
            _ThemeToggleButton(),
            _HeaderIconButton(
              icon: Icons.visibility_off_outlined,
              tooltip: '隐藏到托盘',
              onPressed: () => windowManager.hide(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Header 右侧统一的 32×32 图标按钮。
class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: FarmSizes.iconButton,
      height: FarmSizes.iconButton,
      child: IconButton(
        icon: Icon(icon, size: 18),
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        onPressed: onPressed,
      ),
    );
  }
}

/// 主题切换按钮：浅色/深色/跟随系统三态循环。
class _ThemeToggleButton extends StatelessWidget {
  const _ThemeToggleButton();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsState>();
    final colors = FarmColorScheme.of(context);

    final (icon, tooltip, next) = switch (settings.themeMode) {
      ThemeMode.system => (Icons.brightness_auto, '主题：跟随系统', ThemeMode.light),
      ThemeMode.light => (Icons.light_mode, '主题：浅色', ThemeMode.dark),
      ThemeMode.dark => (Icons.dark_mode, '主题：深色', ThemeMode.system),
    };

    return SizedBox(
      width: FarmSizes.iconButton,
      height: FarmSizes.iconButton,
      child: IconButton(
        icon: Icon(icon, size: 18, color: colors.textSecondary),
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        onPressed: () => settings.themeMode = next,
      ),
    );
  }
}

/// 顶部一级 TabBar（52px）：四等宽，选中态为浅绿圆角块。
class _TopTabBar extends StatelessWidget {
  const _TopTabBar({required this.controller});

  final TabController controller;

  static const _tabs = [
    (Icons.grass, '农场'),
    (Icons.inventory_2, '仓库'),
    (Icons.people, '好友'),
    (Icons.settings, '设置'),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = FarmColorScheme.of(context);
    return Container(
      height: FarmSizes.tabBar,
      color: colors.headerBackground,
      padding: const EdgeInsets.symmetric(
        horizontal: FarmSpacing.md,
        vertical: FarmSpacing.xs,
      ),
      child: Row(
        children: [
          for (var i = 0; i < _tabs.length; i++)
            Expanded(
              child: _TabItem(index: i, controller: controller),
            ),
        ],
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({required this.index, required this.controller});

  final int index;
  final TabController controller;

  @override
  Widget build(BuildContext context) {
    final (icon, label) = _TopTabBar._tabs[index];
    final selected = controller.index == index;
    final colors = FarmColorScheme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FarmSpacing.xxs),
      child: InkWell(
        onTap: () => controller.index = index,
        borderRadius: BorderRadius.circular(FarmRadii.control),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          height: FarmSizes.tabInteractive,
          decoration: BoxDecoration(
            color: selected ? colors.surfaceSelected : Colors.transparent,
            borderRadius: BorderRadius.circular(FarmRadii.control),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? colors.primary : colors.textSecondary,
              ),
              const SizedBox(width: FarmSpacing.xs - 2),
              Text(
                label,
                style:
                    (selected
                            ? FarmTextStyles.tabLabelSelected
                            : FarmTextStyles.tabLabel)
                        .copyWith(
                          color: selected
                              ? colors.primary
                              : colors.textSecondary,
                        ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

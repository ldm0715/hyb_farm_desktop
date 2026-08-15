/// 设置页：账户与安全、自动收菜/补种/务农、通知、外观、关于与数据。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hyb_farm_desktop/auth/auth_service.dart';
import 'package:hyb_farm_desktop/core/constants.dart';
import 'package:hyb_farm_desktop/core/farm_connection_state.dart';
import 'package:hyb_farm_desktop/core/formatters.dart';
import 'package:hyb_farm_desktop/services/auto_care_service.dart';
import 'package:hyb_farm_desktop/state/connection_state_store.dart';
import 'package:hyb_farm_desktop/state/farm_state.dart';
import 'package:hyb_farm_desktop/state/settings_state.dart';
import 'package:hyb_farm_desktop/theme/farm_theme.dart';
import 'account_dialog.dart';
import 'widgets/farm_icon.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Timer? _tickTimer;

  @override
  void initState() {
    super.initState();
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsState>();
    final farmState = context.watch<FarmState>();
    final autoCare = context.watch<AutoCareService>();
    final colors = FarmColorScheme.of(context);
    final invQty = <String, int>{
      for (final i in farmState.inventory) i.seedId: i.quantity,
    };
    final inStockSeeds =
        farmState.seeds.where((s) => (invQty[s.id] ?? 0) > 0).toList()
          ..sort((a, b) => (invQty[b.id] ?? 0).compareTo(invQty[a.id] ?? 0));
    final selectedReplantId =
        settings.replantSeedId != null &&
            inStockSeeds.any((s) => s.id == settings.replantSeedId)
        ? settings.replantSeedId
        : null;

    return ListView(
      padding: kPagePadding,
      children: [
        Text(
          '设置',
          style: FarmTextStyles.pageTitle.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _AccountStatusCard(),
        ),
        _SettingsGroup(
          title: '自动化',
          children: [
            SwitchListTile(
              title: const Text('自动收菜'),
              subtitle: Text(
                _nextHarvestSubtitle(settings, farmState),
                style: FarmTextStyles.settingDescription.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              value: settings.autoHarvest,
              onChanged: (v) => settings.autoHarvest = v,
              contentPadding: EdgeInsets.zero,
            ),
            ListTile(
              title: const Text('补种种子'),
              contentPadding: EdgeInsets.zero,
              trailing: _settingControl(
                DropdownButton<String?>(
                  value: selectedReplantId,
                  underline: const SizedBox.shrink(),
                  isExpanded: true,
                  isDense: true,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('不补种')),
                    for (final s in inStockSeeds)
                      DropdownMenuItem(
                        value: s.id,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FarmIcon(iconUrl: cropIconUrl(s.image), size: 18),
                            const SizedBox(width: 6),
                            Text('${s.name}（${invQty[s.id]}）'),
                          ],
                        ),
                      ),
                  ],
                  onChanged: (v) => settings.replantSeedId = v,
                ),
              ),
            ),
            SwitchListTile(
              title: const Text('自动务农'),
              subtitle: const Text('自动处理缺水 / 杂草 / 虫害'),
              value: settings.autoCare,
              onChanged: (v) => settings.autoCare = v,
              contentPadding: EdgeInsets.zero,
            ),
            if (settings.autoCare)
              ListTile(
                title: const Text('务农间隔'),
                subtitle: Text(
                  _nextCareSubtitle(autoCare),
                  style: FarmTextStyles.settingDescription.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                contentPadding: EdgeInsets.zero,
                trailing: _settingControl(
                  DropdownButton<int>(
                    value: settings.autoCareIntervalMinutes,
                    underline: const SizedBox.shrink(),
                    isExpanded: true,
                    isDense: true,
                    items: [1, 3, 5, 10, 15]
                        .map(
                          (m) =>
                              DropdownMenuItem(value: m, child: Text('$m 分钟')),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) settings.autoCareIntervalMinutes = v;
                    },
                  ),
                ),
              ),
          ],
        ),
        _SettingsGroup(
          title: '通知',
          children: [
            SwitchListTile(
              title: const Text('收菜通知'),
              subtitle: const Text('自动收菜完成后发送系统通知'),
              value: settings.notifyHarvest,
              onChanged: (v) => settings.notifyHarvest = v,
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
        _SettingsGroup(
          title: '外观',
          children: [
            ListTile(
              title: const Text('主题模式'),
              contentPadding: EdgeInsets.zero,
              trailing: _settingControl(
                DropdownButton<ThemeMode>(
                  value: settings.themeMode,
                  underline: const SizedBox.shrink(),
                  isExpanded: true,
                  isDense: true,
                  items: const [
                    DropdownMenuItem(
                      value: ThemeMode.system,
                      child: Text('跟随系统'),
                    ),
                    DropdownMenuItem(value: ThemeMode.light, child: Text('浅色')),
                    DropdownMenuItem(value: ThemeMode.dark, child: Text('深色')),
                  ],
                  onChanged: (v) {
                    if (v != null) settings.themeMode = v;
                  },
                ),
              ),
            ),
            SwitchListTile(
              title: const Text('鼠标移出时隐藏到托盘'),
              subtitle: const Text('光标离开窗口约 0.5 秒后自动缩小到托盘'),
              value: settings.hideOnMouseLeave,
              onChanged: (v) => settings.hideOnMouseLeave = v,
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
        _SettingsGroup(
          title: '关于与数据',
          children: [
            ListTile(
              leading: Icon(Icons.info_outline, color: colors.textSecondary),
              title: const Text('HYB Farm'),
              subtitle: const Text('后台自动收菜 / 补种 / 务农'),
              trailing: Text(
                'v$kAppVersion',
                style: FarmTextStyles.settingValue.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ],
    );
  }

  String _nextHarvestSubtitle(SettingsState settings, FarmState farmState) {
    if (!settings.autoHarvest) return '已关闭';
    final nextAt = farmState.nextMatureAt;
    if (nextAt == null) return '已开启 · 下次检查：—';
    final seconds = nextAt.difference(DateTime.now()).inSeconds;
    return '已开启 · 下次检查：${formatCountdown(seconds)}';
  }

  String _nextCareSubtitle(AutoCareService autoCare) {
    final nextAt = autoCare.nextCareAt;
    if (nextAt == null) return '下次务农：—';
    final seconds = nextAt.difference(DateTime.now()).inSeconds;
    return '下次务农：${formatCountdown(seconds)}';
  }

  /// 统一右侧下拉控件表面：固定宽度圆角容器 + 无下划线，避免「圆角容器内挂下划线」混用。
  Widget _settingControl(Widget child) {
    final colors = FarmColorScheme.of(context);
    return Container(
      height: FarmSizes.button,
      width: FarmSizes.settingDropdown,
      padding: const EdgeInsets.symmetric(horizontal: FarmSpacing.sm),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(FarmRadii.control),
        border: Border.all(color: colors.border),
      ),
      child: Center(child: child),
    );
  }
}

/// 账户状态卡（S2 强调卡）：头像 + 用户名 + 真实连接状态副标题 + 状态圆点 + 箭头入口。
class _AccountStatusCard extends StatelessWidget {
  const _AccountStatusCard();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final connection = context.watch<ConnectionStateStore>();
    final colors = FarmColorScheme.of(context);
    final state = connection.state;
    final statusColor = accountStatusColor(colors, state);

    return InkWell(
      onTap: () => showAccountDialog(context),
      borderRadius: BorderRadius.circular(FarmRadii.container),
      child: Container(
        padding: const EdgeInsets.all(FarmSpacing.md),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(FarmRadii.container),
          border: Border.all(color: colors.borderStrong),
          boxShadow: FarmShadow.level2(colors),
        ),
        child: Row(
          children: [
            ClipOval(
              child: SizedBox(
                width: 40,
                height: 40,
                child: auth.avatar.isEmpty
                    ? Icon(Icons.person, color: colors.textSecondary, size: 26)
                    : Image.network(
                        auth.avatar,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Icon(
                          Icons.person,
                          color: colors.textSecondary,
                          size: 26,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: FarmSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    auth.username.isEmpty ? '尚未登录' : auth.username,
                    style: FarmTextStyles.listTitle.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    state.accountSubtitle,
                    style: FarmTextStyles.settingDescription.copyWith(
                      color: statusColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: FarmSpacing.xs),
            Container(
              width: FarmSpacing.xs,
              height: FarmSpacing.xs,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, color: colors.textTertiary),
          ],
        ),
      ),
    );
  }
}

/// 设置分组：分组标题 + S1 容器（行间用分隔线，不逐项描边）。
class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = FarmColorScheme.of(context);
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(const Divider(height: 1));
      rows.add(children[i]);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              title,
              style: FarmTextStyles.settingGroupTitle.copyWith(
                color: colors.primary,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(FarmRadii.container),
              border: Border.all(color: colors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Column(children: rows),
            ),
          ),
        ],
      ),
    );
  }
}

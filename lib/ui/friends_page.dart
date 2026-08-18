/// 好友农场页：可偷好友列表 + 手动偷菜 + 分页。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hyb_farm_desktop/api/api_client.dart';
import 'package:hyb_farm_desktop/api/models.dart';
import 'package:hyb_farm_desktop/core/formatters.dart';
import 'package:hyb_farm_desktop/state/friend_state.dart';
import 'package:hyb_farm_desktop/theme/farm_theme.dart';
import 'widgets/empty_state.dart';
import 'widgets/farm_icon.dart';

class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key});

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  Timer? _tickTimer;
  bool _onlyStealable = false;

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

  Future<void> _steal(FriendFarm friend) async {
    final friendState = context.read<FriendState>();
    try {
      await friendState.steal(friend.id);
    } on AuthExpiredException {
      // 连接状态与登录页切换已由 onClassified 链路处理。
    } on Exception {
      // 已由 FriendState 设置 notice，此处不再额外处理。
    }
  }

  @override
  Widget build(BuildContext context) {
    final friendState = context.watch<FriendState>();
    final colors = FarmColorScheme.of(context);
    final statuses = friendState.statuses;
    final stealableCount = statuses.where((f) => f.isStealable).length;
    final visible = _onlyStealable
        ? statuses.where((f) => f.isStealable).toList()
        : statuses;

    return ListView(
      padding: kPagePadding,
      children: [
        Row(
          children: [
            Text(
              '好友',
              style: FarmTextStyles.pageTitle.copyWith(
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '可偷好友 $stealableCount',
              style: FarmTextStyles.pageDescription.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (friendState.stealNotice != null) ...[
          _StealNotice(notice: friendState),
          const SizedBox(height: 8),
        ],
        // 顶部过滤开关：默认展示全部好友，可切「只查看可偷」。
        if (statuses.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _StealFilterToggle(
              onlyStealable: _onlyStealable,
              onChanged: (v) => setState(() => _onlyStealable = v),
            ),
          ),
        if (friendState.loading && statuses.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (statuses.isEmpty)
          _FriendsEmpty(onRefresh: () => context.read<FriendState>().refresh())
        else if (visible.isEmpty)
          // 开了「只查看可偷」但当前页无可偷，提示但仍可切回全部。
          _FriendsAllGrowing(
            statuses: statuses,
            onRefresh: () => context.read<FriendState>().refresh(),
          )
        else
          // 整体 S1 分组容器 + 行分隔线，替代逐行卡片。
          Container(
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(FarmRadii.container),
              border: Border.all(color: colors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < visible.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: FarmSpacing.md),
                  _FriendBar(
                    friend: visible[i],
                    onSteal: () => _steal(visible[i]),
                  ),
                ],
              ],
            ),
          ),
        if (friendState.totalPages > 1) _Pager(state: friendState),
      ],
    );
  }
}

/// 顶部「只查看可偷」开关：默认关闭展示全部好友，开启后仅保留可偷好友。
class _StealFilterToggle extends StatelessWidget {
  const _StealFilterToggle({
    required this.onlyStealable,
    required this.onChanged,
  });

  final bool onlyStealable;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = FarmColorScheme.of(context);
    return Row(
      children: [
        InkWell(
          onTap: () => onChanged(!onlyStealable),
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: FarmSpacing.sm,
              vertical: FarmSpacing.xs - 2,
            ),
            decoration: BoxDecoration(
              color: onlyStealable
                  ? colors.surfaceSelected
                  : colors.surfaceSubtle,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: onlyStealable ? colors.primary : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.visibility,
                  size: 14,
                  color: onlyStealable ? colors.primary : colors.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  '只查看可偷',
                  style: FarmTextStyles.listMeta.copyWith(
                    fontWeight: onlyStealable
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: onlyStealable
                        ? colors.primary
                        : colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 有好友但全部都在生长中（无可偷）时的空状态。
class _FriendsAllGrowing extends StatelessWidget {
  const _FriendsAllGrowing({required this.statuses, required this.onRefresh});

  final List<FriendFarm> statuses;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    // statuses 已按可偷优先 + maturesAt 升序排，取最早的可访问时刻。
    DateTime? earliest;
    for (final f in statuses) {
      final at = f.firstCrop?.maturesAt;
      if (at != null && (earliest == null || at.isBefore(earliest))) {
        earliest = at;
      }
    }

    final String subtitle;
    if (earliest == null) {
      subtitle = '稍后再来看看';
    } else {
      final seconds = earliest.difference(DateTime.now()).inSeconds;
      subtitle = seconds > 0 ? '下次可访问：${formatCountdown(seconds)} 后' : '稍后再来看看';
    }

    return EmptyState(
      icon: Icons.schedule,
      title: '好友的作物都还在生长中',
      subtitle: subtitle,
      action: OutlinedButton.icon(
        onPressed: onRefresh,
        icon: const Icon(Icons.refresh, size: 16),
        label: const Text('刷新'),
      ),
    );
  }
}

/// 无可偷好友时的居中 Empty State。
class _FriendsEmpty extends StatelessWidget {
  const _FriendsEmpty({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.people_outline,
      title: '暂无好友数据',
      subtitle: '稍后再来看看，或邀请好友一起种植',
      action: OutlinedButton.icon(
        onPressed: onRefresh,
        icon: const Icon(Icons.refresh, size: 16),
        label: const Text('刷新'),
      ),
    );
  }
}

class _StealNotice extends StatelessWidget {
  const _StealNotice({required this.notice});

  final FriendState notice;

  @override
  Widget build(BuildContext context) {
    final colors = FarmColorScheme.of(context);
    final isSuccess = notice.stealNoticeType == StealNoticeType.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isSuccess ? colors.surfaceSelected : colors.errorSurface,
        borderRadius: BorderRadius.circular(FarmRadii.control),
        border: Border.all(
          color: isSuccess ? colors.border : colors.errorBorder,
        ),
      ),
      child: Text(
        notice.stealNotice ?? '',
        style: FarmTextStyles.bodySecondary.copyWith(
          color: isSuccess ? colors.success : colors.error,
        ),
      ),
    );
  }
}

class _FriendBar extends StatelessWidget {
  const _FriendBar({required this.friend, required this.onSteal});

  final FriendFarm friend;
  final VoidCallback onSteal;

  @override
  Widget build(BuildContext context) {
    final friendState = context.watch<FriendState>();
    final colors = FarmColorScheme.of(context);
    final first = friend.firstCrop;
    final cooling = friendState.isStealCoolingDown;
    final isStealing = friendState.stealingFriendId == friend.id;
    final canSteal = friend.isStealable && !isStealing && !cooling;
    // 本机记录的最近一次成功偷菜时间（24h 内有效），不依赖服务端可偷状态。
    final lastStealAt = friendState.lastStealAt(friend.id);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          ClipOval(
            child: SizedBox(
              width: 36,
              height: 36,
              child: friend.avatar.isEmpty
                  ? const Icon(Icons.person, size: 36)
                  : Image.network(
                      friend.avatar,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.person, size: 36),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  friend.username,
                  style: FarmTextStyles.listTitle.copyWith(
                    color: colors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (first != null) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      FarmIcon(iconUrl: first.iconUrl, size: 16),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          first.seedName,
                          style: FarmTextStyles.listMeta.copyWith(
                            color: colors.textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    first.isMature
                        ? '已成熟'
                        : formatRemaining(first.remainingTime),
                    style: FarmTextStyles.plotStatus.copyWith(
                      color: colors.primary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          // 尾部标签 + 按钮：顺序固定 [可偷] [已偷·x前] [偷菜]。
          // 防溢出：尾部放 Flexible(flex:3) 获得有界宽度；「可偷」与按钮是非 flex 固定项
          // （按钮优先级最高、永不挤压），「已偷」是 Flexible（可收缩到 0）+ maxWidth + ellipsis，
          // 空间不足时先截断再隐藏，结构上不溢出；内容列 flex:2 由用户名/作物名 ellipsis 吸收。
          Flexible(
            flex: 3,
            child: Row(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (friend.isStealable)
                  _StealTag(text: '可偷'),
                if (lastStealAt != null)
                  Flexible(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 120),
                      child: _StealTag(
                        text: '已偷·${formatRelativeTime(lastStealAt)}',
                        subtle: true,
                      ),
                    ),
                  ),
                const SizedBox(width: 6),
                FilledButton(
                  onPressed: canSteal ? onSteal : null,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: const Size(0, 36),
                  ),
                  child: Text(
                    isStealing
                        ? '偷菜中…'
                        : cooling
                        ? '冷却${friendState.stealCooldownRemainingSeconds}s'
                        : '偷菜',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 好友行尾部的状态标签：「可偷」（突出）与「已偷·x前」（弱化辅助）。
class _StealTag extends StatelessWidget {
  const _StealTag({required this.text, this.subtle = false});

  final String text;
  final bool subtle;

  @override
  Widget build(BuildContext context) {
    final colors = FarmColorScheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: subtle ? colors.surfaceSubtle : colors.surfaceSelected,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: FarmTextStyles.statusText.copyWith(
          color: subtle ? colors.textTertiary : colors.primary,
        ),
      ),
    );
  }
}

class _Pager extends StatelessWidget {
  const _Pager({required this.state});

  final FriendState state;

  @override
  Widget build(BuildContext context) {
    final colors = FarmColorScheme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: state.page > 1
              ? () => state.setPage(state.page - 1)
              : null,
        ),
        Text(
          '${state.page} / ${state.totalPages}',
          style: FarmTextStyles.listMeta.copyWith(
            color: colors.textSecondary,
            fontFeatures: kTabularFigures,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: state.page < state.totalPages
              ? () => state.setPage(state.page + 1)
              : null,
        ),
      ],
    );
  }
}

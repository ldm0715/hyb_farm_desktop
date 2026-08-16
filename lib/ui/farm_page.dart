/// 农场页：标题行、2×2 指标卡、田地状态区（筛选 + 最多 6 块）、自动化活动摘要。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hyb_farm_desktop/api/api_client.dart';
import 'package:hyb_farm_desktop/api/farm_api.dart';
import 'package:hyb_farm_desktop/api/models.dart';
import 'package:hyb_farm_desktop/auth/auth_service.dart';
import 'package:hyb_farm_desktop/core/farm_connection_state.dart';
import 'package:hyb_farm_desktop/core/formatters.dart';
import 'package:hyb_farm_desktop/services/care_log.dart';
import 'package:hyb_farm_desktop/services/challenge_verifier.dart';
import 'package:hyb_farm_desktop/services/harvest_log.dart';
import 'package:hyb_farm_desktop/state/connection_state_store.dart';
import 'package:hyb_farm_desktop/state/farm_state.dart';
import 'package:hyb_farm_desktop/theme/farm_theme.dart';
import 'package:hyb_farm_desktop/ui/challenge_dialog.dart';
import 'widgets/farm_icon.dart';

/// 田地筛选类型。
enum _PlotFilter { all, mature, growing, empty }

/// debuff 类型 → (中文名, 图标)，用于活动摘要与地块卡异常标识。
const Map<String, (String, IconData)> kCareKinds = {
  'thirsty': ('浇水', Icons.water_drop_outlined),
  'weed': ('除草', Icons.eco_outlined),
  'pest': ('杀虫', Icons.bug_report_outlined),
};

class FarmPage extends StatelessWidget {
  const FarmPage({super.key});

  Future<void> _openChallenge(BuildContext context) async {
    final verifier = context.read<ChallengeVerifier>();
    final auth = context.read<AuthService>();
    await showChallengeDialog(context, verifier: verifier, auth: auth);
  }

  Future<void> _harvestNow(BuildContext context) async {
    final api = context.read<FarmApi>();
    final farmState = context.read<FarmState>();
    try {
      await api.harvestAll();
      farmState.setLastResult('收菜成功');
      await farmState.refreshCrops(force: true);
      await farmState.refreshInventory(force: true);
    } on AuthExpiredException {
      farmState.setLastResult('登录已失效');
    } on Exception catch (e) {
      farmState.setLastResult('收菜失败：$e');
    }
  }

  Future<void> _careNow(BuildContext context) async {
    final api = context.read<FarmApi>();
    final farmState = context.read<FarmState>();
    try {
      final r = await api.careAll();
      farmState.setLastResult('务农：处理 ${r.processed} 块地');
      await farmState.refreshCrops(force: true);
    } on AuthExpiredException {
      farmState.setLastResult('登录已失效');
    } on Exception catch (e) {
      farmState.setLastResult('务农失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final farmState = context.watch<FarmState>();
    final colors = FarmColorScheme.of(context);
    final totalSlots = farmState.crops?.totalSlots ?? 0;

    return ListView(
      padding: kPagePadding,
      children: [
        // 页面标题行（主操作「收获」收敛到下方概览卡，标题行只留「务农」）。
        Row(
          children: [
            Text(
              '农场',
              style: FarmTextStyles.pageTitle.copyWith(
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(width: FarmSpacing.xs),
            Expanded(
              child: Text(
                '总地块 $totalSlots · 空闲 ${farmState.freeSlots}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: FarmTextStyles.pageDescription.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: FarmSpacing.xs),
            FilledButton.icon(
              onPressed: farmState.hasDebuff ? () => _careNow(context) : null,
              icon: const Icon(Icons.water_drop_outlined, size: 16),
              label: const Text('务农'),
            ),
          ],
        ),
        const SizedBox(height: FarmSpacing.sm),
        if (context.watch<ConnectionStateStore>().state ==
            FarmConnectionState.challengeRequired) ...[
          _ChallengeBanner(onOpen: () => _openChallenge(context)),
          const SizedBox(height: FarmSpacing.sm),
        ],
        // S2 收获概览卡：突出「现在能不能收获 / 下次何时成熟」。
        _HarvestOverviewCard(onHarvest: () => _harvestNow(context)),
        const SizedBox(height: FarmSpacing.sm),
        // 次级双列信息块：空闲地块 / 仓库估值。
        Row(
          children: [
            Expanded(
              child: _CompactStat(
                label: '空闲地块',
                value: '${farmState.freeSlots}',
              ),
            ),
            const SizedBox(width: FarmSpacing.sm),
            Expanded(
              child: _CompactStat(
                label: '仓库估值',
                value: formatMoneyGrouped(farmState.inventoryTotalValue),
              ),
            ),
          ],
        ),
        const SizedBox(height: FarmSpacing.sm),
        _PlotSection(totalSlots: totalSlots),
        const SizedBox(height: FarmSpacing.sm),
        const _AutomationActivityCard(),
        if (farmState.lastResult != null) ...[
          const SizedBox(height: FarmSpacing.xs),
          Text(
            farmState.lastResult!,
            style: FarmTextStyles.bodySecondary.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

/// S2 收获概览卡：有成熟作物时突出「可收获 N 块 + 立即收获」，
/// 无可收获时切为「下一批 [作物名] 将在 … 后成熟」+ 低调进度条（按钮不渲染）。
class _HarvestOverviewCard extends StatelessWidget {
  const _HarvestOverviewCard({required this.onHarvest});

  final VoidCallback onHarvest;

  @override
  Widget build(BuildContext context) {
    final farmState = context.watch<FarmState>();
    final colors = FarmColorScheme.of(context);
    final matureCount = farmState.matureCount;
    final nextAt = farmState.nextMatureAt;
    final nextCrop = farmState.nextMatureCrop;

    return Container(
      padding: const EdgeInsets.all(FarmSpacing.md),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(FarmRadii.container),
        border: Border.all(color: colors.borderStrong),
        boxShadow: FarmShadow.level2(colors),
      ),
      child: matureCount > 0
          ? Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '可收获',
                        style: FarmTextStyles.metricLabel.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: FarmSpacing.xxs),
                      Text(
                        '$matureCount 块',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FarmTextStyles.metricValue.copyWith(
                          color: colors.textPrimary,
                          fontFeatures: kTabularFigures,
                        ),
                      ),
                      const SizedBox(height: FarmSpacing.xxs),
                      Text(
                        nextAt == null
                            ? '下次收获 —'
                            : '下次收获 ${formatCountdown(nextAt.difference(DateTime.now()).inSeconds)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FarmTextStyles.bodySecondary.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: FarmSpacing.sm),
                FilledButton.icon(
                  onPressed: onHarvest,
                  icon: const Icon(Icons.grass, size: 16),
                  label: const Text('立即收获'),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '下一批 ${nextCrop?.seedName ?? '作物'} 将在 ${nextAt == null ? '—' : formatCountdown(nextAt.difference(DateTime.now()).inSeconds)} 后成熟',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FarmTextStyles.bodyEmphasis.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: FarmSpacing.xs),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: nextCrop?.growthProgress ?? 0,
                    minHeight: 4,
                    color: colors.primary,
                    backgroundColor: colors.surfaceSubtle,
                  ),
                ),
              ],
            ),
    );
  }
}

/// 次级紧凑信息块（S1）：左标签 + 右数值，单行。
class _CompactStat extends StatelessWidget {
  const _CompactStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = FarmColorScheme.of(context);
    return Container(
      height: FarmSizes.compactStat,
      padding: const EdgeInsets.symmetric(horizontal: FarmSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(FarmRadii.card),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FarmTextStyles.metricLabel.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: FarmSpacing.xs),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: FarmTextStyles.numericValue(
              FarmTextStyles.metricValueCompact.copyWith(
                color: colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 田地状态区：标题 + 查看全部 + 筛选 Chip + 最多 6 块地。
class _PlotSection extends StatefulWidget {
  const _PlotSection({required this.totalSlots});

  final int totalSlots;

  @override
  State<_PlotSection> createState() => _PlotSectionState();
}

class _PlotSectionState extends State<_PlotSection> {
  _PlotFilter _filter = _PlotFilter.all;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final farmState = context.watch<FarmState>();
    final crops = farmState.crops?.crops ?? const <Crop>[];

    final all = <Crop>[
      for (var i = 0; i < widget.totalSlots; i++) _cropAt(crops, i),
    ];
    final mature = all.where((c) => !c.isEmpty && c.mature).toList();
    final growing = all.where((c) => !c.isEmpty && !c.mature).toList();
    final empty = all.where((c) => c.isEmpty).toList();

    // 成熟优先 → 即将成熟（remaining 升序）→ 生长中 → 空闲。
    final sorted = <Crop>[
      ...mature,
      ...growing..sort((a, b) => a.remainingTime.compareTo(b.remainingTime)),
      ...empty,
    ];
    final filtered = switch (_filter) {
      _PlotFilter.all => sorted,
      _PlotFilter.mature => mature,
      _PlotFilter.growing => growing,
      _PlotFilter.empty => empty,
    };
    final visible = _expanded ? filtered : filtered.take(8).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '田地状态',
              style: FarmTextStyles.sectionTitle.copyWith(
                color: FarmColorScheme.of(context).textPrimary,
              ),
            ),
            const Spacer(),
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _expanded ? '收起' : '查看全部 ${widget.totalSlots} 块地',
                    style: FarmTextStyles.sectionHint.copyWith(
                      color: FarmColorScheme.of(context).primary,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: FarmColorScheme.of(context).primary,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: FarmSpacing.xs),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _filterChip(_PlotFilter.all, '全部', all.length),
              _filterChip(_PlotFilter.mature, '成熟', mature.length),
              _filterChip(_PlotFilter.growing, '生长中', growing.length),
              _filterChip(_PlotFilter.empty, '空闲', empty.length),
            ],
          ),
        ),
        const SizedBox(height: FarmSpacing.sm),
        if (visible.isEmpty)
          Container(
            height: FarmSizes.plotCard,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: FarmColorScheme.of(context).surface,
              borderRadius: BorderRadius.circular(FarmRadii.card),
              border: Border.all(color: FarmColorScheme.of(context).border),
            ),
            child: Text(
              '暂无地块数据',
              style: FarmTextStyles.bodySecondary.copyWith(
                color: FarmColorScheme.of(context).textSecondary,
              ),
            ),
          )
        else
          GridView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisExtent: FarmSizes.plotCard,
              mainAxisSpacing: FarmSpacing.xs,
              crossAxisSpacing: FarmSpacing.xs,
            ),
            children: [for (final c in visible) _PlotCard(crop: c)],
          ),
      ],
    );
  }

  Crop _cropAt(List<Crop> crops, int index) {
    for (final c in crops) {
      if (c.plotIndex == index) return c;
    }
    return const Crop(
      id: '',
      seedId: '',
      seedName: '',
      seedImage: '',
      plotIndex: 0,
    );
  }

  Widget _filterChip(_PlotFilter f, String label, int count) {
    final selected = _filter == f;
    final colors = FarmColorScheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: FarmSpacing.xs),
      child: InkWell(
        onTap: () => setState(() => _filter = f),
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: FarmSpacing.sm,
            vertical: FarmSpacing.xs - 2,
          ),
          decoration: BoxDecoration(
            color: selected ? colors.surfaceSelected : colors.surfaceSubtle,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? colors.primary : Colors.transparent,
            ),
          ),
          child: Text(
            '$label $count',
            style:
                (selected
                        ? FarmTextStyles.listMeta.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colors.primary,
                          )
                        : FarmTextStyles.listMeta.copyWith(
                            color: colors.textSecondary,
                          ))
                    .copyWith(fontFeatures: kTabularFigures),
          ),
        ),
      ),
    );
  }
}

class _PlotCard extends StatelessWidget {
  const _PlotCard({required this.crop});

  final Crop crop;

  @override
  Widget build(BuildContext context) {
    final colors = FarmColorScheme.of(context);
    final empty = crop.isEmpty;
    final mature = !empty && crop.mature;
    final abnormal = !empty && crop.hasDebuff;

    final (statusText, statusColor) = switch ((empty, mature, abnormal)) {
      (true, _, _) => ('空闲', colors.textSecondary),
      (false, true, _) => ('可收获', colors.primary),
      (false, false, true) => ('异常', colors.error),
      _ => ('生长中', colors.textSecondary),
    };

    // 异常地块用有色表面强调；成熟地块用 ready 表面；其余（生长中/空闲）白/次级表面。
    final (bgColor, borderColor) = abnormal
        ? (colors.errorSurface, colors.errorBorder)
        : mature
        ? (colors.readySurface, colors.readyBorder)
        : (empty ? colors.surfaceSubtle : colors.surface, colors.border);

    return Container(
      height: FarmSizes.plotCard,
      padding: const EdgeInsets.symmetric(
        horizontal: FarmSpacing.sm,
        vertical: FarmSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(FarmRadii.card),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '#${(crop.plotIndex + 1).toString().padLeft(2, '0')}',
                style: FarmTextStyles.plotNumber.copyWith(
                  color: colors.textTertiary,
                  fontFeatures: kTabularFigures,
                ),
              ),
              const Spacer(),
              if (abnormal && !mature)
                for (final c in crop.conditions)
                  Padding(
                    padding: const EdgeInsets.only(right: FarmSpacing.xxs),
                    child: Icon(
                      kCareKinds[c]?.$2 ?? Icons.warning_amber_rounded,
                      size: 12,
                      color: colors.error,
                    ),
                  ),
              Text(
                statusText,
                style: mature
                    ? FarmTextStyles.plotStatusMature.copyWith(
                        color: colors.primary,
                      )
                    : FarmTextStyles.plotStatus.copyWith(color: statusColor),
              ),
            ],
          ),
          const Spacer(),
          if (empty)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '空地',
                style: FarmTextStyles.bodySecondary.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            )
          else ...[
            Row(
              children: [
                FarmIcon(iconUrl: crop.iconUrl),
                const SizedBox(width: FarmSpacing.xxs),
                Expanded(
                  child: Text(
                    crop.seedName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FarmTextStyles.listMeta.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: FarmSpacing.xxs - 2),
            Text(
              mature ? '已成熟' : formatRemaining(crop.remainingTime),
              style:
                  (mature
                          ? FarmTextStyles.plotStatusMature.copyWith(
                              color: colors.primary,
                            )
                          : FarmTextStyles.plotStatus.copyWith(
                              color: colors.success,
                            ))
                      .copyWith(fontFeatures: kTabularFigures),
            ),
            const SizedBox(height: FarmSpacing.xxs),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: mature ? 1.0 : crop.growthProgress ?? 0,
                minHeight: 4,
                color: colors.primary,
                backgroundColor: colors.surfaceSubtle,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 自动化活动摘要：拆成「自动收菜」「自动务农」两块，各自显示明细与最近执行。
class _AutomationActivityCard extends StatefulWidget {
  const _AutomationActivityCard();

  @override
  State<_AutomationActivityCard> createState() =>
      _AutomationActivityCardState();
}

class _AutomationActivityCardState extends State<_AutomationActivityCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = FarmColorScheme.of(context);
    final harvestLog = context.watch<HarvestLog>();
    final careLog = context.watch<CareLog>();
    final window = const Duration(hours: 24);

    final harvestCounts = harvestLog.countsWithin(window);
    final harvestTotal = harvestCounts.values.fold(0, (s, c) => s + c.count);
    final careCounts = careLog.countsWithin(window);
    final careTotal = careCounts.values.fold(0, (s, c) => s + c);

    return Container(
      padding: const EdgeInsets.all(FarmSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(FarmRadii.card),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(FarmRadii.control),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: FarmSpacing.xxs),
              child: Row(
                children: [
                  Text(
                    '自动化活动',
                    style: FarmTextStyles.sectionTitle.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '过去 24 小时',
                    style: FarmTextStyles.sectionHint.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: FarmSpacing.xxs),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: colors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: FarmSpacing.sm),
            _sectionHeader(
              '自动收菜',
              '$harvestTotal 次',
              harvestLog.lastRecordedAt,
            ),
            const SizedBox(height: FarmSpacing.xs),
            _harvestDetail(harvestCounts),
            const SizedBox(height: FarmSpacing.md),
            _sectionHeader('自动务农', '$careTotal 次', careLog.lastRecordedAt),
            const SizedBox(height: FarmSpacing.xs),
            _careDetail(careCounts),
          ],
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, String total, DateTime? lastAt) {
    final colors = FarmColorScheme.of(context);
    return Row(
      children: [
        Text(
          title,
          style: FarmTextStyles.bodySecondary.copyWith(
            color: colors.textSecondary,
          ),
        ),
        const Spacer(),
        Text(
          '$total · 最近 ${_recentLabel(lastAt)}',
          style: FarmTextStyles.bodyEmphasis.copyWith(
            color: colors.textPrimary,
            fontFeatures: kTabularFigures,
          ),
        ),
      ],
    );
  }

  Widget _harvestDetail(Map<String, HarvestCount> counts) {
    final items = counts.values.toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    if (items.isEmpty) {
      return Text(
        '暂无收菜记录',
        style: FarmTextStyles.bodySecondary.copyWith(
          color: FarmColorScheme.of(context).textSecondary,
        ),
      );
    }
    return Wrap(
      spacing: FarmSpacing.xs,
      runSpacing: FarmSpacing.xs,
      children: [
        for (final c in items) _harvestChip(c.iconUrl, c.name, '${c.count}'),
      ],
    );
  }

  Widget _careDetail(Map<String, int> counts) {
    final rows = <Widget>[
      for (final e in kCareKinds.entries)
        if ((counts[e.key] ?? 0) > 0)
          _careChip(e.value.$2, e.value.$1, counts[e.key]!),
    ];
    if (rows.isEmpty) {
      return Text(
        '暂无务农记录',
        style: FarmTextStyles.bodySecondary.copyWith(
          color: FarmColorScheme.of(context).textSecondary,
        ),
      );
    }
    return Wrap(
      spacing: FarmSpacing.xs,
      runSpacing: FarmSpacing.xs,
      children: rows,
    );
  }

  Widget _harvestChip(String iconUrl, String name, String count) {
    final colors = FarmColorScheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FarmSpacing.xs,
        vertical: FarmSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceSubtle,
        borderRadius: BorderRadius.circular(FarmRadii.control),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(FarmRadii.small),
            child: Image.network(
              iconUrl,
              width: 16,
              height: 16,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const Icon(Icons.grass, size: 16),
            ),
          ),
          const SizedBox(width: FarmSpacing.xxs),
          Text(
            name,
            style: FarmTextStyles.bodySecondary.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(width: FarmSpacing.xxs),
          Text(
            count,
            style: FarmTextStyles.bodyEmphasis.copyWith(
              color: colors.textPrimary,
              fontFeatures: kTabularFigures,
            ),
          ),
        ],
      ),
    );
  }

  Widget _careChip(IconData icon, String label, int count) {
    final colors = FarmColorScheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FarmSpacing.xs,
        vertical: FarmSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceSubtle,
        borderRadius: BorderRadius.circular(FarmRadii.control),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colors.primary),
          const SizedBox(width: FarmSpacing.xxs),
          Text(
            label,
            style: FarmTextStyles.bodySecondary.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(width: FarmSpacing.xxs),
          Text(
            '$count',
            style: FarmTextStyles.bodyEmphasis.copyWith(
              color: colors.textPrimary,
              fontFeatures: kTabularFigures,
            ),
          ),
        ],
      ),
    );
  }

  String _recentLabel(DateTime? at) {
    if (at == null) return '暂无';
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    return '${diff.inDays} 天前';
  }
}

/// challengeRequired 时的紧凑警告 Banner。
class _ChallengeBanner extends StatelessWidget {
  const _ChallengeBanner({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = FarmColorScheme.of(context);
    return Container(
      padding: const EdgeInsets.all(FarmSpacing.sm),
      decoration: BoxDecoration(
        color: colors.readySurface,
        borderRadius: BorderRadius.circular(FarmRadii.card),
        border: Border.all(color: colors.readyBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '需要完成安全验证',
            style: FarmTextStyles.bodyEmphasis.copyWith(
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: FarmSpacing.xxs),
          Text(
            '检测到网站安全验证，自动化任务已暂停',
            style: FarmTextStyles.bodySecondary.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: FarmSpacing.xs),
          Row(
            children: [
              FilledButton(onPressed: onOpen, child: const Text('打开验证窗口')),
              const SizedBox(width: FarmSpacing.xs),
              TextButton(onPressed: () {}, child: const Text('稍后处理')),
            ],
          ),
        ],
      ),
    );
  }
}

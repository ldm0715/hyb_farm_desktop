/// 仓库页：库存列表（多选 + 数量步进） + 收益排行 + 底部出售栏。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:hyb_farm_desktop/api/api_client.dart';
import 'package:hyb_farm_desktop/api/models.dart';
import 'package:hyb_farm_desktop/auth/auth_service.dart';
import 'package:hyb_farm_desktop/core/formatters.dart';
import 'package:hyb_farm_desktop/core/operation_coordinator.dart';
import 'package:hyb_farm_desktop/core/ranking.dart';
import 'package:hyb_farm_desktop/services/recycle_service.dart';
import 'package:hyb_farm_desktop/services/replant_service.dart';
import 'package:hyb_farm_desktop/state/farm_state.dart';
import 'package:hyb_farm_desktop/theme/farm_theme.dart';
import 'warehouse_segmented_control.dart';
import 'widgets/empty_state.dart';
import 'widgets/farm_icon.dart';

class WarehousePage extends StatefulWidget {
  const WarehousePage({super.key});

  @override
  State<WarehousePage> createState() => _WarehousePageState();
}

class _WarehousePageState extends State<WarehousePage> {
  final Map<String, int> _selected = {};
  bool _busy = false;
  bool _showRanking = false;

  int _sel(String seedId) => _selected[seedId] ?? 0;

  void _setSel(String seedId, int v) {
    setState(() => _selected[seedId] = v.clamp(0, 1 << 30));
  }

  int _selectedTotal() => _selected.values.fold(0, (a, b) => a + b);

  int _selectedKinds() => _selected.values.where((v) => v > 0).length;

  List<({String seedId, String seedName, int quantity})> _selectedEntries(
    FarmState farmState,
  ) => [
    for (final i in farmState.inventory)
      if (_sel(i.seedId) > 0)
        (
          seedId: i.seedId,
          seedName: i.seedName,
          quantity: _sel(i.seedId) > i.quantity ? i.quantity : _sel(i.seedId),
        ),
  ];

  void _selectAll(FarmState farmState) {
    setState(() {
      for (final i in farmState.inventory) {
        _selected[i.seedId] = i.quantity;
      }
    });
  }

  void _clearAll() {
    setState(() => _selected.clear());
  }

  Future<void> _sellSelected() async {
    final farmState = context.read<FarmState>();
    final recycle = context.read<RecycleService>();
    final auth = context.read<AuthService>();
    final entries = _selectedEntries(farmState);
    if (entries.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _busy = true);
    try {
      final messages = await recycle.sellSelected(entries);
      await farmState.refreshInventory(force: true);
      // 卖出后账户余额变化，主动刷新一次（事件驱动，无缓存节流）。
      await auth.loadDashboardStats();
      setState(() => _selected.clear());
      messenger.showSnackBar(
        SnackBar(
          content: Text(messages.isEmpty ? '未卖出任何作物' : messages.join('\n')),
        ),
      );
    } on AuthExpiredException {
      farmState.setLastResult('登录已失效');
    } on Exception catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('卖出失败：$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _plantSelected() async {
    final farmState = context.read<FarmState>();
    final coordinator = context.read<OperationCoordinator>();
    final replant = context.read<ReplantService>();
    final entries = _selectedEntries(farmState);
    if (entries.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);

    final total = _selectedTotal();
    if (total > farmState.freeSlots) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('选择 $total 个超出空地 ${farmState.freeSlots}，将按空地裁剪'),
        ),
      );
    }

    setState(() => _busy = true);
    try {
      final messages = <String>[];
      for (final e in entries) {
        final count = await coordinator.run(
          () => replant.plant(e.seedId, e.quantity),
        );
        messages.add(
          count > 0
              ? '种植 $count 个${e.seedName}'
              : '种植 ${e.seedName} 失败（空地/库存不足）',
        );
      }
      await farmState.refreshCrops(force: true);
      await farmState.refreshInventory(force: true);
      setState(() => _selected.clear());
      messenger.showSnackBar(SnackBar(content: Text(messages.join('\n'))));
    } on AuthExpiredException {
      farmState.setLastResult('登录已失效');
    } on Exception catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('种植失败：$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final farmState = context.watch<FarmState>();
    final colors = FarmColorScheme.of(context);
    final inventory = farmState.inventory;
    final prices = farmState.recyclePriceBySeedId;

    final selected = <({InventoryItem item, int qty})>[
      for (final i in inventory)
        if (_sel(i.seedId) > 0)
          (
            item: i,
            qty: _sel(i.seedId) > i.quantity ? i.quantity : _sel(i.seedId),
          ),
    ];
    final totalCount = selected.fold(0, (sum, e) => sum + e.qty);
    final totalValue = selected.fold(
      0,
      (sum, e) =>
          sum + e.qty * (prices[e.item.seedId] ?? e.item.recyclePriceInt),
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            FarmSpacing.md,
            FarmSpacing.sm,
            FarmSpacing.md,
            0,
          ),
          child: Row(
            children: [
              Text(
                '仓库',
                style: FarmTextStyles.pageTitle.copyWith(
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(width: FarmSpacing.xs),
              Text(
                '总估值 ${formatMoneyGrouped(farmState.inventoryTotalValue)}',
                style: FarmTextStyles.pageDescription.copyWith(
                  color: colors.textSecondary,
                  fontFeatures: kTabularFigures,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            FarmSpacing.md,
            FarmSpacing.xs,
            FarmSpacing.md,
            FarmSpacing.xs,
          ),
          child: SizedBox(
            height: FarmSizes.segmented,
            child: WarehouseSegmentedControl(
              selected: _showRanking,
              onChanged: (v) => setState(() => _showRanking = v),
            ),
          ),
        ),
        Expanded(
          child: _showRanking
              ? const _RankingView()
              : inventory.isEmpty
              ? EmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: '仓库为空',
                  subtitle: '收获的作物会出现在这里',
                )
              : Column(
                  children: [
                    _SelectionBar(
                      selectedKinds: _selectedKinds(),
                      totalCount: totalCount,
                      allSelected:
                          inventory.isNotEmpty &&
                          inventory.every((i) => _sel(i.seedId) >= i.quantity),
                      onSelectAll: () => _selectAll(farmState),
                      onClear: _clearAll,
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(
                          FarmSpacing.md,
                          FarmSpacing.xxs,
                          FarmSpacing.md,
                          FarmSizes.sellBar + FarmSpacing.md,
                        ),
                        children: [
                          // 整体 S1 分组容器：行分隔线 + 选中行轻提升，替代逐行卡片。
                          Container(
                            decoration: BoxDecoration(
                              color: colors.surface,
                              borderRadius: BorderRadius.circular(
                                FarmRadii.container,
                              ),
                              border: Border.all(color: colors.border),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              children: [
                                for (
                                  var idx = 0;
                                  idx < inventory.length;
                                  idx++
                                ) ...[
                                  if (idx > 0)
                                    const Divider(
                                      height: 1,
                                      indent: FarmSpacing.md,
                                    ),
                                  _buildItem(context, inventory[idx], prices),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
        if (!_showRanking && selected.isNotEmpty)
          _SellBar(
            selectedKinds: _selectedKinds(),
            totalCount: totalCount,
            totalValue: totalValue,
            busy: _busy,
            onSell: _sellSelected,
            onPlant: _plantSelected,
          ),
      ],
    );
  }

  Widget _buildItem(
    BuildContext context,
    InventoryItem i,
    Map<String, int> prices,
  ) {
    final colors = FarmColorScheme.of(context);
    final qty = i.quantity;
    final livePrice = prices[i.seedId] ?? i.recyclePriceInt;
    final sel = _sel(i.seedId);

    return Material(
      color: sel > 0 ? colors.surfaceSelected : Colors.transparent,
      child: InkWell(
        onTap: () => _setSel(i.seedId, sel > 0 ? 0 : qty),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: FarmSpacing.sm,
            vertical: FarmSpacing.xs,
          ),
          child: Row(
            children: [
              Checkbox(
                value: sel > 0,
                onChanged: (v) => _setSel(i.seedId, (v ?? false) ? qty : 0),
              ),
              FarmIcon(iconUrl: i.iconUrl),
              const SizedBox(width: FarmSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      i.seedName,
                      style: FarmTextStyles.listTitle.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: FarmSpacing.xxs),
                    Text(
                      '库存 $qty · 单价 ${formatMoney(livePrice)}',
                      style: FarmTextStyles.listMeta.copyWith(
                        color: colors.textSecondary,
                        fontFeatures: kTabularFigures,
                      ),
                    ),
                  ],
                ),
              ),
              _QuantityStepper(
                max: qty,
                value: sel,
                onChanged: (v) => _setSel(i.seedId, v),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 页面级选择操作条。
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.selectedKinds,
    required this.totalCount,
    required this.allSelected,
    required this.onSelectAll,
    required this.onClear,
  });

  final int selectedKinds;
  final int totalCount;
  final bool allSelected;
  final VoidCallback onSelectAll;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colors = FarmColorScheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FarmSpacing.md,
        FarmSpacing.xxs,
        FarmSpacing.md,
        FarmSpacing.xxs,
      ),
      child: Row(
        children: [
          Text(
            '已选 $selectedKinds 项 · 共 $totalCount 件',
            style: FarmTextStyles.bodySecondary.copyWith(
              color: colors.textSecondary,
              fontFeatures: kTabularFigures,
            ),
          ),
          const Spacer(),
          TextButton(onPressed: onSelectAll, child: const Text('全选')),
          TextButton(
            onPressed: selectedKinds > 0 ? onClear : null,
            child: const Text('清空选择'),
          ),
        ],
      ),
    );
  }
}

class _QuantityStepper extends StatefulWidget {
  const _QuantityStepper({
    required this.max,
    required this.value,
    required this.onChanged,
  });

  final int max;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  State<_QuantityStepper> createState() => _QuantityStepperState();
}

class _QuantityStepperState extends State<_QuantityStepper> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value == 0 ? '' : '${widget.value}',
  );

  @override
  void didUpdateWidget(_QuantityStepper oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 值变化时同步文本框：0 显示为空占位，其余回写数字。
    final target = widget.value == 0 ? '' : '${widget.value}';
    if (_controller.text != target) {
      _controller.text = target;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _fillMax() {
    _controller.text = '${widget.max}';
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
    widget.onChanged(widget.max);
  }

  void _clear() {
    _controller.clear();
    widget.onChanged(0);
  }

  @override
  Widget build(BuildContext context) {
    final colors = FarmColorScheme.of(context);
    final selected = widget.value > 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _stepButton(
          Icons.remove,
          enabled: widget.value > 0,
          onTap: () {
            widget.onChanged((widget.value - 1).clamp(0, widget.max));
          },
        ),
        SizedBox(
          width: 40,
          child: TextField(
            controller: _controller,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.center,
            style: FarmTextStyles.numericValue(
              FarmTextStyles.bodyEmphasis.copyWith(
                color: selected ? colors.primary : colors.textSecondary,
              ),
            ),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 6,
              ),
              hintText: '0',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(FarmRadii.control),
                borderSide: BorderSide(
                  color: selected ? colors.primary : colors.border,
                ),
              ),
            ),
            onChanged: (s) {
              final v = int.tryParse(s) ?? 0;
              widget.onChanged(v.clamp(0, widget.max));
            },
          ),
        ),
        _stepButton(
          Icons.add,
          enabled: widget.value < widget.max,
          onTap: () {
            widget.onChanged((widget.value + 1).clamp(0, widget.max));
          },
        ),
        // 未选中时降噪：只显 [- 0 +]，选中后再展开「最大 / 清空」。
        if (selected) ...[
          _actionButton('最大', enabled: widget.max > 0, onTap: _fillMax),
          _actionButton('清空', enabled: widget.value > 0, onTap: _clear),
        ],
      ],
    );
  }

  Widget _stepButton(
    IconData icon, {
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: 28,
      height: 28,
      child: IconButton(
        icon: Icon(icon, size: 16),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        onPressed: enabled ? onTap : null,
      ),
    );
  }

  Widget _actionButton(
    String label, {
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final colors = FarmColorScheme.of(context);
    return TextButton(
      onPressed: enabled ? onTap : null,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: FarmSpacing.xxs),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        label,
        style: FarmTextStyles.bodySecondary.copyWith(
          color: colors.textSecondary,
        ),
      ),
    );
  }
}

/// 底部固定出售栏。
class _SellBar extends StatelessWidget {
  const _SellBar({
    required this.selectedKinds,
    required this.totalCount,
    required this.totalValue,
    required this.busy,
    required this.onSell,
    required this.onPlant,
  });

  final int selectedKinds;
  final int totalCount;
  final int totalValue;
  final bool busy;
  final VoidCallback onSell;
  final VoidCallback onPlant;

  @override
  Widget build(BuildContext context) {
    final colors = FarmColorScheme.of(context);
    return Container(
      height: FarmSizes.sellBar,
      padding: const EdgeInsets.symmetric(horizontal: FarmSpacing.md),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '已选 $selectedKinds 项 · 共 $totalCount 件',
                  style: FarmTextStyles.bodySecondary.copyWith(
                    color: colors.textSecondary,
                    fontFeatures: kTabularFigures,
                  ),
                ),
                Text(
                  '预计 ${formatMoneyGrouped(totalValue)}',
                  style: FarmTextStyles.bodyEmphasis.copyWith(
                    color: colors.textPrimary,
                    fontFeatures: kTabularFigures,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: busy ? null : onPlant,
            child: const Text('种植'),
          ),
          const SizedBox(width: FarmSpacing.xs),
          FilledButton(
            onPressed: busy ? null : onSell,
            child: const Text('出售'),
          ),
        ],
      ),
    );
  }
}

/// 收益排行视图：最优作物 hero + 按每小时收益降序的作物列表。
class _RankingView extends StatelessWidget {
  const _RankingView();

  @override
  Widget build(BuildContext context) {
    final farmState = context.watch<FarmState>();
    final ranking = farmState.ranking;

    if (ranking.isEmpty) {
      return const EmptyState(
        icon: Icons.leaderboard_outlined,
        title: '暂无排行数据',
        subtitle: '获取实时单价后展示收益排行',
      );
    }

    final top = ranking.first;
    final maxProfit = top.revenuePerHour;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        FarmSpacing.md,
        FarmSpacing.sm,
        FarmSpacing.md,
        FarmSpacing.md,
      ),
      children: [
        _RankingHero(top: top, maxProfit: maxProfit),
        const SizedBox(height: FarmSpacing.xs),
        // 第 2 名起为紧凑列表行，整体放进一个 S1 容器 + 行分隔线。
        Container(
          decoration: BoxDecoration(
            color: FarmColorScheme.of(context).surface,
            borderRadius: BorderRadius.circular(FarmRadii.container),
            border: Border.all(color: FarmColorScheme.of(context).border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 1; i < ranking.length; i++) ...[
                if (i > 1) const Divider(height: 1, indent: FarmSpacing.md),
                _RankingRow(row: ranking[i], rank: i + 1, maxProfit: maxProfit),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _RankingHero extends StatelessWidget {
  const _RankingHero({required this.top, required this.maxProfit});

  final RankingRow top;
  final double maxProfit;

  @override
  Widget build(BuildContext context) {
    final colors = FarmColorScheme.of(context);
    return Container(
      padding: const EdgeInsets.all(FarmSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(FarmRadii.container),
        border: Border.all(color: colors.borderStrong),
        boxShadow: FarmShadow.level2(colors),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.gold,
              shape: BoxShape.circle,
            ),
            child: Text(
              '1',
              style: FarmTextStyles.numericValue(
                FarmTextStyles.metricLabel.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.onPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(width: FarmSpacing.xs - 2),
          FarmIcon(iconUrl: top.iconUrl, size: 40),
          const SizedBox(width: FarmSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '最划算 · ${top.name}',
                  style: FarmTextStyles.sectionTitle.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: FarmSpacing.xxs),
                Text(
                  '每小时收益 ${formatPerHour(top.revenuePerHour)}',
                  style: FarmTextStyles.bodyEmphasis.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                Text(
                  '单价 ${formatUsd(top.unitPrice)} · 单次 ${formatUsd(top.harvestRevenue)}',
                  style: FarmTextStyles.bodySecondary.copyWith(
                    color: colors.textSecondary,
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

class _RankingRow extends StatelessWidget {
  const _RankingRow({
    required this.row,
    required this.rank,
    required this.maxProfit,
  });

  final RankingRow row;
  final int rank;
  final double maxProfit;

  @override
  Widget build(BuildContext context) {
    final colors = FarmColorScheme.of(context);
    final percent = maxProfit > 0
        ? (row.revenuePerHour / maxProfit * 100).clamp(4.0, 100.0)
        : 4.0;

    // 排名徽章颜色收敛到语义 token（金/银/铜），前三名前景用 onPrimary，
    // 亮色底深字 / 暗色底浅字自动适应；第 4 名起用中性 surfaceSubtle。
    final accentColor = switch (rank) {
      1 => colors.gold,
      2 => colors.silver,
      3 => colors.bronze,
      _ => null,
    };
    final isTop3 = accentColor != null;
    final badgeColor = accentColor ?? colors.surfaceSubtle;
    final badgeForeground = isTop3 ? colors.onPrimary : colors.textSecondary;
    final barColor = colors.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FarmSpacing.sm,
        vertical: FarmSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: badgeColor,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$rank',
                  style: FarmTextStyles.numericValue(
                    FarmTextStyles.metricLabel.copyWith(
                      fontWeight: FontWeight.w700,
                      color: badgeForeground,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: FarmSpacing.xs - 2),
              FarmIcon(iconUrl: row.iconUrl),
              const SizedBox(width: FarmSpacing.xs),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        row.name,
                        style: FarmTextStyles.listTitle.copyWith(
                          color: colors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (row.isVipOnly) ...[
                      const SizedBox(width: FarmSpacing.xxs),
                      Text(
                        'VIP',
                        style: FarmTextStyles.statusText.copyWith(
                          color: colors.warning,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: FarmSpacing.xs),
              Text(
                formatPerHour(row.revenuePerHour),
                style: FarmTextStyles.bodyEmphasis.copyWith(
                  color: colors.textPrimary,
                  fontFeatures: kTabularFigures,
                ),
              ),
            ],
          ),
          const SizedBox(height: FarmSpacing.xs - 2),
          Row(
            children: [
              Expanded(
                child: Text(
                  '成熟 ${formatGrowthTime(row.growthTimeSeconds)} · 产量 ${row.harvestQuantity}',
                  style: FarmTextStyles.bodySecondary.copyWith(
                    color: colors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '单价 ${formatUsd(row.unitPrice)}',
                style: FarmTextStyles.bodySecondary.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: FarmSpacing.xs - 2),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percent / 100,
              minHeight: 6,
              color: barColor,
              backgroundColor: colors.surfaceSubtle,
            ),
          ),
        ],
      ),
    );
  }
}

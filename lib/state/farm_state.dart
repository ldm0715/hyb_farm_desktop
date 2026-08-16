/// 农场数据与自动化运行状态。
library;

import 'package:flutter/foundation.dart';
import 'package:hyb_farm_desktop/api/farm_api.dart';
import 'package:hyb_farm_desktop/api/models.dart';
import 'package:hyb_farm_desktop/core/constants.dart';
import 'package:hyb_farm_desktop/core/ranking.dart';
import 'package:hyb_farm_desktop/core/resource_cache.dart';

/// 自动化运行状态。
enum AutomationStatus { idle, running, paused }

class FarmState extends ChangeNotifier {
  FarmState(this._api, {DateTime Function()? now}) {
    final clock = now ?? DateTime.now;
    _cropsCache = ResourceCache<CropsResponse>(
      // crops 无 TTL：成熟时间固定，收菜/兜底按精确定时驱动，唯一守卫是最小间隔。
      ttl: Duration.zero,
      minInterval: kMinRequestInterval,
      fetch: _api.fetchCrops,
      now: clock,
    );
    _plotsCache = ResourceCache<FarmPlots>(
      ttl: kPlotsCacheTtl,
      minInterval: kMinRequestInterval,
      fetch: _api.fetchPlots,
      now: clock,
    );
    _inventoryCache = ResourceCache<List<InventoryItem>>(
      ttl: kInventoryCacheTtl,
      minInterval: kMinRequestInterval,
      fetch: _api.fetchInventory,
      now: clock,
    );
    _seedsCache = ResourceCache<List<Seed>>(
      ttl: kSeedsCacheTtl,
      minInterval: kMinRequestInterval,
      fetch: _api.fetchSeeds,
      now: clock,
    );
    _pricesCache = ResourceCache<FarmPrices>(
      ttl: kPricesCacheTtl,
      minInterval: kMinRequestInterval,
      fetch: _api.fetchPrices,
      now: clock,
    );
  }

  final FarmApi _api;

  late final ResourceCache<CropsResponse> _cropsCache;
  late final ResourceCache<FarmPlots> _plotsCache;
  late final ResourceCache<List<InventoryItem>> _inventoryCache;
  late final ResourceCache<List<Seed>> _seedsCache;
  late final ResourceCache<FarmPrices> _pricesCache;

  AutomationStatus _automation = AutomationStatus.idle;
  AutomationStatus get automation => _automation;

  bool _loading = false;
  bool get loading => _loading;

  String? _lastResult;
  String? get lastResult => _lastResult;

  CropsResponse? get crops => _cropsCache.value;
  FarmPlots? get plots => _plotsCache.value;
  List<InventoryItem> get inventory => _inventoryCache.value ?? const [];
  List<Seed> get seeds => _seedsCache.value ?? const [];
  List<RecyclePrice> get recyclePrices =>
      _pricesCache.value?.recyclePrices ?? const [];

  /// 实时单价（seedId → 原始整数），收益排行数据源。
  Map<String, int> get unitPrices => _pricesCache.value?.unitPrices ?? const {};

  /// 收益排行（按每小时收益降序）。
  List<RankingRow> get ranking => buildRanking(seeds, unitPrices);

  /// 实时回收价：seedId → 原始整数价格。
  Map<String, int> get recyclePriceBySeedId => {
    for (final p in recyclePrices) p.seedId: p.recyclePriceInt,
  };

  /// 可收数量（已成熟且非空地）。
  int get matureCount =>
      crops?.crops.where((c) => c.mature && !c.isEmpty).length ?? 0;

  /// 下一成熟倒计时（秒）；已成熟返回 0，无未成熟作物返回 null。
  int? get nextMatureIn {
    final pending =
        crops?.crops.where((c) => !c.isEmpty && !c.mature).toList() ??
        const [];
    if (pending.isEmpty) return null;
    var min = 1 << 30;
    for (final c in pending) {
      if (c.remainingTime < min) min = c.remainingTime;
    }
    return min;
  }

  /// 空闲地块数量。
  int get freeSlots => crops?.freeSlots ?? (plots?.freeSlots ?? 0);

  /// 仓库作物总数。
  int get inventoryTotal => inventory.fold(0, (sum, i) => sum + i.quantity);

  /// 仓库作物总价值（原始整数，展示需除以 kPriceDivisor）。
  int get inventoryTotalValue =>
      inventory.fold(0, (sum, i) => sum + i.quantity * i.recyclePriceInt);

  /// 下一批作物成熟的绝对时刻（据此可逐秒递减倒计时）；无未成熟作物返回 null。
  DateTime? get nextMatureAt {
    final remaining = nextMatureIn;
    if (remaining == null) return null;
    if (remaining <= 0) return DateTime.now();
    final fetchedAt = _cropsCache.fetchedAt;
    if (fetchedAt == null) return null;
    return fetchedAt.add(Duration(seconds: remaining));
  }

  /// 下一批成熟作物（remainingTime 最小的未成熟且非空地）；无则 null。
  /// 与 [nextMatureIn] / [nextMatureAt] 同源，供收获概览卡取「作物名 + 生长进度」。
  Crop? get nextMatureCrop {
    final pending =
        crops?.crops.where((c) => !c.isEmpty && !c.mature).toList() ??
        const [];
    if (pending.isEmpty) return null;
    var min = 1 << 30;
    Crop? best;
    for (final c in pending) {
      if (c.remainingTime < min) {
        min = c.remainingTime;
        best = c;
      }
    }
    return best;
  }

  /// 是否存在 debuff（缺水/杂草/虫害）。
  bool get hasDebuff => crops?.crops.any((c) => c.hasDebuff) ?? false;

  /// 拉取当前地块（资源级 single-flight + 15s 最小间隔）。force 绕过间隔但不过 in-flight。
  Future<void> refreshCrops({bool force = false}) async {
    await _cropsCache.get(force: force);
    notifyListeners();
  }

  /// 拉取地块容量（5min TTL）。
  Future<void> refreshPlots({bool force = false}) async {
    await _plotsCache.get(force: force);
    notifyListeners();
  }

  /// 拉取仓库（5min TTL）。
  Future<void> refreshInventory({bool force = false}) async {
    await _inventoryCache.get(force: force);
    notifyListeners();
  }

  /// 拉取种子图鉴（24h TTL）。失败不阻塞主流程。
  Future<void> loadSeeds({bool force = false}) async {
    try {
      await _seedsCache.get(force: force);
      notifyListeners();
    } on Exception {
      // 忽略：种子列表缺失不影响收菜/务农核心。
    }
  }

  /// 拉取实时价格（回收价 + 单价，30min TTL，合并一次请求）。失败不阻塞主流程。
  Future<void> loadPrices({bool force = false}) async {
    try {
      await _pricesCache.get(force: force);
      notifyListeners();
    } on Exception {
      // 忽略：价格缺失时仓库页回落展示 inventory.recyclePrice，排行显示为空。
    }
  }

  /// 刷新只读数据（crops + plots + inventory）。默认 force=false（命中缓存即复用），
  /// 仅手动刷新按钮传 force=true 全量强制。
  Future<void> refresh({bool force = false}) async {
    _loading = true;
    notifyListeners();
    try {
      await refreshCrops(force: force);
      await refreshPlots(force: force);
      await refreshInventory(force: force);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void setAutomation(AutomationStatus s) {
    if (_automation == s) return;
    _automation = s;
    notifyListeners();
  }

  void setLastResult(String? r) {
    _lastResult = r;
    notifyListeners();
  }
}

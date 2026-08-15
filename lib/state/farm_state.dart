/// 农场数据与自动化运行状态。
library;

import 'package:flutter/foundation.dart';
import 'package:hyb_farm_desktop/api/farm_api.dart';
import 'package:hyb_farm_desktop/api/models.dart';
import 'package:hyb_farm_desktop/core/ranking.dart';

/// 自动化运行状态。
enum AutomationStatus { idle, running, paused }

class FarmState extends ChangeNotifier {
  FarmState(this._api);

  final FarmApi _api;

  CropsResponse? _crops;
  FarmPlots? _plots;
  List<InventoryItem> _inventory = const [];
  List<Seed> _seeds = const [];
  List<RecyclePrice> _recyclePrices = const [];
  Map<String, int> _unitPrices = const {};

  AutomationStatus _automation = AutomationStatus.idle;
  AutomationStatus get automation => _automation;

  bool _loading = false;
  bool get loading => _loading;

  String? _lastResult;
  String? get lastResult => _lastResult;

  /// 最近一次成功拉取 crops 的时刻，用于把剩余秒数换算成绝对时刻。
  DateTime? _fetchedAt;

  CropsResponse? get crops => _crops;
  FarmPlots? get plots => _plots;
  List<InventoryItem> get inventory => _inventory;
  List<Seed> get seeds => _seeds;
  List<RecyclePrice> get recyclePrices => _recyclePrices;

  /// 实时单价（seedId → 原始整数），收益排行数据源。
  Map<String, int> get unitPrices => _unitPrices;

  /// 收益排行（按每小时收益降序）。
  List<RankingRow> get ranking => buildRanking(_seeds, _unitPrices);

  /// 实时回收价：seedId → 原始整数价格。
  Map<String, int> get recyclePriceBySeedId => {
    for (final p in _recyclePrices) p.seedId: p.recyclePriceInt,
  };

  /// 可收数量（已成熟且非空地）。
  int get matureCount =>
      _crops?.crops.where((c) => c.mature && !c.isEmpty).length ?? 0;

  /// 下一成熟倒计时（秒）；已成熟返回 0，无未成熟作物返回 null。
  int? get nextMatureIn {
    final pending =
        _crops?.crops.where((c) => !c.isEmpty && !c.mature).toList() ??
        const [];
    if (pending.isEmpty) return null;
    var min = 1 << 30;
    for (final c in pending) {
      if (c.remainingTime < min) min = c.remainingTime;
    }
    return min;
  }

  /// 空闲地块数量。
  int get freeSlots => _crops?.freeSlots ?? (_plots?.freeSlots ?? 0);

  /// 仓库作物总数。
  int get inventoryTotal => _inventory.fold(0, (sum, i) => sum + i.quantity);

  /// 仓库作物总价值（原始整数，展示需除以 kPriceDivisor）。
  int get inventoryTotalValue =>
      _inventory.fold(0, (sum, i) => sum + i.quantity * i.recyclePriceInt);

  /// 下一批作物成熟的绝对时刻（据此可逐秒递减倒计时）；无未成熟作物返回 null。
  DateTime? get nextMatureAt {
    final remaining = nextMatureIn;
    if (remaining == null) return null;
    if (remaining <= 0) return DateTime.now();
    final fetchedAt = _fetchedAt;
    if (fetchedAt == null) return null;
    return fetchedAt.add(Duration(seconds: remaining));
  }

  /// 下一批成熟作物（remainingTime 最小的未成熟且非空地）；无则 null。
  /// 与 [nextMatureIn] / [nextMatureAt] 同源，供收获概览卡取「作物名 + 生长进度」。
  Crop? get nextMatureCrop {
    final pending =
        _crops?.crops.where((c) => !c.isEmpty && !c.mature).toList() ??
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
  bool get hasDebuff => _crops?.crops.any((c) => c.hasDebuff) ?? false;

  /// 刷新只读数据（crops + plots + inventory）。
  Future<void> refresh() async {
    _loading = true;
    notifyListeners();
    try {
      final crops = await _api.fetchCrops();
      final plots = await _api.fetchPlots();
      final inventory = await _api.fetchInventory();
      _crops = crops;
      _plots = plots;
      _inventory = inventory;
      _fetchedAt = DateTime.now();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 加载种子图鉴（补种种子下拉用），失败不阻塞主流程。
  Future<void> loadSeeds() async {
    try {
      _seeds = await _api.fetchSeeds();
      notifyListeners();
    } on Exception {
      // 忽略：种子列表缺失不影响收菜/务农核心。
    }
  }

  /// 加载实时回收价（仓库页展示用），失败不阻塞主流程。
  Future<void> fetchRecyclePrices() async {
    try {
      _recyclePrices = await _api.fetchRecyclePrices();
      notifyListeners();
    } on Exception {
      // 忽略：回收价缺失时仓库页回落展示 inventory.recyclePrice。
    }
  }

  /// 加载实时单价映射（收益排行用），失败不阻塞主流程。
  Future<void> loadUnitPrices() async {
    try {
      _unitPrices = await _api.fetchUnitPrices();
      notifyListeners();
    } on Exception {
      // 忽略：单价缺失时收益排行显示为空。
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

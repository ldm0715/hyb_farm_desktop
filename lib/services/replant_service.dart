/// 补种服务：按配置种子与库存/空地情况批量种植。
library;

import 'package:hyb_farm_desktop/api/farm_api.dart';
import 'package:hyb_farm_desktop/api/models.dart';

class ReplantService {
  ReplantService({required FarmApi api}) : _api = api;

  final FarmApi _api;

  /// 尝试补种 [seedId]，返回实际种植数量；失败或无空地/库存时返回 0。
  /// 自动补种：按「min(库存, 空地)」补满。
  Future<int> replant(String seedId) async {
    if (seedId.isEmpty) return 0;

    final plots = await _api.fetchPlots();
    final crops = await _api.fetchCrops();
    final planted = crops.crops.where((c) => !c.isEmpty).length;
    final free = plots.totalSlots - planted;
    if (free <= 0) return 0;

    final inventory = await _api.fetchInventory();
    final item = _find(inventory, seedId);
    if (item == null || item.quantity <= 0) return 0;

    return _plant(seedId, item.quantity < free ? item.quantity : free);
  }

  /// 手动种植指定数量，clamp 到空地与库存；返回实际种植数量，无空地/库存时返回 0。
  Future<int> plant(String seedId, int quantity) async {
    if (seedId.isEmpty || quantity <= 0) return 0;

    final plots = await _api.fetchPlots();
    final crops = await _api.fetchCrops();
    final planted = crops.crops.where((c) => !c.isEmpty).length;
    final free = plots.totalSlots - planted;
    if (free <= 0) return 0;

    final inventory = await _api.fetchInventory();
    final item = _find(inventory, seedId);
    if (item == null || item.quantity <= 0) return 0;

    var count = quantity;
    if (count > free) count = free;
    if (count > item.quantity) count = item.quantity;
    if (count <= 0) return 0;

    return _plant(seedId, count);
  }

  Future<int> _plant(String seedId, int count) async {
    final result = await _api.plantBatch(seedId, count);
    return result.plantedCount;
  }

  InventoryItem? _find(List<InventoryItem> items, String seedId) {
    for (final i in items) {
      if (i.seedId == seedId) return i;
    }
    return null;
  }
}

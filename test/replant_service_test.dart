/// ReplantService 手动种植测试：数量对空地/库存的 clamp。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:hyb_farm_desktop/api/api_client.dart';
import 'package:hyb_farm_desktop/api/farm_api.dart';
import 'package:hyb_farm_desktop/api/models.dart';
import 'package:hyb_farm_desktop/services/replant_service.dart';

class _FakeApi extends FarmApi {
  _FakeApi({this.totalSlots = 6, this.planted = 0, this.inventoryQty = 100})
    : super(ApiClient());

  int totalSlots;
  int planted;
  int inventoryQty;
  int plantCalls = 0;
  int lastPlantedCount = 0;

  @override
  Future<FarmPlots> fetchPlots() async =>
      FarmPlots(totalSlots: totalSlots, freeSlots: totalSlots - planted);

  @override
  Future<CropsResponse> fetchCrops() async {
    final crops = [
      for (var i = 0; i < planted; i++)
        Crop(
          id: 'c$i',
          seedId: 's',
          seedName: 'n',
          seedImage: 'img',
          plotIndex: i,
        ),
    ];
    return CropsResponse(crops: crops, maxSlots: totalSlots);
  }

  @override
  Future<List<InventoryItem>> fetchInventory() async => [
    InventoryItem(
      seedId: 'pumpkin',
      seedName: '南瓜',
      seedImage: '/p',
      quantity: inventoryQty,
      recyclePrice: '100',
    ),
  ];

  @override
  Future<PlantBatchResult> plantBatch(String seedId, int quantity) async {
    plantCalls++;
    lastPlantedCount = quantity;
    return PlantBatchResult(plantedCount: quantity);
  }
}

void main() {
  test('plant 数量 clamp 到空地', () async {
    final api = _FakeApi(totalSlots: 6, planted: 4, inventoryQty: 100);
    final svc = ReplantService(api: api);

    final count = await svc.plant('pumpkin', 10);

    expect(count, 2);
    expect(api.lastPlantedCount, 2);
  });

  test('plant 数量 clamp 到库存', () async {
    final api = _FakeApi(totalSlots: 6, planted: 0, inventoryQty: 3);
    final svc = ReplantService(api: api);

    final count = await svc.plant('pumpkin', 10);

    expect(count, 3);
  });

  test('无空地时 plant 返回 0 且不发请求', () async {
    final api = _FakeApi(totalSlots: 4, planted: 4, inventoryQty: 10);
    final svc = ReplantService(api: api);

    final count = await svc.plant('pumpkin', 2);

    expect(count, 0);
    expect(api.plantCalls, 0);
  });

  test('replant 自动补满 min(库存, 空地)', () async {
    final api = _FakeApi(totalSlots: 6, planted: 4, inventoryQty: 100);
    final svc = ReplantService(api: api);

    final count = await svc.replant('pumpkin');

    expect(count, 2);
  });
}

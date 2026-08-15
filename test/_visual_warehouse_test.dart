import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hyb_farm_desktop/api/api_client.dart';
import 'package:hyb_farm_desktop/api/farm_api.dart';
import 'package:hyb_farm_desktop/api/models.dart';
import 'package:hyb_farm_desktop/core/operation_coordinator.dart';
import 'package:hyb_farm_desktop/services/recycle_service.dart';
import 'package:hyb_farm_desktop/services/replant_service.dart';
import 'package:hyb_farm_desktop/state/farm_state.dart';
import 'package:hyb_farm_desktop/theme/farm_theme.dart';
import 'package:hyb_farm_desktop/ui/warehouse_page.dart';

class _FakeApi extends FarmApi {
  _FakeApi() : super(ApiClient());

  @override
  Future<CropsResponse> fetchCrops() async => const CropsResponse(crops: []);

  @override
  Future<FarmPlots> fetchPlots() async =>
      const FarmPlots(totalSlots: 0, freeSlots: 0);

  @override
  Future<List<InventoryItem>> fetchInventory() async => const [
    InventoryItem(
      seedId: 's1',
      seedName: '胡萝卜',
      seedImage: 'carrot',
      quantity: 10,
      recyclePrice: '1000000',
    ),
    InventoryItem(
      seedId: 's2',
      seedName: '白菜',
      seedImage: 'cabbage',
      quantity: 5,
      recyclePrice: '500000',
    ),
  ];

  @override
  Future<List<Seed>> fetchSeeds() async => const [];

  @override
  Future<List<RecyclePrice>> fetchRecyclePrices() async => const [];

  @override
  Future<Map<String, int>> fetchUnitPrices() async => const {};
}

void main() {
  testWidgets('render warehouse with items', (tester) async {
    await tester.binding.setSurfaceSize(const Size(560, 680));
    final api = _FakeApi();
    final farmState = FarmState(api);
    await farmState.refresh();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<FarmApi>.value(value: api),
          ChangeNotifierProvider<FarmState>.value(value: farmState),
          Provider<OperationCoordinator>.value(value: OperationCoordinator()),
          Provider<ReplantService>.value(value: ReplantService(api: api)),
          Provider<RecycleService>.value(
            value: RecycleService(
              api: api,
              coordinator: OperationCoordinator(),
            ),
          ),
        ],
        child: MaterialApp(
          theme: buildLightTheme(),
          home: const Scaffold(body: WarehousePage()),
        ),
      ),
    );
    await tester.pump();
    await expectLater(
      find.byType(WarehousePage),
      matchesGoldenFile('warehouse_items_diag.png'),
    );
  });
}

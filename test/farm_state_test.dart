/// FarmState 派生指标测试：成熟计数、倒计时、空闲地块、仓库价值、debuff。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:hyb_farm_desktop/api/api_client.dart';
import 'package:hyb_farm_desktop/api/farm_api.dart';
import 'package:hyb_farm_desktop/api/models.dart';
import 'package:hyb_farm_desktop/state/farm_state.dart';

/// 可配置的 FarmApi 假实现：覆盖只读接口，避免真实 HTTP。
class _FakeFarmApi extends FarmApi {
  _FakeFarmApi({
    this.crops = const CropsResponse(crops: []),
    this.plots = const FarmPlots(totalSlots: 0, freeSlots: 0),
    this.inventory = const [],
    this.recyclePrices = const [],
  }) : super(ApiClient());

  CropsResponse crops;
  FarmPlots plots;
  List<InventoryItem> inventory;
  List<RecyclePrice> recyclePrices;

  @override
  Future<CropsResponse> fetchCrops() async => crops;

  @override
  Future<FarmPlots> fetchPlots() async => plots;

  @override
  Future<List<InventoryItem>> fetchInventory() async => inventory;

  @override
  Future<List<RecyclePrice>> fetchRecyclePrices() async => recyclePrices;
}

Crop _crop({
  String id = 'c',
  int plotIndex = 0,
  int remainingTime = 0,
  bool isMature = false,
  List<String> conditions = const [],
}) => Crop(
  id: id,
  seedId: 's',
  seedName: 'n',
  seedImage: 'img',
  plotIndex: plotIndex,
  remainingTime: remainingTime,
  isMature: isMature,
  conditions: conditions,
);

void main() {
  test('refresh 后派生指标：成熟数、倒计时、空闲地块', () async {
    final api = _FakeFarmApi(
      crops: CropsResponse(
        crops: [
          _crop(id: 'a', plotIndex: 0, remainingTime: 300),
          _crop(id: 'b', plotIndex: 1, remainingTime: 100),
          _crop(id: 'c', plotIndex: 2, isMature: true),
        ],
        maxSlots: 6,
      ),
      plots: const FarmPlots(totalSlots: 6, freeSlots: 3),
    );
    final state = FarmState(api);

    await state.refresh();

    expect(state.matureCount, 1);
    expect(state.nextMatureIn, 100);
    expect(state.freeSlots, 3);
    expect(state.hasDebuff, isFalse);
  });

  test('nextMatureIn 无未成熟作物时返回 null（含全部成熟）', () async {
    final api = _FakeFarmApi(
      crops: CropsResponse(
        crops: [_crop(id: 'a', isMature: true)],
        maxSlots: 4,
      ),
    );
    final state = FarmState(api);

    await state.refresh();

    expect(state.matureCount, 1);
    expect(state.nextMatureIn, isNull);
    expect(state.nextMatureAt, isNull);
  });

  test('nextMatureAt = 抓取时刻 + 最小剩余秒数', () async {
    final api = _FakeFarmApi(
      crops: CropsResponse(
        crops: [_crop(id: 'a', remainingTime: 120)],
        maxSlots: 4,
      ),
    );
    final state = FarmState(api);

    await state.refresh();

    final remaining = state.nextMatureIn!;
    final at = state.nextMatureAt!;
    expect(at.difference(DateTime.now()).inSeconds, closeTo(remaining, 2));
  });

  test('hasDebuff 检测任一地块 debuff', () async {
    final api = _FakeFarmApi(
      crops: CropsResponse(
        crops: [
          _crop(id: 'a', plotIndex: 0),
          _crop(id: 'b', plotIndex: 1, conditions: const ['weed']),
        ],
        maxSlots: 4,
      ),
    );
    final state = FarmState(api);

    await state.refresh();

    expect(state.hasDebuff, isTrue);
  });

  test('freeSlots 优先 crops 派生值而非 plots', () async {
    final state = FarmState(
      _FakeFarmApi(
        crops: CropsResponse(crops: [_crop(id: 'a')], maxSlots: 6),
        plots: const FarmPlots(totalSlots: 6, freeSlots: 1),
      ),
    );
    await state.refresh();
    expect(state.freeSlots, 5); // crops：6 - 1 planted，而非 plots.freeSlots=1
  });

  test('仓库总数与总价值', () async {
    final api = _FakeFarmApi(
      inventory: [
        const InventoryItem(
          seedId: 'pumpkin',
          seedName: '南瓜',
          seedImage: '/p',
          quantity: 12,
          recyclePrice: '612581',
        ),
        const InventoryItem(
          seedId: 'corn',
          seedName: '玉米',
          seedImage: '/c',
          quantity: 0,
          recyclePrice: '300000',
        ),
        const InventoryItem(
          seedId: 'star',
          seedName: '杨桃',
          seedImage: '/s',
          quantity: 5,
          recyclePrice: '900000',
        ),
      ],
    );
    final state = FarmState(api);

    await state.refresh();

    expect(state.inventoryTotal, 17);
    expect(state.inventoryTotalValue, 12 * 612581 + 5 * 900000);
  });

  test('fetchRecyclePrices 缓存实时回收价并映射 seedId', () async {
    final api = _FakeFarmApi(
      recyclePrices: const [
        RecyclePrice(seedId: 'pumpkin', recyclePrice: '612581'),
        RecyclePrice(seedId: 'corn', recyclePrice: '300000'),
      ],
    );
    final state = FarmState(api);

    await state.fetchRecyclePrices();

    expect(state.recyclePrices.length, 2);
    expect(state.recyclePriceBySeedId['pumpkin'], 612581);
    expect(state.recyclePriceBySeedId['corn'], 300000);
  });
}

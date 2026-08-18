/// FarmState 派生指标测试：成熟计数、倒计时、空闲地块、仓库价值、debuff、
/// 价格趋势加载（自然日一次 / 失败同日不重试 / 刷新路径结构性隔离）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hyb_farm_desktop/api/api_client.dart';
import 'package:hyb_farm_desktop/api/farm_api.dart';
import 'package:hyb_farm_desktop/api/models.dart';
import 'package:hyb_farm_desktop/services/daily_summary_store.dart';
import 'package:hyb_farm_desktop/services/price_trend_store.dart';
import 'package:hyb_farm_desktop/state/farm_state.dart';

/// 可配置的 FarmApi 假实现：覆盖只读接口，避免真实 HTTP。
class _FakeFarmApi extends FarmApi {
  _FakeFarmApi({
    this.crops = const CropsResponse(crops: []),
    this.plots = const FarmPlots(totalSlots: 0, freeSlots: 0),
    this.inventory = const [],
    this.recyclePrices = const [],
    this.priceTrendsResult,
    this.dailySummaryResult,
  }) : super(ApiClient());

  CropsResponse crops;
  FarmPlots plots;
  List<InventoryItem> inventory;
  List<RecyclePrice> recyclePrices;

  PriceTrends? priceTrendsResult;
  bool failTrendFetch = false;
  int trendFetchCalls = 0;

  DailySummary? dailySummaryResult;
  bool failSummaryFetch = false;
  int summaryFetchCalls = 0;

  @override
  Future<CropsResponse> fetchCrops() async => crops;

  @override
  Future<FarmPlots> fetchPlots() async => plots;

  @override
  Future<List<InventoryItem>> fetchInventory() async => inventory;

  @override
  Future<FarmPrices> fetchPrices() async =>
      FarmPrices(recyclePrices: recyclePrices, unitPrices: const {});

  @override
  Future<PriceTrends> fetchPriceTrends() async {
    trendFetchCalls++;
    if (failTrendFetch) throw Exception('network');
    return priceTrendsResult ?? const PriceTrends();
  }

  @override
  Future<DailySummary> fetchDailySummary() async {
    summaryFetchCalls++;
    if (failSummaryFetch) throw Exception('network');
    return dailySummaryResult ?? const DailySummary(summary: DailySummaryData());
  }
}

/// recordAttempt 持久化失败的 Store：模拟 setString 失败场景（不真发网络请求）。
class _ThrowingTrendStore extends PriceTrendStore {
  _ThrowingTrendStore(super.prefs, super.key);

  @override
  Future<void> recordAttempt(CachedPriceTrendState s) async {
    throw Exception('persist failed');
  }
}

/// recordAttempt 持久化失败的日报 Store：模拟 setString 失败场景（不真发网络请求）。
class _ThrowingDailySummaryStore extends DailySummaryStore {
  _ThrowingDailySummaryStore(super.prefs, super.key);

  @override
  Future<void> recordAttempt(CachedDailySummaryState s) async {
    throw Exception('persist failed');
  }
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

  test('loadPrices 缓存实时回收价并映射 seedId', () async {
    final api = _FakeFarmApi(
      recyclePrices: const [
        RecyclePrice(seedId: 'pumpkin', recyclePrice: '612581'),
        RecyclePrice(seedId: 'corn', recyclePrice: '300000'),
      ],
    );
    final state = FarmState(api);

    await state.loadPrices();

    expect(state.recyclePrices.length, 2);
    expect(state.recyclePriceBySeedId['pumpkin'], 612581);
    expect(state.recyclePriceBySeedId['corn'], 300000);
  });

  group('价格趋势：服务器 UTC 自然日一天一次', () {
    late SharedPreferences prefs;
    late _FakeFarmApi api;
    late DateTime clock;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      // 服务器 8/18 04:00Z 刷新；本地时钟 8/18 12:00（测试以 UTC 表示本地）。
      api = _FakeFarmApi(
        priceTrendsResult: PriceTrends(
          bySeedId: {
            'corn': [
              TrendPoint(
                bucketStartedAt: DateTime.utc(2026, 8, 17),
                avgUnitPrice: '21659',
                sampleCount: 10,
              ),
              TrendPoint(
                bucketStartedAt: DateTime.utc(2026, 8, 16),
                avgUnitPrice: '21639',
                sampleCount: 8,
              ),
            ],
          },
          serverObservedAt: DateTime.utc(2026, 8, 18, 4),
          dataRefreshedAt: DateTime.utc(2026, 8, 18, 4),
        ),
      );
      clock = DateTime.utc(2026, 8, 18, 12);
    });

    PriceTrendStore makeStore() =>
        PriceTrendStore(prefs, PriceTrendStore.keyFor(null));

    FarmState makeState([PriceTrendStore? store]) => FarmState(
      api,
      now: () => clock,
      priceTrendStore: store ?? makeStore(),
    );

    test('懒加载一次；同日内再次 loadPriceTrend 不重拉', () async {
      final state = makeState();
      await state.loadPriceTrend();
      expect(api.trendFetchCalls, 1);
      expect(state.priceTrends.keys, contains('corn'));

      await state.loadPriceTrend();
      expect(api.trendFetchCalls, 1); // 当日上限 + 已缓存
    });

    test('请求失败后同日不重试（尝试也计入当天次数）', () async {
      api.failTrendFetch = true;
      final state = makeState();
      await state.loadPriceTrend();
      expect(api.trendFetchCalls, 1);

      await state.loadPriceTrend();
      expect(api.trendFetchCalls, 1); // 失败后当天不得再次请求
    });

    test('请求失败后重启（重建 State+Store 同 prefs）同日仍不重试', () async {
      api.failTrendFetch = true;
      final state = makeState();
      await state.loadPriceTrend();
      expect(api.trendFetchCalls, 1);

      // 「重启」：同一 prefs 新建 Store 与 FarmState。
      api.failTrendFetch = false;
      final restarted = makeState(); // 新 store（同 prefs）+ 新 state
      await restarted.loadPriceTrend();
      expect(api.trendFetchCalls, 1); // 持久化 attempt 阻止同日重试
    });

    test('重启同日不重拉但恢复已持久化趋势（仍显示徽标）', () async {
      final state = makeState();
      await state.loadPriceTrend();
      expect(api.trendFetchCalls, 1);
      expect(state.priceTrends.keys, contains('corn'));

      final restarted = makeState(); // 「重启」：同 prefs 新建 store + state
      await restarted.loadPriceTrend();
      expect(api.trendFetchCalls, 1); // 同日不重拉
      expect(restarted.priceTrends.keys, contains('corn')); // 持久化恢复
    });

    test('次日允许重新尝试', () async {
      api.failTrendFetch = true;
      final state = makeState();
      await state.loadPriceTrend();
      expect(api.trendFetchCalls, 1);

      api.failTrendFetch = false;
      clock = DateTime.utc(2026, 8, 19, 12); // 次日（服务器 8/19）
      await state.loadPriceTrend();
      expect(api.trendFetchCalls, 2);
      expect(state.priceTrends.keys, contains('corn'));
    });

    test('陈旧不能突破当日上限：同日内多次调用不重拉', () async {
      final state = makeState();
      await state.loadPriceTrend();
      expect(api.trendFetchCalls, 1);

      clock = DateTime.utc(2026, 8, 18, 23, 59); // 同日更晚
      await state.loadPriceTrend();
      expect(api.trendFetchCalls, 1);
    });

    test('客户端时间领先（快 2 天）：不产生重复请求循环', () async {
      clock = DateTime.utc(2026, 8, 20, 12); // 客户端 8/20，服务器 8/18
      final state = makeState();
      await state.loadPriceTrend();
      expect(api.trendFetchCalls, 1);

      clock = DateTime.utc(2026, 8, 20, 15);
      await state.loadPriceTrend();
      clock = DateTime.utc(2026, 8, 20, 20);
      await state.loadPriceTrend();
      expect(api.trendFetchCalls, 1); // 固定偏移被抵消，不循环
    });

    test('客户端时间回拨：不抛异常、不绕过当日门控', () async {
      final state = makeState();
      await state.loadPriceTrend();
      expect(api.trendFetchCalls, 1);

      clock = DateTime.utc(2026, 8, 18, 6); // 早于 localObservedAt
      await state.loadPriceTrend(); // 不抛异常
      expect(api.trendFetchCalls, 1);
    });

    test('刷新路径结构性隔离：loadPrices(force) + refresh(force) 不触发趋势加载', () async {
      final store = makeStore(); // 无任何记录 → 门控处于「理论上允许请求」态
      final state = FarmState(api, now: () => clock, priceTrendStore: store);
      expect(store.shouldAttempt(clock), isTrue); // 门控允许，而非被挡住

      await state.loadPrices(force: true);
      expect(api.trendFetchCalls, 0);

      await state.refresh(force: true);
      expect(api.trendFetchCalls, 0); // 证明刷新路径根本没调用趋势加载
    });

    test('实时价格响应不写 _priceTrends（趋势只由 loadPriceTrend 写入）', () async {
      final state = makeState();
      await state.loadPrices(force: true);
      expect(state.priceTrends, isEmpty);

      await state.loadPriceTrend();
      expect(state.priceTrends.keys, contains('corn'));
    });

    test('recordAttempt 持久化失败 → 不发网络请求', () async {
      final state = makeState(_ThrowingTrendStore(prefs, PriceTrendStore.keyFor(null)));
      await state.loadPriceTrend();
      expect(api.trendFetchCalls, 0);
    });
  });

  group('每日日报：服务器 UTC 自然日一天成功一次', () {
    late SharedPreferences prefs;
    late _FakeFarmApi api;
    late DateTime clock;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      // 服务器 8/18 生成的 8/17 日报；本地时钟 8/18 12:00。
      api = _FakeFarmApi(
        dailySummaryResult: const DailySummary(
          summary: DailySummaryData(
            date: '2026-08-17',
            stolen: StolenSummary(totalQuantity: 47, stealerCount: 1),
            helped: HelpedSummary(),
            hasContent: true,
          ),
          shouldAutoShow: false,
          periodDate: '2026-08-18',
        ),
      );
      clock = DateTime.utc(2026, 8, 18, 12);
    });

    DailySummaryStore makeStore() =>
        DailySummaryStore(prefs, DailySummaryStore.keyFor(null));

    FarmState makeState([DailySummaryStore? store]) => FarmState(
      api,
      now: () => clock,
      dailySummaryStore: store ?? makeStore(),
    );

    test('懒加载一次；同日再次 loadDailySummary 不重拉', () async {
      final state = makeState();
      await state.loadDailySummary();
      expect(api.summaryFetchCalls, 1);
      expect(state.dailySummary?.periodDate, '2026-08-18');

      await state.loadDailySummary();
      expect(api.summaryFetchCalls, 1); // 当天已成功 + 已缓存
    });

    test('失败后间隔内不重试、满间隔可重试', () async {
      api.failSummaryFetch = true;
      final state = makeState();
      await state.loadDailySummary();
      expect(api.summaryFetchCalls, 1);

      await state.loadDailySummary(); // 间隔内 → 不重试
      expect(api.summaryFetchCalls, 1);

      api.failSummaryFetch = false;
      clock = clock.add(const Duration(minutes: 31)); // 满 30min
      await state.loadDailySummary();
      expect(api.summaryFetchCalls, 2);
      expect(state.dailySummary?.periodDate, '2026-08-18');
    });

    test('成功同日重启（重建 State+Store 同 prefs）不重拉', () async {
      final state = makeState();
      await state.loadDailySummary();
      expect(api.summaryFetchCalls, 1);

      final restarted = makeState(); // 「重启」：同 prefs 新 store + state
      await restarted.loadDailySummary();
      expect(api.summaryFetchCalls, 1); // 持久化成功日阻止同日重拉
      expect(restarted.dailySummary?.periodDate, '2026-08-18'); // 恢复缓存
    });

    test('次日允许重新请求', () async {
      final state = makeState();
      await state.loadDailySummary();
      expect(api.summaryFetchCalls, 1);

      clock = DateTime.utc(2026, 8, 19, 12);
      await state.loadDailySummary();
      expect(api.summaryFetchCalls, 2);
    });

    test('刷新路径结构性隔离：loadPrices(force) + refresh(force) 不触发日报', () async {
      final store = makeStore(); // 无记录 → 门控允许
      final state = FarmState(api, now: () => clock, dailySummaryStore: store);
      expect(store.shouldAttempt(clock), isTrue);

      await state.loadPrices(force: true);
      expect(api.summaryFetchCalls, 0);

      await state.refresh(force: true);
      expect(api.summaryFetchCalls, 0);
    });

    test('recordAttempt 持久化失败 → 不发网络请求', () async {
      final state = makeState(
        _ThrowingDailySummaryStore(prefs, DailySummaryStore.keyFor(null)),
      );
      await state.loadDailySummary();
      expect(api.summaryFetchCalls, 0);
    });

    test('并发两次 loadDailySummary 只发一个请求', () async {
      final state = makeState();
      await Future.wait([state.loadDailySummary(), state.loadDailySummary()]);
      expect(api.summaryFetchCalls, 1);
    });

    test('periodDate/date 均缺失时不计为成功（满间隔后可重试）', () async {
      // 无效响应：periodDate 与 date 都为空。
      api.dailySummaryResult = const DailySummary(summary: DailySummaryData());
      final state = makeState();
      await state.loadDailySummary();
      expect(api.summaryFetchCalls, 1);
      expect(state.dailySummary, isNull); // 未计为成功

      // 满 30min 后重试，这次返回有效数据。
      api.dailySummaryResult = const DailySummary(
        summary: DailySummaryData(date: '2026-08-17', hasContent: true),
        periodDate: '2026-08-18',
      );
      clock = clock.add(const Duration(minutes: 31));
      await state.loadDailySummary();
      expect(api.summaryFetchCalls, 2);
      expect(state.dailySummary?.periodDate, '2026-08-18');
    });
  });
}

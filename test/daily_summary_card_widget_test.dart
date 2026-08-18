/// 每日日报卡的 widget 测试：摘要渲染、展开/收起、空态、无缓存加载态。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hyb_farm_desktop/api/api_client.dart';
import 'package:hyb_farm_desktop/api/farm_api.dart';
import 'package:hyb_farm_desktop/api/models.dart';
import 'package:hyb_farm_desktop/services/care_log.dart';
import 'package:hyb_farm_desktop/services/daily_summary_store.dart';
import 'package:hyb_farm_desktop/services/harvest_log.dart';
import 'package:hyb_farm_desktop/state/connection_state_store.dart';
import 'package:hyb_farm_desktop/state/farm_state.dart';
import 'package:hyb_farm_desktop/theme/farm_theme.dart';
import 'package:hyb_farm_desktop/ui/farm_page.dart';

/// 只读接口返回空数据的 FarmApi 假实现，避免 widget 测试真发 HTTP。
class _FakeApi extends FarmApi {
  _FakeApi({this.summary}) : super(ApiClient());

  final DailySummary? summary;

  @override
  Future<CropsResponse> fetchCrops() async => const CropsResponse(crops: []);

  @override
  Future<FarmPlots> fetchPlots() async =>
      const FarmPlots(totalSlots: 0, freeSlots: 0);

  @override
  Future<List<InventoryItem>> fetchInventory() async => const [];

  @override
  Future<List<Seed>> fetchSeeds() async => const [];

  @override
  Future<FarmPrices> fetchPrices() async =>
      const FarmPrices(recyclePrices: [], unitPrices: {});

  @override
  Future<PriceTrends> fetchPriceTrends() async => const PriceTrends();

  @override
  Future<DailySummary> fetchDailySummary() async =>
      summary ?? const DailySummary(summary: DailySummaryData());
}

Future<void> _pumpFarmPage(
  WidgetTester tester,
  FarmState farmState,
  FarmApi api,
) async {
  await tester.binding.setSurfaceSize(const Size(440, 900));
  final harvestLog = await HarvestLog.create();
  final careLog = await CareLog.create();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<FarmApi>.value(value: api),
        ChangeNotifierProvider<FarmState>.value(value: farmState),
        ChangeNotifierProvider<HarvestLog>.value(value: harvestLog),
        ChangeNotifierProvider<CareLog>.value(value: careLog),
        ChangeNotifierProvider<ConnectionStateStore>.value(
          value: ConnectionStateStore(),
        ),
      ],
      child: MaterialApp(
        theme: buildLightTheme(),
        home: const Scaffold(body: FarmPage()),
      ),
    ),
  );
  // 处理 loadDailySummary 的异步恢复/拉取 + notifyListeners 后的重建。
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('日报卡：加载后显示摘要，展开显示偷菜 TOP / 帮忙 TOP', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final api = _FakeApi(
      summary: const DailySummary(
        summary: DailySummaryData(
          date: '2026-08-17',
          stolen: StolenSummary(
            totalQuantity: 47,
            stealerCount: 1,
            topStealers: [StealerEntry(username: 'yanzexi', quantity: 47)],
          ),
          helped: HelpedSummary(
            helperCount: 2,
            topHelpers: [HelperEntry(username: '好友甲', quantity: 5)],
          ),
          hasContent: true,
        ),
        shouldAutoShow: false,
        periodDate: '2026-08-18',
      ),
    );
    final farmState = FarmState(
      api,
      dailySummaryStore: DailySummaryStore(prefs, DailySummaryStore.keyFor(null)),
    );

    await _pumpFarmPage(tester, farmState, api);

    // 收起态：标题 + 常驻摘要。
    expect(find.text('每日日报'), findsOneWidget);
    expect(find.text('8/17'), findsOneWidget);
    expect(find.textContaining('昨日被偷 47 份'), findsOneWidget);
    expect(find.textContaining('帮忙 2 人'), findsOneWidget);
    expect(find.text('偷菜 TOP'), findsNothing); // 收起不显示明细区

    // 展开 → 明细区出现，含 TOP 条目。
    await tester.ensureVisible(find.text('每日日报'));
    await tester.tap(find.text('每日日报'));
    await tester.pump();
    expect(find.text('偷菜 TOP'), findsOneWidget);
    expect(find.text('帮忙 TOP'), findsOneWidget);
    expect(find.text('yanzexi'), findsOneWidget);
    expect(find.text('好友甲'), findsOneWidget);

    // 卸载以取消 1 分钟轮询 Timer，避免 pending timer 报错。
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('日报卡：hasContent=false 显示「昨日无偷菜记录」', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final api = _FakeApi();
    final store = DailySummaryStore(prefs, DailySummaryStore.keyFor(null));
    // 预置当日成功缓存（hasContent=false），使 shouldAttempt 同日为 false（不发起拉取）。
    await store.recordSuccess(
      result: const DailySummary(
        summary: DailySummaryData(date: '2026-08-17', hasContent: false),
        periodDate: '2026-08-18',
      ),
      localReceivedAt: DateTime.now(),
    );
    final farmState = FarmState(api, dailySummaryStore: store);

    await _pumpFarmPage(tester, farmState, api);

    expect(find.text('每日日报'), findsOneWidget);
    expect(find.text('昨日无偷菜记录'), findsOneWidget);
    expect(find.text('偷菜 TOP'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });
}

/// RecycleService 测试：报价→回收的 expectedUnitPrice 传递、逐条失败隔离、消息格式。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:hyb_farm_desktop/api/api_client.dart';
import 'package:hyb_farm_desktop/api/farm_api.dart';
import 'package:hyb_farm_desktop/api/models.dart';
import 'package:hyb_farm_desktop/core/operation_coordinator.dart';
import 'package:hyb_farm_desktop/services/recycle_service.dart';

class _FakeApi extends FarmApi {
  _FakeApi() : super(ApiClient());

  /// seedId → 报价单价（原始整数）。
  Map<String, int> quotes = {};
  Set<String> failQuote = {};
  Set<String> failRecycle = {};
  final List<({String seedId, int quantity, String expectedUnitPrice})>
  recycleArgs = [];

  @override
  Future<RecycleQuote> recycleQuote(String seedId, int quantity) async {
    if (failQuote.contains(seedId)) {
      throw const ApiBusinessException(1, '报价失败');
    }
    final unit = quotes[seedId] ?? 500000;
    return RecycleQuote(
      seedId: seedId,
      quantity: quantity,
      unitPrice: '$unit',
      totalQuota: '${unit * quantity}',
    );
  }

  @override
  Future<RecycleResult> recycle(
    String seedId,
    int quantity,
    String expectedUnitPrice,
  ) async {
    recycleArgs.add((
      seedId: seedId,
      quantity: quantity,
      expectedUnitPrice: expectedUnitPrice,
    ));
    if (failRecycle.contains(seedId)) {
      throw const ApiBusinessException(2, '滑点超限');
    }
    final unit = int.parse(expectedUnitPrice);
    return RecycleResult(
      seedId: seedId,
      quantity: quantity,
      unitPrice: expectedUnitPrice,
      totalQuota: '${unit * quantity}',
    );
  }
}

void main() {
  test('sell 以报价 unitPrice 作为 expectedUnitPrice 回收', () async {
    final api = _FakeApi()..quotes = {'pumpkin': 612581};
    final svc = RecycleService(api: api, coordinator: OperationCoordinator());

    final r = await svc.sell('pumpkin', 2);

    expect(r.totalQuotaInt, 612581 * 2);
    expect(api.recycleArgs.single.seedId, 'pumpkin');
    expect(api.recycleArgs.single.quantity, 2);
    expect(api.recycleArgs.single.expectedUnitPrice, '612581');
  });

  test('sellSelected 逐个请求且单条失败不阻断其余', () async {
    final api = _FakeApi()
      ..quotes = {'pumpkin': 612581, 'corn': 300000}
      ..failRecycle = {'corn'};
    final svc = RecycleService(api: api, coordinator: OperationCoordinator());

    final messages = await svc.sellSelected([
      (seedId: 'pumpkin', seedName: '南瓜', quantity: 2),
      (seedId: 'corn', seedName: '玉米', quantity: 3),
    ]);

    expect(api.recycleArgs.length, 2);
    expect(messages.length, 2);
    expect(messages.first, contains('南瓜'));
    expect(messages.last, contains('失败'));
  });

  test('sellSelected 消息格式：卖出N个X获得金额', () async {
    final api = _FakeApi()..quotes = {'pumpkin': 612581};
    final svc = RecycleService(api: api, coordinator: OperationCoordinator());

    final messages = await svc.sellSelected([
      (seedId: 'pumpkin', seedName: '南瓜', quantity: 2),
    ]);

    // 612581 * 2 / 500000 = 2.450324 → 固定 2 位 = 2.45
    expect(messages.single, '卖出2个南瓜获得\$2.45');
  });

  test('sellSelected 报价失败时记录失败消息，不抛出', () async {
    final api = _FakeApi()..failQuote = {'pumpkin'};
    final svc = RecycleService(api: api, coordinator: OperationCoordinator());

    final messages = await svc.sellSelected([
      (seedId: 'pumpkin', seedName: '南瓜', quantity: 2),
    ]);

    expect(api.recycleArgs, isEmpty);
    expect(messages.single, contains('失败'));
  });
}

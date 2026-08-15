/// 回收服务：报价→回收的滑点保护闭环，经 OperationCoordinator 与自动流程串行。
library;

import 'package:hyb_farm_desktop/api/api_client.dart';
import 'package:hyb_farm_desktop/api/farm_api.dart';
import 'package:hyb_farm_desktop/api/models.dart';
import 'package:hyb_farm_desktop/core/formatters.dart';
import 'package:hyb_farm_desktop/core/operation_coordinator.dart';

class RecycleService {
  RecycleService({
    required FarmApi api,
    required OperationCoordinator coordinator,
  }) : _api = api,
       _coordinator = coordinator;

  final FarmApi _api;
  final OperationCoordinator _coordinator;

  /// 卖出单个作物：先报价取最新 [unitPrice]，再以该价为 [expectedUnitPrice] 回收
  /// （滑点保护 300bps）。经协调器串行执行，避免与自动收菜叠加。
  Future<RecycleResult> sell(String seedId, int quantity) =>
      _coordinator.run(() async {
        final quote = await _api.recycleQuote(seedId, quantity);
        return _api.recycle(seedId, quantity, quote.unitPrice);
      });

  /// 逐个卖出多个作物（一次请求只能卖一种），返回结果消息行。
  /// 单条失败不阻断其余作物；认证失效向外抛出，由调用方切换到需登录态。
  Future<List<String>> sellSelected(
    List<({String seedId, String seedName, int quantity})> entries,
  ) async {
    final messages = <String>[];
    for (final e in entries) {
      if (e.quantity <= 0) continue;
      try {
        final r = await sell(e.seedId, e.quantity);
        messages.add(
          '卖出${r.quantity}个${e.seedName}获得${formatMoney(r.totalQuotaInt)}',
        );
      } on AuthExpiredException {
        rethrow;
      } on Exception catch (err) {
        messages.add('卖出${e.seedName}失败：$err');
      }
    }
    return messages;
  }
}

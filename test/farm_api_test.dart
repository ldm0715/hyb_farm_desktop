/// FarmApi 端点封装测试：验证各接口的响应解包位置（data 对象 / data 数组 / 外层字段）。
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyb_farm_desktop/api/api_client.dart';
import 'package:hyb_farm_desktop/api/farm_api.dart';

class _RouterAdapter implements HttpClientAdapter {
  _RouterAdapter(this.routes);

  final Map<String, String> routes;

  /// 记录每个路径最后收到的请求体，用于断言 POST body。
  final Map<String, Object?> bodies = {};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    bodies[options.path] = options.data;
    final body = routes[options.path] ?? '{}';
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

FarmApi _api(Map<String, String> routes) {
  final dio = Dio(BaseOptions(baseUrl: 'https://cdk.hybgzs.com'))
    ..httpClientAdapter = _RouterAdapter(routes);
  return FarmApi(ApiClient(dio: dio));
}

void main() {
  test('fetchCrops 用完整 map 解析（crops/maxSlots 混在外层）', () async {
    final api = _api({
      '/api/farm/crops':
          '{"success":true,"crops":[{"id":"a","seedId":"s","seedName":"n","seedImage":"i","plotIndex":0}],"maxSlots":6}',
    });
    final resp = await api.fetchCrops();
    expect(resp.crops.length, 1);
    expect(resp.totalSlots, 6);
  });

  test('fetchPlots 取 data 对象', () async {
    final api = _api({
      '/api/farm/plots':
          '{"success":true,"data":{"totalSlots":6,"freeSlots":3}}',
    });
    final plots = await api.fetchPlots();
    expect(plots.totalSlots, 6);
    expect(plots.freeSlots, 3);
  });

  test('fetchInventory 取 data 数组', () async {
    final api = _api({
      '/api/farm/inventory':
          '{"success":true,"data":[{"seedId":"p","seedName":"南瓜","seedImage":"/p","quantity":2,"recyclePrice":"100"}]}',
    });
    final items = await api.fetchInventory();
    expect(items.length, 1);
    expect(items.first.seedId, 'p');
    expect(items.first.quantity, 2);
  });

  test('fetchSeeds 取 data.seeds', () async {
    final api = _api({
      '/api/farm/codex/seeds':
          '{"success":true,"data":{"seeds":[{"id":"p","name":"南瓜","image":"/p","growthTime":7200}]}}',
    });
    final seeds = await api.fetchSeeds();
    expect(seeds.length, 1);
    expect(seeds.first.id, 'p');
    expect(seeds.first.growthTime, 7200);
  });

  test('careAll 读外层字段（processed/byKind）', () async {
    final api = _api({
      '/api/farm/care/all':
          '{"success":true,"processed":2,"skipped":1,"energySpent":10,"byKind":{"thirsty":2}}',
    });
    final result = await api.careAll();
    expect(result.processed, 2);
    expect(result.skipped, 1);
    expect(result.energySpent, 10);
    expect(result.byKind['thirsty'], 2);
  });

  test('plantBatch 取 data 对象', () async {
    final api = _api({
      '/api/farm/plant-batch':
          '{"success":true,"data":{"plantedCount":3,"totalCost":"500"}}',
    });
    final result = await api.plantBatch('p', 3);
    expect(result.plantedCount, 3);
    expect(result.totalCost, '500');
  });

  test('fetchPrices 合并 data[] 与 market.items[] 为一次请求派生两份', () async {
    final api = _api({
      '/api/farm/recycle/prices':
          '{"success":true,"data":[{"seedId":"a","recyclePrice":"612581"}],"market":{"items":[{"seedId":"b","unitPrice":"300000"},{"seedId":"a","unitPrice":"999999"}]}}',
    });
    final prices = await api.fetchPrices();
    // recyclePrices 取 data[]。
    expect(prices.recyclePrices.length, 1);
    expect(prices.recyclePrices.first.seedId, 'a');
    expect(prices.recyclePrices.first.recyclePriceInt, 612581);
    // unitPrices：market.items 覆盖 data 的同 seedId 值；data 直接价与 market 并存。
    expect(prices.unitPrices['a'], 999999);
    expect(prices.unitPrices['b'], 300000);
  });

  test('recycleQuote 取 data 对象', () async {
    final api = _api({
      '/api/farm/recycle/quote':
          '{"success":true,"data":{"seedId":"p","quantity":2,"unitPrice":"612581","totalQuota":"1225162","quotedAt":"2026-08-14T10:00:00Z"}}',
    });
    final q = await api.recycleQuote('p', 2);
    expect(q.seedId, 'p');
    expect(q.unitPrice, '612581');
    expect(q.totalQuota, '1225162');
  });

  test('recycle 请求体含 expectedUnitPrice 与 maxSlippageBps=300', () async {
    final adapter = _RouterAdapter({
      '/api/farm/recycle':
          '{"success":true,"data":{"seedId":"p","quantity":2,"unitPrice":"612581","totalQuota":"1225162","slippageBps":0}}',
    });
    final dio = Dio(BaseOptions(baseUrl: 'https://cdk.hybgzs.com'))
      ..httpClientAdapter = adapter;
    final api = FarmApi(ApiClient(dio: dio));

    final r = await api.recycle('p', 2, '612581');
    expect(r.totalQuotaInt, 1225162);

    final body = adapter.bodies['/api/farm/recycle'] as Map<String, dynamic>;
    expect(body['seedId'], 'p');
    expect(body['quantity'], 2);
    expect(body['expectedUnitPrice'], '612581');
    expect(body['maxSlippageBps'], 300);
  });

  test('fetchFriendsStealable 取 data.friends 数组', () async {
    final api = _api({
      '/api/farm/friends/stealable':
          '{"success":true,"data":{"friends":[{"id":"f1","username":"小明","avatar":"/a.png"},{"id":"f2","username":"小红"}]}}',
    });
    final friends = await api.fetchFriendsStealable();
    expect(friends.length, 2);
    expect(friends.first.id, 'f1');
    expect(friends.first.username, '小明');
    expect(friends.last.username, '小红');
  });

  test('fetchFriendsStealable 解析 stealable 摘要字段', () async {
    final api = _api({
      '/api/farm/friends/stealable':
          '{"success":true,"data":{"friends":[{"id":"f1","username":"小明","stealable":{"isStealable":true,"ripeCount":2,"stealableCount":5}}]}}',
    });
    final friends = await api.fetchFriendsStealable();
    expect(friends.single.isStealable, isTrue);
    expect(friends.single.ripeCount, 2);
    expect(friends.single.stealableCount, 5);
  });

  test('fetchFriendFarm 取 data 对象并按第一块地判定可偷', () async {
    final api = _api({
      '/api/farm/friends/f1':
          '{"success":true,"data":{"friend":{"id":"f1","username":"小明","avatar":"/a.png"},"crops":[{"id":"c","seedId":"p","seedName":"南瓜","seedImage":"/p","plotIndex":0,"remainingTime":0,"isMature":true}]}}',
    });
    final farm = await api.fetchFriendFarm('f1');
    expect(farm.username, '小明');
    expect(farm.isStealable, isTrue);
    expect(farm.firstCrop?.seedName, '南瓜');
  });

  test('fetchFriendFarm 第一块地未成熟时不可偷', () async {
    final api = _api({
      '/api/farm/friends/f1':
          '{"success":true,"data":{"friend":{"id":"f1","username":"小明"},"crops":[{"id":"c","seedId":"p","seedName":"南瓜","seedImage":"/p","plotIndex":0,"remainingTime":300,"isMature":false}]}}',
    });
    final farm = await api.fetchFriendFarm('f1');
    expect(farm.isStealable, isFalse);
    expect(farm.firstCrop?.remainingTime, 300);
  });

  test('stealFriend 取外层字段且请求体含 friendId', () async {
    final adapter = _RouterAdapter({
      '/api/farm/steal/friend-auto':
          '{"success":true,"message":"偷菜成功","stolenCrops":[{"seedId":"p","quantity":3}]}',
    });
    final dio = Dio(BaseOptions(baseUrl: 'https://cdk.hybgzs.com'))
      ..httpClientAdapter = adapter;
    final api = FarmApi(ApiClient(dio: dio));

    final result = await api.stealFriend('f1');
    expect(result.message, '偷菜成功');
    expect(result.totalStolen, 3);

    final body =
        adapter.bodies['/api/farm/steal/friend-auto'] as Map<String, dynamic>;
    expect(body['friendId'], 'f1');
  });

  test('fetchUserInfo 取 data.user 对象', () async {
    final api = _api({
      '/api/user/info':
          '{"success":true,"data":{"user":{"username":"Alice","avatar":"https://cdn.example.com/a.png"}}}',
    });
    final info = await api.fetchUserInfo();
    expect(info.username, 'Alice');
    expect(info.avatar, 'https://cdn.example.com/a.png');
  });
}

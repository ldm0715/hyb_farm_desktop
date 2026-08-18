/// HYB Farm 接口封装。
library;

import 'package:hyb_farm_desktop/api/api_client.dart';
import 'package:hyb_farm_desktop/api/models.dart';
import 'package:hyb_farm_desktop/core/constants.dart';

class FarmApi {
  FarmApi(this._client);

  final ApiClient _client;

  /// 当前地块。响应字段（crops/data/maxSlots）混在外层，用完整 map 解析。
  Future<CropsResponse> fetchCrops() async {
    final json = await _client.get('/api/farm/crops');
    return CropsResponse.fromJson(_asMap(json));
  }

  /// 农场地块容量。标准信封 `{ data: { totalSlots, freeSlots, ... } }`。
  Future<FarmPlots> fetchPlots() async {
    final json = await _client.get('/api/farm/plots');
    return FarmPlots.fromJson(_dataMap(_asMap(json)));
  }

  /// 我的仓库。标准信封 `{ data: [InventoryItem...] }`。
  Future<List<InventoryItem>> fetchInventory() async {
    final json = await _client.get('/api/farm/inventory');
    final list = json is List
        ? json
        : _asMap(json)['data'] as List? ?? const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(InventoryItem.fromJson)
        .toList();
  }

  /// 种子图鉴（补种种子下拉用）。`{ data: { seeds: [...] } }`。
  Future<List<Seed>> fetchSeeds() async {
    final json = await _client.get('/api/farm/codex/seeds');
    final map = _asMap(json);
    final dataMap = _dataMap(map);
    final raw = dataMap['seeds'] ?? map['seeds'] ?? const [];
    return (raw as List)
        .whereType<Map<String, dynamic>>()
        .map(Seed.fromJson)
        .toList();
  }

  /// 一键收菜。
  Future<void> harvestAll() async {
    await _client.post('/api/farm/harvest-all');
  }

  /// 批量种植。`{ data: { plantedCount, ... } }`。
  Future<PlantBatchResult> plantBatch(String seedId, int quantity) async {
    final json = await _client.post(
      '/api/farm/plant-batch',
      body: {'seedId': seedId, 'quantity': quantity},
    );
    return PlantBatchResult.fromJson(_dataMap(_asMap(json)));
  }

  /// 一键务农。`{ success, processed, skipped, energySpent, ... }` 字段在外层。
  Future<CareAllResult> careAll() async {
    final json = await _client.post('/api/farm/care/all');
    return CareAllResult.fromJson(_asMap(json));
  }

  /// 实时价格（一次请求派生两份）：`data[]`（recyclePrice）与 `market.items[]`
  /// （unitPrice）。原 fetchRecyclePrices 与 fetchUnitPrices 打同一 URL 同一参数，
  /// 合并为单次请求，避免仓库页与收益排行重复拉取。
  Future<FarmPrices> fetchPrices() async {
    final json = await _client.get(
      '/api/farm/recycle/prices',
      query: const {
        'includeTrend': '1',
        'granularity': 'day',
        'trendRange': '7',
      },
    );
    final map = _asMap(json);

    final direct = map['data'] is List
        ? map['data'] as List
        : const <dynamic>[];
    final recyclePrices = direct
        .whereType<Map<String, dynamic>>()
        .map(RecyclePrice.fromJson)
        .toList();

    final unitPrices = <String, int>{};
    for (final p in recyclePrices) {
      if (p.seedId.isNotEmpty && p.recyclePriceInt > 0) {
        unitPrices[p.seedId] = p.recyclePriceInt;
      }
    }

    final market = map['market'] is Map<String, dynamic>
        ? (map['market'] as Map<String, dynamic>)['items']
        : null;
    final items = market is List ? market : const <dynamic>[];
    for (final item in items.whereType<Map<String, dynamic>>()) {
      final m = MarketItem.fromJson(item);
      if (m.seedId.isNotEmpty && m.unitPriceInt > 0) {
        unitPrices[m.seedId] = m.unitPriceInt;
      }
    }

    return FarmPrices(
      recyclePrices: recyclePrices,
      unitPrices: unitPrices,
    );
  }

  /// 回收报价。`{ data: { seedId, quantity, unitPrice, totalQuota, quotedAt } }`。
  Future<RecycleQuote> recycleQuote(String seedId, int quantity) async {
    final json = await _client.post(
      '/api/farm/recycle/quote',
      body: {'seedId': seedId, 'quantity': quantity},
    );
    return RecycleQuote.fromJson(_dataMap(_asMap(json)));
  }

  /// 作物回收。滑点保护固定 300bps，`expectedUnitPrice` 来自报价接口 `unitPrice`。
  Future<RecycleResult> recycle(
    String seedId,
    int quantity,
    String expectedUnitPrice,
  ) async {
    final json = await _client.post(
      '/api/farm/recycle',
      body: {
        'seedId': seedId,
        'quantity': quantity,
        'expectedUnitPrice': expectedUnitPrice,
        'maxSlippageBps': kMaxSlippageBps,
      },
    );
    return RecycleResult.fromJson(_dataMap(_asMap(json)));
  }

  /// 可偷好友列表。`{ data: { friends: [...] } }`。
  Future<List<FriendSummary>> fetchFriendsStealable() async {
    final json = await _client.get('/api/farm/friends/stealable');
    final map = _asMap(json);
    final dataMap = _dataMap(map);
    final raw = dataMap['friends'] ?? map['friends'] ?? const [];
    return (raw as List)
        .whereType<Map<String, dynamic>>()
        .map(FriendSummary.fromJson)
        .toList();
  }

  /// 单个好友农场详情。`{ data: { friend, crops } }`，按第一块地判定可偷。
  Future<FriendFarm> fetchFriendFarm(String friendId) async {
    final json = await _client.get(
      '/api/farm/friends/${Uri.encodeComponent(friendId)}',
    );
    final map = _asMap(json);
    final data = _dataMap(map);
    final friend = data['friend'] is Map<String, dynamic>
        ? data['friend'] as Map<String, dynamic>
        : const <String, dynamic>{};

    final crops =
        (data['crops'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .map(Crop.fromJson)
            .toList() ??
        const <Crop>[];
    // 只看第一块地：优先 plotIndex == 0，否则 crops[0]。
    Crop? first;
    for (final c in crops) {
      if (c.plotIndex == 0) {
        first = c;
        break;
      }
    }
    first ??= crops.isEmpty ? null : crops.first;

    final firstCrop = first == null
        ? null
        : FriendFirstCrop(
            seedName: first.seedName.isNotEmpty ? first.seedName : '未知作物',
            seedImage: first.seedImage,
            maturesAt: first.maturesAt,
            remainingTime: first.remainingTime,
          );
    final isStealable =
        firstCrop != null &&
        (firstCrop.remainingTime <= 0 || (first?.isMature ?? false));

    return FriendFarm(
      id: friend['id'] as String? ?? friendId,
      username: friend['username'] as String? ?? '未知好友',
      avatar: friend['avatar'] as String? ?? '',
      isStealable: isStealable,
      firstCrop: firstCrop,
    );
  }

  /// 好友偷菜。`{ friendId }`，响应字段（message/stolenCrops）在外层。
  Future<StealResult> stealFriend(String friendId) async {
    final json = await _client.post(
      '/api/farm/steal/friend-auto',
      body: {'friendId': friendId},
    );
    return StealResult.fromJson(_asMap(json));
  }

  /// 当前用户信息。`{ data: { user: { username, avatar } } }`。
  Future<UserInfo> fetchUserInfo() async {
    final json = await _client.get('/api/user/info');
    final data = _dataMap(_asMap(json));
    final user = data['user'] is Map<String, dynamic>
        ? data['user'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return UserInfo.fromJson(user);
  }

  /// 账户统计（VIP / 余额）。`{ data: { walletBalance, vipInfo: { isVip } } }`。
  Future<DashboardStats> fetchDashboardStats() async {
    final json = await _client.get('/api/dashboard/stats');
    return DashboardStats.fromJson(_dataMap(_asMap(json)));
  }

  Map<String, dynamic> _asMap(dynamic v) =>
      v is Map<String, dynamic> ? v : const {};

  Map<String, dynamic> _dataMap(Map<String, dynamic> json) {
    final d = json['data'];
    return d is Map<String, dynamic> ? d : json;
  }
}

/// 实时价格合并结果：一份请求派生回收价列表与单价映射两份数据。
class FarmPrices {
  const FarmPrices({required this.recyclePrices, required this.unitPrices});

  final List<RecyclePrice> recyclePrices;
  final Map<String, int> unitPrices;
}

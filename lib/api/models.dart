/// API 响应与数据模型，基于 docs/api.md 的字段定义。
library;

import 'package:hyb_farm_desktop/core/constants.dart';

/// 业务失败时的 error 字段。
class ApiError {
  const ApiError({this.code, this.message});

  final int? code;
  final String? message;

  factory ApiError.fromJson(Map<String, dynamic> json) => ApiError(
    code: (json['code'] as num?)?.toInt(),
    message: json['message'] as String?,
  );
}

/// 作物地块。
class Crop {
  const Crop({
    required this.id,
    required this.seedId,
    required this.seedName,
    required this.seedImage,
    required this.plotIndex,
    this.plantedAt,
    this.maturesAt,
    this.isHarvested = false,
    this.isMature = false,
    this.remainingTime = 0,
    this.conditions = const [],
  });

  final String id;
  final String seedId;
  final String seedName;
  final String seedImage;
  final int plotIndex;
  final DateTime? plantedAt;
  final DateTime? maturesAt;
  final bool isHarvested;
  final bool isMature;
  final int remainingTime;

  /// debuff 类型列表（"thirsty" / "weed" / "pest"）。
  final List<String> conditions;

  /// 未种植的空地（接口未返回该地块数据）。
  bool get isEmpty => id.isEmpty;

  /// 是否已成熟（isMature 或剩余时间已耗尽）。
  bool get mature => isMature || remainingTime <= 0;

  /// 截至 [now] 是否已成熟。剩余秒数 [remainingTime] 是后端请求时刻的快照、
  /// 不随墙钟自减，到点收菜时仍可能是旧值；用绝对成熟时刻 [maturesAt] 兜底，
  /// 镜像油猴脚本 `getLiveCrop` 的实时成熟重算。
  bool matureAt(DateTime now) =>
      isMature ||
      remainingTime <= 0 ||
      (maturesAt != null && !maturesAt!.isAfter(now));

  /// 是否存在 debuff（缺水/杂草/虫害）。
  bool get hasDebuff => conditions.isNotEmpty;

  /// 生长进度 0~1（`plantedAt → maturesAt`）；数据不足返回 null。
  double? get growthProgress {
    final p = plantedAt;
    final m = maturesAt;
    if (p == null || m == null) return null;
    final total = m.difference(p).inSeconds;
    if (total <= 0) return null;
    final elapsed = DateTime.now().difference(p).inSeconds;
    return (elapsed / total).clamp(0.0, 1.0);
  }

  /// 图标完整地址。
  String get iconUrl => cropIconUrl(seedImage);

  factory Crop.fromJson(Map<String, dynamic> json) => Crop(
    id: json['id'] as String? ?? '',
    seedId: json['seedId'] as String? ?? '',
    seedName: json['seedName'] as String? ?? '',
    seedImage: json['seedImage'] as String? ?? '',
    plotIndex: (json['plotIndex'] as num?)?.toInt() ?? 0,
    plantedAt: _parseDate(json['plantedAt']),
    maturesAt: _parseDate(json['maturesAt']),
    isHarvested: json['isHarvested'] as bool? ?? false,
    isMature: json['isMature'] as bool? ?? false,
    remainingTime: (json['remainingTime'] as num?)?.toInt() ?? 0,
    conditions: _parseConditions(json['conditions']),
  );
}

/// 地块等级信息（maxSlots 缺失时的兜底来源）。
class PlotLevel {
  const PlotLevel({
    required this.plotIndex,
    required this.level,
    required this.theme,
  });

  final int plotIndex;
  final int level;
  final String theme;

  factory PlotLevel.fromJson(Map<String, dynamic> json) => PlotLevel(
    plotIndex: (json['plotIndex'] as num?)?.toInt() ?? 0,
    level: (json['level'] as num?)?.toInt() ?? 0,
    theme: json['theme'] as String? ?? '',
  );
}

/// 当前地块接口响应（crops 字段直接在外层，data 可能缺省）。
class CropsResponse {
  const CropsResponse({
    required this.crops,
    this.maxSlots,
    this.baseSlots,
    this.plotLevels = const [],
  });

  final List<Crop> crops;
  final int? maxSlots;
  final int? baseSlots;
  final List<PlotLevel> plotLevels;

  /// 地块总数：优先 maxSlots，其次按 plotLevels 最大 plotIndex+1 兜底。
  int get totalSlots {
    if (maxSlots != null && maxSlots! > 0) return maxSlots!;
    var maxIndex = -1;
    for (final p in plotLevels) {
      if (p.plotIndex > maxIndex) maxIndex = p.plotIndex;
    }
    return maxIndex + 1;
  }

  /// 已种植数量。
  int get plantedCount => crops.where((c) => !c.isEmpty).length;

  /// 空闲地块数量。
  int get freeSlots {
    final total = totalSlots;
    final planted = plantedCount;
    return total > planted ? total - planted : 0;
  }

  factory CropsResponse.fromJson(Map<String, dynamic> json) {
    final rawCrops =
        (json['crops'] as List?) ?? (json['data'] as List?) ?? const [];
    return CropsResponse(
      crops: rawCrops
          .whereType<Map<String, dynamic>>()
          .map(Crop.fromJson)
          .toList(),
      maxSlots: (json['maxSlots'] as num?)?.toInt(),
      baseSlots: (json['baseSlots'] as num?)?.toInt(),
      plotLevels:
          (json['plotLevels'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(PlotLevel.fromJson)
              .toList() ??
          const <PlotLevel>[],
    );
  }
}

/// 农场地块容量。
class FarmPlots {
  const FarmPlots({required this.totalSlots, required this.freeSlots});

  final int totalSlots;
  final int freeSlots;

  factory FarmPlots.fromJson(Map<String, dynamic> json) => FarmPlots(
    totalSlots: (json['totalSlots'] as num?)?.toInt() ?? 0,
    freeSlots: (json['freeSlots'] as num?)?.toInt() ?? 0,
  );
}

/// 仓库作物条目。
class InventoryItem {
  const InventoryItem({
    required this.seedId,
    required this.seedName,
    required this.seedImage,
    required this.quantity,
    this.recyclePrice = '0',
  });

  final String seedId;
  final String seedName;
  final String seedImage;
  final int quantity;
  final String recyclePrice;

  int get recyclePriceInt => int.tryParse(recyclePrice) ?? 0;
  String get iconUrl => cropIconUrl(seedImage);

  factory InventoryItem.fromJson(Map<String, dynamic> json) => InventoryItem(
    seedId: json['seedId'] as String? ?? '',
    seedName: json['seedName'] as String? ?? '',
    seedImage: json['seedImage'] as String? ?? '',
    quantity: (json['quantity'] as num?)?.toInt() ?? 0,
    recyclePrice: json['recyclePrice'] as String? ?? '0',
  );
}

/// 种子图鉴条目（补种种子下拉 + 收益排行用）。
class Seed {
  const Seed({
    required this.id,
    required this.name,
    required this.image,
    this.isVipOnly = false,
    this.growthTime = 0,
    this.harvestQuantity = 0,
  });

  final String id;
  final String name;
  final String image;
  final bool isVipOnly;
  final int growthTime;

  /// 单次成熟产量（收益排行用）。
  final int harvestQuantity;

  factory Seed.fromJson(Map<String, dynamic> json) => Seed(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    image: json['image'] as String? ?? '',
    isVipOnly: json['isVipOnly'] as bool? ?? false,
    growthTime: (json['growthTime'] as num?)?.toInt() ?? 0,
    harvestQuantity: (json['harvestQuantity'] as num?)?.toInt() ?? 0,
  );
}

/// 一键务农结果。
class CareAllResult {
  const CareAllResult({
    required this.processed,
    required this.skipped,
    required this.energySpent,
    this.byKind = const {},
  });

  final int processed;
  final int skipped;
  final int energySpent;

  /// 各类 debuff 处理数量（thirsty / weed / pest）。
  final Map<String, int> byKind;

  factory CareAllResult.fromJson(Map<String, dynamic> json) => CareAllResult(
    processed: (json['processed'] as num?)?.toInt() ?? 0,
    skipped: (json['skipped'] as num?)?.toInt() ?? 0,
    energySpent: (json['energySpent'] as num?)?.toInt() ?? 0,
    byKind: _parseByKind(json['byKind']),
  );
}

/// 批量种植结果。
class PlantBatchResult {
  const PlantBatchResult({required this.plantedCount, this.totalCost = '0'});

  final int plantedCount;
  final String totalCost;

  factory PlantBatchResult.fromJson(Map<String, dynamic> json) =>
      PlantBatchResult(
        plantedCount: (json['plantedCount'] as num?)?.toInt() ?? 0,
        totalCost: json['totalCost'] as String? ?? '0',
      );
}

/// 实时回收价格条目。
class RecyclePrice {
  const RecyclePrice({required this.seedId, this.recyclePrice = '0'});

  final String seedId;
  final String recyclePrice;

  int get recyclePriceInt => int.tryParse(recyclePrice) ?? 0;

  factory RecyclePrice.fromJson(Map<String, dynamic> json) => RecyclePrice(
    seedId: json['seedId'] as String? ?? '',
    recyclePrice: json['recyclePrice'] as String? ?? '0',
  );
}

/// 回收报价结果（卖出前取最新市场单价）。
class RecycleQuote {
  const RecycleQuote({
    required this.seedId,
    required this.quantity,
    this.unitPrice = '0',
    this.totalQuota = '0',
    this.quotedAt,
  });

  final String seedId;
  final int quantity;
  final String unitPrice;
  final String totalQuota;
  final DateTime? quotedAt;

  factory RecycleQuote.fromJson(Map<String, dynamic> json) => RecycleQuote(
    seedId: json['seedId'] as String? ?? '',
    quantity: (json['quantity'] as num?)?.toInt() ?? 0,
    unitPrice: json['unitPrice'] as String? ?? '0',
    totalQuota: json['totalQuota'] as String? ?? '0',
    quotedAt: _parseDate(json['quotedAt']),
  );
}

/// 作物回收结果。
class RecycleResult {
  const RecycleResult({
    required this.seedId,
    required this.quantity,
    this.unitPrice = '0',
    this.totalQuota = '0',
    this.slippageBps = 0,
  });

  final String seedId;
  final int quantity;
  final String unitPrice;
  final String totalQuota;
  final int slippageBps;

  /// 成交总额（原始整数，展示需除以 kPriceDivisor）。
  int get totalQuotaInt => int.tryParse(totalQuota) ?? 0;

  factory RecycleResult.fromJson(Map<String, dynamic> json) => RecycleResult(
    seedId: json['seedId'] as String? ?? '',
    quantity: (json['quantity'] as num?)?.toInt() ?? 0,
    unitPrice: json['unitPrice'] as String? ?? '0',
    totalQuota: json['totalQuota'] as String? ?? '0',
    slippageBps: (json['slippageBps'] as num?)?.toInt() ?? 0,
  );
}

/// 市场行情条目（`recycle/prices` 的 `market.items[]`，收益排行价格合并用）。
class MarketItem {
  const MarketItem({required this.seedId, this.unitPrice = '0'});

  final String seedId;
  final String unitPrice;

  int get unitPriceInt => int.tryParse(unitPrice) ?? 0;

  factory MarketItem.fromJson(Map<String, dynamic> json) => MarketItem(
    seedId: json['seedId'] as String? ?? json['id'] as String? ?? '',
    unitPrice: json['unitPrice'] as String? ?? '0',
  );
}

/// 可偷好友列表条目（`friends/stealable` 的基础信息）。
class FriendSummary {
  const FriendSummary({
    required this.id,
    required this.username,
    this.avatar = '',
    this.isStealable = false,
    this.ripeCount = 0,
    this.stealableCount = 0,
  });

  final String id;
  final String username;
  final String avatar;

  /// 列表接口的 stealable 摘要（仅预筛用，最终判定以详情第一块地为准）。
  final bool isStealable;
  final int ripeCount;
  final int stealableCount;

  factory FriendSummary.fromJson(Map<String, dynamic> json) {
    final stealable = json['stealable'];
    final s = stealable is Map<String, dynamic>
        ? stealable
        : const <String, dynamic>{};
    return FriendSummary(
      id: json['id'] as String? ?? '',
      username: json['username'] as String? ?? '未知好友',
      avatar: json['avatar'] as String? ?? '',
      isStealable: s['isStealable'] as bool? ?? false,
      ripeCount: (s['ripeCount'] as num?)?.toInt() ?? 0,
      stealableCount: (s['stealableCount'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 当前登录用户信息（`/api/user/info` 的 `data.user`）。
class UserInfo {
  const UserInfo({this.username = '', this.avatar = ''});

  final String username;
  final String avatar;

  factory UserInfo.fromJson(Map<String, dynamic> json) => UserInfo(
    username: json['username'] as String? ?? '',
    avatar: json['avatar'] as String? ?? '',
  );
}

/// 账户统计（`/api/dashboard/stats` 的 `data`）。
class DashboardStats {
  const DashboardStats({this.walletBalance = 0, this.isVip = false});

  /// 账户总余额（原始整数，展示时除以 [kPriceDivisor]）。
  final int walletBalance;

  /// 是否为 VIP（`data.vipInfo.isVip`）。
  final bool isVip;

  factory DashboardStats.fromJson(Map<String, dynamic> json) {
    final v = json['vipInfo'];
    final vip = v is Map<String, dynamic> ? v : const <String, dynamic>{};
    // vipInfo 的 vipType/endDate/remainingDays 暂无消费方，先不解析。
    return DashboardStats(
      walletBalance: (json['walletBalance'] as num?)?.toInt() ?? 0,
      isVip: vip['isVip'] as bool? ?? false,
    );
  }
}

/// 好友第一块地的摘要信息（偷菜判定只看第一块地）。
class FriendFirstCrop {
  const FriendFirstCrop({
    required this.seedName,
    required this.seedImage,
    this.maturesAt,
    this.remainingTime = 0,
  });

  final String seedName;
  final String seedImage;
  final DateTime? maturesAt;
  final int remainingTime;

  bool get isMature => remainingTime <= 0;
  String get iconUrl => cropIconUrl(seedImage);
}

/// 单个好友农场状态（由 `friends/{id}` 详情接口归一化）。
class FriendFarm {
  const FriendFarm({
    required this.id,
    required this.username,
    this.avatar = '',
    this.isStealable = false,
    this.firstCrop,
  });

  final String id;
  final String username;
  final String avatar;

  /// 第一块地是否可偷（isMature 或 remainingTime<=0）。
  final bool isStealable;
  final FriendFirstCrop? firstCrop;
}

/// 偷菜成功响应中的单个被盗作物。
class StolenCrop {
  const StolenCrop({required this.seedId, this.quantity = 0});

  final String seedId;
  final int quantity;

  factory StolenCrop.fromJson(Map<String, dynamic> json) => StolenCrop(
    seedId: json['seedId'] as String? ?? '',
    quantity: (json['quantity'] as num?)?.toInt() ?? 0,
  );
}

/// 偷菜响应（`steal/friend-auto` 字段在外层）。
class StealResult {
  const StealResult({
    this.message,
    this.stolenCrops = const [],
    this.victimId,
    this.watchdogTriggered = false,
    this.cropsReturned = 0,
    this.quotaPenalty,
  });

  final String? message;
  final List<StolenCrop> stolenCrops;
  final String? victimId;
  final bool watchdogTriggered;
  final int cropsReturned;
  final String? quotaPenalty;

  /// 被盗作物总数（无 message 时的汇总兜底）。
  int get totalStolen => stolenCrops.fold(0, (sum, c) => sum + c.quantity);

  /// 对齐脚本 formatStealSuccessMessage：优先接口 message，否则按数量汇总。
  String displayMessage(String farmName) {
    final msg = message;
    if (msg != null && msg.isNotEmpty) return '$farmName：$msg';
    return totalStolen > 0
        ? '$farmName：偷菜成功，获得 $totalStolen 个作物'
        : '$farmName：偷菜成功';
  }

  factory StealResult.fromJson(Map<String, dynamic> json) => StealResult(
    message: json['message'] as String?,
    stolenCrops:
        (json['stolenCrops'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .map(StolenCrop.fromJson)
            .toList() ??
        const <StolenCrop>[],
    victimId: json['victimId'] as String?,
    watchdogTriggered: json['watchdogTriggered'] as bool? ?? false,
    cropsReturned: (json['cropsReturned'] as num?)?.toInt() ?? 0,
    quotaPenalty: json['quotaPenalty'] as String?,
  );
}

DateTime? _parseDate(dynamic value) {
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}

List<String> _parseConditions(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map<String, dynamic>>()
      .map((e) => e['kind'] as String? ?? '')
      .where((e) => e.isNotEmpty)
      .toList();
}

Map<String, int> _parseByKind(dynamic value) {
  if (value is! Map) return const {};
  final map = <String, int>{};
  value.forEach((k, v) {
    if (v is num) map['$k'] = v.toInt();
  });
  return map;
}

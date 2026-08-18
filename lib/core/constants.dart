/// 全局常量与工具。
library;

/// HYB Farm 后端基础地址。
const String kBaseUrl = 'https://cdk.hybgzs.com';

/// 价格单位：接口价格整数除以该值得到展示金额。
const int kPriceDivisor = 500000;

/// 回收滑点保护：卖出时允许的最大滑点（基点，300 = 3%）。
const int kMaxSlippageBps = 300;

/// 请求超时时长。
const Duration kRequestTimeout = Duration(seconds: 15);

/// 收菜成功后延迟补种的等待时长。
const Duration kReplantDelay = Duration(seconds: 10);

/// 调度器兜底检查间隔（成熟 Timer 漏触发 / 系统休眠恢复 / 网络失败恢复）。
const Duration kHarvestFallbackInterval = Duration(minutes: 5);

/// 成熟到点后的触发延迟：仅补服务端时钟偏差，毫秒级，避免被偷菜。
const Duration kHarvestTriggerDelay = Duration(milliseconds: 500);

/// 资源缓存 TTL（值 + 时间戳，决定何时可复用缓存）。
const Duration kPlotsCacheTtl = Duration(minutes: 5);
const Duration kInventoryCacheTtl = Duration(minutes: 5);
const Duration kSeedsCacheTtl = Duration(hours: 24);
const Duration kPricesCacheTtl = Duration(minutes: 30);
const Duration kFriendsListCacheTtl = Duration(minutes: 5);

/// 价格趋势缓存陈旧阈值；请求频率仍由服务器 UTC 自然日门控（不是「24h 时间下限」）。
const Duration kPriceTrendStaleAfter = Duration(hours: 24);

/// 资源请求最小间隔（决定两次实际请求之间的最短间隔，失败也更新）。
const Duration kMinRequestInterval = Duration(seconds: 15);

/// 请求失败退避：指数 1min × 2^n，上限 30min。
const Duration kBackoffBaseDelay = Duration(minutes: 1);
const Duration kBackoffMaxDelay = Duration(minutes: 30);

/// 回前台距上次成功刷新超过此时长才强制刷新（保留阈值语义）。
const Duration kBackgroundResumeThreshold = Duration(minutes: 2);

/// 系统恢复（powerResume）事件的去抖窗口：短时间多条 resume 只保留一次。
const Duration kResumeDebounce = Duration(seconds: 2);

/// 恢复流程（recoverAndReschedule）的网络失败重试退避序列（含首试共 4 次）。
/// 仅 ApiNetworkException 重试；唤醒后 Wi-Fi 恢复可能超过数秒。
const List<Duration> kRecoveryRetryDelays = [
  Duration(seconds: 2),
  Duration(seconds: 5),
  Duration(seconds: 15),
];

/// 作物图标文件名后缀。
const String kCropIconSuffix = '_s4.png';

/// 偷菜接口全局冷却时长（所有好友共用）。
const Duration kStealCooldown = Duration(seconds: 5);

/// 好友列表分页大小。
const int kFriendsPageSize = 5;

/// 好友详情缓存时长（详情放大治理：可偷态只在成熟瞬间翻转一次）。
const Duration kFriendDetailCache = Duration(minutes: 2);

/// 应用版本号（展示于设置页「关于与数据」，需与 pubspec.yaml 的 version 手动同步）。
const String kAppVersion = '0.1.5';

/// 安装包下载时的响应超时兜底（覆盖 BaseOptions 的 15s；dio 5.11 中仅作用于响应头部，
/// 主要用于兜慢网络/慢 CDN 场景，不中断 body 流式读取）。
const Duration kUpdateDownloadTimeout = Duration(minutes: 10);

/// 安装包专用子目录名（位于 getApplicationSupportDirectory() 之下，杜绝误删无关文件）。
const String kUpdatesDirName = 'updates';

/// 拼接作物图标完整地址。
String cropIconUrl(String seedImage) => '$kBaseUrl$seedImage$kCropIconSuffix';

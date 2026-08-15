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

/// 调度器兜底检查间隔。
const Duration kFallbackPollInterval = Duration(seconds: 30);

/// 作物图标文件名后缀。
const String kCropIconSuffix = '_s4.png';

/// 偷菜接口全局冷却时长（所有好友共用）。
const Duration kStealCooldown = Duration(seconds: 5);

/// 好友列表分页大小。
const int kFriendsPageSize = 5;

/// 好友详情缓存时长。
const Duration kFriendDetailCache = Duration(seconds: 30);

/// 应用版本号（展示于设置页「关于与数据」，需与 pubspec.yaml 的 version 手动同步）。
const String kAppVersion = '0.1.0';

/// 拼接作物图标完整地址。
String cropIconUrl(String seedImage) => '$kBaseUrl$seedImage$kCropIconSuffix';

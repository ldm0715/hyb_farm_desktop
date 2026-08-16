/// 资源缓存：统一封装「值 + 时间戳 + TTL + 最小间隔 + in-flight 复用」。
///
/// 供 plots/inventory/seeds/prices/friends-list 等低频资源复用，避免多份重复逻辑。
/// 三种命中语义（分别对应单测断言）：
///  - in-flight 复用：请求尚未完成，并发调用复用同一 Future（force 也不能绕过）；
///  - TTL 命中：缓存仍新鲜（[fetchedAt] 在 [ttl] 内），非 force 直接返回缓存值；
///  - minInterval 命中：最近一次尝试已完成但窗口未到，非 force 不发新请求。
library;

/// 无旧缓存 + 首次请求失败后、在最小间隔内再次调用时抛出的受控异常。
///
/// 区别于静默返回空数据：此时没有可用缓存值，调用方应展示加载中/错误态，
/// 而不是把 null/空列表当作成功。
class ResourceThrottledException implements Exception {
  const ResourceThrottledException([this.message = '请求过于频繁，请稍后重试']);

  final String message;

  @override
  String toString() => message;
}

class ResourceCache<T> {
  ResourceCache({
    required this.ttl,
    required this.minInterval,
    required this.fetch,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// 缓存有效期：决定 [fetchedAt] 距现在多久内视为新鲜。
  final Duration ttl;

  /// 最小请求间隔：决定两次实际请求之间的最短间隔（失败也更新 [lastAttemptAt]）。
  final Duration minInterval;

  /// 真正发起网络请求的函数。
  final Future<T> Function() fetch;

  final DateTime Function() _now;

  /// 最近一次成功拉取的资源值；首次成功前为 null。
  T? value;

  /// 最近一次请求成功的时刻；**仅成功时更新**，决定 TTL（失败不得更新）。
  DateTime? fetchedAt;

  /// 最近一次实际发起请求的时刻；**每次请求都更新**（含失败），决定最小间隔。
  DateTime? lastAttemptAt;

  /// 正在进行的请求 Future；并发调用复用同一 Future（single-flight）。
  Future<T>? inFlight;

  /// 拉取资源。force 绕过 TTL 与最小间隔，但不绕过 in-flight。
  Future<T> get({bool force = false}) async {
    final existing = inFlight;
    if (existing != null) return existing;

    if (!force) {
      final now = _now();
      final fetched = fetchedAt;
      if (fetched != null && now.difference(fetched) < ttl) {
        return value as T; // TTL 命中：缓存仍新鲜。
      }
      final lastAttempt = lastAttemptAt;
      if (lastAttempt != null && now.difference(lastAttempt) < minInterval) {
        final cached = value;
        if (cached != null) return cached; // minInterval 命中：有旧缓存返回 stale。
        throw const ResourceThrottledException(); // 无旧缓存：明确报错，不伪装成功。
      }
    }

    final future = _load();
    inFlight = future;
    try {
      return await future;
    } finally {
      inFlight = null;
    }
  }

  Future<T> _load() async {
    lastAttemptAt = _now();
    try {
      final v = await fetch();
      value = v;
      fetchedAt = _now();
      return v;
    } catch (_) {
      // 失败只更新 lastAttemptAt（已在 fetch 前更新），保留旧 value、fetchedAt 不变。
      rethrow;
    }
  }

  /// 使缓存过期（等价于下次 get 带 force:true），写操作后强制刷新用。
  void invalidate() {
    fetchedAt = null;
  }
}

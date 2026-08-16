/// ResourceCache 单元测试：single-flight、三种命中语义、失败不标新鲜、
/// 无旧缓存 + 首次失败 + 间隔内重试抛受控异常。
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyb_farm_desktop/core/resource_cache.dart';

void main() {
  test('in-flight 复用：并发 get 只产生一次 fetch', () async {
    var fetchCalls = 0;
    final gate = Completer<String>();
    final cache = ResourceCache<String>(
      ttl: const Duration(minutes: 5),
      minInterval: const Duration(seconds: 15),
      fetch: () {
        fetchCalls++;
        return gate.future;
      },
    );

    final f1 = cache.get();
    final f2 = cache.get();
    // force 也不能绕过 in-flight。
    final f3 = cache.get(force: true);

    gate.complete('v');
    final values = await Future.wait([f1, f2, f3]);

    expect(values, ['v', 'v', 'v']);
    expect(fetchCalls, 1);
  });

  test('TTL 命中：新鲜缓存内非 force 不发新请求', () async {
    var fetchCalls = 0;
    var now = DateTime(2026, 8, 16, 12, 0, 0);
    final cache = ResourceCache<String>(
      ttl: const Duration(minutes: 5),
      minInterval: const Duration(seconds: 15),
      fetch: () async {
        fetchCalls++;
        return 'v1';
      },
      now: () => now,
    );

    expect(await cache.get(), 'v1');
    now = now.add(const Duration(minutes: 4));
    expect(await cache.get(), 'v1');
    expect(fetchCalls, 1);
  });

  test('minInterval 命中：ttl 过期但间隔内，返回 stale 缓存', () async {
    var fetchCalls = 0;
    var now = DateTime(2026, 8, 16, 12, 0, 0);
    final cache = ResourceCache<String>(
      ttl: Duration.zero, // 无 TTL，靠 minInterval 控频。
      minInterval: const Duration(seconds: 15),
      fetch: () async {
        fetchCalls++;
        return 'v1';
      },
      now: () => now,
    );

    expect(await cache.get(), 'v1');
    now = now.add(const Duration(seconds: 10));
    expect(await cache.get(), 'v1'); // 命中 minInterval，返回 stale。
    expect(fetchCalls, 1);
  });

  test('minInterval 过后重新 fetch', () async {
    var fetchCalls = 0;
    var now = DateTime(2026, 8, 16, 12, 0, 0);
    final cache = ResourceCache<String>(
      ttl: Duration.zero,
      minInterval: const Duration(seconds: 15),
      fetch: () async {
        fetchCalls++;
        return 'v$fetchCalls';
      },
      now: () => now,
    );

    expect(await cache.get(), 'v1');
    now = now.add(const Duration(seconds: 16));
    expect(await cache.get(), 'v2');
    expect(fetchCalls, 2);
  });

  test('force 绕过 TTL 与 minInterval', () async {
    var fetchCalls = 0;
    var now = DateTime(2026, 8, 16, 12, 0, 0);
    final cache = ResourceCache<String>(
      ttl: const Duration(minutes: 5),
      minInterval: const Duration(seconds: 15),
      fetch: () async {
        fetchCalls++;
        return 'v$fetchCalls';
      },
      now: () => now,
    );

    expect(await cache.get(), 'v1');
    // 仍在 TTL 与 minInterval 内，但 force 强制重拉。
    expect(await cache.get(force: true), 'v2');
    expect(fetchCalls, 2);
  });

  test('失败不标新鲜：fetch 抛异常后 fetchedAt 不变、value 保留', () async {
    var now = DateTime(2026, 8, 16, 12, 0, 0);
    var fail = false;
    final cache = ResourceCache<String>(
      ttl: const Duration(minutes: 5),
      minInterval: const Duration(seconds: 15),
      fetch: () async {
        if (fail) throw Exception('boom');
        return 'v1';
      },
      now: () => now,
    );

    expect(await cache.get(), 'v1');
    final fetchedBefore = cache.fetchedAt;

    fail = true;
    // 过期后 fetch 失败：value 保留、fetchedAt 不变。
    now = now.add(const Duration(minutes: 6));
    await expectLater(cache.get(), throwsException);
    expect(cache.value, 'v1');
    expect(cache.fetchedAt, fetchedBefore);
    // 但 lastAttemptAt 已更新，间隔内再次调用返回 stale（有旧缓存）。
    expect(await cache.get(), 'v1');
  });

  test('无旧缓存 + 首次失败 + 间隔内重试抛 ResourceThrottledException', () async {
    var now = DateTime(2026, 8, 16, 12, 0, 0);
    final cache = ResourceCache<String>(
      ttl: const Duration(minutes: 5),
      minInterval: const Duration(seconds: 15),
      fetch: () async => throw Exception('boom'),
      now: () => now,
    );

    await expectLater(cache.get(), throwsException);
    // 无旧缓存（value == null），间隔内再次调用抛受控异常而非静默返回。
    expect(() => cache.get(), throwsA(isA<ResourceThrottledException>()));
  });
}

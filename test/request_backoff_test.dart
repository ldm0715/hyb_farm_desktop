/// RequestBackoff 单元测试：分作用域退避（网络全局 / 5xx 单资源 / 429 Retry-After）、
/// 成功只清对应作用域、指数退避上限 30min。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:hyb_farm_desktop/core/constants.dart';
import 'package:hyb_farm_desktop/core/farm_connection_state.dart';
import 'package:hyb_farm_desktop/core/request_backoff.dart';
import 'package:hyb_farm_desktop/core/request_failure_classifier.dart';

ClassificationResult _result(
  FarmConnectionState state, {
  String url = 'https://cdk.hybgzs.com/api/farm/crops',
  DateTime? retryAfter,
}) => ClassificationResult(
  state: state,
  reason: '',
  confidence: 1.0,
  diagnostics: ConnectionDiagnostics(url: url, retryAfter: retryAfter),
);

void main() {
  test('networkError 全局退避：所有资源都受限制', () {
    var now = DateTime(2026, 8, 16, 12, 0, 0);
    final backoff = RequestBackoff(now: () => now);

    backoff.record(_result(FarmConnectionState.networkError));
    expect(backoff.allowedAt('/api/farm/crops', now), isFalse);
    expect(backoff.allowedAt('/api/farm/plots', now), isFalse);
    expect(backoff.allowedAt('/api/farm/inventory', now), isFalse);

    // 退避到期后恢复。
    now = now.add(kBackoffBaseDelay);
    expect(backoff.allowedAt('/api/farm/crops', now), isTrue);
  });

  test('5xx 按 resource 键隔离：crops 5xx 不影响 plots', () {
    var now = DateTime(2026, 8, 16, 12, 0, 0);
    final backoff = RequestBackoff(now: () => now);

    backoff.record(
      _result(FarmConnectionState.serverError, url: 'https://cdk.hybgzs.com/api/farm/crops'),
    );
    expect(backoff.allowedAt('/api/farm/crops', now), isFalse);
    expect(backoff.allowedAt('/api/farm/plots', now), isTrue);
  });

  test('成功只清对应作用域：crops 成功清 crops 退避，不动 plots', () {
    var now = DateTime(2026, 8, 16, 12, 0, 0);
    final backoff = RequestBackoff(now: () => now);

    backoff.record(
      _result(FarmConnectionState.serverError, url: 'https://cdk.hybgzs.com/api/farm/crops'),
    );
    backoff.record(
      _result(FarmConnectionState.serverError, url: 'https://cdk.hybgzs.com/api/farm/plots'),
    );

    // crops 成功：只清 crops 退避。
    backoff.record(
      _result(FarmConnectionState.healthy, url: 'https://cdk.hybgzs.com/api/farm/crops'),
    );
    expect(backoff.allowedAt('/api/farm/crops', now), isTrue);
    expect(backoff.allowedAt('/api/farm/plots', now), isFalse);
  });

  test('网络成功清全局退避', () {
    var now = DateTime(2026, 8, 16, 12, 0, 0);
    final backoff = RequestBackoff(now: () => now);

    backoff.record(_result(FarmConnectionState.networkError));
    expect(backoff.allowedAt('/api/farm/crops', now), isFalse);

    backoff.record(_result(FarmConnectionState.healthy));
    expect(backoff.allowedAt('/api/farm/crops', now), isTrue);
  });

  test('429 采用 Retry-After 时刻，到期前受限', () {
    var now = DateTime(2026, 8, 16, 12, 0, 0);
    final backoff = RequestBackoff(now: () => now);
    final retryAt = now.add(const Duration(seconds: 30));

    backoff.record(
      _result(FarmConnectionState.rateLimited, retryAfter: retryAt),
    );
    expect(backoff.allowedAt('/api/farm/crops', now), isFalse);
    expect(backoff.retryIn('/api/farm/crops', now), const Duration(seconds: 30));

    now = now.add(const Duration(seconds: 30));
    expect(backoff.allowedAt('/api/farm/crops', now), isTrue);
  });

  test('指数退避：连续失败延迟翻倍至 30min 上限', () {
    var now = DateTime(2026, 8, 16, 12, 0, 0);
    final backoff = RequestBackoff(now: () => now);

    // 第 1 次：1min；第 2 次：2min；第 3 次：4min … 连续累积到 30min 上限。
    backoff.record(_result(FarmConnectionState.networkError));
    var retry = backoff.retryIn('/api/farm/crops', now);
    expect(retry, const Duration(minutes: 1));

    // 第 2 次失败把延迟翻倍。
    backoff.record(_result(FarmConnectionState.networkError));
    retry = backoff.retryIn('/api/farm/crops', now);
    expect(retry, const Duration(minutes: 2));

    // 连续失败到超过上限（2^5 = 32min > 30min，封顶 30min）。
    backoff.record(_result(FarmConnectionState.networkError));
    backoff.record(_result(FarmConnectionState.networkError));
    backoff.record(_result(FarmConnectionState.networkError));
    backoff.record(_result(FarmConnectionState.networkError));
    retry = backoff.retryIn('/api/farm/crops', now);
    expect(retry, kBackoffMaxDelay);
  });

  test('resourceKey 缺省时从诊断 URL 提取 path', () {
    var now = DateTime(2026, 8, 16, 12, 0, 0);
    final backoff = RequestBackoff(now: () => now);

    backoff.record(
      _result(
        FarmConnectionState.serverError,
        url: 'https://cdk.hybgzs.com/api/farm/codex/seeds',
      ),
    );
    // 未显式传 resourceKey，退避按 URL path 隔离。
    expect(backoff.allowedAt('/api/farm/codex/seeds', now), isFalse);
    expect(backoff.allowedAt('/api/farm/crops', now), isTrue);
  });
}

/// 请求失败分类器单元测试：覆盖 challenge / auth / rateLimit / server / network 优先级。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:hyb_farm_desktop/core/farm_connection_state.dart';
import 'package:hyb_farm_desktop/core/request_failure_classifier.dart';

void main() {
  test('1. 403 + cf-mitigated: challenge → challengeRequired', () {
    final r = classifyRequest(
      statusCode: 403,
      headers: {
        'cf-mitigated': ['challenge'],
      },
      body: 'blocked',
      contentType: 'text/html',
    );
    expect(r.state, FarmConnectionState.challengeRequired);
    expect(r.diagnostics.hasCfMitigated, isTrue);
  });

  test('2. 403 + body 含 /cdn-cgi/challenge-platform/ → challengeRequired', () {
    final r = classifyRequest(
      statusCode: 403,
      body: 'Redirecting to /cdn-cgi/challenge-platform/...',
      contentType: 'text/html',
    );
    expect(r.state, FarmConnectionState.challengeRequired);
    expect(r.diagnostics.bodyHits, contains('/cdn-cgi/challenge-platform/'));
  });

  test('3. 503 + body 含 Just a moment... + cf-ray → challengeRequired', () {
    final r = classifyRequest(
      statusCode: 503,
      headers: {
        'cf-ray': ['abc123'],
      },
      body: 'Just a moment... checking your browser',
      contentType: 'text/html',
    );
    expect(r.state, FarmConnectionState.challengeRequired);
  });

  test('4. 403 + server: cloudflare 但无其他信号 → 不判 challengeRequired', () {
    final r = classifyRequest(
      statusCode: 403,
      headers: {
        'server': ['cloudflare'],
      },
      body: 'Forbidden',
      contentType: 'application/json',
    );
    expect(r.state, isNot(FarmConnectionState.challengeRequired));
  });

  test('5. 401 → authRequired', () {
    final r = classifyRequest(statusCode: 401, body: '{}');
    expect(r.state, FarmConnectionState.authRequired);
  });

  test('6. 403 + JSON success:false 明确未登录 → authRequired', () {
    final r = classifyRequest(
      statusCode: 403,
      body: {
        'success': false,
        'error': {'code': 401, 'message': '未登录'},
      },
      contentType: 'application/json',
    );
    expect(r.state, FarmConnectionState.authRequired);
  });

  test('7. 429 + Retry-After: 120 → rateLimited 且解析 retryAfter', () {
    final now = DateTime(2026, 8, 15, 12, 0, 0);
    final r = classifyRequest(
      statusCode: 429,
      headers: {
        'retry-after': ['120'],
      },
      body: 'too many requests',
      now: now,
    );
    expect(r.state, FarmConnectionState.rateLimited);
    expect(r.diagnostics.retryAfter, now.add(const Duration(seconds: 120)));
  });

  test('8. statusCode 0（超时/连接错误）→ networkError', () {
    final r = classifyRequest(statusCode: 0, body: null);
    expect(r.state, FarmConnectionState.networkError);
  });

  test('9. 500 → serverError', () {
    final r = classifyRequest(statusCode: 500, body: '{}');
    expect(r.state, FarmConnectionState.serverError);
  });

  test('10. challenge 优先于同响应中的模糊登录关键词', () {
    final r = classifyRequest(
      statusCode: 403,
      headers: {
        'cf-mitigated': ['challenge'],
      },
      body: '登录 please complete /cdn-cgi/challenge-platform/ verification',
      contentType: 'text/html',
    );
    expect(r.state, FarmConnectionState.challengeRequired);
    expect(r.state, isNot(FarmConnectionState.authRequired));
  });

  test('403 + cf-ray 单独出现（无文本特征、非 html）→ 不判 challenge', () {
    final r = classifyRequest(
      statusCode: 403,
      headers: {
        'cf-ray': ['abc'],
      },
      body: 'forbidden',
      contentType: 'application/json',
    );
    expect(r.state, isNot(FarmConnectionState.challengeRequired));
  });

  test('sanitizeUrl 丢弃 query 参数', () {
    expect(
      sanitizeUrl('https://cdk.hybgzs.com/api/farm/crops?token=secret&a=1'),
      'https://cdk.hybgzs.com/api/farm/crops',
    );
  });
}

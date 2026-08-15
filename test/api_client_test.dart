/// ApiClient 测试：GET 去重、Cookie 注入与错误映射。
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyb_farm_desktop/api/api_client.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.onFetch);

  final Future<ResponseBody> Function(RequestOptions options) onFetch;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    calls++;
    return onFetch(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _jsonBody(String json, {int status = 200}) =>
    ResponseBody.fromString(
      json,
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

ApiClient _clientWith(_FakeAdapter adapter) => ApiClient(adapter: adapter);

void main() {
  test('GET 同 URL 并发去重：底层只请求一次', () async {
    final adapter = _FakeAdapter((_) async => _jsonBody('{"ok":true}'));
    final client = _clientWith(adapter);

    final results = await Future.wait([
      client.get('/api/farm/crops'),
      client.get('/api/farm/crops'),
    ]);

    expect(adapter.calls, 1);
    expect(results, [
      {'ok': true},
      {'ok': true},
    ]);
  });

  test('不同 URL 不去重', () async {
    final adapter = _FakeAdapter((_) async => _jsonBody('{}'));
    final client = _clientWith(adapter);

    await Future.wait([
      client.get('/api/farm/crops'),
      client.get('/api/farm/plots'),
    ]);

    expect(adapter.calls, 2);
  });

  test('setCookie 后请求附加 Cookie header', () async {
    String? captured;
    final adapter = _FakeAdapter((opts) async {
      captured = opts.headers['cookie'] as String?;
      return _jsonBody('{"ok":true}');
    });
    final client = _clientWith(adapter);

    client.setCookie('session=abc');
    await client.get('/api/farm/crops');

    expect(captured, 'session=abc');
  });

  test('401 抛 AuthExpiredException', () async {
    final adapter = _FakeAdapter((_) async => _jsonBody('{}', status: 401));
    final client = _clientWith(adapter);

    await expectLater(
      client.get('/api/farm/crops'),
      throwsA(isA<AuthExpiredException>()),
    );
  });

  test('403 无特征信号 → 不判失效，抛 ApiNetworkException', () async {
    final adapter = _FakeAdapter((_) async => _jsonBody('{}', status: 403));
    final client = _clientWith(adapter);

    await expectLater(
      client.get('/api/farm/crops'),
      throwsA(isA<ApiNetworkException>()),
    );
  });

  test('403 + Cloudflare challenge 强信号抛 ChallengeException', () async {
    final adapter = _FakeAdapter(
      (_) async => ResponseBody.fromString(
        'Please verify...',
        403,
        headers: {
          Headers.contentTypeHeader: ['text/html'],
          'cf-mitigated': ['challenge'],
        },
      ),
    );
    final client = _clientWith(adapter);

    await expectLater(
      client.get('/api/farm/crops'),
      throwsA(isA<ChallengeException>()),
    );
  });

  test('success:false 抛 ApiBusinessException（业务错误码不判失效）', () async {
    final adapter = _FakeAdapter(
      (_) async =>
          _jsonBody('{"success":false,"error":{"code":400,"message":"库存不足"}}'),
    );
    final client = _clientWith(adapter);

    await expectLater(
      client.get('/api/farm/crops'),
      throwsA(
        isA<ApiBusinessException>()
            .having((e) => e.code, 'code', 400)
            .having((e) => e.message, 'message', '库存不足'),
      ),
    );
  });

  test('5xx 抛 ApiNetworkException（临时错误不判失效）', () async {
    final adapter = _FakeAdapter((_) async => _jsonBody('{}', status: 500));
    final client = _clientWith(adapter);

    await expectLater(
      client.get('/api/farm/crops'),
      throwsA(isA<ApiNetworkException>()),
    );
  });

  test('连接错误映射为 ApiNetworkException', () async {
    final adapter = _FakeAdapter((opts) async {
      throw DioException(
        requestOptions: opts,
        type: DioExceptionType.connectionError,
        message: 'network down',
      );
    });
    final client = _clientWith(adapter);

    await expectLater(
      client.get('/api/farm/crops'),
      throwsA(isA<ApiNetworkException>()),
    );
  });
}

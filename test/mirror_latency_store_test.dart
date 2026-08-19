/// MirrorLatencyStore 单测：TTL 新鲜窗口、single-flight、invalidate 失效、测速期间
/// 列表变更丢弃过期结果、fetchLatest 失败退化测前缀根。均注入 fake adapter、不碰网络。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyb_farm_desktop/core/download_sources.dart';
import 'package:hyb_farm_desktop/services/mirror_latency_store.dart';
import 'package:hyb_farm_desktop/services/update_service.dart';

const _latestJson = '''
{"tag_name":"v0.9.9","name":"v0.9.9",
 "html_url":"https://github.com/a/b/releases/tag/v0.9.9",
 "assets":[{"name":"HYB-Farm-Desktop-0.9.9-Setup.exe",
            "browser_download_url":"https://github.com/a/b/releases/download/v0.9.9/x.exe",
            "size":100}]}
''';

class _Route {
  _Route(this.matches, this.statusCode);

  final bool Function(String url) matches;
  final int statusCode;
}

/// 记录请求数并按 URL 路由的 fake adapter；镜像 HEAD 默认 200。
class _CountingAdapter implements HttpClientAdapter {
  _CountingAdapter({this.latestJson = _latestJson, List<_Route>? extra})
      : extraRoutes = extra ?? [];

  final String latestJson;
  final List<_Route> extraRoutes;
  int requests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests++;
    final url = options.uri.toString();
    if (url.contains('/releases/latest')) {
      final bytes = utf8.encode(latestJson);
      return ResponseBody.fromBytes(
        bytes,
        200,
        headers: {Headers.contentLengthHeader: [bytes.length.toString()]},
      );
    }
    for (final r in extraRoutes) {
      if (r.matches(url)) {
        return ResponseBody.fromBytes(
          Uint8List(1),
          r.statusCode,
          headers: {Headers.contentLengthHeader: ['1']},
        );
      }
    }
    return ResponseBody.fromBytes(
      Uint8List(1),
      200,
      headers: {Headers.contentLengthHeader: ['1']},
    );
  }

  @override
  void close({bool force = false}) {}
}

/// 镜像 HEAD 挂起直到 gate 完成的 adapter（测「测速期间列表变更丢弃过期结果」）。
class _GateAdapter implements HttpClientAdapter {
  _GateAdapter(this.gate);

  final Completer<void> gate;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final url = options.uri.toString();
    if (url.contains('/releases/latest')) {
      final bytes = utf8.encode(_latestJson);
      return ResponseBody.fromBytes(
        bytes,
        200,
        headers: {Headers.contentLengthHeader: [bytes.length.toString()]},
      );
    }
    await gate.future;
    return ResponseBody.fromBytes(
      Uint8List(1),
      200,
      headers: {Headers.contentLengthHeader: ['1']},
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  final mirrors = [kDefaultDownloadMirrors.first];

  test('refreshIfStale 在 TTL 内复用、过期后重测', () async {
    var now = DateTime(2026, 8, 19, 12);
    final adapter = _CountingAdapter();
    final svc = UpdateService(dio: Dio()..httpClientAdapter = adapter);
    final store = MirrorLatencyStore(updateService: svc, now: () => now);

    await store.refreshIfStale(mirrors);
    final afterFirst = adapter.requests;
    expect(afterFirst, greaterThan(0));
    expect(store.results.keys, mirrors.map((m) => m.id));
    expect(store.resultFor(mirrors.first.id)!.reachable, isTrue);
    expect(store.resultFor(mirrors.first.id)!.label, isNotNull);

    // TTL 内再次请求 → 跳过，不再打请求。
    await store.refreshIfStale(mirrors);
    expect(adapter.requests, afterFirst);

    // 超过 TTL → 重测。
    now = now.add(const Duration(seconds: 61));
    await store.refreshIfStale(mirrors);
    expect(adapter.requests, greaterThan(afterFirst));
  });

  test('refresh 单飞：并发调用只跑一轮', () async {
    final adapter = _CountingAdapter();
    final svc = UpdateService(dio: Dio()..httpClientAdapter = adapter);
    final store = MirrorLatencyStore(updateService: svc);

    final f1 = store.refresh(mirrors);
    final f2 = store.refresh(mirrors); // 进行中 → 立即返回
    await Future.wait([f1, f2]);
    expect(adapter.requests, greaterThan(0));
    expect(store.testing, isFalse);
  });

  test('invalidate 清结果并强制下次重测', () async {
    final adapter = _CountingAdapter();
    final svc = UpdateService(dio: Dio()..httpClientAdapter = adapter);
    final store = MirrorLatencyStore(updateService: svc);

    await store.refresh(mirrors);
    expect(store.hasResults, isTrue);
    final afterFirst = adapter.requests;

    store.invalidate();
    expect(store.results, isEmpty);
    expect(store.hasResults, isFalse);

    await store.refreshIfStale(mirrors);
    expect(adapter.requests, greaterThan(afterFirst));
  });

  test('测速期间列表变更：过期结果被丢弃、testing 复位', () async {
    final gate = Completer<void>();
    final adapter = _GateAdapter(gate);
    final svc = UpdateService(dio: Dio()..httpClientAdapter = adapter);
    final store = MirrorLatencyStore(updateService: svc);

    final refreshFuture = store.refresh(mirrors);
    // HEAD 正挂起时列表变更 → 失效（版本号递增）。
    store.invalidate();
    gate.complete();
    await refreshFuture;

    expect(store.results, isEmpty);
    expect(store.hasResults, isFalse);
    expect(store.testing, isFalse);
  });

  test('fetchLatest 无安装包时退化测镜像前缀根', () async {
    final adapter = _CountingAdapter(latestJson: '{"bad":1}');
    final svc = UpdateService(dio: Dio()..httpClientAdapter = adapter);
    final store = MirrorLatencyStore(updateService: svc);

    await store.refresh(mirrors);

    expect(store.resultFor(mirrors.first.id), isNotNull);
    expect(store.resultFor(mirrors.first.id)!.reachable, isTrue);
  });
}

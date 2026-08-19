import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyb_farm_desktop/core/download_sources.dart';
import 'package:hyb_farm_desktop/services/update_service.dart';

/// 内联 fake adapter：返回固定字节与 content-length，供 download 测试、不碰网络。
class _BytesAdapter implements HttpClientAdapter {
  _BytesAdapter(this.bytes, {this.statusCode = 200});

  final List<int> bytes;
  final int statusCode;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromBytes(
      bytes is Uint8List ? bytes as Uint8List : Uint8List.fromList(bytes),
      statusCode,
      headers: {Headers.contentLengthHeader: [bytes.length.toString()]},
    );
  }

  @override
  void close({bool force = false}) {}
}

/// 按 URL 路由的 fake adapter：首个匹配的 route 生效，无匹配返回 404。
class _Route {
  _Route(this.matches, this.bytes, {this.statusCode = 200});

  final bool Function(String url) matches;
  final List<int> bytes;
  final int statusCode;
}

class _RoutingAdapter implements HttpClientAdapter {
  _RoutingAdapter(this.routes);

  final List<_Route> routes;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final url = options.uri.toString();
    for (final r in routes) {
      if (r.matches(url)) {
        return ResponseBody.fromBytes(
          r.bytes is Uint8List
              ? r.bytes as Uint8List
              : Uint8List.fromList(r.bytes),
          r.statusCode,
          headers: {Headers.contentLengthHeader: [r.bytes.length.toString()]},
        );
      }
    }
    return ResponseBody.fromBytes(
      Uint8List(0),
      404,
      headers: {Headers.contentLengthHeader: ['0']},
    );
  }

  @override
  void close({bool force = false}) {}
}

/// 任何请求都抛取消型 DioException 的 fake adapter（测「清单拉取遇取消立即 rethrow」）。
class _CancelAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw DioException(requestOptions: options, type: DioExceptionType.cancel);
  }

  @override
  void close({bool force = false}) {}
}

/// 生成带 MZ 头的字节（`_basicFileCheck` 要求 Windows 可执行头）。
Uint8List _mzBytes(int size) {
  final b = Uint8List(size);
  b[0] = 0x4D;
  b[1] = 0x5A;
  return b;
}

const _officialUrl =
    'https://github.com/ldm0715/hyb_farm_desktop/releases/download/v0.2.0/'
    'HYB-Farm-Desktop-0.2.0-Setup.exe';
const _checksumUrl =
    'https://github.com/ldm0715/hyb_farm_desktop/releases/download/v0.2.0/'
    'HYB-Farm-Desktop-0.2.0-SHA256.txt';
const _installerName = 'HYB-Farm-Desktop-0.2.0-Setup.exe';

void main() {
  test('UpdateInfo.fromJson 解析字段', () {
    final info = UpdateInfo.fromJson(const {
      'tag_name': 'v0.2.0',
      'name': 'v0.2.0',
      'body': '## 更新\n- 修复 bug',
      'html_url':
          'https://github.com/ldm0715/hyb_farm_desktop/releases/tag/v0.2.0',
      'published_at': '2026-08-17T10:00:00Z',
    });

    expect(info.tagName, 'v0.2.0');
    expect(info.version, '0.2.0');
    expect(info.body, contains('修复 bug'));
    expect(info.htmlUrl, isNotEmpty);
    expect(info.publishedAt, isNotNull);
    expect(info.publishedAt!.year, 2026);
  });

  test('缺失字段用空值兜底', () {
    final info = UpdateInfo.fromJson(const <String, dynamic>{});
    expect(info.tagName, '');
    expect(info.body, '');
    expect(info.htmlUrl, '');
    expect(info.publishedAt, isNull);
    expect(info.installerUrl, isNull);
    expect(info.installerName, isNull);
    expect(info.installerSize, isNull);
    expect(info.checksumUrl, isNull);
  });

  test('hasUpdate 用注入的 currentVersion 比较', () {
    final svc = UpdateService(currentVersion: '0.1.2');
    UpdateInfo info(String tag) => UpdateInfo.fromJson({'tag_name': tag});

    expect(svc.hasUpdate(info('v0.1.3')), isTrue);
    expect(svc.hasUpdate(info('v0.1.2')), isFalse);
    expect(svc.hasUpdate(info('v0.1.1')), isFalse);
  });

  test('fromJson 解析 Setup 安装包资产与 SHA256 清单', () {
    final info = UpdateInfo.fromJson(const {
      'tag_name': 'v0.2.0',
      'assets': [
        {
          'name': 'HYB-Farm-Desktop-0.2.0-SHA256.txt',
          'browser_download_url': 'https://example.com/SHA256.txt',
          'size': 200,
        },
        {
          'name': 'HYB-Farm-Desktop-0.2.0-Setup.exe',
          'browser_download_url': _officialUrl,
          'size': 12345678,
        },
      ],
    });

    expect(info.hasInstaller, isTrue);
    expect(info.installerUrl, contains('Setup.exe'));
    expect(info.installerName, 'HYB-Farm-Desktop-0.2.0-Setup.exe');
    expect(info.installerSize, 12345678);
    expect(info.checksumUrl, contains('SHA256.txt'));
  });

  test('fromJson 无 Setup 资产时 installer 字段为 null', () {
    final info = UpdateInfo.fromJson(const {
      'tag_name': 'v0.2.0',
      'assets': [
        {'name': 'a.txt', 'browser_download_url': 'https://x', 'size': 1},
      ],
    });

    expect(info.hasInstaller, isFalse);
    expect(info.installerUrl, isNull);
    expect(info.installerName, isNull);
    expect(info.installerSize, isNull);
  });

  test('updatesDirFor 拼接专用目录', () {
    expect(
      updatesDirFor('C:/support'),
      'C:/support${Platform.pathSeparator}updates',
    );
  });

  group('downloadInstaller', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('update_service_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    UpdateInfo infoWithAsset() => UpdateInfo.fromJson(const {
          'tag_name': 'v0.2.0',
          'assets': [
            {
              'name': _installerName,
              'browser_download_url': _officialUrl,
              'size': 4096,
            },
          ],
        });

    UpdateInfo infoWithChecksum() => UpdateInfo.fromJson(const {
          'tag_name': 'v0.2.0',
          'assets': [
            {
              'name': 'HYB-Farm-Desktop-0.2.0-SHA256.txt',
              'browser_download_url': _checksumUrl,
              'size': 200,
            },
            {
              'name': _installerName,
              'browser_download_url': _officialUrl,
              'size': 4096,
            },
          ],
        });

    test('下载到专用目录并 rename 成 .exe，无 .part 残留', () async {
      final bytes = _mzBytes(4096);
      final svc = UpdateService(
        dio: Dio()..httpClientAdapter = _BytesAdapter(bytes),
        updatesDir: tempDir.path,
      );

      final path = await svc.downloadInstaller(infoWithAsset());

      expect(path, endsWith(_installerName));
      final f = File(path);
      expect(f.existsSync(), isTrue);
      expect(f.lengthSync(), 4096);
      final files = tempDir.listSync().whereType<File>().toList();
      expect(files.where((e) => e.path.endsWith('.part')), isEmpty);
    });

    test('无安装包资产时抛 StateError', () {
      final svc = UpdateService(
        dio: Dio(),
        updatesDir: tempDir.path,
      );
      final info = UpdateInfo.fromJson({'tag_name': 'v0.2.0'});

      expect(svc.downloadInstaller(info), throwsStateError);
    });

    test('下载失败（404）后无 .part/.exe 残留', () async {
      final svc = UpdateService(
        dio: Dio()..httpClientAdapter = _BytesAdapter(const [], statusCode: 404),
        updatesDir: tempDir.path,
      );

      await expectLater(
        svc.downloadInstaller(infoWithAsset()),
        throwsA(isA<DioException>()),
      );
      expect(tempDir.listSync().whereType<File>(), isEmpty);
    });

    test('进度回调收到 received/total 且 total>0', () async {
      final bytes = _mzBytes(2048);
      final svc = UpdateService(
        dio: Dio()..httpClientAdapter = _BytesAdapter(bytes),
        updatesDir: tempDir.path,
      );

      int? gotReceived;
      int? gotTotal;
      await svc.downloadInstaller(
        infoWithAsset(),
        onProgress: (r, t) {
          gotReceived = r;
          gotTotal = t;
        },
      );

      expect(gotReceived, 2048);
      expect(gotTotal, greaterThan(0));
    });

    test('有清单且 SHA256 匹配则成功', () async {
      final bytes = _mzBytes(4096);
      final hex = sha256.convert(bytes).toString();
      final manifest = utf8.encode('$hex  $_installerName\n');
      final svc = UpdateService(
        dio: Dio()
          ..httpClientAdapter = _RoutingAdapter([
            _Route((u) => u == _checksumUrl, manifest),
            _Route((u) => u == _officialUrl, bytes),
          ]),
        updatesDir: tempDir.path,
      );

      final path = await svc.downloadInstaller(infoWithChecksum());

      expect(path, endsWith(_installerName));
      expect(File(path).lengthSync(), 4096);
      expect(
        tempDir
            .listSync()
            .whereType<File>()
            .where((e) => e.path.endsWith('.part')),
        isEmpty,
      );
    });

    test('有清单但 SHA256 不匹配则拒绝并清理 .part', () async {
      final bytes = _mzBytes(4096);
      final manifest = utf8.encode('${'0' * 64}  $_installerName\n');
      final svc = UpdateService(
        dio: Dio()
          ..httpClientAdapter = _RoutingAdapter([
            _Route((u) => u == _checksumUrl, manifest),
            _Route((u) => u == _officialUrl, bytes),
          ]),
        updatesDir: tempDir.path,
      );

      await expectLater(
        svc.downloadInstaller(infoWithChecksum()),
        throwsA(isA<FormatException>()),
      );
      expect(tempDir.listSync().whereType<File>(), isEmpty);
    });

    test('无校验清单且含第三方候选则拒绝下载', () async {
      final svc = UpdateService(
        dio: Dio(),
        updatesDir: tempDir.path,
      );

      await expectLater(
        svc.downloadInstaller(
          infoWithAsset(),
          source: kDownloadSourceAuto,
        ),
        throwsA(isA<FormatException>()),
      );
      expect(tempDir.listSync().whereType<File>(), isEmpty);
    });

    test('auto 模式：镜像失败后回退官方成功，onCandidate 记录来源顺序', () async {
      final bytes = _mzBytes(4096);
      final hex = sha256.convert(bytes).toString();
      final manifest = utf8.encode('$hex  $_installerName\n');
      final mirror = kDefaultDownloadMirrors.first;
      final mirrorUrl = '${mirror.prefix}$_officialUrl';
      final mirrorChecksumUrl = '${mirror.prefix}$_checksumUrl';
      final svc = UpdateService(
        dio: Dio()
          ..httpClientAdapter = _RoutingAdapter([
            // 镜像候选先同源拉清单（成功），再下载安装包（500）→ 回退官方。
            _Route((u) => u == mirrorChecksumUrl, manifest),
            _Route((u) => u == _checksumUrl, manifest),
            _Route((u) => u == mirrorUrl, const [], statusCode: 500),
            _Route((u) => u == _officialUrl, bytes),
          ]),
        updatesDir: tempDir.path,
      );
      final tried = <String>[];

      final path = await svc.downloadInstaller(
        infoWithChecksum(),
        source: kDownloadSourceAuto,
        mirrors: [mirror],
        onCandidate: (c) => tried.add(c.sourceId),
      );

      expect(path, endsWith(_installerName));
      expect(tried, ['gh-proxy', kDownloadSourceOfficial]);
      expect(
        tempDir
            .listSync()
            .whereType<File>()
            .where((e) => e.path.endsWith('.part')),
        isEmpty,
      );
    });

    test('指定镜像失败不自动回退官方', () async {
      final bytes = _mzBytes(4096);
      final hex = sha256.convert(bytes).toString();
      final manifest = utf8.encode('$hex  $_installerName\n');
      final mirror = kDefaultDownloadMirrors.first;
      final mirrorUrl = '${mirror.prefix}$_officialUrl';
      final mirrorChecksumUrl = '${mirror.prefix}$_checksumUrl';
      final svc = UpdateService(
        dio: Dio()
          ..httpClientAdapter = _RoutingAdapter([
            // 镜像同源拉清单成功，安装包下载失败 → 指定镜像不自动回退官方。
            _Route((u) => u == mirrorChecksumUrl, manifest),
            _Route((u) => u == mirrorUrl, const [], statusCode: 500),
            // 官方路由存在，但指定镜像模式下不应被尝试。
            _Route((u) => u == _officialUrl, bytes),
          ]),
        updatesDir: tempDir.path,
      );
      final tried = <String>[];

      await expectLater(
        svc.downloadInstaller(
          infoWithChecksum(),
          source: mirrorSource(mirror.id),
          mirrors: [mirror],
          onCandidate: (c) => tried.add(c.sourceId),
        ),
        throwsA(isA<DioException>()),
      );
      expect(tried, ['gh-proxy']);
      expect(tempDir.listSync().whereType<File>(), isEmpty);
    });

    test('镜像候选从同源镜像拉取校验清单并成功（不再碰官方 GitHub）', () async {
      final bytes = _mzBytes(4096);
      final hex = sha256.convert(bytes).toString();
      final manifest = utf8.encode('$hex  $_installerName\n');
      final mirror = kDefaultDownloadMirrors.first;
      final mirrorUrl = '${mirror.prefix}$_officialUrl';
      final mirrorChecksumUrl = '${mirror.prefix}$_checksumUrl';
      final svc = UpdateService(
        dio: Dio()
          ..httpClientAdapter = _RoutingAdapter([
            // 只路由镜像前缀地址；官方 _checksumUrl/_officialUrl 均无路由（404）。
            _Route((u) => u == mirrorChecksumUrl, manifest),
            _Route((u) => u == mirrorUrl, bytes),
          ]),
        updatesDir: tempDir.path,
      );
      final tried = <String>[];

      final path = await svc.downloadInstaller(
        infoWithChecksum(),
        source: mirrorSource(mirror.id),
        mirrors: [mirror],
        onCandidate: (c) => tried.add(c.sourceId),
      );

      expect(path, endsWith(_installerName));
      expect(File(path).lengthSync(), 4096);
      expect(tried, ['gh-proxy']);
      // 官方校验清单/官方安装包一次都没被请求（同源拉取）。
      expect(
        tempDir
            .listSync()
            .whereType<File>()
            .where((e) => e.path.endsWith('.part')),
        isEmpty,
      );
    });

    test('镜像候选校验清单获取失败则跳过该候选（auto 落到官方）', () async {
      final bytes = _mzBytes(4096);
      final hex = sha256.convert(bytes).toString();
      final manifest = utf8.encode('$hex  $_installerName\n');
      final mirror = kDefaultDownloadMirrors.first;
      final mirrorChecksumUrl = '${mirror.prefix}$_checksumUrl';
      final svc = UpdateService(
        dio: Dio()
          ..httpClientAdapter = _RoutingAdapter([
            // 镜像同源清单 500 → 该候选被跳过（不进入下载），官方正常走完。
            _Route((u) => u == mirrorChecksumUrl, const [], statusCode: 500),
            _Route((u) => u == _checksumUrl, manifest),
            _Route((u) => u == _officialUrl, bytes),
          ]),
        updatesDir: tempDir.path,
      );
      final tried = <String>[];

      final path = await svc.downloadInstaller(
        infoWithChecksum(),
        source: kDownloadSourceAuto,
        mirrors: [mirror],
        onCandidate: (c) => tried.add(c.sourceId),
      );

      expect(path, endsWith(_installerName));
      expect(tried, ['gh-proxy', kDownloadSourceOfficial]);
      expect(
        tempDir
            .listSync()
            .whereType<File>()
            .where((e) => e.path.endsWith('.part')),
        isEmpty,
      );
    });

    test('校验清单拉取遇取消立即 rethrow，不当作源失败继续', () async {
      final svc = UpdateService(
        dio: Dio()..httpClientAdapter = _CancelAdapter(),
        updatesDir: tempDir.path,
      );
      final tried = <String>[];

      await expectLater(
        svc.downloadInstaller(
          infoWithChecksum(),
          onCandidate: (c) => tried.add(c.sourceId),
        ),
        throwsA(
          isA<DioException>().having(
            (e) => e.type,
            'type',
            DioExceptionType.cancel,
          ),
        ),
      );
      // 取消不在候选上继续（tried 只记录过一次 onCandidate 前的来源）。
      expect(tried, [kDownloadSourceOfficial]);
      expect(tempDir.listSync().whereType<File>(), isEmpty);
    });

    test('预取消的 cancelToken 立即停止，不尝试任何来源', () async {
      final svc = UpdateService(
        dio: Dio(),
        updatesDir: tempDir.path,
      );
      final token = CancelToken()..cancel();
      final tried = <String>[];

      await expectLater(
        svc.downloadInstaller(
          infoWithAsset(),
          cancelToken: token,
          onCandidate: (c) => tried.add(c.sourceId),
        ),
        throwsA(
          isA<DioException>().having(
            (e) => e.type,
            'type',
            DioExceptionType.cancel,
          ),
        ),
      );
      expect(tried, isEmpty);
      expect(tempDir.listSync().whereType<File>(), isEmpty);
    });
  });

  group('testMirrorLatency', () {
    final mirror = kDefaultDownloadMirrors.first;
    const url = 'https://example.com/x.exe';

    test('2xx 可达且可用，记录延迟', () async {
      final svc = UpdateService(
        dio: Dio()..httpClientAdapter = _BytesAdapter(Uint8List(1), statusCode: 200),
      );
      final r = await svc.testMirrorLatency(mirror, installerUrl: url);
      expect(r.reachable, isTrue);
      expect(r.usable, isTrue);
      expect(r.latencyMs, isNotNull);
      expect(r.label, isNotNull);
      expect(r.label, contains('·'));
    });

    test('4xx 可达但不可用（不显示为优秀/良好）', () async {
      final svc = UpdateService(
        dio: Dio()..httpClientAdapter = _BytesAdapter(const [], statusCode: 404),
      );
      final r = await svc.testMirrorLatency(mirror, installerUrl: url);
      expect(r.reachable, isTrue);
      expect(r.usable, isFalse);
      expect(r.label, '异常');
    });

    test('网络失败不可达', () async {
      final svc = UpdateService(
        dio: Dio()..httpClientAdapter = _CancelAdapter(),
      );
      final r = await svc.testMirrorLatency(mirror, installerUrl: url);
      expect(r.reachable, isFalse);
      expect(r.usable, isFalse);
      expect(r.label, '不可达');
    });

    test('无 installerUrl 时测镜像前缀根，任何状态都算可用', () async {
      final svc = UpdateService(
        dio: Dio()..httpClientAdapter = _BytesAdapter(const [], statusCode: 403),
      );
      final r = await svc.testMirrorLatency(mirror);
      expect(r.reachable, isTrue);
      expect(r.usable, isTrue);
    });
  });

  group('cleanupStaleInstallers', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('update_service_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('只删 .exe/.part，保留其它文件', () async {
      final sep = Platform.pathSeparator;
      File('${tempDir.path}$sep' 'a.exe').writeAsStringSync('x');
      File('${tempDir.path}$sep' 'b.part').writeAsStringSync('x');
      File('${tempDir.path}$sep' 'c.txt').writeAsStringSync('x');
      final svc = UpdateService(dio: Dio(), updatesDir: tempDir.path);

      await svc.cleanupStaleInstallers();

      expect(File('${tempDir.path}$sep' 'a.exe').existsSync(), isFalse);
      expect(File('${tempDir.path}$sep' 'b.part').existsSync(), isFalse);
      expect(File('${tempDir.path}$sep' 'c.txt').existsSync(), isTrue);
    });

    test('目录不存在时安全 no-op', () async {
      final svc = UpdateService(
        dio: Dio(),
        updatesDir: '${tempDir.path}${Platform.pathSeparator}nope',
      );
      await svc.cleanupStaleInstallers();
    });
  });
}

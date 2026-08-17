import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
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
  });

  test('hasUpdate 用注入的 currentVersion 比较', () {
    final svc = UpdateService(currentVersion: '0.1.2');
    UpdateInfo info(String tag) => UpdateInfo.fromJson({'tag_name': tag});

    expect(svc.hasUpdate(info('v0.1.3')), isTrue);
    expect(svc.hasUpdate(info('v0.1.2')), isFalse);
    expect(svc.hasUpdate(info('v0.1.1')), isFalse);
  });

  test('fromJson 解析 Setup 安装包资产', () {
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
          'browser_download_url':
              'https://github.com/ldm0715/hyb_farm_desktop/releases/download/v0.2.0/HYB-Farm-Desktop-0.2.0-Setup.exe',
          'size': 12345678,
        },
      ],
    });

    expect(info.hasInstaller, isTrue);
    expect(info.installerUrl, contains('Setup.exe'));
    expect(info.installerName, 'HYB-Farm-Desktop-0.2.0-Setup.exe');
    expect(info.installerSize, 12345678);
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
              'name': 'HYB-Farm-Desktop-0.2.0-Setup.exe',
              'browser_download_url':
                  'https://github.com/ldm0715/hyb_farm_desktop/releases/download/v0.2.0/HYB-Farm-Desktop-0.2.0-Setup.exe',
              'size': 4096,
            },
          ],
        });

    test('下载到专用目录并 rename 成 .exe，无 .part 残留', () async {
      final bytes = Uint8List.fromList(List.generate(4096, (i) => i % 256));
      final svc = UpdateService(
        dio: Dio()..httpClientAdapter = _BytesAdapter(bytes),
        updatesDir: tempDir.path,
      );

      final path = await svc.downloadInstaller(infoWithAsset());

      expect(path, endsWith('HYB-Farm-Desktop-0.2.0-Setup.exe'));
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
      final bytes = Uint8List.fromList(List.generate(2048, (i) => 1));
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

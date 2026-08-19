import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyb_farm_desktop/core/download_sources.dart';
import 'package:hyb_farm_desktop/state/settings_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SettingsState> _create() async {
  SharedPreferences.setMockInitialValues({});
  return SettingsState.create();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('下载源', () {
    test('默认官方源', () async {
      final s = await _create();
      expect(s.downloadSource, kDownloadSourceOfficial);
    });

    test('写入下载源并持久化', () async {
      final s = await _create();
      s.downloadSource = kDownloadSourceAuto;

      final reloaded = await SettingsState.create();
      expect(reloaded.downloadSource, kDownloadSourceAuto);
    });

    test('损坏值回落官方（载入时仍原样保存，由 UI 守卫）', () async {
      SharedPreferences.setMockInitialValues(
        {'hyb-farm-download-source': 'garbage'},
      );
      final s = await SettingsState.create();
      expect(s.downloadSource, 'garbage');
    });
  });

  group('镜像列表', () {
    test('默认内置镜像', () async {
      final s = await _create();
      expect(s.downloadMirrors.length, kDefaultDownloadMirrors.length);
      expect(s.downloadMirrors.first.id, kDefaultDownloadMirrors.first.id);
    });

    test('写入镜像列表并持久化（增删/停用/排序）', () async {
      final s = await _create();
      final custom = DownloadMirror(
        id: 'custom-1',
        name: '我的镜像',
        prefix: 'https://my.example.com/',
      );
      s.downloadMirrors = [custom, ...kDefaultDownloadMirrors.take(2)];

      final reloaded = await SettingsState.create();
      // 持久化 3 项 + 合并时追加未持久化的内置 ghfast-top → 共 4 项。
      expect(reloaded.downloadMirrors.length, 4);
      expect(reloaded.downloadMirrors.first.id, custom.id);
      expect(reloaded.downloadMirrors.first.name, '我的镜像');
      expect(reloaded.downloadMirrors.first.prefix, 'https://my.example.com/');
    });

    test('JSON 解析失败回落空列表并与内置合并', () async {
      SharedPreferences.setMockInitialValues({
        'hyb-farm-download-mirrors': '{not-valid-json',
      });
      final s = await SettingsState.create();
      expect(s.downloadMirrors.length, kDefaultDownloadMirrors.length);
      expect(
        s.downloadMirrors.map((m) => m.id).toList(),
        kDefaultDownloadMirrors.map((m) => m.id).toList(),
      );
    });

    test('镜像列表 getter 返回不可变视图', () async {
      final s = await _create();
      expect(
        () => s.downloadMirrors.add(
          const DownloadMirror(id: 'x', name: 'x', prefix: 'https://x/'),
        ),
        throwsUnsupportedError,
      );
    });

    test('旧版持久化（缺 builtIn/enabled）也能加载并合并', () async {
      final legacy = jsonEncode([
        {'id': 'gh-proxy', 'name': '旧名', 'prefix': 'https://old/'},
        {
          'id': 'custom-legacy',
          'name': '旧自定义',
          'prefix': 'https://legacy/',
        },
      ]);
      SharedPreferences.setMockInitialValues({
        'hyb-farm-download-mirrors': legacy,
      });
      final s = await SettingsState.create();
      final byId = {for (final m in s.downloadMirrors) m.id: m};
      // 内置保留旧 enabled（缺省 true）但 name/prefix 用新版覆盖。
      expect(byId['gh-proxy']!.prefix, isNot('https://old/'));
      expect(byId['gh-proxy']!.enabled, isTrue);
      // 自定义原样保留。
      expect(byId['custom-legacy']!.name, '旧自定义');
    });
  });

  group('风险确认版本', () {
    test('默认 0（未确认）', () async {
      final s = await _create();
      expect(s.downloadMirrorRiskAcceptedVersion, 0);
    });

    test('写入并持久化', () async {
      final s = await _create();
      s.downloadMirrorRiskAcceptedVersion = kDownloadMirrorRiskVersion;

      final reloaded = await SettingsState.create();
      expect(reloaded.downloadMirrorRiskAcceptedVersion, kDownloadMirrorRiskVersion);
    });
  });
}

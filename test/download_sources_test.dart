import 'package:flutter_test/flutter_test.dart';
import 'package:hyb_farm_desktop/core/download_sources.dart';

void main() {
  group('DownloadMirror.buildUrl', () {
    const official =
        'https://github.com/ldm0715/hyb_farm_desktop/releases/download/v0.1.3/'
        'HYB-Farm-Desktop-0.1.3-Setup.exe';

    test('前缀尾带 / 原样拼接官方 URL', () {
      const m = DownloadMirror(
        id: 'a',
        name: 'a',
        prefix: 'https://gh-proxy.com/',
      );
      expect(m.buildUrl(official), 'https://gh-proxy.com/$official');
    });

    test('前缀尾不带 / 时归一补上', () {
      const m = DownloadMirror(
        id: 'a',
        name: 'a',
        prefix: 'https://gh-proxy.com',
      );
      expect(m.buildUrl(official), 'https://gh-proxy.com/$official');
    });

    test('官方 URL 原样拼接、不做任何编码', () {
      const m = DownloadMirror(id: 'a', name: 'a', prefix: 'https://x/');
      const odd = 'https://example.com/a b/c?q=1#f';
      expect(m.buildUrl(odd), 'https://x/https://example.com/a b/c?q=1#f');
    });
  });

  group('toJson/fromJson', () {
    test('往返保留全部字段', () {
      const m = DownloadMirror(
        id: 'custom-x',
        name: '我的镜像',
        prefix: 'https://my.example.com/',
        builtIn: false,
        enabled: false,
      );
      final restored = DownloadMirror.fromJson(m.toJson());
      expect(restored, isNotNull);
      expect(restored!.id, m.id);
      expect(restored.name, m.name);
      expect(restored.prefix, m.prefix);
      expect(restored.builtIn, isFalse);
      expect(restored.enabled, isFalse);
    });

    test('enabled 缺省视为 true', () {
      final restored = DownloadMirror.fromJson({
        'id': 'x',
        'name': 'x',
        'prefix': 'https://x/',
      });
      expect(restored!.enabled, isTrue);
    });

    test('损坏输入返回 null', () {
      expect(DownloadMirror.fromJson(null), isNull);
      expect(DownloadMirror.fromJson('x'), isNull);
      expect(DownloadMirror.fromJson({'id': 'x'}), isNull);
      expect(DownloadMirror.fromJson({'id': '', 'name': 'x', 'prefix': 'p'}), isNull);
    });
  });

  group('resolveDownloadCandidates', () {
    const official = 'https://github.com/a/b/releases/download/v1/x.exe';
    final mirrors = [
      const DownloadMirror(id: 'm1', name: '镜像1', prefix: 'https://m1/'),
      const DownloadMirror(
        id: 'm2',
        name: '镜像2',
        prefix: 'https://m2/',
        enabled: false,
      ),
    ];

    test('official → 仅官方候选', () {
      final c = resolveDownloadCandidates(official, kDownloadSourceOfficial, mirrors);
      expect(c.length, 1);
      expect(c.first.url, official);
      expect(c.first.isOfficial, isTrue);
      expect(c.first.sourceId, kDownloadSourceOfficial);
    });

    test('auto → 启用镜像按序 + 官方兜底', () {
      final c = resolveDownloadCandidates(official, kDownloadSourceAuto, mirrors);
      expect(c.length, 2);
      expect(c[0].url, 'https://m1/$official');
      expect(c[0].isOfficial, isFalse);
      expect(c[0].sourceName, '镜像1');
      expect(c[1].url, official);
      expect(c[1].isOfficial, isTrue);
    });

    test('指定启用镜像 → 仅该镜像候选', () {
      final c = resolveDownloadCandidates(
        official,
        mirrorSource('m1'),
        mirrors,
      );
      expect(c.length, 1);
      expect(c.first.url, 'https://m1/$official');
      expect(c.first.isOfficial, isFalse);
    });

    test('指定停用镜像 → 回落官方', () {
      final c = resolveDownloadCandidates(
        official,
        mirrorSource('m2'),
        mirrors,
      );
      expect(c.length, 1);
      expect(c.first.isOfficial, isTrue);
    });

    test('指定不存在的镜像 → 回落官方', () {
      final c = resolveDownloadCandidates(
        official,
        mirrorSource('nope'),
        mirrors,
      );
      expect(c.length, 1);
      expect(c.first.isOfficial, isTrue);
    });

    test('未知/损坏 source → 回落官方', () {
      for (final bad in [null, '', 'garbage', 'mirror:']) {
        final c = resolveDownloadCandidates(official, bad ?? '', mirrors);
        expect(c.length, 1, reason: 'source=$bad');
        expect(c.first.isOfficial, isTrue);
      }
    });
  });

  group('validateMirrorPrefix', () {
    test('合法 https 前缀返回 null', () {
      expect(validateMirrorPrefix('https://gh-proxy.com/'), isNull);
      expect(validateMirrorPrefix('https://gh-proxy.com'), isNull);
      expect(validateMirrorPrefix('  https://a.b/c/d/  '), isNull);
    });

    test('非 https / 缺主机 / userInfo / query / fragment 均拒绝', () {
      expect(validateMirrorPrefix('http://a.com/'), isNotNull);
      expect(validateMirrorPrefix('ftp://a.com/'), isNotNull);
      expect(validateMirrorPrefix('https:///x'), isNotNull);
      expect(validateMirrorPrefix('https://user:pw@a.com/'), isNotNull);
      expect(validateMirrorPrefix('https://a.com/?x=1'), isNotNull);
      expect(validateMirrorPrefix('https://a.com/#f'), isNotNull);
      expect(validateMirrorPrefix(''), isNotNull);
      expect(validateMirrorPrefix('abc'), isNotNull);
    });
  });

  group('hasDuplicatePrefix', () {
    final mirrors = [
      const DownloadMirror(id: 'a', name: 'a', prefix: 'https://x.com/'),
      const DownloadMirror(id: 'b', name: 'b', prefix: 'https://y.com'),
    ];

    test('大小写不敏感、忽略尾部 /', () {
      expect(hasDuplicatePrefix(mirrors, 'https://x.com'), isTrue);
      expect(hasDuplicatePrefix(mirrors, 'https://Y.com/'), isTrue);
    });

    test('排除自身后可复用自己的前缀', () {
      expect(
        hasDuplicatePrefix(mirrors, 'https://x.com', excludeId: 'a'),
        isFalse,
      );
    });

    test('新前缀不冲突', () {
      expect(hasDuplicatePrefix(mirrors, 'https://z.com/'), isFalse);
    });
  });

  group('sourceUsesThirdParty / usesThirdPartyMirror', () {
    final mirrors = [
      const DownloadMirror(id: 'a', name: 'a', prefix: 'https://a/'),
      const DownloadMirror(id: 'b', name: 'b', prefix: 'https://b/', enabled: false),
    ];

    test('auto 有任一启用镜像即为第三方', () {
      expect(sourceUsesThirdParty(kDownloadSourceAuto, mirrors), isTrue);
      expect(
        sourceUsesThirdParty(kDownloadSourceAuto, [
          const DownloadMirror(id: 'b', name: 'b', prefix: 'https://b/', enabled: false),
        ]),
        isFalse,
      );
    });

    test('official 永不触发', () {
      expect(sourceUsesThirdParty(kDownloadSourceOfficial, mirrors), isFalse);
    });

    test('指定启用镜像触发、停用不触发', () {
      expect(sourceUsesThirdParty(mirrorSource('a'), mirrors), isTrue);
      expect(sourceUsesThirdParty(mirrorSource('b'), mirrors), isFalse);
      expect(sourceUsesThirdParty(mirrorSource('nope'), mirrors), isFalse);
    });

    test('usesThirdPartyMirror 按候选判断', () {
      const official = 'https://github.com/a/b/releases/download/v1/x.exe';
      expect(
        usesThirdPartyMirror(
          resolveDownloadCandidates(official, kDownloadSourceOfficial, mirrors),
        ),
        isFalse,
      );
      expect(
        usesThirdPartyMirror(
          resolveDownloadCandidates(official, kDownloadSourceAuto, mirrors),
        ),
        isTrue,
      );
    });
  });

  group('mergeDownloadMirrors', () {
    final defaults = const [
      DownloadMirror(id: 'a', name: '内置A', prefix: 'https://a/'),
      DownloadMirror(id: 'b', name: '内置B', prefix: 'https://b/'),
      DownloadMirror(id: 'c', name: '内置C', prefix: 'https://c/'),
    ];

    test('幸存内置保留 enabled 与顺序，name/prefix 用新版覆盖', () {
      final persisted = [
        const DownloadMirror(id: 'b', name: '旧B', prefix: 'https://old-b/', enabled: false),
        const DownloadMirror(id: 'a', name: '旧A', prefix: 'https://old-a/'),
      ];
      final merged = mergeDownloadMirrors(persisted, defaults);
      expect(merged.map((m) => m.id), ['b', 'a', 'c']);
      // b 被停用、排最前；name/prefix 用新版。
      expect(merged[0].name, '内置B');
      expect(merged[0].prefix, 'https://b/');
      expect(merged[0].enabled, isFalse);
      expect(merged[1].name, '内置A');
      // 新增内置 c 追加末尾、默认启用。
      expect(merged[2].id, 'c');
      expect(merged[2].enabled, isTrue);
    });

    test('新版移除的内置被丢弃', () {
      final persisted = [
        const DownloadMirror(id: 'old', name: '旧', prefix: 'https://old/', builtIn: true),
      ];
      final merged = mergeDownloadMirrors(persisted, defaults);
      expect(merged.map((m) => m.id), ['a', 'b', 'c']);
    });

    test('自定义镜像原样保留', () {
      final persisted = [
        const DownloadMirror(id: 'cust', name: '我的', prefix: 'https://cust/'),
      ];
      final merged = mergeDownloadMirrors(persisted, defaults);
      expect(merged.map((m) => m.id), ['cust', 'a', 'b', 'c']);
      expect(merged.first.name, '我的');
    });
  });
}

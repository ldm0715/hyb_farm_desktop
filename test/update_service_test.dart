import 'package:flutter_test/flutter_test.dart';
import 'package:hyb_farm_desktop/services/update_service.dart';

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
  });

  test('hasUpdate 用注入的 currentVersion 比较', () {
    final svc = UpdateService(currentVersion: '0.1.2');
    UpdateInfo info(String tag) => UpdateInfo.fromJson({'tag_name': tag});

    expect(svc.hasUpdate(info('v0.1.3')), isTrue);
    expect(svc.hasUpdate(info('v0.1.2')), isFalse);
    expect(svc.hasUpdate(info('v0.1.1')), isFalse);
  });
}
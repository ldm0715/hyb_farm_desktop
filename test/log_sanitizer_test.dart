/// 日志脱敏纯函数测试。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:hyb_farm_desktop/core/log/sanitizer.dart';

void main() {
  group('sanitizeText', () {
    test('遮蔽 cookie=value 形式', () {
      final out = sanitizeText('cookie=abc123; name=value');
      expect(out, contains('cookie=•••'));
      expect(out, isNot(contains('abc123')));
      expect(out, contains('name=value'));
    });

    test('遮蔽 token: value 形式（冒号，保留原分隔符）', () {
      final out = sanitizeText('token: secret123');
      expect(out, contains('token:•••'));
      expect(out, isNot(contains('secret123')));
    });

    test('authorization Bearer 遮蔽', () {
      final out = sanitizeText('authorization=Bearer eyJhbGciOiJ');
      expect(out, contains('authorization=•••'));
      expect(out, isNot(contains('eyJhbGciOiJ')));
    });

    test('非敏感内容原样保留', () {
      final out = sanitizeText('msg=ok state=healthy');
      expect(out, 'msg=ok state=healthy');
    });

    test('空输入返回空串', () {
      expect(sanitizeText(null), '');
      expect(sanitizeText(''), '');
    });
  });

  group('sanitizeValue', () {
    test('map 命中敏感 key 递归遮蔽', () {
      final out = sanitizeValue({
        'cookie': 'raw',
        'nested': {'token': 'raw2', 'ok': 'keep'},
        'list': [1, 2],
      });
      expect((out as Map)['cookie'], '•••');
      expect(((out['nested'] as Map))['token'], '•••');
      expect(((out['nested'] as Map))['ok'], 'keep');
      expect((out['list'] as List).length, 2);
    });

    test('普通字符串走 sanitizeText', () {
      final out = sanitizeValue('token=abc');
      expect(out, contains('token=•••'));
    });
  });

  group('sanitizeCookie', () {
    test('委托 maskCookie：保留 key 遮蔽 value', () {
      final out = sanitizeCookie('a=1; b=2');
      expect(out, 'a=•••; b=•••');
    });
  });
}

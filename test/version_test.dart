import 'package:flutter_test/flutter_test.dart';
import 'package:hyb_farm_desktop/core/version.dart';

void main() {
  group('normalizeVersion', () {
    test('去掉 v/V 前缀与首尾空白', () {
      expect(normalizeVersion('v0.1.3'), '0.1.3');
      expect(normalizeVersion('V1.0.0'), '1.0.0');
      expect(normalizeVersion('0.1.2'), '0.1.2');
      expect(normalizeVersion('  v0.1.2  '), '0.1.2');
    });
  });

  group('isNewerVersion', () {
    test('候选更高为真', () {
      expect(isNewerVersion('0.1.3', '0.1.2'), isTrue);
      expect(isNewerVersion('1.0.0', '0.9.9'), isTrue);
      expect(isNewerVersion('0.2.0', '0.1.9'), isTrue);
      expect(isNewerVersion('v0.1.3', '0.1.2'), isTrue);
    });

    test('相同或更低为假', () {
      expect(isNewerVersion('0.1.2', '0.1.2'), isFalse);
      expect(isNewerVersion('0.1.1', '0.1.2'), isFalse);
      expect(isNewerVersion('0.0.9', '0.1.0'), isFalse);
    });

    test('段数不足按 0 补齐', () {
      expect(isNewerVersion('0.2', '0.1.9.5'), isTrue);
      expect(isNewerVersion('1.0.0.0', '1.0.0'), isFalse);
    });
  });
}
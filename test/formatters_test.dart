import 'package:flutter_test/flutter_test.dart';
import 'package:hyb_farm_desktop/core/formatters.dart';

void main() {
  test('formatMoney 除以价格除数并保留 2 位小数', () {
    expect(formatMoney(500000), '\$1.00');
    expect(formatMoney(250000), '\$0.50');
    expect(formatMoney(0), '\$0.00');
  });

  test('formatMoneyGrouped 千分位分隔并保留 2 位小数', () {
    expect(formatMoneyGrouped(500000), '\$1.00');
    expect(formatMoneyGrouped(0), '\$0.00');
    expect(formatMoneyGrouped(617283500000), '\$1,234,567.00');
  });

  test('formatCountdown 格式化秒数', () {
    expect(formatCountdown(0), '00:00');
    expect(formatCountdown(5), '00:05');
    expect(formatCountdown(65), '01:05');
    expect(formatCountdown(3661), '1:01:01');
  });

  test('formatRemaining 人性化剩余时长', () {
    expect(formatRemaining(0), '已成熟');
    expect(formatRemaining(60), '1分');
    expect(formatRemaining(2 * 3600 + 13 * 60), '2小时13分');
  });

  test('formatGrowthTime 格式化成熟耗时', () {
    expect(formatGrowthTime(0), '0分钟');
    expect(formatGrowthTime(30 * 60), '30分钟');
    expect(formatGrowthTime(10 * 3600), '10小时0分钟');
    expect(formatGrowthTime(2 * 3600 + 15 * 60), '2小时15分钟');
  });

  test('formatUsd 美元展示（千分位 + 2 位小数）', () {
    expect(formatUsd(0), '\$0.00');
    expect(formatUsd(1.5), '\$1.50');
    expect(formatUsd(1234.567), '\$1,234.57');
  });

  test('formatPerHour 最多 4 位小数并去除末尾零', () {
    expect(formatPerHour(1.2345), '\$1.2345');
    expect(formatPerHour(1.2), '\$1.2');
    expect(formatPerHour(2.0), '\$2');
  });

  test('maskCookie 保留 key、遮蔽 value', () {
    expect(maskCookie(''), '');
    expect(maskCookie('session=abc123'), 'session=•••');
    expect(
      maskCookie('session=abc; cf_clearance=xyz; token=123'),
      'session=•••; cf_clearance=•••; token=•••',
    );
    expect(maskCookie('flag'), 'flag=•••');
  });
}

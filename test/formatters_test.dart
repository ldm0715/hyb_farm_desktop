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

  test('formatBytes 字节人性化', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(512), '512 B');
    expect(formatBytes(1024), '1.0 KB');
    expect(formatBytes(1536), '1.5 KB');
    expect(formatBytes(1048576), '1.0 MB');
    expect(formatBytes(1572864), '1.5 MB');
    expect(formatBytes(1073741824), '1.0 GB');
  });

  group('formatRelativeTime 固定 now 边界', () {
    final now = DateTime(2026, 1, 1, 12, 0, 0);

    test('null → 暂无', () {
      expect(formatRelativeTime(null, now: now), '暂无');
    });

    test('未来/同一时刻 → 刚刚（时钟回拨不出现负时长）', () {
      expect(formatRelativeTime(now, now: now), '刚刚');
      expect(formatRelativeTime(now.add(const Duration(minutes: 1)), now: now), '刚刚');
      expect(formatRelativeTime(now.add(const Duration(hours: 3)), now: now), '刚刚');
    });

    test('59 秒前 → 刚刚', () {
      expect(
        formatRelativeTime(now.subtract(const Duration(seconds: 59)), now: now),
        '刚刚',
      );
    });

    test('恰好 60 秒前 → 1 分钟前', () {
      expect(
        formatRelativeTime(now.subtract(const Duration(minutes: 1)), now: now),
        '1 分钟前',
      );
    });

    test('59 分钟前 → 59 分钟前', () {
      expect(
        formatRelativeTime(now.subtract(const Duration(minutes: 59)), now: now),
        '59 分钟前',
      );
    });

    test('恰好 60 分钟前 → 1 小时前', () {
      expect(
        formatRelativeTime(now.subtract(const Duration(hours: 1)), now: now),
        '1 小时前',
      );
    });

    test('23 小时前 → 23 小时前', () {
      expect(
        formatRelativeTime(now.subtract(const Duration(hours: 23)), now: now),
        '23 小时前',
      );
    });

    // formatter 不管 24h 过期（由 StealHistory 判定），恰好 24h 仍输出「1 天前」。
    test('恰好 24 小时前 → 1 天前', () {
      expect(
        formatRelativeTime(now.subtract(const Duration(hours: 24)), now: now),
        '1 天前',
      );
    });

    test('多天前 → N 天前', () {
      expect(
        formatRelativeTime(now.subtract(const Duration(days: 3)), now: now),
        '3 天前',
      );
    });
  });
}

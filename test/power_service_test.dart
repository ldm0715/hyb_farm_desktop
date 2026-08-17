/// PowerService 单元测试：睡眠阻止异步串行状态机 + resume 去抖 + 生命周期。
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyb_farm_desktop/services/power_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('hyb_farm/power');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final codec = StandardMethodCodec();

  /// 让 setSleepPrevention 成功并记录每次调用参数。
  List<bool> recordCalls() {
    final calls = <bool>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'setSleepPrevention') {
        calls.add(call.arguments as bool);
        return true;
      }
      return null;
    });
    return calls;
  }

  /// 模拟原生向 Dart 推送一个电源方法调用。
  Future<void> sendPower(MethodCall call) async {
    await messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(call),
      (ByteData? _) {},
    );
  }

  test('睡眠阻止：enabled && automationRunning 才持有', () async {
    final calls = recordCalls();
    final power = PowerService();
    await power.init();

    await power.syncSleepPrevention(enabled: true, automationRunning: true);
    expect(calls, [true]);

    await power.syncSleepPrevention(enabled: true, automationRunning: false);
    expect(calls, [true, false]);

    // 同状态不重复调用原生。
    await power.syncSleepPrevention(enabled: false, automationRunning: true);
    expect(calls, [true, false]);

    await power.dispose();
  });

  test('快速切换 true→false→true 最终为 true', () async {
    final calls = recordCalls();
    final power = PowerService();
    await power.init();

    await power.syncSleepPrevention(enabled: true, automationRunning: true);
    expect(calls.last, true);
    await power.syncSleepPrevention(enabled: true, automationRunning: false);
    expect(calls.last, false);
    await power.syncSleepPrevention(enabled: true, automationRunning: true);
    expect(calls.last, true);

    await power.dispose();
  });

  test('原生调用失败不标记 held，重试后真正 apply', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'set_sleep_prevention_failed');
    });

    final power = PowerService();
    await power.init();
    await power.syncSleepPrevention(enabled: true, automationRunning: true);

    // 换成成功 handler：本地未标 held，再次 sync 应真正 apply。
    final calls = recordCalls();
    await power.syncSleepPrevention(enabled: true, automationRunning: true);
    expect(calls, [true]);

    await power.dispose();
  });

  test('resume 去抖：短时间多条只保留一次', () async {
    var now = DateTime(2026, 1, 1, 0, 0, 0);
    final power = PowerService(now: () => now);
    final resumes = <PowerEvent>[];
    power.events.listen(resumes.add);
    await power.init();

    await sendPower(const MethodCall('resume', 'automatic'));
    expect(resumes.length, 1);

    now = now.add(const Duration(milliseconds: 500));
    await sendPower(const MethodCall('resume', 'suspend'));
    expect(resumes.length, 1); // 去抖窗口内丢弃

    now = now.add(const Duration(seconds: 3));
    await sendPower(const MethodCall('resume', 'automatic'));
    expect(resumes.length, 2);

    await power.dispose();
  });

  test('非 Windows 平台（无原生实现）安全 no-op', () async {
    // 不设置 mock handler：invokeMethod 抛 MissingPluginException，应被吞掉。
    final power = PowerService();
    await power.init();
    await power.syncSleepPrevention(enabled: true, automationRunning: true);
    await power.releaseSleepPrevention(reason: 'test');
    await power.dispose();
  });

  test('dispose 后释放睡眠阻止且不再接收事件', () async {
    final calls = recordCalls();
    final power = PowerService();
    await power.init();

    await power.syncSleepPrevention(enabled: true, automationRunning: true);
    expect(calls, [true]);

    await power.dispose();
    expect(calls, [true, false]); // dispose 主动释放

    // dispose 后 handler 已清空，再发事件不应崩溃。
    await sendPower(const MethodCall('resume', 'automatic'));
  });
}

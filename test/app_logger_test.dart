/// AppLogger / AppLog 测试：级别过滤、sink 分发、dispose 语义。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:hyb_farm_desktop/core/log/app_logger.dart';
import 'package:hyb_farm_desktop/core/log/log_entry.dart';
import 'package:hyb_farm_desktop/core/log/log_level.dart';
import 'package:hyb_farm_desktop/core/log/log_sink.dart';

class _RecordingSink implements LogSink {
  final List<AppLogEntry> entries = [];
  bool disposed = false;

  @override
  void write(AppLogEntry entry) => entries.add(entry);

  @override
  void dispose() => disposed = true;
}

void main() {
  test('级别过滤：production 不记录 debug', () {
    final sink = _RecordingSink();
    AppLogger.instance.initWithSinks(
      [sink],
      environment: LogEnvironment.production,
    );

    AppLog.d('T', 'debug-msg');
    AppLog.i('T', 'info-msg');

    expect(sink.entries.map((e) => e.level), isNot(contains(LogLevel.debug)));
    expect(sink.entries.map((e) => e.level), contains(LogLevel.info));
  });

  test('development 记录 debug', () {
    final sink = _RecordingSink();
    AppLogger.instance.initWithSinks(
      [sink],
      environment: LogEnvironment.development,
    );

    AppLog.d('T', 'debug-msg');

    expect(sink.entries.map((e) => e.level), contains(LogLevel.debug));
  });

  test('error 级记录 error 与 stackTrace', () {
    final sink = _RecordingSink();
    AppLogger.instance.initWithSinks([sink]);

    final st = StackTrace.current;
    AppLog.e('T', 'boom', error: Exception('x'), stackTrace: st);

    expect(sink.entries, hasLength(1));
    expect(sink.entries.first.error, isNotNull);
    expect(sink.entries.first.stackTrace, st);
  });

  test('dispose 后不再写', () async {
    final sink = _RecordingSink();
    AppLogger.instance.initWithSinks([sink]);

    await AppLogger.instance.dispose();
    AppLog.i('T', 'after-dispose');

    expect(sink.entries, isEmpty);
    expect(sink.disposed, isTrue);
  });

  test('extra 中敏感 key 被脱敏', () {
    final sink = _RecordingSink();
    AppLogger.instance.initWithSinks([sink]);

    AppLog.i('T', 'login', {'cookie': 'raw-secret', 'user': 'alice'});

    final extra = sink.entries.first.extra!;
    expect(extra['cookie'], '•••');
    expect(extra['user'], 'alice');
  });
}

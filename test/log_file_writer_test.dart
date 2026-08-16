/// 文件日志写入器测试：日期文件名、跨午夜切换、追加、保留清理。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyb_farm_desktop/core/log/file_writer.dart';
import 'package:hyb_farm_desktop/core/log/log_entry.dart';
import 'package:hyb_farm_desktop/core/log/log_level.dart';
import 'package:hyb_farm_desktop/core/log/log_sink.dart';

void main() {
  late Directory tempRoot;
  late LogSink sink;
  late DateTime current;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('hyb_log_test_');
    current = DateTime(2026, 8, 16, 23, 59, 59);
  });

  tearDown(() {
    sink.dispose();
    try {
      tempRoot.deleteSync(recursive: true);
    } catch (_) {}
  });

  AppLogEntry entry(String tag, String msg) => AppLogEntry(
    level: LogLevel.info,
    time: current,
    tag: tag,
    message: msg,
  );

  Directory logsDir() => Directory('${tempRoot.path}${Platform.pathSeparator}logs');

  File logFile(String day) =>
      File('${logsDir().path}${Platform.pathSeparator}app_$day.log');

  test('日志目录自动创建，文件名按日期', () {
    sink = createFileSink(tempRoot.path, now: () => current);
    sink.write(entry('T', 'hello'));

    expect(logsDir().existsSync(), isTrue);
    expect(logFile('2026-08-16').existsSync(), isTrue);
    expect(logFile('2026-08-16').readAsStringSync(), contains('hello'));
  });

  test('跨午夜自动切换到新日期文件', () {
    sink = createFileSink(tempRoot.path, now: () => current);
    sink.write(entry('T', 'before-midnight'));

    current = DateTime(2026, 8, 17, 0, 0, 1);
    sink.write(entry('T', 'after-midnight'));

    expect(logFile('2026-08-16').existsSync(), isTrue);
    expect(logFile('2026-08-17').existsSync(), isTrue);
    expect(logFile('2026-08-16').readAsStringSync(), contains('before-midnight'));
    expect(logFile('2026-08-17').readAsStringSync(), contains('after-midnight'));
  });

  test('同一天追加写，不覆盖历史', () {
    sink = createFileSink(tempRoot.path, now: () => current);
    sink.write(entry('T', 'first'));
    sink.write(entry('T', 'second'));

    final content = logFile('2026-08-16').readAsStringSync();
    expect(content, contains('first'));
    expect(content, contains('second'));
    // 两条都在，且 first 在 second 之前。
    expect(content.indexOf('first'), lessThan(content.indexOf('second')));
  });

  test('启动时清理超出 retainDays 的旧文件', () {
    // 预置一个 10 天前的旧日志文件。
    final oldDay = '2026-08-06';
    final logs = logsDir()..createSync(recursive: true);
    File('${logs.path}${Platform.pathSeparator}app_$oldDay.log')
        .writeAsStringSync('stale');
    // 预置一个保留期内的文件。
    File('${logs.path}${Platform.pathSeparator}app_2026-08-15.log')
        .writeAsStringSync('fresh');

    sink = createFileSink(tempRoot.path, now: () => current, retainDays: 7);

    expect(logFile(oldDay).existsSync(), isFalse);
    expect(logFile('2026-08-15').existsSync(), isTrue);
  });

  test('日志行带完整本地时间戳', () {
    sink = createFileSink(tempRoot.path, now: () => current);
    sink.write(entry('T', 'ts'));

    final content = logFile('2026-08-16').readAsStringSync();
    expect(content, contains('2026-08-16 23:59:59.000 [INFO] [T] ts'));
  });
}

/// 统一日志入口：装配 sink、过滤级别、脱敏、分发。
///
/// 用法：
/// - 启动时 `await AppLogger.init()` 一次（`main()` 中，早于其他初始化）。
/// - 业务代码统一走静态门面 [`AppLog`]（`AppLog.d/i/w/e`），禁止散落 `print`/`debugPrint`。
/// - 未来接入 Sentry/Crashlytics 只需新增一个实现 [`LogSink`] 的远程 sink 并在
///   [AppLogger.init] 里加入，无需改动核心与调用方。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hyb_farm_desktop/core/log/file_writer.dart';
import 'package:hyb_farm_desktop/core/log/log_entry.dart';
import 'package:hyb_farm_desktop/core/log/log_level.dart';
import 'package:hyb_farm_desktop/core/log/log_sink.dart';
import 'package:hyb_farm_desktop/core/log/sanitizer.dart';

class AppLogger {
  AppLogger._();

  static final AppLogger _instance = AppLogger._();

  /// 全局单例，供 `main()` 初始化时调用 [init]。
  static AppLogger get instance => _instance;

  LogEnvironment _environment = LogEnvironment.development;
  final List<LogSink> _sinks = [];
  bool _disposed = false;
  bool _initialized = false;

  /// 初始化日志系统。同一进程内只应调用一次。
  ///
  /// [directory] 为应用可写目录（`getApplicationSupportDirectory` 结果）。
  /// [environment] 可显式指定，默认由 `resolveEnvironment()` 解析。
  /// [now] / [retainDays] 注入测试。
  Future<void> init({
    required String directory,
    LogEnvironment? environment,
    DateTime Function()? now,
    int retainDays = 7,
  }) async {
    if (_initialized) return;
    _initialized = true;
    _environment = environment ?? resolveEnvironment();
    if (_environment.consoleEnabled) {
      _sinks.add(ConsoleLogSink());
    }
    _sinks.add(createFileSink(directory, now: now, retainDays: retainDays));
  }

  /// 测试专用：用内存 sink 替换默认装配。
  @visibleForTesting
  void initWithSinks(
    List<LogSink> sinks, {
    LogEnvironment environment = LogEnvironment.development,
  }) {
    _initialized = true;
    _disposed = false;
    _environment = environment;
    _sinks
      ..clear()
      ..addAll(sinks);
  }

  void debug(String tag, String message, [Map<String, dynamic>? extra]) =>
      _log(LogLevel.debug, tag, message, extra: extra);

  void info(String tag, String message, [Map<String, dynamic>? extra]) =>
      _log(LogLevel.info, tag, message, extra: extra);

  void warning(String tag, String message, [Map<String, dynamic>? extra]) =>
      _log(LogLevel.warning, tag, message, extra: extra);

  void error(
    String tag,
    String message, {
    Map<String, dynamic>? extra,
    Object? error,
    StackTrace? stackTrace,
  }) => _log(LogLevel.error, tag, message,
      extra: extra, error: error, stackTrace: stackTrace);

  void _log(
    LogLevel level,
    String tag,
    String message, {
    Map<String, dynamic>? extra,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (_disposed || !_initialized) return;
    if (!level.atLeast(_environment.minLevel)) return;

    final entry = AppLogEntry(
      level: level,
      time: DateTime.now(),
      tag: sanitizeText(tag),
      message: sanitizeText(message),
      extra: extra == null ? null : _sanitizeExtra(extra),
      error: error == null ? null : sanitizeText(error.toString()),
      stackTrace: stackTrace,
    );

    for (final sink in _sinks) {
      try {
        sink.write(entry);
      } catch (_) {
        // 单个 sink 写失败不阻断其它 sink 与主流程。
      }
    }
  }

  Map<String, dynamic> _sanitizeExtra(Map<String, dynamic> extra) =>
      (sanitizeValue(extra) as Map).cast<String, dynamic>();
  /// 释放全部 sink（关闭文件等）。之后调用 [AppLog] 不再写入。
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final sink in _sinks) {
      try {
        sink.dispose();
      } catch (_) {
        // 释放失败忽略。
      }
    }
    _sinks.clear();
  }
}

/// 全局静态门面，业务代码唯一入口。
abstract final class AppLog {
  static void d(String tag, String message, [Map<String, dynamic>? extra]) =>
      AppLogger._instance.debug(tag, message, extra);

  static void i(String tag, String message, [Map<String, dynamic>? extra]) =>
      AppLogger._instance.info(tag, message, extra);

  static void w(String tag, String message, [Map<String, dynamic>? extra]) =>
      AppLogger._instance.warning(tag, message, extra);

  static void e(
    String tag,
    String message, {
    Map<String, dynamic>? extra,
    Object? error,
    StackTrace? stackTrace,
  }) => AppLogger._instance.error(tag, message,
      extra: extra, error: error, stackTrace: stackTrace);
}

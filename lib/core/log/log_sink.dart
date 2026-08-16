/// 日志落点抽象：文件、控制台、未来的远程上报（Sentry/Crashlytics）都实现同一接口。
library;

import 'package:flutter/foundation.dart';

import 'package:hyb_farm_desktop/core/log/log_entry.dart';

/// 日志输出目标。实现需保证 `write` 可被多入口串行调用而不交叉。
abstract class LogSink {
  /// 写入一条已格式化的日志文本（含末尾换行）。
  void write(AppLogEntry entry);

  /// 释放资源（关闭文件等）；之后不再调用 [write]。
  void dispose() {}
}

/// 控制台 sink：开发/预发环境同步输出。
class ConsoleLogSink implements LogSink {
  @override
  void write(AppLogEntry entry) {
    // debugPrint 避免 Windows 下 stdout 重定向对中文/长文本的截断问题。
    debugPrint(entry.format().trimRight());
  }

  @override
  void dispose() {}
}

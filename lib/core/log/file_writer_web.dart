/// Web 平台日志文件写入降级实现。
///
/// Web 无法使用 `dart:io` 文件系统，这里优雅降级为仅丢弃日志（控制台由
/// `ConsoleLogSink` 负责），保证代码在 web 编译通过。文件落盘由 IO 平台实现承担。
library;

import 'package:hyb_farm_desktop/core/log/log_entry.dart';
import 'package:hyb_farm_desktop/core/log/log_sink.dart';

LogSink createFileSink(
  String directory, {
  DateTime Function()? now,
  int retainDays = 7,
}) => _NoopFileSink();

class _NoopFileSink implements LogSink {
  @override
  void write(AppLogEntry entry) {}

  @override
  void dispose() {}
}

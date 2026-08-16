/// 文件日志写入的条件导入入口。
///
/// IO 平台（Android/iOS/Windows/macOS/Linux）用 `file_writer_io.dart`；
/// Web 无 `dart:io`，用 no-op 实现保证编译并优雅降级（仅丢弃日志）。
library;

import 'package:hyb_farm_desktop/core/log/file_writer_io.dart'
    if (dart.library.js_interop) 'package:hyb_farm_desktop/core/log/file_writer_web.dart'
    as impl;

import 'package:hyb_farm_desktop/core/log/log_sink.dart';

/// 构造文件写入 sink。
///
/// [directory] 为日志根目录（已确保存在），内部追加 `logs/` 子目录。
/// [now] 注入时钟（测试用），默认 `DateTime.now`。时间语义为本地时间。
/// [retainDays] 保留天数，超出该天数的 `app_*.log` 会在启动/切文件时清理。
LogSink createFileSink(
  String directory, {
  DateTime Function()? now,
  int retainDays = 7,
}) => impl.createFileSink(directory, now: now, retainDays: retainDays);

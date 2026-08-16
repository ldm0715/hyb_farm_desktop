/// 日志级别与环境定义。
///
/// 环境决定最低记录级别与是否输出到控制台：
/// - `development` / `staging`：从 debug 起记录，控制台同步输出。
/// - `production`：从 info 起记录，关闭控制台，仅写文件。
library;

import 'package:flutter/foundation.dart';

/// 日志级别，按严重程度递增。
enum LogLevel {
  debug,
  info,
  warning,
  error;

  /// 用于日志行内的级别标签（`DEBUG`/`INFO`/`WARNING`/`ERROR`）。
  String get label => name.toUpperCase();

  /// 是否达到给定级别（用于环境最低级别过滤）。
  bool atLeast(LogLevel other) => index >= other.index;
}

/// 运行环境。
enum LogEnvironment {
  development,
  staging,
  production;

  /// 该环境下的最低记录级别。
  LogLevel get minLevel => switch (this) {
    LogEnvironment.development => LogLevel.debug,
    LogEnvironment.staging => LogLevel.debug,
    LogEnvironment.production => LogLevel.info,
  };

  /// 是否同步输出到控制台（生产环境关闭，避免污染 stdout）。
  bool get consoleEnabled => this != LogEnvironment.production;
}

/// 解析当前环境：
/// 1. 优先读 `--dart-define=APP_ENV=<value>`（`String.fromEnvironment`）；
/// 2. 未定义时用 `kReleaseMode` 兜底：release 构建视为 production，否则 development。
///
/// 纯函数便于测试。构建命令示例：`flutter build windows --dart-define=APP_ENV=staging`。
LogEnvironment resolveEnvironment({bool? isRelease}) {
  const raw = String.fromEnvironment('APP_ENV');
  if (raw.isNotEmpty) {
    switch (raw.toLowerCase()) {
      case 'development':
      case 'dev':
        return LogEnvironment.development;
      case 'staging':
      case 'stage':
        return LogEnvironment.staging;
      case 'production':
      case 'prod':
        return LogEnvironment.production;
    }
  }
  final release = isRelease ?? kReleaseMode;
  return release ? LogEnvironment.production : LogEnvironment.development;
}

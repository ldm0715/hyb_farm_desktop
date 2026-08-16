/// 单条日志条目与格式化。
///
/// 时间使用**本地时间**（`DateTime.now()` 语义），便于直接对照用户所在时区排查；
/// 全项目统一本地时间，不混用 UTC。
library;

import 'package:hyb_farm_desktop/core/log/log_level.dart';

/// 一条待落盘的日志。
class AppLogEntry {
  const AppLogEntry({
    required this.level,
    required this.time,
    required this.tag,
    required this.message,
    this.extra,
    this.error,
    this.stackTrace,
  });

  final LogLevel level;
  final DateTime time;

  /// 模块/页面标签，如 `FarmState`、`ApiClient`、`Network`。
  final String tag;
  final String message;

  /// 结构化附加信息（会被 JSON 序列化 + 脱敏后拼入行尾）。
  final Map<String, dynamic>? extra;

  /// 异常对象（error 级日志携带）。
  final Object? error;

  /// 堆栈（可空，未捕获异常时由全局捕获器传入）。
  final StackTrace? stackTrace;

  /// 输出到文件/控制台的单行文本，末尾带换行。
  String format() {
    final buf = StringBuffer()
      ..write(_ts())
      ..write(' [')
      ..write(level.label)
      ..write('] [')
      ..write(tag.isEmpty ? '-' : tag)
      ..write('] ')
      ..write(message);

    if (extra != null && extra!.isNotEmpty) {
      buf
        ..write(' | extra=')
        ..write(extra);
    }
    if (error != null) {
      buf
        ..write(' | error=')
        ..write(error);
    }
    buf.write('\n');
    if (stackTrace != null) {
      buf
        ..write('  ')
        ..write(_indent(stackTrace.toString()));
    }
    return buf.toString();
  }

  /// 本地时间戳 `yyyy-MM-dd HH:mm:ss.SSS`。
  String _ts() {
    final t = time;
    String two(int v) => v.toString().padLeft(2, '0');
    String three(int v) => v.toString().padLeft(3, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.${three(t.millisecond)}';
  }

  static String _indent(String s) => s.replaceAll('\n', '\n  ');
}

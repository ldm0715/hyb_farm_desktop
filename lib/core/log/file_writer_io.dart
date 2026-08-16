/// 文件日志写入实现（dart:io）。
///
/// 规则：
/// - 目录 `<root>/logs/`，不存在自动创建。
/// - 文件名 `app_yyyy-MM-dd.log`（**本地时间**，见 [LogFileWriter._now]）。
/// - 每次写入前按当前日期判断是否需要切换文件，跨越午夜自动切到新文件。
/// - 同一天追加写、不覆盖历史。
/// - 使用同步 append（`writeAsStringSync(mode: FileMode.append, flush: true)`）：
///   Dart 单线程事件循环下同步写天然保证多条日志顺序、不交叉、无句柄泄漏；
///   日志量小（每分钟个位数），同步开销可忽略。
/// - 启动/切文件时清理超出 [retainDays] 的旧 `app_*.log`。
library;

import 'dart:io';

import 'package:hyb_farm_desktop/core/log/log_entry.dart';
import 'package:hyb_farm_desktop/core/log/log_sink.dart';

LogSink createFileSink(
  String directory, {
  DateTime Function()? now,
  int retainDays = 7,
}) => LogFileWriter(directory, now: now, retainDays: retainDays);

class LogFileWriter implements LogSink {
  LogFileWriter(
    this._root, {
    DateTime Function()? now,
    int retainDays = 7,
  }) : _now = now ?? DateTime.now,
       _retainDays = retainDays {
    _logsDir = Directory('$_root${Platform.pathSeparator}logs');
    _ensureDir();
    _currentDay = _today();
    _currentFile = _fileFor(_currentDay);
    _cleanup();
  }

  final String _root;
  final DateTime Function() _now;
  final int _retainDays;

  late final Directory _logsDir;
  late String _currentDay;
  late File _currentFile;

  @override
  void write(AppLogEntry entry) {
    final day = _today();
    if (day != _currentDay) {
      _currentDay = day;
      _currentFile = _fileFor(day);
      _cleanup();
    }
    _currentFile.writeAsStringSync(
      entry.format(),
      mode: FileMode.append,
      flush: true,
    );
  }

  @override
  void dispose() {
    // 文件句柄在每次 writeAsStringSync 后已关闭，此处无需额外释放。
  }

  /// 当前本地日期 `yyyy-MM-dd`。
  String _today() {
    final t = _now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)}';
  }

  File _fileFor(String day) => File('${_logsDir.path}${Platform.pathSeparator}app_$day.log');

  void _ensureDir() {
    if (!_logsDir.existsSync()) {
      _logsDir.createSync(recursive: true);
    }
  }

  /// 清理早于 `retainDays` 的日志文件。
  void _cleanup() {
    final cutoff = _now().subtract(Duration(days: _retainDays));
    final prefix = 'app_';
    try {
      for (final f in _logsDir.listSync()) {
        if (f is! File) continue;
        final name = f.uri.pathSegments.last;
        if (!name.startsWith(prefix) || !name.endsWith('.log')) continue;
        final dateStr = name.substring(prefix.length, name.length - 4);
        final date = DateTime.tryParse(dateStr);
        if (date == null) continue;
        if (date.isBefore(cutoff)) {
          try {
            f.deleteSync();
          } catch (_) {
            // 单个文件删除失败不阻断后续写入。
          }
        }
      }
    } catch (_) {
      // 目录扫描异常时静默，避免日志系统自身影响主流程。
    }
  }
}

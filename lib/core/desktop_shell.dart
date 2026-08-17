/// Windows 桌面外壳操作：定位日志目录、打开文件夹、打开 URL。
///
/// 应用是 Windows 专属桌面程序，这里直接用 `dart:io` 调系统 `explorer` / `cmd`，
/// 不引入 `url_launcher` 等额外依赖。仅在 Windows 下使用；`logsDirFor` 与
/// [file_writer_io] 的 `logs/` 子目录契约保持一致（有测试对齐）。
library;

import 'dart:io';

import 'package:hyb_farm_desktop/core/log/app_logger.dart';

/// 由日志根目录派生实际的 `logs` 目录路径（与 `LogFileWriter` 内部一致）。
String logsDirFor(String root) =>
    Directory('$root${Platform.pathSeparator}logs').path;

/// 打开目录（Windows 资源管理器）。失败静默记录到日志。
Future<void> openDirectory(String path) async {
  try {
    await Process.start('explorer', [path]);
  } catch (e) {
    AppLog.w('Shell', '打开目录失败', {'path': path, 'error': e.toString()});
  }
}

/// 用默认浏览器打开 URL。失败静默记录到日志。
///
/// `cmd /c start "" <url>` 是 Windows 下打开默认浏览器的通用方式；空串作窗口标题，
/// 避免 `start` 把首个带引号参数误判为标题。
Future<void> openUrl(String url) async {
  try {
    await Process.start('cmd', ['/c', 'start', '', url]);
  } catch (e) {
    AppLog.w('Shell', '打开链接失败', {'url': url, 'error': e.toString()});
  }
}
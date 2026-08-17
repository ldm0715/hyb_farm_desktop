/// 检查更新：从 GitHub Releases 拉取最新发布版本与更新说明，并可下载安装包到专用目录。
///
/// 独立 `Dio` 指向 `https://api.github.com`，**不复用 `ApiClient`**——后者的 `baseUrl`
/// 写死农场主机、会注入 Cookie、`classifyRequest/_decode` 是农场专用信封，会误分类
/// GitHub 的 403/404/429。此服务也不挂 `NetworkLogInterceptor`，让更新检查不进农场日志。
///
/// 下载的安装包落在应用支持目录下的 `updates/` 专用子目录（见 `kUpdatesDirName`），
/// 只放本服务的下载产物；`cleanupStaleInstallers` 只删该目录内的 `.exe`/`.part`。
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:hyb_farm_desktop/core/constants.dart';
import 'package:hyb_farm_desktop/core/log/app_logger.dart';
import 'package:hyb_farm_desktop/core/version.dart';

/// 单个 GitHub Release 的最小字段集。
class UpdateInfo {
  const UpdateInfo({
    required this.tagName,
    required this.name,
    required this.body,
    required this.htmlUrl,
    this.publishedAt,
    this.installerUrl,
    this.installerName,
    this.installerSize,
  });

  /// 版本标签（通常带 `v` 前缀，如 `v0.1.3`）。
  final String tagName;

  /// 发布标题（可能为空，展示回退用 [tagName]）。
  final String name;

  /// 更新说明（Markdown 原文，展示时按纯文本渲染）。
  final String body;

  /// 发布页地址。
  final String htmlUrl;

  /// 发布时间（ISO8601）。
  final DateTime? publishedAt;

  /// Setup 安装包资产下载地址（`browser_download_url`）；该版本无 Setup 资产时为 null。
  final String? installerUrl;

  /// Setup 安装包资产名（用于落盘文件名）。
  final String? installerName;

  /// Setup 安装包资产大小（字节），未知为 null。
  final int? installerSize;

  /// 是否存在可下载的安装包资产。
  bool get hasInstaller => installerUrl != null && installerUrl!.isNotEmpty;

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    final asset = _setupAsset(json['assets']);
    return UpdateInfo(
      tagName: json['tag_name'] as String? ?? '',
      name: json['name'] as String? ?? '',
      body: json['body'] as String? ?? '',
      htmlUrl: json['html_url'] as String? ?? '',
      publishedAt: _parseDate(json['published_at']),
      installerUrl: asset.$1,
      installerName: asset.$2,
      installerSize: asset.$3,
    );
  }

  /// 版本展示文本：优先展示标签，去掉前导 `v`。
  String get version => normalizeVersion(tagName);
}

/// 从 `assets[]` 取第一个以 `-Setup.exe` 结尾的资产，返回 (url, name, size)。
(String?, String?, int?) _setupAsset(dynamic assets) {
  if (assets is! List) return (null, null, null);
  for (final a in assets) {
    if (a is! Map) continue;
    final n = a['name'];
    final u = a['browser_download_url'];
    final s = a['size'];
    if (n is String &&
        u is String &&
        u.isNotEmpty &&
        n.toLowerCase().endsWith('-setup.exe')) {
      return (u, n, s is int ? s : null);
    }
  }
  return (null, null, null);
}

DateTime? _parseDate(dynamic value) {
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}

/// 资产名只取 basename，剥离任何路径分隔符，防路径穿越。
String _sanitizeFileName(String name) {
  var clean = name.replaceAll(RegExp(r'[\\/]'), '').trim();
  if (clean.isEmpty) clean = 'setup.exe';
  return clean;
}

void _deleteQuietly(String path) {
  try {
    final f = File(path);
    if (f.existsSync()) f.deleteSync();
  } catch (_) {
    // 删除失败不影响主流程，交由下次启动清理兜底。
  }
}

/// 由应用支持目录派生 `updates` 专用子目录（镜像 `logsDirFor` 的拼接契约）。
String updatesDirFor(String supportRoot) =>
    '$supportRoot${Platform.pathSeparator}$kUpdatesDirName';

class UpdateService {
  UpdateService({
    Dio? dio,
    String? currentVersion,
    String repoPath = 'ldm0715/hyb_farm_desktop',
    String? updatesDir,
  }) : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: 'https://api.github.com',
                connectTimeout: kRequestTimeout,
                receiveTimeout: kRequestTimeout,
                headers: {'accept': 'application/vnd.github+json'},
              ),
            ),
       _currentVersion = currentVersion ?? kAppVersion,
       _repoPath = repoPath,
       _updatesDir = updatesDir;

  final Dio _dio;
  final String _currentVersion;
  final String _repoPath;

  /// 注入的专用下载目录（main 传应用支持目录下的 updates，测试传临时目录）；null 时惰性解析。
  final String? _updatesDir;

  /// 是否存在比当前版本更新的发布。
  bool hasUpdate(UpdateInfo info) =>
      isNewerVersion(info.tagName, _currentVersion);

  /// 拉取最新 released 发布（不含 prerelease/draft）。失败抛异常，由调用方转提示。
  Future<UpdateInfo> fetchLatest() async {
    // `validateStatus` 保持默认：非 2xx 直接抛 DioException，调用方统一按「失败」处理。
    final res = await _dio.get<dynamic>('/repos/$_repoPath/releases/latest');
    final data = res.data;
    if (data is Map<String, dynamic>) {
      return UpdateInfo.fromJson(data);
    }
    throw const FormatException('无效的 releases 响应');
  }

  /// 解析专用目录并确保存在。
  Future<Directory> _ensureUpdatesDir() async {
    final root = _updatesDir ??
        updatesDirFor((await getApplicationSupportDirectory()).path);
    final dir = Directory(root);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// 专用目录绝对路径（UI 确认框展示用）。
  Future<String> updatesDirPath() async => (await _ensureUpdatesDir()).path;

  /// 下载安装包到专用目录；成功返回最终 `.exe` 绝对路径。
  ///
  /// 先写 `<name>.part` 再 rename 成 `<name>.exe`，避免下载中途崩溃留下命名成 `.exe` 的
  /// 残缺文件。失败抛异常（`.part` 残留已清理），`[onProgress]` 回调 (received, total)，
  /// `total` 未知时为 -1。
  Future<String> downloadInstaller(
    UpdateInfo info, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final url = info.installerUrl;
    if (url == null || url.isEmpty) {
      throw StateError('该版本没有可下载的安装包资产');
    }
    final dir = await _ensureUpdatesDir();
    final fileName = _sanitizeFileName(
      info.installerName ?? url.split('/').last,
    );
    final partPath = '${dir.path}${Platform.pathSeparator}$fileName.part';
    final finalPath = '${dir.path}${Platform.pathSeparator}$fileName';
    try {
      await _dio.download(
        url,
        partPath,
        onReceiveProgress: onProgress,
        cancelToken: cancelToken,
        deleteOnError: true,
        options: Options(receiveTimeout: kUpdateDownloadTimeout),
      );
    } catch (_) {
      // dio deleteOnError 之外的残留双保险。
      _deleteQuietly(partPath);
      rethrow;
    }
    final finalFile = File(finalPath);
    if (finalFile.existsSync()) _deleteQuietly(finalPath);
    await File(partPath).rename(finalPath);
    return finalPath;
  }

  /// 启动时清理专用目录内所有 `.exe`/`.part`（本服务的下载产物）。
  ///
  /// 逐文件容错，失败仅记日志，**不阻断启动**——安装器退出与新版自启可能短暂重叠导致
  /// 删除失败，下次启动重试即可。目录不存在时安全 no-op。
  Future<void> cleanupStaleInstallers() async {
    try {
      final root = _updatesDir ??
          updatesDirFor((await getApplicationSupportDirectory()).path);
      final dir = Directory(root);
      if (!dir.existsSync()) return;
      for (final e in dir.listSync()) {
        if (e is! File) continue;
        final n = e.path.toLowerCase();
        if (n.endsWith('.exe') || n.endsWith('.part')) {
          _deleteQuietly(e.path);
        }
      }
    } catch (e) {
      AppLog.w('Update', '清理安装包失败', {'error': e.toString()});
    }
  }
}

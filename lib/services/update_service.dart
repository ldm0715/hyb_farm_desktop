/// 检查更新：从 GitHub Releases 拉取最新发布版本与更新说明，并可下载安装包到专用目录。
///
/// 独立 `Dio` 指向 `https://api.github.com`，**不复用 `ApiClient`**——后者的 `baseUrl`
/// 写死农场主机、会注入 Cookie、`classifyRequest/_decode` 是农场专用信封，会误分类
/// GitHub 的 403/404/429。此服务也不挂 `NetworkLogInterceptor`，让更新检查不进农场日志。
///
/// 下载的安装包落在应用支持目录下的 `updates/` 专用子目录（见 `kUpdatesDirName`），
/// 只放本服务的下载产物；`cleanupStaleInstallers` 只删该目录内的 `.exe`/`.part`。
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:hyb_farm_desktop/core/constants.dart';
import 'package:hyb_farm_desktop/core/download_sources.dart';
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
    this.checksumUrl,
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

  /// `-SHA256.txt` 校验清单的官方下载地址（`browser_download_url`）；缺失为 null。
  final String? checksumUrl;

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
      checksumUrl: _checksumAsset(json['assets']),
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

/// 从 `assets[]` 取 `-SHA256.txt` 资产的官方下载地址（校验清单，绝不走镜像）。
String? _checksumAsset(dynamic assets) {
  if (assets is! List) return null;
  for (final a in assets) {
    if (a is! Map) continue;
    final n = a['name'];
    final u = a['browser_download_url'];
    if (n is String &&
        u is String &&
        u.isNotEmpty &&
        n.toLowerCase().endsWith('-sha256.txt')) {
      return u;
    }
  }
  return null;
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

/// 下载的最小合理字节数：任何真实 Windows 安装器都远大于此，用于拒绝错误页。
const int _kMinInstallerBytes = 512;

/// 校验清单最大字节数：SHA256 清单仅几百字节，超此视为异常。
const int _kMaxChecksumBytes = 4096;

/// 日志用：去除 URL 的 query/fragment，避免记录敏感参数。
String _sanitizeUrlForLog(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return url;
  return uri.replace(query: null, fragment: null).toString();
}

/// 基础完整性检查：文件存在、大小合理、头为 MZ。返回 null 表示通过，否则错误文案。
///
/// MZ 头（0x4D 0x5A）是 Windows PE/安装器前缀；HTML/JSON/XML 错误页必然不满足，故一并拒绝。
String? _basicFileCheck(File f) {
  if (!f.existsSync()) return '文件不存在';
  if (f.lengthSync() < _kMinInstallerBytes) return '文件过小，疑似错误页';
  final raf = f.openSync();
  List<int> head;
  try {
    head = raf.readSync(16);
  } finally {
    raf.closeSync();
  }
  if (head.length < 2) return '文件过小，疑似错误页';
  if (head[0] != 0x4D || head[1] != 0x5A) {
    return '文件头不是 Windows 可执行文件（疑似错误页）';
  }
  return null;
}

/// 流式计算文件 SHA256，返回小写 hex。
Future<String> _sha256Hex(File f) async {
  final digest = await sha256.bind(f.openRead()).first;
  return digest.toString();
}

/// 解析 `-SHA256.txt` 内容，返回 [assetName] 对应的小写 64 位 hex 期望哈希。
///
/// 严格校验 64 位 hex 并按资产名精确匹配；多条且哈希冲突视为异常。
String? _parseChecksum(String text, String? assetName) {
  if (assetName == null || assetName.isEmpty) return null;
  final hashes = <String>{};
  for (final raw in text.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final parts = line.split(RegExp(r'\s+'));
    if (parts.length < 2) continue;
    final hex = parts.first;
    final name = parts.skip(1).join(' ').trim();
    if (name != assetName) continue;
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(hex)) continue;
    hashes.add(hex.toLowerCase());
  }
  if (hashes.isEmpty) throw const FormatException('校验清单未包含该安装包');
  if (hashes.length > 1) throw const FormatException('校验清单存在冲突条目');
  return hashes.first;
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
  /// 按 [source]/[mirrors] 解析候选列表并逐个尝试：`auto` 镜像失败后回退官方，指定镜像
  /// 失败不自动回退。每个候选下载成功后先做基础校验（MZ 头/大小）与 SHA256 校验
  /// （清单从官方渠道获取），通过才 rename 成 `.exe`，否则清理 `.part` 继续下一候选。
  /// 用户取消（`cancelToken`）立即停止、不再尝试其它源。`[onProgress]` 回调
  /// (received, total)，`total` 未知时为 -1；`[onCandidate]` 在每次尝试新来源前触发，
  /// 供 UI 显示当前来源。
  Future<String> downloadInstaller(
    UpdateInfo info, {
    String source = kDownloadSourceOfficial,
    List<DownloadMirror> mirrors = kDefaultDownloadMirrors,
    void Function(int received, int total)? onProgress,
    void Function(DownloadCandidate candidate)? onCandidate,
    CancelToken? cancelToken,
  }) async {
    final official = info.installerUrl;
    if (official == null || official.isEmpty) {
      throw StateError('该版本没有可下载的安装包资产');
    }
    final dir = await _ensureUpdatesDir();
    final fileName = _sanitizeFileName(
      info.installerName ?? official.split('/').last,
    );
    final partPath = '${dir.path}${Platform.pathSeparator}$fileName.part';
    final finalPath = '${dir.path}${Platform.pathSeparator}$fileName';

    final candidates = resolveDownloadCandidates(official, source, mirrors);

    // 第三方来源必须有可信校验清单；清单始终从官方 URL 获取，绝不走镜像。
    String? expectedSha256;
    if (info.checksumUrl != null && info.checksumUrl!.isNotEmpty) {
      expectedSha256 = await _fetchExpectedSha256(info, cancelToken);
    } else if (usesThirdPartyMirror(candidates)) {
      throw const FormatException('该版本无校验清单，无法安全使用第三方镜像，请改用官方源');
    }

    Object? lastError;
    for (final c in candidates) {
      if (cancelToken?.isCancelled ?? false) {
        throw DioException(
          requestOptions: RequestOptions(path: c.url),
          type: DioExceptionType.cancel,
        );
      }
      onCandidate?.call(c);
      onProgress?.call(0, -1);
      AppLog.i('Update', '下载安装包', {
        'source': c.sourceId,
        'url': _sanitizeUrlForLog(c.url),
      });
      try {
        await _dio.download(
          c.url,
          partPath,
          onReceiveProgress: onProgress,
          cancelToken: cancelToken,
          deleteOnError: true,
          options: Options(receiveTimeout: kUpdateDownloadTimeout),
        );
        final err = await _verifyDownloaded(File(partPath), expectedSha256);
        if (err == null) {
          lastError = null;
          break;
        }
        AppLog.w('Update', '下载校验失败', {'source': c.sourceId, 'reason': err});
        _deleteQuietly(partPath);
        lastError = FormatException(err);
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel) rethrow;
        lastError = e;
        _deleteQuietly(partPath);
        AppLog.w('Update', '下载失败', {
          'source': c.sourceId,
          'type': e.type.name,
        });
      } catch (e) {
        lastError = e;
        _deleteQuietly(partPath);
        AppLog.w('Update', '下载失败', {
          'source': c.sourceId,
          'error': e.toString(),
        });
      }
    }

    if (lastError != null) {
      throw lastError;
    }

    final finalFile = File(finalPath);
    if (finalFile.existsSync()) _deleteQuietly(finalPath);
    await File(partPath).rename(finalPath);
    return finalPath;
  }

  /// 从官方渠道拉取 `-SHA256.txt` 并解析出安装包对应的期望哈希（小写 64 位 hex）。
  Future<String?> _fetchExpectedSha256(
    UpdateInfo info,
    CancelToken? cancelToken,
  ) async {
    final url = info.checksumUrl!;
    final res = await _dio.get<List<int>>(
      url,
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.bytes,
        receiveTimeout: kRequestTimeout,
      ),
    );
    final bytes = res.data;
    if (bytes == null || bytes.length > _kMaxChecksumBytes) {
      throw const FormatException('校验清单异常');
    }
    final text = utf8.decode(bytes, allowMalformed: true);
    return _parseChecksum(text, info.installerName);
  }

  /// 校验已下载的 `.part`：基础检查 +（可选）SHA256 比对。返回 null 表示通过，否则错误文案。
  Future<String?> _verifyDownloaded(File f, String? expectedSha256) async {
    final basic = _basicFileCheck(f);
    if (basic != null) return basic;
    if (expectedSha256 == null) return null;
    final actual = await _sha256Hex(f);
    if (actual != expectedSha256) return 'SHA256 校验不匹配';
    return null;
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

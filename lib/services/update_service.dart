/// 检查更新：从 GitHub Releases 拉取最新发布版本与更新说明。
///
/// 独立 `Dio` 指向 `https://api.github.com`，**不复用 `ApiClient`**——后者的 `baseUrl`
/// 写死农场主机、会注入 Cookie、`classifyRequest/_decode` 是农场专用信封，会误分类
/// GitHub 的 403/404/429。此服务也不挂 `NetworkLogInterceptor`，让更新检查不进农场日志。
library;

import 'package:dio/dio.dart';
import 'package:hyb_farm_desktop/core/constants.dart';
import 'package:hyb_farm_desktop/core/version.dart';

/// 单个 GitHub Release 的最小字段集。
class UpdateInfo {
  const UpdateInfo({
    required this.tagName,
    required this.name,
    required this.body,
    required this.htmlUrl,
    this.publishedAt,
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

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      tagName: json['tag_name'] as String? ?? '',
      name: json['name'] as String? ?? '',
      body: json['body'] as String? ?? '',
      htmlUrl: json['html_url'] as String? ?? '',
      publishedAt: _parseDate(json['published_at']),
    );
  }

  /// 版本展示文本：优先展示标签，去掉前导 `v`。
  String get version => normalizeVersion(tagName);
}

DateTime? _parseDate(dynamic value) {
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}

class UpdateService {
  UpdateService({
    Dio? dio,
    String? currentVersion,
    String repoPath = 'ldm0715/hyb_farm_desktop',
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
       _repoPath = repoPath;

  final Dio _dio;
  final String _currentVersion;
  final String _repoPath;

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
}
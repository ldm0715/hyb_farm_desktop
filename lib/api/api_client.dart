/// 统一 HTTP 客户端：Cookie 注入、GET 去重、错误映射。
library;

import 'package:dio/dio.dart';
import 'package:hyb_farm_desktop/api/models.dart';
import 'package:hyb_farm_desktop/core/constants.dart';
import 'package:hyb_farm_desktop/core/farm_connection_state.dart';
import 'package:hyb_farm_desktop/core/request_failure_classifier.dart';

/// 认证失效异常：仅在确认 401 或已验证的"未登录"业务错误时抛出。
class AuthExpiredException implements Exception {
  const AuthExpiredException([this.message = '登录已失效']);

  final String message;

  @override
  String toString() => message;
}

/// 业务失败异常（success: false）。
class ApiBusinessException implements Exception {
  const ApiBusinessException(this.code, this.message);

  final int? code;
  final String message;

  @override
  String toString() => message;
}

/// 网络/传输异常（超时、DNS、无法解析等临时错误）。
class ApiNetworkException implements Exception {
  const ApiNetworkException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Cloudflare 人机验证异常：请求被安全验证拦截。
class ChallengeException implements Exception {
  const ChallengeException(this.diagnostics);

  final ConnectionDiagnostics diagnostics;

  @override
  String toString() => '需要安全验证';
}

/// 频率限制异常：请求过于频繁，可能携带下次重试时间。
class RateLimitedException implements Exception {
  const RateLimitedException([this.retryAfter]);

  final DateTime? retryAfter;

  @override
  String toString() => '请求过于频繁';
}

/// 统一 HTTP 客户端。Cookie 由 AuthService 通过 [setCookie] 注入，不输出到日志。
class ApiClient {
  ApiClient({Dio? dio, HttpClientAdapter? adapter})
    : _dio = dio ?? Dio(_baseOptions()) {
    if (adapter != null) {
      _dio.httpClientAdapter = adapter;
    }
  }

  final Dio _dio;

  /// 当前会话 Cookie；为空时不附加 Cookie header。
  String? cookie;

  /// 分类结果回调：每个请求分类后上报（无论成功或失败），用于驱动连接状态。
  /// 注入时机在 main.dart，避免 ApiClient 直接依赖状态 Store。
  void Function(ClassificationResult result)? onClassified;

  /// 记录同 URL 的 GET in-flight Future，并发重复请求复用同一结果。
  final Map<String, Future<dynamic>> _inflightGet = {};

  static BaseOptions _baseOptions() => BaseOptions(
    baseUrl: kBaseUrl,
    connectTimeout: kRequestTimeout,
    receiveTimeout: kRequestTimeout,
    sendTimeout: kRequestTimeout,
    headers: {'accept': 'application/json'},
    // 非 2xx 状态码交由 _decode 统一分类：401 判认证失效，403 走 challenge/认证兜底，
    // 5xx 判服务错误，网络/超时判网络错误。若用 dio 默认 validateStatus，401/403 会
    // 直接抛 DioException，认证失效与 challenge 判定都会失效。
    validateStatus: (_) => true,
  );

  void setCookie(String? value) => cookie = value;

  /// 追加 dio 拦截器（如网络日志）。在发请求前调用，保持 ApiClient 不依赖日志模块。
  void addInterceptor(Interceptor interceptor) =>
      _dio.interceptors.add(interceptor);

  /// GET：按完整 URL（含稳定序列化的 query）去重，返回已解包的 data（或整个 map，
  /// 取决于响应结构）。key 纳入 query，避免带不同 query 的同 path 请求误共享。
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) {
    final url = _dio.options.baseUrl + path + _stableQuery(query);
    final existing = _inflightGet[url];
    if (existing != null) return existing;

    final future = _request('GET', path, query: query);
    _inflightGet[url] = future;
    // whenComplete 返回的 future 会继承原 future 的错误，忽略它避免未处理异步异常。
    future.whenComplete(() => _inflightGet.remove(url)).ignore();
    return future;
  }

  /// query 稳定序列化：key 排序后拼成 `?k=v&...`，保证同参数顺序一致的去重 key。
  static String _stableQuery(Map<String, dynamic>? query) {
    if (query == null || query.isEmpty) return '';
    final keys = query.keys.toList()..sort();
    final parts = keys.map((k) => '$k=${query[k]}').toList();
    return '?${parts.join('&')}';
  }

  /// POST：不去重，不通过通用重试器盲目重放。
  Future<dynamic> post(String path, {Object? body}) =>
      _request('POST', path, body: body);

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? body,
  }) async {
    final headers = <String, dynamic>{
      if (cookie != null && cookie!.isNotEmpty) 'cookie': cookie,
      if (body != null) 'content-type': 'application/json',
    };

    try {
      final response = await _dio.request<dynamic>(
        path,
        queryParameters: query,
        data: body,
        options: Options(method: method, headers: headers),
      );
      return _decode(response);
    } on DioException catch (e) {
      final networkResult = _classifyNetworkError(e);
      onClassified?.call(networkResult);
      throw _mapError(e);
    }
  }

  /// 把 Dio 网络异常分类为 networkError 并上报，随后仍按现有语义抛异常。
  ClassificationResult _classifyNetworkError(DioException e) {
    final uri = e.requestOptions.uri;
    return classifyRequest(statusCode: 0, finalUrl: uri.toString());
  }

  dynamic _decode(Response<dynamic> response) {
    final status = response.statusCode ?? 0;
    final data = response.data;
    final headers = _toHeaderMap(response.headers);
    final contentType = _contentType(response);
    final url = response.requestOptions.uri.toString();

    final result = classifyRequest(
      statusCode: status,
      headers: headers,
      body: data,
      contentType: contentType,
      finalUrl: url,
    );

    // 先上报分类结果（抛异常之前），保证无论异常被谁捕获，连接状态都已更新。
    onClassified?.call(result);

    switch (result.state) {
      case FarmConnectionState.authRequired:
        throw const AuthExpiredException();
      case FarmConnectionState.challengeRequired:
        throw ChallengeException(result.diagnostics);
      case FarmConnectionState.rateLimited:
        throw RateLimitedException(result.diagnostics.retryAfter);
      case FarmConnectionState.serverError:
      case FarmConnectionState.networkError:
        throw ApiNetworkException('HTTP $status');
      case FarmConnectionState.healthy:
      case FarmConnectionState.unknownError:
        break;
    }

    // 剩余非 2xx（普通 4xx 非 auth 非 challenge）按网络错误处理。
    if (status < 200 || status >= 300) {
      throw ApiNetworkException('HTTP $status');
    }

    if (data is Map<String, dynamic>) {
      if (data['success'] == false) {
        final err = data['error'];
        final apiError = err is Map<String, dynamic>
            ? ApiError.fromJson(err)
            : const ApiError();
        throw ApiBusinessException(apiError.code, apiError.message ?? '请求失败');
      }
    }
    // 返回完整响应体（不解包 data）：crops 等接口的 data/crops/maxSlots 字段
    // 混在外层，解包会丢失字段。由 FarmApi 各方法按各自结构解析。
    return data;
  }

  Exception _mapError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return ApiNetworkException('网络请求失败');
      default:
        return ApiNetworkException(e.message ?? '网络请求失败');
    }
  }

  /// dio 的 `Headers` → 大小写不敏感可读的 header map。
  static Map<String, List<String>> _toHeaderMap(Headers headers) {
    final map = <String, List<String>>{};
    for (final entry in headers.map.entries) {
      map[entry.key] = entry.value.map((e) => e.toString()).toList();
    }
    return map;
  }

  static String? _contentType(Response<dynamic> response) {
    final ct = response.headers.value(Headers.contentTypeHeader);
    return ct;
  }
}

/// 网络请求日志拦截器（log-only）。
///
/// 挂在 `dio.interceptors`，一处覆盖 GET/POST：
/// - `onRequest`：记录方法、脱敏 URL（丢弃 query）、脱敏 headers、截断 body，并开始计时。
/// - `onResponse`：记录状态码 + 耗时。**不落响应 body**（避免大响应刷爆日志）。
/// - `onError`：记录 `DioExceptionType` + 耗时（传输层错误）。
///
/// 只读、纯记录，不修改请求/响应、不抛错，避免干扰 `ApiClient._decode` 的
/// 分类与 `validateStatus: (_) => true` 语义。注意 4xx/5xx 因 validateStatus 走
/// `onResponse` 而非 `onError`，状态码日志在 `onResponse` 里记录。
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:hyb_farm_desktop/core/farm_connection_state.dart';
import 'package:hyb_farm_desktop/core/log/app_logger.dart';
import 'package:hyb_farm_desktop/core/log/sanitizer.dart';
import 'package:hyb_farm_desktop/core/request_failure_classifier.dart';

class NetworkLogInterceptor extends Interceptor {
  static const _startKey = 'hyb_farm_log_start';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final sw = Stopwatch()..start();
    options.extra[_startKey] = sw;

    final headers = _sanitizeHeaders(options.headers);
    AppLog.i('Network', '${options.method} ${sanitizeUrl(options.uri.toString())}', {
      'headers': headers,
      if (_hasBody(options)) 'body': _truncateBody(options.data),
    });

    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final elapsed = _elapsedMs(response.requestOptions);
    AppLog.i('Network', '${response.requestOptions.method} '
        '${sanitizeUrl(response.requestOptions.uri.toString())} '
        '-> ${response.statusCode}', {
      'ms': elapsed,
    });
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final elapsed = _elapsedMs(err.requestOptions);
    AppLog.w('Network', '${err.requestOptions.method} '
        '${sanitizeUrl(err.requestOptions.uri.toString())} '
        '-> ${err.type.name}', {
      'ms': elapsed,
    });
    handler.next(err);
  }

  static bool _hasBody(RequestOptions options) {
    final d = options.data;
    return d != null && d.toString().isNotEmpty;
  }

  Map<String, dynamic> _sanitizeHeaders(Map<String, dynamic> headers) {
    final out = <String, dynamic>{};
    headers.forEach((k, v) {
      final key = k.toString();
      if (key.toLowerCase() == 'cookie') {
        out[key] = sanitizeCookie(v?.toString());
      } else {
        out[key] = sanitizeValue(v);
      }
    });
    return out;
  }

  static String _truncateBody(Object? body) {
    String text;
    if (body is String) {
      text = body;
    } else {
      try {
        text = jsonEncode(body);
      } catch (_) {
        text = body.toString();
      }
    }
    if (text.length > kBodyInspectLimit) {
      text = text.substring(0, kBodyInspectLimit);
    }
    return sanitizeText(text);
  }

  int _elapsedMs(RequestOptions options) {
    final sw = options.extra[_startKey];
    if (sw is Stopwatch) {
      sw.stop();
      return sw.elapsedMilliseconds;
    }
    return 0;
  }
}

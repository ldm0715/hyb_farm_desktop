/// 敏感信息脱敏纯函数。
///
/// 目标：任何进入日志的文本（错误消息、异常、header、body、extra 字段）在写盘前
/// 都要经过这里，确保 Cookie、token、authorization 等凭证值永不落盘。
///
/// 两条路径：
/// - [`sanitizeValue`] 结构化数据（Map/List）的精确脱敏，按 key 名精确匹配。
/// - [`sanitizeText`] 任意字符串的兜底脱敏，遮蔽 `key=value`/`key: value` 形式中
///   敏感 key 的 value（到下一个 `;` / `\n` 或串尾为止）。
library;

import 'package:hyb_farm_desktop/core/formatters.dart';

/// 敏感 key 名（小写），命中后其 value 整体遮蔽。
const Set<String> _sensitiveKeys = {
  'cookie',
  'set-cookie',
  'authorization',
  'token',
  'access_token',
  'access-token',
  'refresh_token',
  'refresh-token',
  'apikey',
  'api_key',
  'api-key',
  'password',
  'passwd',
  'secret',
  'session',
  'sessionid',
  'session_id',
  'cf_clearance',
  'cf-clearance',
};

/// 遮蔽占位符。
const String _mask = '•••';

/// 匹配 `key=` / `key:`，捕获 key 名与分隔符，不含尾随空白。
final RegExp _kvRe = RegExp(
  r'([A-Za-z][A-Za-z0-9_.\-]*)\s*([=:])',
  caseSensitive: false,
);

/// 对任意字符串做键值对脱敏。命中敏感 key 时遮蔽其 value 到下一个
/// `;` / `\n` 或串尾（宁可过度遮蔽，不泄露凭证值）；其余内容原样保留。
String sanitizeText(String? input) {
  if (input == null || input.isEmpty) return '';
  final matches = _kvRe.allMatches(input).toList();
  if (matches.isEmpty) return input;

  final buf = StringBuffer();
  var last = 0;
  for (final m in matches) {
    if (m.start < last) continue; // 已被前一个敏感 value 覆盖的区间跳过。
    buf.write(input.substring(last, m.start));
    final key = m.group(1)!;
    final delim = m.group(2)!;
    if (_isSensitive(key)) {
      buf
        ..write(key)
        ..write(delim)
        ..write(_mask);
      last = _segmentEnd(input, m.end);
    } else {
      buf.write(m.group(0));
      last = m.end;
    }
  }
  buf.write(input.substring(last));
  return buf.toString();
}

/// 返回 value 的结束位置：下一个 `;` 或 `\n`，否则串尾。
int _segmentEnd(String s, int from) {
  var i = from;
  while (i < s.length) {
    final c = s[i];
    if (c == ';' || c == '\n') break;
    i++;
  }
  return i;
}

/// 递归脱敏 map/list，命中敏感 key 的值整体替换为遮蔽占位符。
Object? sanitizeValue(Object? value) {
  if (value is Map) {
    final out = <String, dynamic>{};
    value.forEach((k, v) {
      final key = k.toString();
      if (_isSensitive(key)) {
        out[key] = _mask;
      } else {
        out[key] = sanitizeValue(v);
      }
    });
    return out;
  }
  if (value is List) {
    return value.map(sanitizeValue).toList();
  }
  if (value is String) {
    return sanitizeText(value);
  }
  return value;
}

/// Cookie 脱敏：委托 [`maskCookie`]，保留 key、遮蔽 value。
String sanitizeCookie(String? cookie) => maskCookie(cookie ?? '');

bool _isSensitive(String key) => _sensitiveKeys.contains(key.toLowerCase().trim());

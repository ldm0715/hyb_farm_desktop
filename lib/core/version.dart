/// 版本号比较纯函数（检查更新用）。
///
/// GitHub release 的 `tag_name` 通常带 `v` 前缀（如 `v0.1.3`），当前版本 `kAppVersion`
/// 不带前缀；比较前先归一化。逐段按数字比较，段数不足按 0 补齐，纯数字段降级字符串比较。
library;

/// 去掉开头的 `v`/`V` 前缀与首尾空白。
String normalizeVersion(String v) {
  var s = v.trim();
  if (s.isNotEmpty && (s[0] == 'v' || s[0] == 'V')) {
    s = s.substring(1);
  }
  return s;
}

/// 判断 [candidate] 是否新于 [current]。
bool isNewerVersion(String candidate, String current) {
  final a = normalizeVersion(candidate).split('.');
  final b = normalizeVersion(current).split('.');
  final n = a.length > b.length ? a.length : b.length;
  for (var i = 0; i < n; i++) {
    final as = i < a.length ? a[i].trim() : '0';
    final bs = i < b.length ? b[i].trim() : '0';
    final an = int.tryParse(as);
    final bn = int.tryParse(bs);
    final cmp = (an != null && bn != null)
        ? an.compareTo(bn)
        : as.compareTo(bs);
    if (cmp != 0) return cmp > 0;
  }
  return false;
}
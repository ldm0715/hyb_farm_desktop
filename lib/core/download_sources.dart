/// 更新安装包下载源：第三方镜像模型、候选解析与内置合并策略。
///
/// 第三方镜像为「URL 前缀反代」：`前缀 + 官方完整 URL`（官方 URL 不编码、不带 query/fragment）。
/// 本模块是纯 Dart（不依赖 `dart:io`），供 [SettingsState]（持久化）与 `UpdateService`
/// （下载/校验）共用，便于单测。所有第三方镜像由用户自担风险，项目不保证其安全性、
/// 下载速度与长期可用性。
library;

import 'dart:math';

/// 单个第三方下载镜像（URL 前缀反代）。
class DownloadMirror {
  const DownloadMirror({
    required this.id,
    required this.name,
    required this.prefix,
    this.builtIn = false,
    this.enabled = true,
  });

  /// 稳定标识。内置镜像 ID 固定（升级时按 ID 合并）；自定义为 `custom-<时间戳>-<随机>`。
  final String id;

  /// 展示名（下拉与列表显示）。
  final String name;

  /// URL 前缀，须以 `http(s)://` 开头；尾部 `/` 可有可无（[buildUrl] 归一）。
  final String prefix;

  /// 是否内置：内置只能停用、不能删除；自定义可编辑删除。
  final bool builtIn;

  /// 是否启用：`auto` 模式只尝试启用的镜像。
  final bool enabled;

  DownloadMirror copyWith({
    String? name,
    String? prefix,
    bool? builtIn,
    bool? enabled,
  }) =>
      DownloadMirror(
        id: id,
        name: name ?? this.name,
        prefix: prefix ?? this.prefix,
        builtIn: builtIn ?? this.builtIn,
        enabled: enabled ?? this.enabled,
      );

  /// 前缀 + 完整官方 URL（官方 URL 原样拼接、不编码），归一尾部 `/`。
  String buildUrl(String official) {
    return '${_trailingSlash(prefix)}$official';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'prefix': prefix,
        'builtIn': builtIn,
        'enabled': enabled,
      };

  static DownloadMirror? fromJson(dynamic v) {
    if (v is! Map) return null;
    final id = v['id'];
    final name = v['name'];
    final prefix = v['prefix'];
    if (id is! String || id.isEmpty) return null;
    if (name is! String || name.isEmpty) return null;
    if (prefix is! String || prefix.isEmpty) return null;
    return DownloadMirror(
      id: id,
      name: name,
      prefix: prefix,
      builtIn: v['builtIn'] == true,
      enabled: v['enabled'] != false,
    );
  }
}

/// 单个下载候选：已解析出最终 URL 与来源元信息，供校验策略/日志/UI 来源显示使用，
/// 不反向从 URL 推断来源。
class DownloadCandidate {
  const DownloadCandidate({
    required this.url,
    required this.sourceId,
    required this.sourceName,
    required this.isOfficial,
    this.mirrorPrefix,
  });

  final String url;

  /// 来源稳定标识：`official` 或镜像 [DownloadMirror.id]。
  final String sourceId;

  /// 来源展示名：`官方源` 或镜像 [DownloadMirror.name]。
  final String sourceName;

  /// 是否官方源（官方 URL 直连）。
  final bool isOfficial;

  /// 镜像前缀（**带尾 `/`**）。null 表示官方源；非空时用它拼接同源的
  /// 校验清单 URL（见 [buildCandidateSourceUrl]），保证镜像下载全程不碰官方 GitHub。
  final String? mirrorPrefix;
}

/// 下载源取值：`official` / `auto` / `mirror:<id>`。
const String kDownloadSourceOfficial = 'official';
const String kDownloadSourceAuto = 'auto';

/// 构造指定镜像的 source 值（`mirror:<id>`），避免与 `official`/`auto` 冲突。
String mirrorSource(String id) => 'mirror:$id';

/// 是否为指定镜像 source 值。
bool isMirrorSource(String source) => source.startsWith('mirror:');

/// 风险说明版本号：文案变更时递增；用户已确认版本低于此值则重新提示。
const int kDownloadMirrorRiskVersion = 1;

/// 内置第三方镜像。ID 固定；升级时按 ID 合并，新版可更新 prefix、新增或移除。
const List<DownloadMirror> kDefaultDownloadMirrors = [
  DownloadMirror(
    id: 'gh-proxy',
    name: 'gh-proxy',
    prefix: 'https://gh-proxy.com/',
    builtIn: true,
  ),
  DownloadMirror(
    id: 'ghproxy-net',
    name: 'ghproxy.net',
    prefix: 'https://ghproxy.net/',
    builtIn: true,
  ),
  DownloadMirror(
    id: 'ghfast-top',
    name: 'ghfast.top',
    prefix: 'https://ghfast.top/',
    builtIn: true,
  ),
];

/// 生成自定义镜像稳定 ID：微秒时间戳 + 安全随机后缀，保证唯一（不单靠毫秒时间戳）。
String newCustomMirrorId() {
  final rng = Random.secure();
  final suffix =
      List.generate(8, (_) => rng.nextInt(16).toRadixString(16)).join();
  return 'custom-${DateTime.now().microsecondsSinceEpoch}-$suffix';
}

/// 校验镜像前缀。返回 null 表示合法，否则返回中文错误文案。
///
/// 仅允许合法 HTTPS URL，拒绝 `http`、缺主机名、内嵌 userInfo、query 或 fragment。
String? validateMirrorPrefix(String prefix) {
  final p = prefix.trim();
  if (p.isEmpty) return '前缀不能为空';
  final uri = Uri.tryParse(p);
  if (uri == null || !uri.isAbsolute) return '不是合法的 URL';
  if (uri.scheme != 'https') return '仅支持 https 前缀';
  if (uri.host.isEmpty) return '缺少主机名';
  if (uri.userInfo.isNotEmpty) return '不允许包含用户名或密码';
  if (uri.query.isNotEmpty || uri.fragment.isNotEmpty) {
    return '不允许包含查询参数或片段';
  }
  return null;
}

/// 前缀是否与现有镜像重复（大小写不敏感、忽略尾部 `/`），用于新增/编辑校验。
bool hasDuplicatePrefix(
  List<DownloadMirror> mirrors,
  String prefix, {
  String? excludeId,
}) {
  final norm = _normalizePrefix(prefix).toLowerCase();
  return mirrors.any(
    (m) => m.id != excludeId && _normalizePrefix(m.prefix).toLowerCase() == norm,
  );
}

String _normalizePrefix(String p) {
  var s = p.trim();
  while (s.endsWith('/')) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

/// 归一为带单个尾 `/` 的前缀（拼接 URL 用）。
String _trailingSlash(String p) => p.endsWith('/') ? p : '$p/';

/// 候选同源拼接：镜像候选在官方 URL 前加前缀，官方候选原样返回。
///
/// 用于让校验清单与安装包从同一来源拉取（镜像下载全程不碰官方 GitHub）。
String buildCandidateSourceUrl(DownloadCandidate c, String officialUrl) =>
    c.mirrorPrefix == null ? officialUrl : '${c.mirrorPrefix}$officialUrl';

/// 镜像测速延迟分段文案（毫秒）。
///
/// `<=300` 优秀、`<=1000` 良好、`<=3000` 一般、其余较慢。不可达/HTTP 异常由
/// `MirrorSpeedResult` 单独判定，不走本函数。
String describeMirrorLatencyMs(int ms) {
  if (ms <= 300) return '优秀';
  if (ms <= 1000) return '良好';
  if (ms <= 3000) return '一般';
  return '较慢';
}

/// 解析下载候选列表。
///
/// - `official` / 未知 / 空 / 损坏 → `[官方候选]`
/// - `auto` → 启用镜像按序各一候选 + 末尾官方候选
/// - `mirror:<id>` → 找到且启用 ? `[该镜像候选]` : `[官方候选]`（删除/停用回落官方）
List<DownloadCandidate> resolveDownloadCandidates(
  String official,
  String source,
  List<DownloadMirror> mirrors,
) {
  DownloadCandidate officialCandidate() => DownloadCandidate(
        url: official,
        sourceId: kDownloadSourceOfficial,
        sourceName: '官方源',
        isOfficial: true,
      );

  if (source == kDownloadSourceOfficial) {
    return [officialCandidate()];
  }

  if (source == kDownloadSourceAuto) {
    final list = <DownloadCandidate>[
      for (final m in mirrors)
        if (m.enabled)
          DownloadCandidate(
            url: m.buildUrl(official),
            sourceId: m.id,
            sourceName: m.name,
            isOfficial: false,
            mirrorPrefix: _trailingSlash(m.prefix),
          ),
    ];
    list.add(officialCandidate());
    return list;
  }

  // 指定镜像（或损坏的其它值）：按 `mirror:<id>` 解析，找不到或停用则回落官方。
  final id = isMirrorSource(source)
      ? source.substring('mirror:'.length)
      : source;
  for (final m in mirrors) {
    if (m.id == id && m.enabled) {
      return [
        DownloadCandidate(
          url: m.buildUrl(official),
          sourceId: m.id,
          sourceName: m.name,
          isOfficial: false,
          mirrorPrefix: _trailingSlash(m.prefix),
        ),
      ];
    }
  }
  return [officialCandidate()];
}

/// 候选列表中是否包含第三方镜像来源。
bool usesThirdPartyMirror(List<DownloadCandidate> candidates) =>
    candidates.any((c) => !c.isOfficial);

/// 该 source 在给定镜像下是否会产生第三方候选（用于 UI 风险确认门控，与解析后判定等价）。
bool sourceUsesThirdParty(String source, List<DownloadMirror> mirrors) {
  if (source == kDownloadSourceAuto) {
    return mirrors.any((m) => m.enabled);
  }
  if (isMirrorSource(source)) {
    final id = source.substring('mirror:'.length);
    return mirrors.any((m) => m.id == id && m.enabled);
  }
  return false;
}

/// 合并持久化镜像列表与新版内置定义，防止旧持久化列表永久覆盖新版内置。
///
/// - 幸存内置（persisted 有、defaults 也有同 id）：保留用户 `enabled` 与顺序位置，
///   `name`/`prefix` 用新版 defaults 覆盖。
/// - 新版新增内置（defaults 有、persisted 无）：追加到末尾（`enabled` 默认 true）。
/// - 新版移除内置（persisted 有且 `builtIn`、defaults 无）：丢弃。
/// - 自定义镜像：原样保留（顺序/enabled/name/prefix）。
List<DownloadMirror> mergeDownloadMirrors(
  List<DownloadMirror> persisted,
  List<DownloadMirror> defaults,
) {
  final byId = {for (final d in defaults) d.id: d};
  final merged = <DownloadMirror>[];
  final seenIds = <String>{};

  for (final p in persisted) {
    final def = byId[p.id];
    if (def != null) {
      merged.add(def.copyWith(enabled: p.enabled));
      seenIds.add(p.id);
    } else if (!p.builtIn) {
      merged.add(p);
      seenIds.add(p.id);
    }
    // 内置 id 已在新版移除（builtIn 且不在 defaults）→ 丢弃。
  }

  for (final d in defaults) {
    if (seenIds.contains(d.id)) continue;
    merged.add(d);
  }
  return merged;
}

/// 镜像测速结果的共享数据源（`ChangeNotifier`），供镜像列表对话框与下载源下拉共用，
/// 两处展示同一份延迟、避免重复测速。
///
/// - **60s TTL**：`refreshIfStale` 在结果新鲜时跳过，不重复打请求。
/// - **single-flight**：`refresh` 进行中重复调用直接返回。
/// - **镜像变更失效**：镜像增删/prefix 修改后调用 `invalidate()` 清缓存并递增版本号，
///   正在进行的过期测速结果会被丢弃（不写入、不计新鲜），下次 `refreshIfStale` 重测。
/// - **try/finally**：`_testing` 在任何失败路径都复位。
/// - 不依赖 [SettingsState]：镜像列表由调用方传入（符合「服务不依赖 SettingsState」）。
library;

import 'package:flutter/foundation.dart';
import 'package:hyb_farm_desktop/core/download_sources.dart';
import 'package:hyb_farm_desktop/core/log/app_logger.dart';
import 'package:hyb_farm_desktop/services/update_service.dart';

class MirrorLatencyStore extends ChangeNotifier {
  MirrorLatencyStore({
    required this.updateService,
    this.ttl = const Duration(seconds: 60),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final UpdateService updateService;

  /// 测速结果新鲜窗口。
  final Duration ttl;

  final DateTime Function() _now;

  final Map<String, MirrorSpeedResult> _results = {};
  DateTime? _testedAt;
  bool _testing = false;
  int _version = 0;

  /// 按镜像 id 的测速结果（不可变快照）。
  Map<String, MirrorSpeedResult> get results => Map.unmodifiable(_results);

  /// 是否正在测速。
  bool get testing => _testing;

  /// 是否已有新鲜结果（用于 UI 占位）。
  bool get hasResults => _testedAt != null && _results.isNotEmpty;

  MirrorSpeedResult? resultFor(String id) => _results[id];

  /// 镜像列表变更（增删/prefix 修改等）后调用：清缓存、递增版本号，强制下次重测。
  ///
  /// 正在进行的测速若基于旧列表，其版本号与当前不符，结果会被丢弃。
  void invalidate() {
    _version++;
    _results.clear();
    _testedAt = null;
    notifyListeners();
  }

  /// 结果新鲜（< [ttl]）则跳过，否则执行 [refresh]。
  Future<void> refreshIfStale(List<DownloadMirror> mirrors) async {
    if (mirrors.isEmpty) return;
    final now = _now();
    if (_testedAt != null && now.difference(_testedAt!) < ttl) return;
    await refresh(mirrors);
  }

  /// 强制测速；进行中重复调用直接返回（single-flight）。
  Future<void> refresh(List<DownloadMirror> mirrors) async {
    if (mirrors.isEmpty) return;
    if (_testing) return;
    _testing = true;
    _results.clear();
    final version = _version;
    notifyListeners();
    try {
      // 用最新版本安装包 URL 测速；拉不到（api.github.com 不可达）退化为测镜像前缀根。
      String? installerUrl;
      try {
        installerUrl = (await updateService.fetchLatest()).installerUrl;
      } catch (e) {
        AppLog.w('Update', '测速获取最新版本失败，改用镜像前缀根测速', {
          'error': e.toString(),
        });
      }
      final entries = await Future.wait(
        mirrors.map(
          (m) async =>
              MapEntry(m.id, await updateService.testMirrorLatency(m, installerUrl: installerUrl)),
        ),
      );
      // 测速期间列表已变更 → 丢弃过期结果，保持已清空状态等待重测。
      if (version != _version) return;
      _results
        ..clear()
        ..addEntries(entries);
      _testedAt = _now();
    } finally {
      _testing = false;
      notifyListeners();
    }
  }
}

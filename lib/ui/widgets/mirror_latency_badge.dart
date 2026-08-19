/// 镜像测速延迟徽标：镜像列表与下载页共用的美化展示。
///
/// 颜色分级：优秀/良好（≤1000ms）→ `success`（绿）、一般/较慢（>1000ms）→ `warning`
/// （琥珀）、不可达/异常 → `error`（红）、测速中 → `textTertiary`。无结果且未测速时
/// 不占位（`SizedBox.shrink`）。背景色由语义色 `withValues(alpha: 0.12)` 派生，亮暗自适应。
library;

import 'package:flutter/material.dart';
import 'package:hyb_farm_desktop/services/update_service.dart';
import 'package:hyb_farm_desktop/theme/farm_theme.dart';

class MirrorLatencyBadge extends StatelessWidget {
  const MirrorLatencyBadge({
    super.key,
    required this.result,
    required this.testing,
  });

  final MirrorSpeedResult? result;

  /// Store 是否正在测速。
  final bool testing;

  @override
  Widget build(BuildContext context) {
    final colors = FarmColorScheme.of(context);
    if (testing) {
      return _pill(
        color: colors.textTertiary,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                valueColor: AlwaysStoppedAnimation<Color>(colors.textTertiary),
              ),
            ),
            const SizedBox(width: 6),
            Text('测速中…', style: _style(colors, colors.textTertiary)),
          ],
        ),
      );
    }
    final label = result?.label;
    if (label == null) return const SizedBox.shrink();
    return _pill(color: _tone(colors), child: Text(label, style: _style(colors, _tone(colors))));
  }

  Color _tone(FarmColorScheme colors) {
    final r = result;
    if (r == null) return colors.textTertiary;
    if (!r.reachable || !r.usable) return colors.error;
    // 优秀/良好（≤1000ms）绿；一般/较慢（>1000ms）琥珀。
    return (r.latencyMs ?? 0) <= 1000 ? colors.success : colors.warning;
  }

  TextStyle _style(FarmColorScheme colors, Color tone) =>
      FarmTextStyles.plotStatus.copyWith(color: tone, fontWeight: FontWeight.w600);

  Widget _pill({required Color color, required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(FarmRadii.small),
      ),
      child: child,
    );
  }
}

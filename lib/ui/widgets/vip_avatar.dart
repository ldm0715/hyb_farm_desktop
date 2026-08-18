/// VIP 金色光环头像：非 VIP 与原 ClipOval 完全一致；VIP 时外圈包金色描边圆环 + 3 层外侧光晕。
///
/// 光环 = 金色描边圆环（border，绘制在 child 之上）+ 3 层向外扩散的 boxShadow 光晕
/// （blur 6/7/8，alpha 0.5/0.4/0.25）。boxShadow 绘制在 child 之下、由头像 ClipOval
/// 自身遮挡内部，故光晕只在外侧，不污染头像图片。
/// 颜色取 FarmColorScheme.gold 语义令牌（亮/暗自适应，与排行第 1 徽章同源），
/// 不引入 Color(0x...) 字面量、不按 brightness 分支。
library;

import 'package:flutter/material.dart';

import '../../theme/farm_theme.dart';

class VipAvatar extends StatelessWidget {
  const VipAvatar({
    required this.avatar,
    required this.size,
    required this.isVip,
    this.iconSize = 22,
    super.key,
  });

  /// 头像 URL（空则显示占位图标）。
  final String avatar;

  /// 头像尺寸（宽高一致，不含光环外扩）。
  final double size;

  /// 是否为 VIP（决定是否渲染金色光环）。
  final bool isVip;

  /// 占位/兜底图标尺寸。
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final colors = FarmColorScheme.of(context);
    final avatarWidget = ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: avatar.isEmpty
            ? Icon(Icons.person, color: colors.textSecondary, size: iconSize)
            : Image.network(
                avatar,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Icon(
                  Icons.person,
                  color: colors.textSecondary,
                  size: iconSize,
                ),
              ),
      ),
    );
    if (!isVip) return avatarWidget;
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // 金色描边圆环本体：绘制在 child 之上，紧贴头像边缘。
        border: Border.all(color: colors.gold, width: 2),
        // 3 层光晕：只在外侧（内部被头像自身遮挡），从内到外 blur 6/7/8。
        boxShadow: [
          BoxShadow(color: colors.gold.withValues(alpha: 0.5), blurRadius: 6),
          BoxShadow(color: colors.gold.withValues(alpha: 0.4), blurRadius: 7),
          BoxShadow(color: colors.gold.withValues(alpha: 0.25), blurRadius: 8),
        ],
      ),
      child: avatarWidget,
    );
  }
}

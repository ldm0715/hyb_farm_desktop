/// 空状态：统一「图标 + 标题 + 可选副文案 + 可选操作」的轻量空态。
///
/// 不引入插画资产，仅用 Material Icon + 文案，保持自然安静的气质。
library;

import 'package:flutter/material.dart';

import '../../theme/farm_theme.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = FarmColorScheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: colors.textTertiary),
          const SizedBox(height: FarmSpacing.sm),
          Text(
            title,
            textAlign: TextAlign.center,
            style: FarmTextStyles.bodyEmphasis.copyWith(
              color: colors.textPrimary,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: FarmSpacing.xxs),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: FarmTextStyles.bodySecondary.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: FarmSpacing.sm),
            action!,
          ],
        ],
      ),
    );
  }
}

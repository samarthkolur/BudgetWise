import 'package:budgetwise/core/theme/app_theme.dart';
import 'package:budgetwise/core/theme/app_typography.dart';
import 'package:budgetwise/core/theme/category_icons.dart';
import 'package:budgetwise/core/widgets/bento.dart';
import 'package:budgetwise/core/widgets/motion.dart';
import 'package:budgetwise/features/budget/domain/models.dart';
import 'package:flutter/material.dart';

/// One category, as a shadowed grid tile: icon, name, spend-of-budget, and a
/// bar that changes colour before the limit rather than at it.
///
/// This is deliberately compact — a two-column grid tile has no room for the
/// reallocation-suggestion text the previous row layout carried alongside an
/// over-budget category, so that suggestion now surfaces in Alerts instead
/// (same `suggestReallocation` call, different presentation).
class CategoryCard extends StatelessWidget {
  const CategoryCard({required this.category, this.onTap, super.key});

  final CategorySpend category;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final progress = category.progress;
    final status = scheme.statusColor(progress.status);
    final isExceeded = progress.isExceeded;

    return PressableScale.onTap(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(Gap.md),
        decoration: AppTheme.card(scheme, radius: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconBadge(
                  icon: categoryIconFor(category.key),
                  tone: isExceeded ? status : null,
                  size: 30,
                  iconSize: 15,
                ),
                Gap.w8,
                Expanded(
                  child: Text(
                    category.name,
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            Gap.h8,
            Text(
              '${category.spent.formatCompact()} of ${category.allocated.formatCompact()}',
              style: theme.textTheme.bodySmall?.money,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Gap.h8,
            FlatBar(value: progress.displayRatio, color: status, height: 4),
            if (isExceeded) ...[
              Gap.h4,
              Text(
                '${progress.overspend.formatCompact()} over',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: status,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

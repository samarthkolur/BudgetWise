import 'package:budgetwise/core/theme/app_theme.dart';
import 'package:budgetwise/core/theme/app_typography.dart';
import 'package:budgetwise/core/widgets/bento.dart';
import 'package:budgetwise/features/budget/domain/models.dart';
import 'package:budgetwise_domain/budgetwise_domain.dart';
import 'package:flutter/material.dart';

/// One category: allocation, spend, remaining, and a bar that changes colour
/// before the limit rather than at it.
///
/// Over budget, the card states the overspend as its own figure and names a
/// category with room to cover it — a suggestion only. Moving the money
/// automatically would rewrite a plan the user made.
class CategoryCard extends StatelessWidget {
  const CategoryCard({
    required this.category,
    required this.categoryNames,
    this.suggestion,
    this.onTap,
    super.key,
  });

  final CategorySpend category;
  final Map<String, String> categoryNames;
  final ReallocationSuggestion? suggestion;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final progress = category.progress;
    final status = scheme.statusColor(progress.status);
    final isExceeded = progress.isExceeded;

    return BentoTile(
      onTap: onTap,
      tone: isExceeded ? scheme.exceeded : null,
      padding: const EdgeInsets.all(Gap.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // A tinted glyph square rather than a bare emoji: it gives every
              // row the same left edge whatever the icon's width.
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text(
                  category.icon,
                  style: const TextStyle(fontSize: 17),
                ),
              ),
              Gap.w12,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(category.name, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 1),
                    Text(
                      '${category.spent.formatCompact()} of ${category.allocated.formatCompact()}',
                      style: theme.textTheme.bodySmall?.money,
                    ),
                  ],
                ),
              ),
              Gap.w8,
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    isExceeded
                        ? '−${progress.overspend.formatCompact()}'
                        : progress.remaining.formatCompact(),
                    style: theme.textTheme.titleSmall?.money.copyWith(
                      color: status,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    isExceeded ? 'over' : 'left',
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
            ],
          ),
          Gap.h12,
          FlatBar(value: progress.displayRatio, color: status, height: 5),
          if (suggestion != null) ...[
            Gap.h12,
            _Suggestion(
              suggestion: suggestion!,
              sourceName:
                  categoryNames[suggestion!.fromKey] ?? suggestion!.fromKey,
            ),
          ],
        ],
      ),
    );
  }
}

class _Suggestion extends StatelessWidget {
  const _Suggestion({required this.suggestion, required this.sourceName});

  final ReallocationSuggestion suggestion;
  final String sourceName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.auto_awesome_outlined, size: 14, color: scheme.advisory),
          Gap.w8,
          Expanded(
            child: Text(
              '$sourceName has ${suggestion.availableAtSource.formatCompact()} spare — '
              'you could move ${suggestion.amount.formatCompact()} across.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

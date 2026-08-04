import 'package:budgetwise/core/budget/budget_math.dart';
import 'package:budgetwise/core/theme/app_theme.dart';
import 'package:budgetwise/features/budget/domain/models.dart';
import 'package:flutter/material.dart';

/// One category: allocation, spend, remaining, and a bar that changes colour
/// before the limit rather than at it.
///
/// When the category is over budget the card states the overspend as its own
/// figure and, if some other category has room, names where the money could
/// come from. It only ever suggests — moving the money would rewrite a plan the
/// user made.
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
    final progress = category.progress;
    final statusColor = theme.colorScheme.statusColor(progress.status);

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(category.icon, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      category.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    progress.isExceeded
                        ? '${progress.overspend.formatCompact()} over'
                        : '${progress.remaining.formatCompact()} left',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: LinearProgressIndicator(
                  value: progress.displayRatio,
                  minHeight: 7,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(statusColor),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${category.spent.formatCompact()} of ${category.allocated.formatCompact()}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    '${(progress.ratio * 100).toStringAsFixed(0)}%',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: statusColor,
                    ),
                  ),
                ],
              ),
              if (suggestion != null) ...[
                const SizedBox(height: 12),
                _SuggestionChip(
                  suggestion: suggestion!,
                  sourceName:
                      categoryNames[suggestion!.fromKey] ?? suggestion!.fromKey,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.suggestion, required this.sourceName});

  final ReallocationSuggestion suggestion;
  final String sourceName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.lightbulb_outline, size: 16),
          const SizedBox(width: 8),
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

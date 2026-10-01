import 'package:budgetwise/core/theme/app_theme.dart';
import 'package:budgetwise/core/widgets/bento.dart';
import 'package:budgetwise/features/insights/domain/insight_rules.dart';
import 'package:flutter/material.dart';

/// The assistant surface — guidance addressed to the user, in the second
/// person, with the reasoning attached.
///
/// **These are rule-based, not model-generated, and the UI says so.** The PRD
/// puts AI coaching in a future release; presenting deterministic thresholds as
/// if a model produced them would be a lie the user cannot check, and would
/// make the eventual real thing indistinguishable from the placeholder. The
/// surface is shaped for a model to fill later — one observation, one reason,
/// one optional action — but the footer reads "based on your budget rules"
/// until one actually does.
class AdvisorCard extends StatelessWidget {
  const AdvisorCard({
    required this.insight,
    this.onAction,
    this.actionLabel,
    super.key,
  });

  final Insight insight;
  final VoidCallback? onAction;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final tone = switch (insight.tone) {
      InsightTone.warning => scheme.warning,
      InsightTone.celebration => scheme.healthy,
      InsightTone.info => scheme.advisory,
    };

    final icon = switch (insight.tone) {
      InsightTone.warning => Icons.trending_up_rounded,
      InsightTone.celebration => Icons.check_circle_outline_rounded,
      InsightTone.info => Icons.auto_awesome_outlined,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gap.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(icon: icon, tone: tone),
          Gap.w12,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(insight.title, style: theme.textTheme.titleSmall),
                Gap.h4,
                Text(insight.body, style: theme.textTheme.bodyMedium),
                if (onAction != null && actionLabel != null) ...[
                  Gap.h8,
                  OutlinedButton(
                    onPressed: onAction,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 38),
                      padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
                    ),
                    child: Text(actionLabel!),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The header above a run of [AdvisorCard]s.
///
/// Carries the honesty note about where the guidance comes from, once, rather
/// than repeating it on every card.
class AdvisorHeader extends StatelessWidget {
  const AdvisorHeader({required this.subtitle, super.key});

  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      children: [
        IconBadge(icon: Icons.auto_awesome, tone: scheme.advisory),
        Gap.w12,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('What we noticed', style: theme.textTheme.titleMedium),
              Text(subtitle, style: theme.textTheme.labelSmall),
            ],
          ),
        ),
      ],
    );
  }
}

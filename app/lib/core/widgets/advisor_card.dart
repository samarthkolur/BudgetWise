import 'package:budgetwise/core/theme/app_theme.dart';
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

    return Container(
      padding: const EdgeInsets.all(Gap.lg),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 17, color: tone),
              ),
              Gap.w12,
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(insight.title, style: theme.textTheme.titleSmall),
                ),
              ),
            ],
          ),
          Gap.h8,
          Padding(
            padding: const EdgeInsets.only(left: 42),
            child: Text(insight.body, style: theme.textTheme.bodyMedium),
          ),
          if (onAction != null && actionLabel != null) ...[
            Gap.h12,
            Padding(
              padding: const EdgeInsets.only(left: 42),
              child: OutlinedButton(
                onPressed: onAction,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 38),
                  padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
                ),
                child: Text(actionLabel!),
              ),
            ),
          ],
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
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: scheme.advisory.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(Icons.auto_awesome, size: 18, color: scheme.advisory),
        ),
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

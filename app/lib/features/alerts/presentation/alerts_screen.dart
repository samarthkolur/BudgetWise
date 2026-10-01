import 'package:budgetwise/core/providers.dart';
import 'package:budgetwise/core/theme/app_theme.dart';
import 'package:budgetwise/core/widgets/advisor_card.dart';
import 'package:budgetwise/core/widgets/async_view.dart';
import 'package:budgetwise/core/widgets/bento.dart';
import 'package:budgetwise/features/budget/domain/models.dart';
import 'package:budgetwise/features/insights/domain/insight_rules.dart';
import 'package:budgetwise_domain/budgetwise_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Alerts — everything the app already knows worth telling the user, in one
/// feed.
///
/// Every item here is derived from state the app already computes elsewhere:
/// the same rule-based [generateInsights] the Home screen's advisor cards
/// render, the same savings-confirmation fields the savings-reminder card
/// uses, and the same streak progress the investing-unlock section shows. There is
/// no separate "notifications" data model and no fabricated content — an item
/// with no real trigger (a subscription renewal, an income credit) simply
/// isn't included, because there is nothing here to derive it from.
class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = Period.current();
    final summary = ref.watch(budgetSummaryProvider(period));

    return Scaffold(
      appBar: AppBar(title: const Text('Alerts')),
      body: AsyncView(
        value: summary,
        onRetry: () => ref.invalidate(budgetSummaryProvider),
        builder: (data) {
          if (data == null) {
            return const EmptyView(
              icon: Icons.notifications_none_rounded,
              title: 'Nothing to show yet',
              message: 'Set up this month to start seeing alerts here.',
            );
          }
          return _AlertsBody(summary: data);
        },
      ),
    );
  }
}

class _AlertsBody extends ConsumerWidget {
  const _AlertsBody({required this.summary});

  final BudgetSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider(summary.budgetId));
    final unlock = ref.watch(investingStatusProvider);

    return AsyncView(
      value: categories,
      onRetry: () => ref.invalidate(categoriesProvider),
      builder: (list) {
        // The rule-based insights already cover a "savings pending" note, but
        // only in the last week of the month — Alerts shows it for as long as
        // it's actually true, the same window SavingsReminderCard uses, so
        // it's built here instead and the generated one is dropped to avoid
        // showing the same fact twice.
        final items = generateInsights(summary: summary, categories: list)
            .where(
              (i) =>
                  i.kind != 'savings_pending' && i.kind != 'savings_complete',
            )
            .toList();

        if (!summary.savingsTarget.isZero) {
          items.insert(
            0,
            summary.isSavingsConfirmed || summary.savingsOutstanding.isZero
                ? Insight(
                    kind: 'savings_confirmed',
                    tone: InsightTone.celebration,
                    title: 'Savings locked in',
                    body:
                        '${summary.savedActual.formatCompact()} saved this month.',
                  )
                : Insight(
                    kind: 'savings_reminder',
                    tone: InsightTone.warning,
                    title: 'Savings still pending',
                    body:
                        'Move ${summary.savingsOutstanding.formatCompact()} to '
                        'your savings account, then confirm it on Home.',
                  ),
          );
        }

        final claim = unlock.value;
        if (claim != null) {
          items.add(
            claim.isUnlocked
                ? const Insight(
                    kind: 'investing_unlocked',
                    tone: InsightTone.celebration,
                    title: 'Investing is unlocked',
                    body:
                        'You built the habit first. Investing features are '
                        'available from here on.',
                  )
                : Insight(
                    kind: 'streak_progress',
                    tone: InsightTone.info,
                    title: '${claim.streakMonths} of 6 months saved',
                    body: claim.monthsRemaining > 0
                        ? '${claim.monthsRemaining} more consistent month'
                              '${claim.monthsRemaining == 1 ? "" : "s"} unlocks investing.'
                        : 'Keep the streak going to unlock investing.',
                  ),
          );
        }

        // Reallocation suggestions — the Home category grid is too compact
        // for this text, so it surfaces here instead. Same domain call the
        // old row layout used, just a different presentation.
        final byKey = {for (final c in list) c.key: c.progress};
        final names = {for (final c in list) c.key: c.name};
        for (final category in list) {
          if (!category.progress.isExceeded) continue;
          final suggestion = suggestReallocation(
            overspend: category.progress.overspend,
            categories: byKey,
            excludingKey: category.key,
          );
          if (suggestion == null) continue;
          final sourceName = names[suggestion.fromKey] ?? suggestion.fromKey;
          items.add(
            Insight(
              kind: 'reallocation_suggestion',
              tone: InsightTone.info,
              title: 'Move money into ${category.name}?',
              body:
                  '$sourceName has ${suggestion.availableAtSource.formatCompact()} '
                  'spare — you could move ${suggestion.amount.formatCompact()} across.',
            ),
          );
        }

        if (items.isEmpty) {
          return const EmptyView(
            icon: Icons.notifications_none_rounded,
            title: 'Nothing needs your attention',
            message: 'Alerts show up here as they become relevant.',
          );
        }

        final scheme = Theme.of(context).colorScheme;
        return ListView(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.xxl),
          children: [
            const AdvisorHeader(subtitle: 'Based on your budget rules'),
            Gap.h16,
            Container(
              padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
              decoration: AppTheme.card(scheme),
              child: ListSection(
                children: [
                  for (final item in items) AdvisorCard(insight: item),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

import 'package:budgetwise/core/providers.dart';
import 'package:budgetwise_domain/budgetwise_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Runs the on-device SMS scan and records anything that parses as a debit.
///
/// A no-op unless Android, the setting is on, and permission is already
/// granted — it never requests permission or shows any UI itself. That's the
/// Settings screen's job, paired with the rationale dialog Play policy
/// expects before the system prompt.
class SmsDetectionController extends Notifier<void> {
  @override
  void build() {}

  Future<void> checkForNewTransactions(String budgetId) async {
    if (!ref.read(smsCapableProvider)) return;

    final settings = ref.read(smsDetectionSettingsRepositoryProvider);
    if (!await settings.isEnabled()) return;
    if (!await ref.read(smsPermissionServiceProvider).hasPermission()) {
      return;
    }

    // First-ever run has no checkpoint: 7 days is enough to catch what's
    // accumulated since the user turned the feature on, without dumping
    // months of backlog into one popup.
    final since =
        await settings.lastCheckedAt() ??
        DateTime.now().subtract(const Duration(days: 7));

    final messages = await ref.read(smsReaderProvider)(since);

    final candidates = <({String dedupKey, DetectedTransaction transaction})>[
      for (final message in messages)
        if (SmsTransactionParser.tryParse(
              sender: message.sender,
              body: message.body,
              receivedAt: message.receivedAt,
            )
            case final transaction?)
          (dedupKey: message.dedupKey, transaction: transaction),
    ];

    await ref
        .read(detectedExpenseRepositoryProvider)
        .recordCandidates(budgetId, candidates);
    await settings.markCheckedNow();

    ref.invalidate(pendingDetectedExpensesProvider(budgetId));
  }
}

final smsDetectionControllerProvider =
    NotifierProvider<SmsDetectionController, void>(
      SmsDetectionController.new,
    );

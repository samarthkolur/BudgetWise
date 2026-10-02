import 'dart:io';

import 'package:budgetwise/core/api/api_client.dart';
import 'package:budgetwise/core/api/token_store.dart';
import 'package:budgetwise/core/db/local_database.dart';
import 'package:budgetwise/core/sync/hydration_service.dart';
import 'package:budgetwise/core/sync/sync_queue_repository.dart';
import 'package:budgetwise/core/sync/sync_service.dart';
import 'package:budgetwise/features/auth/data/auth_service.dart';
import 'package:budgetwise/features/auth/data/profile_repository.dart';
import 'package:budgetwise/features/auth/domain/profile.dart';
import 'package:budgetwise/features/budget/data/budget_repository.dart';
import 'package:budgetwise/features/budget/data/syncing_budget_repository.dart';
import 'package:budgetwise/features/budget/domain/models.dart';
import 'package:budgetwise/features/expenses/data/expense_repository.dart';
import 'package:budgetwise/features/expenses/data/syncing_expense_repository.dart';
import 'package:budgetwise/features/goals/data/goal_repository.dart';
import 'package:budgetwise/features/goals/data/syncing_goal_repository.dart';
import 'package:budgetwise/features/sms_detection/data/detected_expense_repository.dart';
import 'package:budgetwise/features/sms_detection/data/sms_detection_settings_repository.dart';
import 'package:budgetwise/features/sms_detection/data/sms_permission_service.dart';
import 'package:budgetwise/features/sms_detection/data/sms_reader.dart';
import 'package:budgetwise_domain/budgetwise_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;
// ProviderOrFamily is not in flutter_riverpod's default export surface; it is
// needed to hold providers of differing types in one list.

/// The app's dependency graph.
///
/// Everything reaches the API through [apiClientProvider] rather than
/// constructing an HTTP client, so a test can override one provider and the
/// whole tree below it talks to a double.

final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());

final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(tokens: ref.watch(tokenStoreProvider));
  ref.onDispose(client.close);
  return client;
});

/// The on-device database, opened once and reused. A plain [Provider] holding
/// a [Future] rather than a [FutureProvider]: repository methods are already
/// async, so they can just await this directly, and nothing has to rebuild a
/// widget tree while the database file opens.
final localDatabaseProvider = Provider<Future<LocalDatabase>>(
  (ref) => LocalDatabase.open(),
);

// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------

final authServiceProvider = Provider<AuthService>(
  (ref) => AuthService(
    api: ref.watch(apiClientProvider),
    tokens: ref.watch(tokenStoreProvider),
  ),
);

/// Whether a session exists on this device.
///
/// With a hosted auth vendor this would be a session stream; with our own API
/// "is there a refresh token in the keystore". It is a [Notifier] rather than a
/// FutureProvider because sign-in and sign-out have to push a new value
/// synchronously — the router listens to this, and a stale answer would leave
/// the user on the wrong screen.
class SessionState extends AsyncNotifier<bool> {
  @override
  Future<bool> build() => ref.watch(tokenStoreProvider).hasSession;

  Future<void> refreshFromStorage() async {
    state = AsyncData(await ref.read(tokenStoreProvider).hasSession);
  }
}

final sessionProvider = AsyncNotifierProvider<SessionState, bool>(
  SessionState.new,
);

final isSignedInProvider = Provider<bool>(
  (ref) => ref.watch(sessionProvider).value ?? false,
);

/// Chooses the API repository when signed in, the on-device one otherwise.
/// The one pattern behind all four repository providers below — screens and
/// controllers only ever depend on the interface, so this is the entire seam
/// between "server-backed" and "local-first".
///
/// Profile has no offline-write path worth queuing — `updateProfile` and
/// `completeOnboarding` are rare, deliberate actions a user can simply retry,
/// unlike an expense logged in the middle of a purchase — so it stays a plain
/// switch rather than going through a `Syncing*` wrapper like budgets,
/// expenses and goals do below.
final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ref.watch(isSignedInProvider)
      ? ApiProfileRepository(ref.watch(apiClientProvider))
      : LocalProfileRepository(ref.watch(localDatabaseProvider)),
);

final profileProvider = FutureProvider<Profile?>(
  (ref) => ref.watch(profileRepositoryProvider).current(),
);

// ---------------------------------------------------------------------------
// Offline-first sync — see core/sync/ for the outbox design.
// ---------------------------------------------------------------------------

final syncQueueRepositoryProvider = Provider<SyncQueueRepository>(
  (ref) => SyncQueueRepository(ref.watch(localDatabaseProvider)),
);

final pendingSyncCountProvider = FutureProvider<int>(
  (ref) => ref.watch(syncQueueRepositoryProvider).count(),
);

final syncServiceProvider = Provider<SyncService>(
  (ref) => SyncService(
    queue: ref.watch(syncQueueRepositoryProvider),
    apiBudgets: ApiBudgetRepository(ref.watch(apiClientProvider)),
    apiExpenses: ApiExpenseRepository(ref.watch(apiClientProvider)),
    apiGoals: ApiGoalRepository(ref.watch(apiClientProvider)),
  ),
);

final hydrationServiceProvider = Provider<HydrationService>(
  (ref) => HydrationService(
    api: ref.watch(apiClientProvider),
    dbFuture: ref.watch(localDatabaseProvider),
  ),
);

// ---------------------------------------------------------------------------
// Budget
// ---------------------------------------------------------------------------

final budgetRepositoryProvider = Provider<BudgetRepository>((ref) {
  if (!ref.watch(isSignedInProvider)) {
    return LocalBudgetRepository(ref.watch(localDatabaseProvider));
  }
  return SyncingBudgetRepository(
    local: LocalBudgetRepository(ref.watch(localDatabaseProvider)),
    remote: ApiBudgetRepository(ref.watch(apiClientProvider)),
    queue: ref.watch(syncQueueRepositoryProvider),
  );
});

final expenseRepositoryProvider = Provider<ExpenseRepository>((ref) {
  if (!ref.watch(isSignedInProvider)) {
    return LocalExpenseRepository(ref.watch(localDatabaseProvider));
  }
  return SyncingExpenseRepository(
    local: LocalExpenseRepository(ref.watch(localDatabaseProvider)),
    remote: ApiExpenseRepository(ref.watch(apiClientProvider)),
    queue: ref.watch(syncQueueRepositoryProvider),
  );
});

final goalRepositoryProvider = Provider<GoalRepository>((ref) {
  if (!ref.watch(isSignedInProvider)) {
    return LocalGoalRepository(ref.watch(localDatabaseProvider));
  }
  return SyncingGoalRepository(
    local: LocalGoalRepository(ref.watch(localDatabaseProvider)),
    remote: ApiGoalRepository(ref.watch(apiClientProvider)),
    queue: ref.watch(syncQueueRepositoryProvider),
  );
});

// ---------------------------------------------------------------------------
// SMS detection — Android only, opt-in, always local. See
// features/sms_detection for why this has no API-backed counterpart: SMS
// only ever exists on the device it arrived on, regardless of sign-in state.
// ---------------------------------------------------------------------------

/// Routed through a provider rather than an inline `Platform.isAndroid`
/// check so widget tests can override it — the same reason every other
/// dependency here is a provider.
final smsCapableProvider = Provider<bool>((ref) => Platform.isAndroid);

final smsPermissionServiceProvider = Provider<SmsPermissionService>(
  (ref) => SmsPermissionService(),
);

final smsReaderProvider = Provider<SmsReader>((ref) => fetchDeviceSmsSince);

final detectedExpenseRepositoryProvider = Provider<DetectedExpenseRepository>(
  (ref) => LocalDetectedExpenseRepository(ref.watch(localDatabaseProvider)),
);

final smsDetectionSettingsRepositoryProvider =
    Provider<SmsDetectionSettingsRepository>(
      (ref) => SmsDetectionSettingsRepository(ref.watch(localDatabaseProvider)),
    );

/// The Settings-screen toggle. A [Notifier] rather than a plain
/// [FutureProvider] for the same reason [SessionState] is one: flipping the
/// switch has to push a new value synchronously so the UI doesn't lag behind
/// the tap.
class SmsDetectionEnabled extends AsyncNotifier<bool> {
  @override
  Future<bool> build() =>
      ref.watch(smsDetectionSettingsRepositoryProvider).isEnabled();

  Future<void> set({required bool enabled}) async {
    await ref
        .read(smsDetectionSettingsRepositoryProvider)
        .setEnabled(enabled: enabled);
    state = AsyncData(enabled);
  }
}

final smsDetectionEnabledProvider =
    AsyncNotifierProvider<SmsDetectionEnabled, bool>(SmsDetectionEnabled.new);

final pendingDetectedExpensesProvider =
    FutureProvider.family<List<DetectedExpense>, String>(
      (ref, budgetId) =>
          ref.watch(detectedExpenseRepositoryProvider).pendingFor(budgetId),
    );

/// The month currently being viewed.
///
/// Held as a provider rather than route state so the dashboard, ledger and
/// export all agree on which month they are talking about.
class SelectedPeriod extends Notifier<Period> {
  @override
  Period build() => Period.current();

  void next() => state = state.next;

  void previous() => state = state.previous;
}

final selectedPeriodProvider = NotifierProvider<SelectedPeriod, Period>(
  SelectedPeriod.new,
);

/// The current month's plan, or null when it has not been created yet.
///
/// Null is not an error — it is the signal the router uses to send the user
/// into onboarding for a new month.
final currentBudgetProvider = FutureProvider<MonthlyBudget?>(
  (ref) => ref.watch(budgetRepositoryProvider).currentBudget(),
);

final budgetSummaryProvider = FutureProvider.family<BudgetSummary?, Period>(
  (ref, period) => ref.watch(budgetRepositoryProvider).summaryFor(period),
);

final expensesProvider = FutureProvider.family<List<Expense>, String>((
  ref,
  budgetId,
) {
  return ref.watch(expenseRepositoryProvider).forBudget(budgetId);
});

final allBudgetsProvider = FutureProvider<List<MonthlyBudget>>(
  (ref) => ref.watch(budgetRepositoryProvider).allBudgets(),
);

final allSummariesProvider = FutureProvider<List<BudgetSummary>>(
  (ref) => ref.watch(budgetRepositoryProvider).allSummaries(),
);

final goalsProvider = FutureProvider<List<Goal>>(
  (ref) => ref.watch(goalRepositoryProvider).all(),
);

/// Locked whenever there is no local database. Investing is a
/// server-verified achievement — see [LocalProfileRepository.investingStatus].
final investingStatusProvider = FutureProvider<UnlockClaim>(
  (ref) => ref.watch(profileRepositoryProvider).investingStatus(),
);

/// Everything a write could have changed.
///
/// Centralised because the alternative — each screen remembering which
/// providers its own write invalidated — is how a dashboard ends up showing a
/// stale total after an expense was added somewhere else.
final _budgetDataProviders = <ProviderOrFamily>[
  currentBudgetProvider,
  budgetSummaryProvider,
  expensesProvider,
  allBudgetsProvider,
  allSummariesProvider,
  goalsProvider,
  investingStatusProvider,
];

/// Riverpod 3 keeps `Ref` and `WidgetRef` as separate types, so the same helper
/// cannot take both. Two extensions over one shared list is the honest version:
/// the list is the single definition, and neither caller can drift from it.
extension BudgetRefresh on WidgetRef {
  void refreshBudgetData() {
    for (final provider in _budgetDataProviders) {
      invalidate(provider);
    }
  }
}

extension BudgetRefreshRef on Ref {
  void refreshBudgetData() {
    for (final provider in _budgetDataProviders) {
      invalidate(provider);
    }
  }
}

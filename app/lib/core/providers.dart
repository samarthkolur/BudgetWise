import 'package:budgetwise/core/api/api_client.dart';
import 'package:budgetwise/core/api/token_store.dart';
import 'package:budgetwise/features/auth/data/google_auth_service.dart';
import 'package:budgetwise/features/auth/data/profile_repository.dart';
import 'package:budgetwise/features/auth/domain/profile.dart';
import 'package:budgetwise/features/budget/data/budget_repository.dart';
import 'package:budgetwise/features/budget/domain/models.dart';
import 'package:budgetwise/features/expenses/data/expense_repository.dart';
import 'package:budgetwise/features/goals/data/goal_repository.dart';
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

// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------

final googleAuthServiceProvider = Provider<GoogleAuthService>(
  (ref) => GoogleAuthService(
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

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ProfileRepository(ref.watch(apiClientProvider)),
);

final profileProvider = FutureProvider<Profile?>((ref) async {
  if (!ref.watch(isSignedInProvider)) return null;
  return ref.watch(profileRepositoryProvider).current();
});

// ---------------------------------------------------------------------------
// Budget
// ---------------------------------------------------------------------------

final budgetRepositoryProvider = Provider<BudgetRepository>(
  (ref) => BudgetRepository(ref.watch(apiClientProvider)),
);

final expenseRepositoryProvider = Provider<ExpenseRepository>(
  (ref) => ExpenseRepository(ref.watch(apiClientProvider)),
);

final goalRepositoryProvider = Provider<GoalRepository>(
  (ref) => GoalRepository(ref.watch(apiClientProvider)),
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
final currentBudgetProvider = FutureProvider<MonthlyBudget?>((ref) async {
  if (!ref.watch(isSignedInProvider)) return null;
  return ref.watch(budgetRepositoryProvider).currentBudget();
});

final budgetSummaryProvider = FutureProvider.family<BudgetSummary?, Period>((
  ref,
  period,
) async {
  if (!ref.watch(isSignedInProvider)) return null;
  return ref.watch(budgetRepositoryProvider).summaryFor(period);
});

final categoriesProvider = FutureProvider.family<List<CategorySpend>, String>((
  ref,
  budgetId,
) {
  return ref.watch(budgetRepositoryProvider).categoriesFor(budgetId);
});

final expensesProvider = FutureProvider.family<List<Expense>, String>((
  ref,
  budgetId,
) {
  return ref.watch(expenseRepositoryProvider).forBudget(budgetId);
});

final allBudgetsProvider = FutureProvider<List<MonthlyBudget>>((ref) async {
  if (!ref.watch(isSignedInProvider)) return const [];
  return ref.watch(budgetRepositoryProvider).allBudgets();
});

final allSummariesProvider = FutureProvider<List<BudgetSummary>>((ref) async {
  if (!ref.watch(isSignedInProvider)) return const [];
  return ref.watch(budgetRepositoryProvider).allSummaries();
});

final goalsProvider = FutureProvider<List<Goal>>((ref) async {
  if (!ref.watch(isSignedInProvider)) return const [];
  return ref.watch(goalRepositoryProvider).all();
});

final investingStatusProvider = FutureProvider<UnlockClaim>((ref) async {
  if (!ref.watch(isSignedInProvider)) {
    return const UnlockClaim(isUnlocked: false);
  }
  return ref.watch(profileRepositoryProvider).investingStatus();
});

/// Everything a write could have changed.
///
/// Centralised because the alternative — each screen remembering which
/// providers its own write invalidated — is how a dashboard ends up showing a
/// stale total after an expense was added somewhere else.
final _budgetDataProviders = <ProviderOrFamily>[
  currentBudgetProvider,
  budgetSummaryProvider,
  categoriesProvider,
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

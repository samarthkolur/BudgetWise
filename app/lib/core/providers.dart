import 'package:budgetwise/core/time/period.dart';
import 'package:budgetwise/features/auth/data/google_auth_service.dart';
import 'package:budgetwise/features/auth/data/profile_repository.dart';
import 'package:budgetwise/features/auth/domain/profile.dart';
import 'package:budgetwise/features/budget/data/budget_repository.dart';
import 'package:budgetwise/features/budget/domain/models.dart';
import 'package:budgetwise/features/expenses/data/expense_repository.dart';
import 'package:budgetwise/features/goals/data/goal_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ProviderOrFamily is not in flutter_riverpod's default export surface; it is
// needed to hold providers of differing types in one list.
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;
import 'package:supabase_flutter/supabase_flutter.dart';

/// The app's dependency graph.
///
/// Everything reaches Supabase through [supabaseClientProvider] rather than
/// `Supabase.instance` directly, so a test can override one provider and the
/// whole tree below it uses the double.

final supabaseClientProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------

final googleAuthServiceProvider = Provider<GoogleAuthService>(
  (ref) => GoogleAuthService(ref.watch(supabaseClientProvider)),
);

/// The live session, straight from Supabase.
///
/// Supabase persists and refreshes sessions itself, so there is no token
/// storage code here and nothing to keep in sync — this stream is the single
/// source of truth for whether anyone is signed in.
final authStateProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(supabaseClientProvider).auth.onAuthStateChange,
);

final currentSessionProvider = Provider<Session?>((ref) {
  // Watch the stream so the provider recomputes on every auth change, but read
  // the client for the answer: the stream's first event arrives asynchronously
  // and a restored session is already present before it does.
  ref.watch(authStateProvider);
  return ref.watch(supabaseClientProvider).auth.currentSession;
});

final isSignedInProvider = Provider<bool>(
  (ref) => ref.watch(currentSessionProvider) != null,
);

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ProfileRepository(ref.watch(supabaseClientProvider)),
);

final profileProvider = FutureProvider<Profile?>((ref) async {
  if (!ref.watch(isSignedInProvider)) return null;
  return ref.watch(profileRepositoryProvider).current();
});

// ---------------------------------------------------------------------------
// Budget
// ---------------------------------------------------------------------------

final budgetRepositoryProvider = Provider<BudgetRepository>(
  (ref) => BudgetRepository(ref.watch(supabaseClientProvider)),
);

final expenseRepositoryProvider = Provider<ExpenseRepository>(
  (ref) => ExpenseRepository(ref.watch(supabaseClientProvider)),
);

final goalRepositoryProvider = Provider<GoalRepository>(
  (ref) => GoalRepository(ref.watch(supabaseClientProvider)),
);

/// The month currently being viewed.
///
/// Defaults to now and is changed by the ledger's month switcher. Held as a
/// provider rather than route state so the dashboard, ledger and export all
/// agree on which month they are talking about.
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
/// Null is not an error here — it is the signal the router uses to send the
/// user into onboarding for a new month.
final currentBudgetProvider = FutureProvider<MonthlyBudget?>((ref) async {
  if (!ref.watch(isSignedInProvider)) return null;
  return ref.watch(budgetRepositoryProvider).budgetFor(Period.current());
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
  return ref.watch(profileRepositoryProvider).claimInvestingUnlock();
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

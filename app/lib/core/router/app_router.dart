import 'package:budgetwise/core/providers.dart';
import 'package:budgetwise/features/auth/presentation/sign_in_screen.dart';
import 'package:budgetwise/features/dashboard/presentation/dashboard_screen.dart';
import 'package:budgetwise/features/goals/presentation/goals_screen.dart';
import 'package:budgetwise/features/insights/presentation/insights_screen.dart';
import 'package:budgetwise/features/ledger/presentation/ledger_screen.dart';
import 'package:budgetwise/features/onboarding/presentation/onboarding_screen.dart';
import 'package:budgetwise/features/settings/presentation/settings_screen.dart';
import 'package:budgetwise/features/shell/presentation/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

abstract final class Routes {
  static const signIn = '/sign-in';
  static const onboarding = '/onboarding';
  static const dashboard = '/dashboard';
  static const ledger = '/ledger';
  static const goals = '/goals';
  static const insights = '/insights';
  static const settings = '/settings';
}

final _shellKey = GlobalKey<NavigatorState>();

/// Routing, including the three questions that decide where a launch lands.
///
/// The redirect is the PRD's opening behaviour expressed as a guard: is anyone
/// signed in, have they finished onboarding, and does this month have a plan
/// yet? Answering the third with the absence of a database row is what lets a
/// returning user go straight to their dashboard while a new month sends them
/// through setup — with no "has the month rolled over" flag to keep correct.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: Routes.dashboard,

    // Re-evaluates the guard whenever auth or the month's plan changes, so
    // signing out or finishing onboarding moves the user without any screen
    // having to navigate imperatively.
    refreshListenable: _RouterRefresh(ref),

    redirect: (context, state) {
      final isSignedIn = ref.read(isSignedInProvider);
      final location = state.matchedLocation;

      if (!isSignedIn) {
        return location == Routes.signIn ? null : Routes.signIn;
      }

      // Signed in. Wait for the month's plan before deciding — redirecting on
      // an unresolved future would bounce the user to onboarding for a moment
      // on every cold start, which reads as a bug even though it corrects
      // itself.
      final budget = ref.read(currentBudgetProvider);
      if (budget.isLoading || budget.hasError) return null;

      final needsOnboarding = budget.value == null;

      if (needsOnboarding) {
        return location == Routes.onboarding ? null : Routes.onboarding;
      }

      if (location == Routes.signIn || location == Routes.onboarding) {
        return Routes.dashboard;
      }
      return null;
    },

    routes: [
      GoRoute(
        path: Routes.signIn,
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: Routes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      ShellRoute(
        navigatorKey: _shellKey,
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: Routes.dashboard,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: DashboardScreen()),
          ),
          GoRoute(
            path: Routes.ledger,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: LedgerScreen()),
          ),
          GoRoute(
            path: Routes.goals,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: GoalsScreen()),
          ),
          GoRoute(
            path: Routes.insights,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: InsightsScreen()),
          ),
          GoRoute(
            path: Routes.settings,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: SettingsScreen()),
          ),
        ],
      ),
    ],
  );
});

/// Bridges Riverpod to go_router's [Listenable]-based refresh.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(this._ref) {
    _ref
      ..listen(sessionProvider, (_, _) => notifyListeners())
      ..listen(currentBudgetProvider, (_, _) => notifyListeners());
  }

  final Ref _ref;
}

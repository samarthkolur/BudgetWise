import 'package:budgetwise/core/providers.dart';
import 'package:budgetwise/core/router/app_router.dart';
import 'package:budgetwise/features/expenses/presentation/expense_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The signed-in frame: five destinations, persistent across navigation.
///
/// Flat by construction — the bar carries a hairline top border rather than an
/// elevation shadow, so it sits in the same plane as everything above it. The
/// one exception is the add-expense button docked in the middle: raised above
/// the bar and larger than the destinations either side of it, because it is
/// the single most frequent action in the app and reachable from every tab,
/// not just the dashboard.
class AppShell extends ConsumerWidget {
  const AppShell({required this.child, super.key});

  final Widget child;

  static const _destinations = <_Destination>[
    _Destination(
      Routes.dashboard,
      Icons.grid_view_outlined,
      Icons.grid_view_rounded,
      'Home',
    ),
    _Destination(
      Routes.ledger,
      Icons.receipt_long_outlined,
      Icons.receipt_long_rounded,
      'Ledger',
    ),
    _Destination(
      Routes.goals,
      Icons.flag_outlined,
      Icons.flag_rounded,
      'Goals',
    ),
    _Destination(
      Routes.insights,
      Icons.auto_awesome_outlined,
      Icons.auto_awesome_rounded,
      'Insights',
    ),
    _Destination(
      Routes.settings,
      Icons.person_outline_rounded,
      Icons.person_rounded,
      'You',
    ),
  ];

  int _indexFor(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final index = _destinations.indexWhere((d) => location.startsWith(d.path));
    return index < 0 ? 0 : index;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final budgetId = ref.watch(currentBudgetProvider).value?.id;

    return Scaffold(
      body: child,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            NavigationBar(
              selectedIndex: _indexFor(context),
              onDestinationSelected: (index) =>
                  context.go(_destinations[index].path),
              destinations: [
                for (final d in _destinations)
                  NavigationDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: d.label,
                  ),
              ],
            ),
            if (budgetId != null)
              Positioned(
                top: -26,
                child: FloatingActionButton(
                  heroTag: 'add-expense',
                  onPressed: () => showExpenseSheet(context, ref, budgetId),
                  child: const Icon(Icons.add_rounded, size: 28),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Destination {
  const _Destination(this.path, this.icon, this.selectedIcon, this.label);

  final String path;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

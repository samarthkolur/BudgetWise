import 'package:budgetwise/core/router/app_router.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// The signed-in frame: five destinations, persistent across navigation.
class AppShell extends StatelessWidget {
  const AppShell({required this.child, super.key});

  final Widget child;

  static const _destinations = <_Destination>[
    _Destination(Routes.dashboard, Icons.home_outlined, Icons.home, 'Home'),
    _Destination(
      Routes.ledger,
      Icons.receipt_long_outlined,
      Icons.receipt_long,
      'Ledger',
    ),
    _Destination(Routes.goals, Icons.flag_outlined, Icons.flag, 'Goals'),
    _Destination(
      Routes.insights,
      Icons.insights_outlined,
      Icons.insights,
      'Insights',
    ),
    _Destination(Routes.settings, Icons.person_outline, Icons.person, 'You'),
  ];

  int _indexFor(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final index = _destinations.indexWhere((d) => location.startsWith(d.path));
    return index < 0 ? 0 : index;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _indexFor(context),
        onDestinationSelected: (index) => context.go(_destinations[index].path),
        destinations: [
          for (final d in _destinations)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: d.label,
            ),
        ],
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

import 'package:budgetwise/core/providers.dart';
import 'package:budgetwise/core/router/app_router.dart';
import 'package:budgetwise/core/theme/app_theme.dart';
import 'package:budgetwise/core/widgets/celebration_overlay.dart';
import 'package:budgetwise/core/widgets/motion.dart';
import 'package:budgetwise/features/expenses/presentation/expense_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The signed-in frame: four destinations plus Add, all as plain, equal
/// items in one bar — no floating action button, no docked/notched button.
///
/// A `FloatingActionButton` (in any of its docked/notched/raised forms) is a
/// widget that belongs to the *outer* Scaffold and is positioned on top of
/// whatever else is on screen, including a modal bottom sheet's own content —
/// that's exactly why it kept visibly overlapping a sheet's Save/Create
/// button once the keyboard pushed things up. Making Add just another button
/// in the bar removes the whole class of problem: it has no special
/// position, no elevation, nothing floats.
///
/// This is also where the investing-unlock celebration is triggered — it
/// watches [investingStatusProvider] for the one real `false → true`
/// transition on the unlock claim's `isUnlocked` flag, never a timer or a
/// re-render, so it plays exactly once per unlock regardless of which tab
/// the user is on when it happens.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  static const _destinations = <_Destination>[
    _Destination(
      Routes.dashboard,
      'Home',
      Icons.grid_view_outlined,
      Icons.grid_view_rounded,
    ),
    _Destination(
      Routes.ledger,
      'Ledger',
      Icons.receipt_long_outlined,
      Icons.receipt_long_rounded,
    ),
    _Destination(
      Routes.goals,
      'Goals',
      Icons.flag_outlined,
      Icons.flag_rounded,
    ),
    _Destination(
      Routes.alerts,
      'Alerts',
      Icons.notifications_none_rounded,
      Icons.notifications_rounded,
    ),
  ];

  int _indexFor(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final index = _destinations.indexWhere((d) => location.startsWith(d.path));
    return index < 0 ? 0 : index;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final budgetId = ref.watch(currentBudgetProvider).value?.id;

    ref.listen(investingStatusProvider, (previous, next) {
      final was = previous?.value?.isUnlocked ?? false;
      final isNow = next.value?.isUnlocked ?? false;
      if (!was && isNow) {
        CelebrationOverlay.show(
          context,
          streakMonths: next.value!.streakMonths,
        );
      }
    });

    final selected = _indexFor(context);

    return Scaffold(
      body: widget.child,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 60,
            child: Row(
              children: [
                for (var i = 0; i < _destinations.length; i++) ...[
                  // Add sits in the middle of the bar — the single most
                  // frequent action, reachable from every tab — as a plain
                  // item in the same row as everything else. Still flat,
                  // still inline: the filled circle is a decoration on this
                  // one icon, not elevation or a different position.
                  if (i == _destinations.length ~/ 2 && budgetId != null)
                    Expanded(
                      child: _AddButton(
                        onTap: () {
                          AppHaptics.tap();
                          showExpenseSheet(context, ref, budgetId);
                        },
                      ),
                    ),
                  Expanded(
                    child: _TabButton(
                      icon: i == selected
                          ? _destinations[i].selectedIcon
                          : _destinations[i].icon,
                      label: _destinations[i].label,
                      active: i == selected,
                      onTap: () {
                        AppHaptics.tap();
                        context.go(_destinations[i].path);
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The center Add item — visually distinct (a filled circle, since it's an
/// action rather than a destination) but structurally identical to every
/// other item in the row: same height, same flat decoration, no elevation,
/// no `Positioned`, no offset from the bar. It never floats above or outside
/// the row it lives in.
class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return PressableScale.onTap(
      onTap: onTap,
      child: Center(
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: scheme.primary,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.add_rounded, size: 24, color: Colors.white),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = active ? scheme.primary : scheme.onSurfaceVariant;

    return PressableScale.onTap(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22, color: color),
          Gap.h4,
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _Destination {
  const _Destination(this.path, this.label, this.icon, this.selectedIcon);

  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

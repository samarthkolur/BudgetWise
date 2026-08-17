import 'package:budgetwise/core/env/env.dart';
import 'package:budgetwise/core/router/app_router.dart';
import 'package:budgetwise/core/theme/app_theme.dart';
import 'package:budgetwise/core/widgets/motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // A build without configuration cannot reach the API, and every screen would
  // fail as an unexplained network error. Say so plainly instead.
  if (!Env.isConfigured) {
    runApp(const _MisconfiguredApp());
    return;
  }

  runApp(const ProviderScope(child: BudgetWiseApp()));
}

class BudgetWiseApp extends ConsumerWidget {
  const BudgetWiseApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'BudgetWise',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      scrollBehavior: AppScrollBehavior(),
      routerConfig: ref.watch(routerProvider),
    );
  }
}

/// Shown when the build carries no configuration.
///
/// Names the missing keys rather than showing a generic failure: the fix is a
/// `--dart-define-from-file` flag, and a developer left to guess that will spend
/// an hour on it.
class _MisconfiguredApp extends StatelessWidget {
  const _MisconfiguredApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('⚙️', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 16),
                Text(
                  'Configuration missing',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(
                  'This build has no values for:',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                for (final key in Env.missingKeys)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '  • $key',
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
                const SizedBox(height: 20),
                const SelectableText(
                  'flutter run --dart-define-from-file=config/dev.json',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
                const SizedBox(height: 12),
                Text(
                  'Copy config/example.json to config/dev.json and fill it in. '
                  'It is git-ignored.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

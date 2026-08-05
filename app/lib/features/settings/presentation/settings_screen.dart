import 'package:budgetwise/core/providers.dart';
import 'package:budgetwise/core/widgets/async_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('You')),
      body: AsyncView(
        value: profile,
        onRetry: () => ref.invalidate(profileProvider),
        builder: (data) {
          if (data == null) return const SizedBox.shrink();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundImage: data.avatarUrl == null
                            ? null
                            : NetworkImage(data.avatarUrl!),
                        child: data.avatarUrl == null
                            ? Text(
                                data.firstName.characters.first.toUpperCase(),
                                style: theme.textTheme.titleLarge,
                              )
                            : null,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              data.displayName ?? 'BudgetWise user',
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              data.email ?? '',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.currency_rupee),
                      title: const Text('Currency'),
                      trailing: Text(data.currency),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.lock_outline),
                      title: const Text('Investing'),
                      trailing: Text(
                        data.isInvestingUnlocked ? 'Unlocked' : 'Locked',
                        style: TextStyle(
                          color: data.isInvestingUnlocked
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Card(
                child: ListTile(
                  leading: Icon(Icons.logout, color: theme.colorScheme.error),
                  title: Text(
                    'Sign out',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  onTap: () => _signOut(context, ref),
                ),
              ),
              const SizedBox(height: 24),
              Center(
                child: Text(
                  'BudgetWise · Earn → Save → Invest → Spend',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'Your data stays safe and will be here when you return.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref.read(googleAuthServiceProvider).signOut();
      // Every cached provider is dropped so the next user cannot see a frame of
      // the previous one's data before their own loads.
      ref
        ..refreshBudgetData()
        ..invalidate(profileProvider);
    } on Object catch (error) {
      if (context.mounted) showFailure(context, error);
    }
  }
}

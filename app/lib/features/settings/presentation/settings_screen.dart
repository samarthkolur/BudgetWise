import 'package:budgetwise/core/providers.dart';
import 'package:budgetwise/core/router/routes.dart';
import 'package:budgetwise/core/theme/app_theme.dart';
import 'package:budgetwise/core/widgets/async_view.dart';
import 'package:budgetwise/core/widgets/bento.dart';
import 'package:budgetwise/core/widgets/motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final isSignedIn = ref.watch(isSignedInProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('You')),
      body: AsyncView(
        value: profile,
        onRetry: () => ref.invalidate(profileProvider),
        builder: (data) {
          if (data == null) return const SizedBox.shrink();

          return ListView(
            padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.xl, Gap.lg, Gap.xxl),
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundImage: data.avatarUrl == null
                        ? null
                        : NetworkImage(data.avatarUrl!),
                    child: data.avatarUrl == null
                        ? Icon(
                            isSignedIn
                                ? Icons.person_outline
                                : Icons.phone_iphone,
                            size: 24,
                          )
                        : null,
                  ),
                  Gap.w16,
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
                          isSignedIn
                              ? (data.email ?? '')
                              : 'On this device only',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Gap.h28,
              Container(
                padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
                decoration: AppTheme.card(theme.colorScheme),
                child: ListSection(
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.currency_rupee),
                      title: const Text('Currency'),
                      trailing: Text(
                        data.currency,
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.lock_outline),
                      title: const Text('Investing'),
                      trailing: Text(
                        data.isInvestingUnlocked ? 'Unlocked' : 'Locked',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: data.isInvestingUnlocked
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Gap.h16,
              Container(
                padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
                decoration: AppTheme.card(theme.colorScheme),
                child: isSignedIn
                    ? PressableScale(
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.logout,
                            color: theme.colorScheme.error,
                          ),
                          title: Text(
                            'Sign out',
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                          onTap: () => _signOut(context, ref),
                        ),
                      )
                    : PressableScale(
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.sync_outlined,
                            color: theme.colorScheme.primary,
                          ),
                          title: const Text('Sign in with Google'),
                          subtitle: const Text(
                            'Optional — back up and sync later',
                          ),
                          onTap: () => context.push(Routes.signIn),
                        ),
                      ),
              ),
              Gap.h28,
              Center(
                child: Text(
                  'BudgetWise · Earn → Save → Invest → Spend',
                  style: theme.textTheme.bodySmall,
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

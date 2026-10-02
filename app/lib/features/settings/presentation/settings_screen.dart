import 'package:budgetwise/core/providers.dart';
import 'package:budgetwise/core/theme/app_theme.dart';
import 'package:budgetwise/core/widgets/async_view.dart';
import 'package:budgetwise/core/widgets/bento.dart';
import 'package:budgetwise/core/widgets/motion.dart';
import 'package:budgetwise/features/sms_detection/application/sms_detection_controller.dart';
import 'package:budgetwise/features/sms_detection/presentation/detected_expenses_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

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
              if (ref.watch(smsCapableProvider)) ...[
                Gap.h16,
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
                  decoration: AppTheme.card(theme.colorScheme),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.sms_outlined),
                    title: const Text('Detect expenses from SMS'),
                    subtitle: const Text(
                      'Scans bank & UPI messages on-device, never leaves '
                      'your phone',
                    ),
                    trailing: Switch(
                      value:
                          ref.watch(smsDetectionEnabledProvider).value ?? false,
                      onChanged: (value) =>
                          _onSmsDetectionToggle(context, ref, value),
                    ),
                  ),
                ),
              ],
              Gap.h16,
              Container(
                padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
                decoration: AppTheme.card(theme.colorScheme),
                child: PressableScale(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.logout, color: theme.colorScheme.error),
                    title: Text(
                      'Sign out',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    onTap: () => _signOut(context, ref),
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
      await ref.read(authServiceProvider).signOut();
      // Every cached provider is dropped so the next user cannot see a frame of
      // the previous one's data before their own loads.
      ref
        ..refreshBudgetData()
        ..invalidate(profileProvider);
    } on Object catch (error) {
      if (context.mounted) showFailure(context, error);
    }
  }

  Future<void> _onSmsDetectionToggle(
    BuildContext context,
    WidgetRef ref,
    bool value,
  ) async {
    if (!value) {
      await ref.read(smsDetectionEnabledProvider.notifier).set(enabled: false);
      return;
    }

    // Play Store requires this kind of disclosure to appear *before* the
    // system permission prompt, not just in a privacy policy — this dialog
    // is that disclosure, not decoration.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Detect expenses from SMS?'),
        content: const Text(
          'BudgetWise will read your SMS inbox to find bank and UPI debit '
          'messages, so it can suggest expenses for you to categorize. '
          'Messages are processed entirely on this device and never leave '
          'your phone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final status = await ref.read(smsPermissionServiceProvider).request();
    if (!status.isGranted) {
      if (context.mounted) {
        // Android's Restricted Settings silently refuses to even show the
        // system prompt for a sideloaded (non-Play-Store) app requesting
        // SMS access — it reports straight to permanentlyDenied/restricted
        // instead of the usual one-time "denied". That needs a different
        // instruction than "deny" does, because there's no permission
        // dialog to retry: the fix lives in a non-obvious overflow menu.
        final isBlockedAsSideloaded =
            status.isPermanentlyDenied || status.isRestricted;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                isBlockedAsSideloaded
                    ? "Android is blocking this because the app wasn't "
                          'installed from the Play Store. Open Settings, tap '
                          'the ⋮ menu, choose "Allow restricted settings", '
                          'then try again.'
                    : 'Permission denied — enable SMS access in system '
                          'settings to use this.',
              ),
              duration: const Duration(seconds: 8),
              action: const SnackBarAction(
                label: 'Open settings',
                onPressed: openAppSettings,
              ),
            ),
          );
      }
      return;
    }

    await ref.read(smsDetectionEnabledProvider.notifier).set(enabled: true);

    final budgetId = ref.read(currentBudgetProvider).value?.id;
    if (budgetId == null) return;

    await ref
        .read(smsDetectionControllerProvider.notifier)
        .checkForNewTransactions(budgetId);
    final pending = await ref.read(
      pendingDetectedExpensesProvider(budgetId).future,
    );
    if (pending.isNotEmpty && context.mounted) {
      await showDetectedExpensesSheet(context, ref, budgetId);
    }
  }
}

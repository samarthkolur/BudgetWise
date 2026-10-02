import 'package:budgetwise/core/providers.dart';
import 'package:budgetwise/core/widgets/async_view.dart';
import 'package:budgetwise/core/widgets/motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Email + password, sign up or log in.
///
/// This is now the **mandatory first screen** — see the router's redirect in
/// `core/router/app_router.dart`, which sends anyone with no session here
/// before anything else renders, with no way to dismiss it. There is no
/// "optional" or "continue offline" path left: without an account there is
/// nowhere else in the app to go.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailField = TextEditingController();
  final _passwordField = TextEditingController();
  final _nameField = TextEditingController();

  bool _isSignUp = false;
  bool _obscurePassword = true;
  bool _busy = false;

  @override
  void dispose() {
    _emailField.dispose();
    _passwordField.dispose();
    _nameField.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _busy = true);
    try {
      final service = ref.read(authServiceProvider);
      if (_isSignUp) {
        await service.signUp(
          email: _emailField.text,
          password: _passwordField.text,
          displayName: _nameField.text,
        );
      } else {
        await service.logIn(
          email: _emailField.text,
          password: _passwordField.text,
        );
      }
      await ref.read(sessionProvider.notifier).refreshFromStorage();
      // Pulls this account's server data into the local database once, so
      // offline reads have something real from the very first sign-in rather
      // than staying empty until a write happens to touch each table. Best
      // effort: a brand-new signup has nothing to pull yet, and a failure
      // here (e.g. signing up while briefly offline) must not block sign-in
      // itself — the dashboard/onboarding redirect below still works from
      // whatever's already local, and ordinary use repopulates it.
      try {
        await ref.read(hydrationServiceProvider).hydrate();
      } on Object {
        // Non-fatal — see above.
      }
      // Every provider that depended on "signed in or not" now needs to
      // re-resolve against the server instead of the local database — and
      // the router's redirect (now watching sessionProvider) moves the user
      // on its own; this screen never navigates imperatively.
      ref
        ..refreshBudgetData()
        ..invalidate(profileProvider);
    } on Object catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 32),
                Text(
                  'BudgetWise',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.displayMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'EARN · SAVE · INVEST · SPEND',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 40),
                Text(
                  _isSignUp ? 'Create your account' : 'Welcome back',
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 20),
                if (_isSignUp) ...[
                  TextFormField(
                    controller: _nameField,
                    textCapitalization: TextCapitalization.words,
                    autofillHints: const [AutofillHints.name],
                    decoration: const InputDecoration(labelText: 'Your name'),
                    validator: (value) => (value == null || value.trim().isEmpty)
                        ? 'Enter your name'
                        : null,
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _emailField,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: _validateEmail,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordField,
                  obscureText: _obscurePassword,
                  autofillHints: [
                    if (_isSignUp) AutofillHints.newPassword else AutofillHints.password,
                  ],
                  decoration: InputDecoration(
                    labelText: 'Password',
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: _validatePassword,
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 28),
                PressableScale(
                  child: FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: theme.colorScheme.onPrimary,
                            ),
                          )
                        : Text(_isSignUp ? 'Sign up' : 'Log in'),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() => _isSignUp = !_isSignUp),
                  child: Text(
                    _isSignUp
                        ? 'Already have an account? Log in'
                        : "Don't have an account? Sign up",
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String? _validateEmail(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) return 'Enter your email';
  if (!trimmed.contains('@') || !trimmed.contains('.')) {
    return 'Enter a valid email';
  }
  return null;
}

String? _validatePassword(String? value) {
  if (value == null || value.isEmpty) return 'Enter your password';
  if (value.length < 8) return 'At least 8 characters';
  return null;
}

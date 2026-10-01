import 'package:budgetwise/core/env/env.dart';
import 'package:budgetwise/core/providers.dart';
import 'package:budgetwise/core/widgets/async_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One button, because Google is the only provider.
///
/// There is no password field, no "forgot password", no email verification and
/// no account-recovery path — the whole surface simply does not exist. That is
/// the point of choosing a single federated provider, and it is enforced in the
/// API, which accepts Google ID tokens and nothing else — not by hiding UI here.
///
/// Reached from Settings, not a gate the app forces on launch — the app works
/// fully offline, so signing in is something a user opts into, not a
/// prerequisite. See [BudgetRefresh] and `profileRepositoryProvider` for how
/// the app switches from local to server-backed data once this succeeds.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  bool _busy = false;

  Future<void> _signIn({bool local = false}) async {
    setState(() => _busy = true);
    try {
      final service = ref.read(googleAuthServiceProvider);
      if (local) {
        await service.signInLocally();
      } else {
        await service.signIn();
      }
      await ref.read(sessionProvider.notifier).refreshFromStorage();
      // Every provider that depended on "signed in or not" now needs to
      // re-resolve against the server instead of the local database.
      ref
        ..refreshBudgetData()
        ..invalidate(profileProvider);
      if (mounted) Navigator.of(context).pop();
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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'BudgetWise',
                        style: theme.textTheme.displayMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'EARN · SAVE · INVEST · SPEND',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.4,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        'Decide where every rupee goes before you spend it — '
                        'not after.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 40),
              if (!Env.devLogin)
                _GoogleButton(busy: _busy, onPressed: _busy ? null : _signIn),
              if (Env.devLogin) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _signIn(local: true),
                  icon: _busy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        )
                      : const Icon(Icons.dns_outlined, size: 18),
                  label: const Text('Sign in to local dev server'),
                ),
                const SizedBox(height: 8),
                Text(
                  'DEV BUILD · NEEDS A LOCAL SERVER RUNNING',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                'Optional. Anything already on this device stays here and '
                'reappears if you sign out.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        foregroundColor: theme.colorScheme.onSurface,
      ),
      child: busy
          ? const SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Google's mark, drawn rather than bundled as an asset so there
                // is no image to license, ship or scale.
                const _GoogleMark(),
                const SizedBox(width: 12),
                Text(
                  'Continue with Google',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
    );
  }
}

class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 20,
      width: 20,
      child: CustomPaint(painter: _GooglePainter()),
    );
  }
}

class _GooglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final stroke = size.width * 0.22;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    final rect = Rect.fromCircle(center: center, radius: radius - stroke / 2);

    // The four brand arcs, in Google's order.
    canvas
      ..drawArc(
        rect,
        -0.35,
        1.15,
        false,
        paint..color = const Color(0xFF4285F4),
      )
      ..drawArc(rect, 0.85, 1.55, false, paint..color = const Color(0xFF34A853))
      ..drawArc(rect, 2.45, 1.15, false, paint..color = const Color(0xFFFBBC05))
      ..drawArc(rect, 3.65, 1.75, false, paint..color = const Color(0xFFEA4335))
      // The horizontal bar of the G.
      ..drawLine(
        Offset(center.dx, center.dy),
        Offset(size.width, center.dy),
        Paint()
          ..color = const Color(0xFF4285F4)
          ..strokeWidth = stroke,
      );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

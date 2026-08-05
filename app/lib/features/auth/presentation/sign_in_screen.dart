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
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  bool _busy = false;

  Future<void> _signIn() async {
    setState(() => _busy = true);
    try {
      await ref.read(googleAuthServiceProvider).signIn();
      // No navigation here. The router's redirect watches the session and moves
      // the user itself, so there is exactly one place that decides where a
      // signed-in user belongs.
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
              const Spacer(flex: 2),
              Text('💰', style: theme.textTheme.displayLarge),
              const SizedBox(height: 20),
              Text(
                'BudgetWise',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Earn → Save → Invest → Spend',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Decide where every rupee goes before you spend it — '
                'not after.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const Spacer(flex: 3),
              _GoogleButton(busy: _busy, onPressed: _busy ? null : _signIn),
              const SizedBox(height: 16),
              Text(
                'We only ever see your name, email and profile picture.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
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

import 'dart:math' as math;

import 'package:budgetwise/core/theme/app_theme.dart';
import 'package:budgetwise/core/theme/app_typography.dart';
import 'package:budgetwise/core/widgets/motion.dart';
import 'package:flutter/material.dart';

/// The investing-unlock celebration: a full-screen near-black takeover with
/// falling square confetti and a violet streak badge, hard-shadowed in lime.
///
/// This is the one deliberate exception to the app's usual restraint around
/// gamification — reserved for the single real milestone the whole "pay
/// yourself first" habit is built toward, six consecutive months of
/// confirmed savings, and shown exactly once per unlock. [show] is called
/// from the app shell only on the `false → true` transition of
/// `UnlockClaim.isUnlocked`, never on a timer or a re-render, so it can't
/// replay for a state that was already unlocked.
abstract final class CelebrationOverlay {
  static Future<void> show(BuildContext context, {required int streakMonths}) {
    return showGeneralDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, _, _) =>
          _CelebrationScreen(streakMonths: streakMonths),
      transitionBuilder: (context, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    );
  }
}

class _CelebrationScreen extends StatefulWidget {
  const _CelebrationScreen({required this.streakMonths});

  final int streakMonths;

  @override
  State<_CelebrationScreen> createState() => _CelebrationScreenState();
}

class _CelebrationScreenState extends State<_CelebrationScreen>
    with SingleTickerProviderStateMixin {
  late final _confettiController = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  );

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = AppMotion.reduceMotion(context);
    if (reduceMotion) {
      if (_confettiController.isAnimating) _confettiController.stop();
    } else if (!_confettiController.isAnimating) {
      _confettiController.repeat();
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Stack(
          children: [
            if (!reduceMotion)
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _confettiController,
                  builder: (context, _) => CustomPaint(
                    painter: _ConfettiPainter(_confettiController.value),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: const BoxDecoration(
                      color: Color(0xFF7B5CFF),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0xFFD4FF3D),
                          offset: Offset(6, 6),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        '${widget.streakMonths}',
                        style: const TextStyle(
                          fontFamily: AppType.display,
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  Gap.h28,
                  const Text(
                    'Investing unlocked!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: AppType.display,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  Gap.h12,
                  const Text(
                    "Six months of consistent saving. You're ready for the "
                    'next stage of your financial plan.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: AppType.body,
                      fontSize: 14,
                      height: 1.5,
                      color: Color(0xB3FFFFFF),
                    ),
                  ),
                  Gap.h28,
                  PressableScale.onTap(
                    onTap: () {
                      AppHaptics.tap();
                      Navigator.of(context).pop();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                      decoration: const BoxDecoration(color: Color(0xFFD4FF3D)),
                      child: const Text(
                        "Let's go",
                        style: TextStyle(
                          fontFamily: AppType.body,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0A0A0A),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A handful of falling, rotating confetti pieces, each on its own phase and
/// speed so the loop doesn't read as a single repeating stamp. Square only,
/// in the page's own three colours — a rainbow burst would be the one thing
/// in this screen breaking the "one or two accents" rule.
class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.t);

  final double t;

  static const _colors = [
    Color(0xFFD4FF3D),
    Color(0xFF7B5CFF),
    Colors.white,
  ];

  static const _pieces = [
    (x: 0.15, phase: 0.0, speed: 1.0, color: 0),
    (x: 0.30, phase: 0.3, speed: 0.85, color: 2),
    (x: 0.48, phase: 0.6, speed: 1.1, color: 1),
    (x: 0.64, phase: 0.15, speed: 0.95, color: 2),
    (x: 0.80, phase: 0.45, speed: 1.05, color: 0),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (final piece in _pieces) {
      final local = ((t * piece.speed) + piece.phase) % 1.0;
      final y = local * (size.height + 40) - 20;
      final opacity = local < 0.1 ? local / 0.1 : (1 - local).clamp(0.0, 1.0);
      final dx = size.width * piece.x;
      final paint = Paint()
        ..color = _colors[piece.color].withValues(
          alpha: opacity.clamp(0.0, 1.0) * 0.9,
        );

      canvas
        ..save()
        ..translate(dx, y)
        ..rotate(local * math.pi * 2)
        ..drawRect(const Rect.fromLTWH(-4, -4, 8, 8), paint)
        ..restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) => oldDelegate.t != t;
}

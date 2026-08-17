import 'dart:math' as math;

import 'package:budgetwise/core/theme/app_theme.dart';
import 'package:budgetwise/core/theme/app_typography.dart';
import 'package:budgetwise/core/widgets/motion.dart';
import 'package:flutter/material.dart';

/// The financial health score as a ring.
///
/// A ring and a word — the one exception to the light-gamification approach
/// is the investing-unlock celebration (`CelebrationOverlay`), reserved for
/// that single real milestone. The score itself stays quiet: no badges, no
/// levels, nothing here competes with the number.
///
/// The arc animates from zero on first build so the number feels earned rather
/// than assigned.
class ScoreRing extends StatelessWidget {
  const ScoreRing({
    required this.score,
    required this.label,
    this.size = 132,
    this.stroke = 10,
    super.key,
  });

  final int score;
  final String label;
  final double size;
  final double stroke;

  /// Colour follows the band, so the ring says the same thing as the word.
  Color _color(ColorScheme scheme) {
    if (score >= 85) return scheme.healthy;
    if (score >= 70) return scheme.primary;
    if (score >= 50) return scheme.warning;
    return scheme.exceeded;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = _color(scheme);

    final reduceMotion = AppMotion.reduceMotion(context);

    return TweenAnimationBuilder<double>(
      tween: Tween(
        begin: reduceMotion ? score / 100 : 0,
        end: score / 100,
      ),
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, progress, _) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(
            progress: progress,
            color: color,
            track: scheme.surfaceContainerHigh,
            stroke: stroke,
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${(progress * 100).round()}',
                  style: theme.textTheme.displaySmall?.money.copyWith(
                    // Scaled to the ring instead of a fixed 32px — at the
                    // compact 56px size this app also uses (Home's
                    // health-score row), a fixed display-size number
                    // overflowed past the stroke and read as misaligned.
                    fontSize: size * 0.24,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                    height: 1,
                  ),
                ),
                if (label.isNotEmpty) ...[
                  SizedBox(height: size * 0.015),
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: color,
                      fontSize: (size * 0.085).clamp(9.0, 11.0),
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

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.color,
    required this.track,
    required this.stroke,
  });

  final double progress;
  final Color color;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );

    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = track;

    // Starts at the top and sweeps clockwise — the direction people read a
    // dial. -90° puts 0 at 12 o'clock.
    canvas
      ..drawArc(rect, -math.pi / 2, math.pi * 2, false, base)
      ..drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * progress.clamp(0.0, 1.0),
        false,
        base..color = color,
      );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}

import 'dart:math' as math;

import 'package:budgetwise/core/theme/app_theme.dart';
import 'package:budgetwise/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// The financial health score as a ring.
///
/// Gamification here is deliberately light: a ring and a word, no badges, no
/// confetti, no levels. The PRD asks the score to motivate, and a finance app
/// that celebrates too loudly starts to feel like it is congratulating you for
/// spending — which is the opposite of the point.
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

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: score / 100),
      duration: const Duration(milliseconds: 900),
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
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${(progress * 100).round()}',
                  style: theme.textTheme.displaySmall?.money.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(color: color),
                ),
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

/// The savings streak, as a row of months.
///
/// Six dots, one per month toward the investing unlock. Concrete and countable
/// — "4 of 6" is a thing you can finish, where a percentage bar is not.
class StreakDots extends StatelessWidget {
  const StreakDots({
    required this.completed,
    this.total = 6,
    this.size = 9,
    super.key,
  });

  final int completed;
  final int total;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < total; i++)
          Padding(
            padding: EdgeInsets.only(right: i == total - 1 ? 0 : 5),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < completed
                    ? scheme.primary
                    : scheme.surfaceContainerHighest,
              ),
            ),
          ),
      ],
    );
  }
}

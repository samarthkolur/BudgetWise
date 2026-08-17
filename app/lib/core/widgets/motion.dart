import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shared timing and the reduced-motion switch, so every animated widget reads
/// the same signal instead of each one checking `MediaQuery` its own way.
abstract final class AppMotion {
  static const press = Duration(milliseconds: 120);

  /// The Flutter-level proxy for the OS "reduce motion" accessibility
  /// setting. Honouring it means jumping to the end value instead of
  /// animating, not removing feedback entirely.
  static bool reduceMotion(BuildContext context) =>
      MediaQuery.of(context).disableAnimations;
}

/// Three haptics, named by what they mean rather than by the underlying
/// pattern, used only at moments a user would call a "commit" — never on
/// every keystroke or scroll, per the rule that over-used feedback trains
/// people to ignore all of it.
abstract final class AppHaptics {
  static void tap() => HapticFeedback.selectionClick();
  static void success() => HapticFeedback.mediumImpact();
  static void warning() => HapticFeedback.heavyImpact();
}

/// Rubber-bands at scroll bounds on every platform instead of Android's
/// default clamp-and-glow — a scrollable that resists past its edge instead
/// of stopping dead reads as responsive rather than frozen.
class AppScrollBehavior extends MaterialScrollBehavior {
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
}

/// A light physical "give" on press, layered on top of whatever tap handling
/// the child already has (an `InkWell`'s ripple, a button's own state) rather
/// than replacing it. Feedback starts on pointer-down, not on release — the
/// scale is already visible before the tap has even been decided as a tap.
///
/// Skips the scale under reduced motion; the wrapped widget's own tap
/// handling still fires normally.
class PressableScale extends StatefulWidget {
  const PressableScale({required this.child, super.key})
    : onTap = null,
      behavior = HitTestBehavior.opaque;

  /// Also owns the tap gesture, for a child that isn't already tappable
  /// (e.g. a plain `Container` acting as a button).
  const PressableScale.onTap({
    required this.onTap,
    required this.child,
    this.behavior = HitTestBehavior.opaque,
    super.key,
  });

  final VoidCallback? onTap;
  final HitTestBehavior behavior;
  final Widget child;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: AppMotion.press,
  );
  late final _scale = Tween<double>(
    begin: 1,
    end: 0.97,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _down(TapDownDetails _) {
    if (!AppMotion.reduceMotion(context)) _controller.forward();
  }

  void _up(TapUpDetails _) => _controller.reverse();

  void _cancel() => _controller.reverse();

  @override
  Widget build(BuildContext context) {
    final child = AnimatedBuilder(
      animation: _scale,
      builder: (context, child) =>
          Transform.scale(scale: _scale.value, child: child),
      child: widget.child,
    );

    return GestureDetector(
      behavior: widget.behavior,
      onTapDown: _down,
      onTapUp: _up,
      onTapCancel: _cancel,
      onTap: widget.onTap,
      child: child,
    );
  }
}

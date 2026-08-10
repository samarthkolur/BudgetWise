import 'package:budgetwise/core/theme/app_theme.dart';
import 'package:budgetwise/core/theme/app_typography.dart';
import 'package:budgetwise_domain/budgetwise_domain.dart';
import 'package:flutter/material.dart';

/// A section heading with an optional trailing action.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.title,
    this.trailing,
    this.action,
    super.key,
  });

  final String title;
  final String? trailing;
  final VoidCallback? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.xs, 0, Gap.xs, Gap.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          if (trailing != null)
            action == null
                ? Text(trailing!, style: theme.textTheme.labelMedium)
                : TextButton(
                    onPressed: action,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(trailing!),
                  ),
        ],
      ),
    );
  }
}

/// A monochrome icon on a tinted circular background.
///
/// The one "icon as decoration" the design system allows — a single glyph in
/// a single tone, never a multi-colour emoji. Used for category, stat, and
/// insight markers so the same visual language covers all three instead of
/// each screen inventing its own treatment.
class IconBadge extends StatelessWidget {
  const IconBadge({
    required this.icon,
    this.tone,
    this.size = 40,
    this.iconSize = 19,
    super.key,
  });

  final IconData icon;
  final Color? tone;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = tone ?? scheme.onSurfaceVariant;

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: iconSize, color: color),
    );
  }
}

/// A thin progress bar with a flat track.
///
/// Animates toward a new [value] rather than jumping to it — adding an
/// expense or moving a slider should read as the bar *responding*, not
/// resetting. `TweenAnimationBuilder` re-tweens from wherever it last
/// stopped, so this needs no state of its own.
class FlatBar extends StatelessWidget {
  const FlatBar({
    required this.value,
    required this.color,
    this.height = 6,
    super.key,
  });

  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: value.clamp(0.0, 1.0)),
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
          builder: (context, animated, _) => LinearProgressIndicator(
            value: animated,
            backgroundColor: scheme.surfaceContainerHigh,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ),
    );
  }
}

/// A money figure that counts toward a new value instead of snapping to it —
/// for the one or two figures on a screen worth making feel alive (the
/// dashboard's hero number). Reused too widely, a counting digit stops
/// reading as a response to something and starts reading as decoration,
/// which is exactly what the rest of this design system avoids.
class AnimatedMoneyText extends StatelessWidget {
  const AnimatedMoneyText({required this.value, this.style, super.key});

  final Money value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<int>(
      tween: IntTween(end: value.minor),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      builder: (context, animated, _) =>
          Text(Money(animated).formatCompact(), style: style),
    );
  }
}

/// A label/value line — the basic unit of a ledger, a settings screen, or an
/// onboarding summary.
///
/// No border, no fill. A column of these reads as a statement, not a grid of
/// facts, which is the point: rows belong together because they are lined up,
/// not because they share a box.
class MoneyRow extends StatelessWidget {
  const MoneyRow({
    required this.label,
    required this.value,
    this.emphasise = false,
    this.valueColor,
    this.tabular = true,
    this.padding = const EdgeInsets.symmetric(vertical: Gap.xs),
    super.key,
  });

  final String label;
  final String value;
  final bool emphasise;
  final Color? valueColor;
  final bool tabular;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valueStyle = emphasise
        ? theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)
        : theme.textTheme.bodyLarge;

    return Padding(
      padding: padding,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: emphasise
                ? theme.textTheme.titleSmall
                : theme.textTheme.bodyMedium,
          ),
          Text(
            value,
            style: (tabular ? valueStyle?.money : valueStyle)?.copyWith(
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// One typographic figure: an icon badge, then value, then label. No border,
/// no fill on the column itself — only the badge carries any tint, so a row
/// of these still reads as a statement rather than a grid of tiles.
class StatColumn extends StatelessWidget {
  const StatColumn({
    required this.icon,
    required this.label,
    required this.value,
    this.footnote,
    this.tone,
    super.key,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? footnote;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      children: [
        IconBadge(icon: icon, tone: tone),
        Gap.h8,
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: theme.textTheme.titleLarge?.money.copyWith(
              color: tone ?? scheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Gap.h4,
        Text(
          label,
          style: theme.textTheme.labelMedium,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (footnote != null)
          Text(
            footnote!,
            style: theme.textTheme.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }
}

/// A row of [StatColumn]s separated by a hairline vertical divider instead of
/// tile boundaries — the month-at-a-glance figures, lined up rather than
/// boxed.
class StatRow extends StatelessWidget {
  const StatRow({required this.children, super.key});

  final List<StatColumn> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
                child: VerticalDivider(width: 1, color: scheme.outlineVariant),
              ),
            Expanded(child: children[i]),
          ],
        ],
      ),
    );
  }
}

/// A grouped list: children separated by a hairline divider, no outer border
/// or background. The flat replacement for a tile wrapping a column of rows.
class ListSection extends StatelessWidget {
  const ListSection({
    required this.children,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// A small pill. Used for streaks and status, never for actions.
class TonePill extends StatelessWidget {
  const TonePill({
    required this.label,
    required this.tone,
    this.icon,
    super.key,
  });

  final String label;
  final Color tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: tone),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: tone,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

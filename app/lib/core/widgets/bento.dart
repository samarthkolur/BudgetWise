import 'package:budgetwise/core/theme/app_theme.dart';
import 'package:budgetwise/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// A bento tile.
///
/// One fact per tile. The layout's job is to make the important tile bigger,
/// not to make every tile shout — so a tile has exactly one number, one label,
/// and at most one supporting line.
///
/// [tone] tints the whole tile at 12% alpha and is reserved for state that
/// matters (over budget, savings pending). A grid where every tile is tinted
/// has no hierarchy, so the default is untinted.
class BentoTile extends StatelessWidget {
  const BentoTile({
    required this.child,
    this.onTap,
    this.tone,
    this.padding = const EdgeInsets.all(Gap.xl),
    this.height,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final Color? tone;
  final EdgeInsetsGeometry padding;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = tone == null
        ? scheme.surfaceContainerLow
        : Color.alphaBlend(
            tone!.withValues(alpha: 0.10),
            scheme.surfaceContainerLow,
          );

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: tone?.withValues(alpha: 0.22) ?? scheme.outlineVariant,
            ),
          ),
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}

/// A tile showing one figure: caption, value, optional footnote.
///
/// The value uses tabular figures so a column of tiles does not jitter as the
/// numbers change.
class BentoStat extends StatelessWidget {
  const BentoStat({
    required this.label,
    required this.value,
    this.footnote,
    this.icon,
    this.tone,
    this.onTap,
    this.emphasise = false,
    super.key,
  });

  final String label;
  final String value;
  final String? footnote;
  final IconData? icon;
  final Color? tone;
  final VoidCallback? onTap;

  /// Promotes the value to display size. At most one tile per grid should.
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return BentoTile(
      onTap: onTap,
      tone: tone,
      padding: const EdgeInsets.all(Gap.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: tone ?? scheme.onSurfaceVariant),
                Gap.w4,
              ],
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.labelMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Gap.h8,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style:
                      (emphasise
                              ? theme.textTheme.displaySmall
                              : theme.textTheme.titleLarge)
                          ?.money
                          .copyWith(
                            color: tone ?? scheme.onSurface,
                            fontWeight: emphasise
                                ? FontWeight.w600
                                : FontWeight.w600,
                          ),
                ),
              ),
              if (footnote != null) ...[
                Gap.h4,
                Text(
                  footnote!,
                  style: theme.textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// A row of equal-width tiles.
///
/// Uses IntrinsicHeight so tiles in a row share the tallest one's height —
/// bento reads as a grid only when the tiles actually line up.
class BentoRow extends StatelessWidget {
  const BentoRow({required this.children, this.spacing = Gap.md, super.key});

  final List<Widget> children;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(width: spacing),
            Expanded(child: children[i]),
          ],
        ],
      ),
    );
  }
}

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

/// A thin progress bar with a flat track.
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
        child: LinearProgressIndicator(
          value: value.clamp(0.0, 1.0),
          backgroundColor: scheme.surfaceContainerHigh,
          valueColor: AlwaysStoppedAnimation(color),
        ),
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

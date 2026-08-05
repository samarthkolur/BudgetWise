import 'package:flutter/material.dart';

/// The Geist type scale.
///
/// Weight carries the hierarchy, not size. A minimalist screen has few sizes
/// and uses weight and colour to separate levels — the alternative, a new point
/// size for every role, is what makes a dashboard look like a spreadsheet.
///
/// Five weights, each with one job:
///
/// | Weight | Used for |
/// |---|---|
/// | 300 Light    | Large display numerals — thin strokes read as calm at 40px+ |
/// | 400 Regular  | Body copy, descriptions, list subtitles |
/// | 500 Medium   | Labels, captions, tabular figures in tiles |
/// | 600 SemiBold | Card titles, section headers, buttons |
/// | 700 Bold     | The one number a screen is about, and nothing else |
///
/// Money is always rendered with [tabular], because figures that shift width as
/// they change turn a column of amounts into a jitter.
abstract final class AppType {
  static const family = 'Geist';

  /// Lining tabular figures: every digit the same width. Without this a
  /// changing balance visibly wobbles as digits swap.
  static const tabular = <FontFeature>[
    FontFeature.tabularFigures(),
    FontFeature.slashedZero(),
  ];

  static TextTheme textTheme(ColorScheme scheme) {
    final ink = scheme.onSurface;
    final muted = scheme.onSurfaceVariant;

    return TextTheme(
      // Display — the safe-to-spend figure and nothing else competes with it.
      displayLarge: _t(52, FontWeight.w300, ink, height: 1.05, spacing: -1.5),
      displayMedium: _t(40, FontWeight.w300, ink, height: 1.08, spacing: -1.2),
      displaySmall: _t(32, FontWeight.w400, ink, height: 1.12, spacing: -0.8),

      // Headline — screen titles.
      headlineLarge: _t(28, FontWeight.w600, ink, height: 1.18, spacing: -0.6),
      headlineMedium: _t(24, FontWeight.w600, ink, height: 1.2, spacing: -0.4),
      headlineSmall: _t(20, FontWeight.w600, ink, height: 1.25, spacing: -0.3),

      // Title — card headers.
      titleLarge: _t(18, FontWeight.w600, ink, spacing: -0.2),
      titleMedium: _t(16, FontWeight.w600, ink, height: 1.35),
      titleSmall: _t(14, FontWeight.w600, ink, height: 1.4),

      // Body.
      bodyLarge: _t(16, FontWeight.w400, ink, height: 1.5),
      bodyMedium: _t(14, FontWeight.w400, muted, height: 1.45),
      bodySmall: _t(12.5, FontWeight.w400, muted, height: 1.4),

      // Label — tile captions and buttons.
      labelLarge: _t(14, FontWeight.w600, ink, height: 1.2),
      labelMedium: _t(12, FontWeight.w500, muted, height: 1.2, spacing: 0.1),
      labelSmall: _t(11, FontWeight.w500, muted, height: 1.2, spacing: 0.3),
    );
  }

  static TextStyle _t(
    double size,
    FontWeight weight,
    Color color, {
    double height = 1.3,
    double spacing = 0,
  }) => TextStyle(
    fontFamily: family,
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height,
    letterSpacing: spacing,
  );
}

/// Applies tabular figures to any style showing money.
extension MoneyText on TextStyle {
  TextStyle get money => copyWith(fontFeatures: AppType.tabular);
}

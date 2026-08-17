import 'package:flutter/material.dart';

/// The Space Grotesk / Work Sans type scale.
///
/// Two families, split by role rather than mixed per-element: Space Grotesk
/// carries the numbers, screen headlines, and buttons — the things a screen
/// is about, or the thing you press. Work Sans carries everything read as
/// prose: card/section titles, body copy, captions. This mirrors the
/// prototype's own dominant pattern (its few exceptions — an inline money
/// mention inside a caption sentence, for instance — stay in Work Sans by
/// design, since a sentence with one word in a different typeface reads as a
/// typo, not emphasis).
///
/// Weight still carries the hierarchy within each family, the same principle
/// the previous single-family (Geist) scale used:
///
/// | Role | Family | Weight |
/// |---|---|---|
/// | Display — the one number a screen is about | Space Grotesk | 700 Bold |
/// | Headline — screen/step titles | Space Grotesk | 700 Bold |
/// | Title — card and section headers | Work Sans | 600 SemiBold |
/// | Body — descriptions, subtitles | Work Sans | 400 Regular |
/// | Label large — buttons | Space Grotesk | 700 Bold |
/// | Label medium/small — captions, eyebrows | Work Sans | 600/500 |
///
/// Money is always rendered with [tabular], because figures that shift width as
/// they change turn a column of amounts into a jitter.
abstract final class AppType {
  static const display = 'Space Grotesk';
  static const body = 'Work Sans';

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
      displayLarge: _t(
        display,
        52,
        FontWeight.w700,
        ink,
        height: 1.05,
        spacing: -1.5,
      ),
      displayMedium: _t(
        display,
        40,
        FontWeight.w700,
        ink,
        height: 1.08,
        spacing: -1.2,
      ),
      displaySmall: _t(
        display,
        32,
        FontWeight.w700,
        ink,
        height: 1.12,
        spacing: -0.8,
      ),

      // Headline — screen and onboarding-step titles.
      headlineLarge: _t(
        display,
        28,
        FontWeight.w700,
        ink,
        height: 1.18,
        spacing: -0.6,
      ),
      headlineMedium: _t(
        display,
        24,
        FontWeight.w700,
        ink,
        height: 1.2,
        spacing: -0.4,
      ),
      headlineSmall: _t(
        display,
        20,
        FontWeight.w700,
        ink,
        height: 1.25,
        spacing: -0.3,
      ),

      // Title — card and section headers.
      titleLarge: _t(body, 18, FontWeight.w600, ink, spacing: -0.2),
      titleMedium: _t(body, 16, FontWeight.w600, ink, height: 1.35),
      titleSmall: _t(body, 14, FontWeight.w600, ink, height: 1.4),

      // Body.
      bodyLarge: _t(body, 16, FontWeight.w400, ink, height: 1.5),
      bodyMedium: _t(body, 14, FontWeight.w400, muted, height: 1.45),
      bodySmall: _t(body, 12.5, FontWeight.w400, muted, height: 1.4),

      // Label — buttons stay in the display family; captions stay in body.
      labelLarge: _t(display, 14, FontWeight.w700, ink, height: 1.2),
      labelMedium: _t(
        body,
        12,
        FontWeight.w600,
        muted,
        height: 1.2,
        spacing: 0.1,
      ),
      labelSmall: _t(
        body,
        11,
        FontWeight.w500,
        muted,
        height: 1.2,
        spacing: 0.3,
      ),
    );
  }

  static TextStyle _t(
    String family,
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

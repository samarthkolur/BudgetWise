import 'package:flutter/material.dart';

/// The Archivo / Inter / IBM Plex Mono type scale — "Obsidian", the second
/// re-skin. See the design-system entry in `CLAUDE.md` for why: it follows
/// CRED's NeoPOP discipline rather than guessing at it, after a first attempt
/// (rounded, light, illustrated) missed what actually reads as premium.
///
/// Three families, three jobs, never mixed per-element:
///
/// | Role | Family | Weight |
/// |---|---|---|
/// | Display — the one figure a screen is about | Archivo | 900 Black |
/// | Headline — screen/step titles | Archivo | 800 ExtraBold |
/// | Title — card and section headers | Inter | 700/600 |
/// | Body — descriptions, subtitles | Inter | 400 Regular |
/// | Label large — buttons | Inter | 700 Bold |
/// | Label medium/small — eyebrows, tags, captions | IBM Plex Mono | 500 |
///
/// The mono eyebrow is deliberate, not a leftover: CRED's own small caps read
/// as an instrument readout, not a label, and that's the detail that sells
/// the rest of the system. Money in a list or ledger row goes through
/// [MoneyText.ledger] (Plex Mono, tabular); the one hero figure a screen is
/// about stays in Archivo via [MoneyText.money], because it needs to read as
/// a headline, not a receipt line.
abstract final class AppType {
  static const display = 'Archivo';
  static const body = 'Inter';
  static const mono = 'IBM Plex Mono';

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
        FontWeight.w900,
        ink,
        height: 1,
        spacing: -1.8,
      ),
      displayMedium: _t(
        display,
        40,
        FontWeight.w900,
        ink,
        height: 1.02,
        spacing: -1.4,
      ),
      displaySmall: _t(
        display,
        32,
        FontWeight.w900,
        ink,
        height: 1.05,
        spacing: -1,
      ),

      // Headline — screen and onboarding-step titles.
      headlineLarge: _t(
        display,
        28,
        FontWeight.w800,
        ink,
        height: 1.1,
        spacing: -0.6,
      ),
      headlineMedium: _t(
        display,
        24,
        FontWeight.w800,
        ink,
        height: 1.15,
        spacing: -0.4,
      ),
      headlineSmall: _t(
        display,
        20,
        FontWeight.w800,
        ink,
        height: 1.2,
        spacing: -0.3,
      ),

      // Title — card and section headers.
      titleLarge: _t(body, 18, FontWeight.w700, ink, spacing: -0.1),
      titleMedium: _t(body, 16, FontWeight.w600, ink, height: 1.35),
      titleSmall: _t(body, 14, FontWeight.w600, ink, height: 1.4),

      // Body.
      bodyLarge: _t(body, 16, FontWeight.w400, ink, height: 1.5),
      bodyMedium: _t(body, 14, FontWeight.w400, muted, height: 1.45),
      bodySmall: _t(body, 12.5, FontWeight.w400, muted, height: 1.4),

      // Label — buttons stay in the body family (Inter Bold reads better at
      // button size than a tightly-tracked display face); eyebrows and tags
      // move to Plex Mono, wide-tracked, so they read as a readout.
      labelLarge: _t(body, 14.5, FontWeight.w700, ink, height: 1.2),
      labelMedium: _t(mono, 11, FontWeight.w500, muted, spacing: 0.8),
      labelSmall: _t(mono, 10, FontWeight.w500, muted, spacing: 0.6),
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
  /// For the one hero figure a screen is about — keeps whatever family the
  /// base style already carries (usually Archivo), adds tabular figures.
  TextStyle get money => copyWith(fontFeatures: AppType.tabular);

  /// For a money figure inside a list, ledger row, or stat tile — switches
  /// to Plex Mono so it reads as a line item, not a headline.
  TextStyle get ledger => copyWith(
    fontFamily: AppType.mono,
    fontFeatures: AppType.tabular,
    fontWeight: FontWeight.w500,
  );
}

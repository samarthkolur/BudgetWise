import 'package:budgetwise/core/theme/app_typography.dart';
import 'package:budgetwise_domain/budgetwise_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Warm and tactile, built from the "BudgetWise Prototype" Claude Design
/// mockup.
///
/// This supersedes the app's original flat/no-elevation language. That
/// earlier system is documented in git history and in the superseded
/// paragraphs this file used to carry; the short version is that the product
/// owner reviewed a from-scratch visual prototype and chose to move the whole
/// app onto it rather than reconcile the two languages piecemeal:
///
/// - **Soft-shadow cards, not hairlines.** Separation comes from a white
///   surface + a faint border + a soft drop shadow (light theme only — see
///   [cardShadow]). Dark theme keeps a border-only treatment, since a drop
///   shadow reads as a smudge once the surface itself is already dark.
/// - **One warm accent** (`#FF6B4A`), used only where the eye must go, paired
///   with a navy ink (`#1B2340`) instead of a neutral grey — money apps
///   default to blue-on-grey, which reads as banking; this pairing reads as
///   considered rather than corporate.
/// - **Semantic colour is reserved for budget state.** Green/amber/red mean
///   healthy/warning/exceeded and are used for nothing decorative, so a red
///   number on this screen always means the same thing.
abstract final class AppTheme {
  static const _accent = Color(0xFFFF6B4A);
  static const _inkLight = Color(0xFF1B2340);
  static const _inkDark = Color(0xFFF2F1EC);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  /// The soft card shadow, light theme only. Dark theme returns an empty
  /// list — a drop shadow needs a lighter surface to fall *onto*, and a dark
  /// background swallows it into a smudge instead.
  static List<BoxShadow> cardShadow(Brightness brightness) =>
      brightness == Brightness.light
      ? const [
          BoxShadow(
            color: Color(0x0D1B2340),
            offset: Offset(0, 2),
            blurRadius: 8,
          ),
        ]
      : const [];

  /// The shared "card" decoration every custom card container in the app
  /// builds from: a surface colour, a faint border, [cardShadow], and a
  /// radius. Centralised so the soft-shadow language stays one decision
  /// instead of a `BoxShadow` copied into a dozen widgets.
  static BoxDecoration card(
    ColorScheme scheme, {
    double radius = 20,
    Color? color,
    Color? tone,
  }) => BoxDecoration(
    color:
        color ??
        (tone == null
            ? scheme.surfaceContainerLow
            : Color.alphaBlend(
                tone.withValues(alpha: 0.06),
                scheme.surfaceContainerLow,
              )),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(
      color: tone == null
          ? scheme.outlineVariant
          : tone.withValues(alpha: 0.16),
    ),
    boxShadow: cardShadow(scheme.brightness),
  );

  static ThemeData _build(Brightness brightness) {
    final isLight = brightness == Brightness.light;

    // Hand-tuned neutrals rather than the seeded ones, for the same reason
    // the original scheme avoided `fromSeed` for every surface: tinting
    // everything toward the accent flattens the warm/cool contrast that
    // makes navy-on-cream read as considered rather than corporate.
    final scheme =
        ColorScheme.fromSeed(
          seedColor: _accent,
          brightness: brightness,
        ).copyWith(
          primary: _accent,
          onPrimary: Colors.white,
          surface: isLight ? const Color(0xFFF7F3EC) : const Color(0xFF11131B),
          surfaceContainerLowest: isLight
              ? const Color(0xFFFFFFFF)
              : const Color(0xFF0B0C12),
          surfaceContainerLow: isLight
              ? const Color(0xFFFFFFFF)
              : const Color(0xFF181B26),
          surfaceContainer: isLight
              ? const Color(0xFFF0ECE2)
              : const Color(0xFF1E212E),
          surfaceContainerHigh: isLight
              ? const Color(0xFFE8E2D4)
              : const Color(0xFF262A39),
          surfaceContainerHighest: isLight
              ? const Color(0xFFDED7C5)
              : const Color(0xFF2E3241),
          onSurface: isLight ? _inkLight : _inkDark,
          onSurfaceVariant: isLight
              ? const Color(0xFF5C6178)
              : const Color(0xFFA6ABC0),
          outlineVariant: isLight
              ? const Color(0xFFE6E0D2)
              : const Color(0xFF2A2E3D),
        );

    final text = AppType.textTheme(scheme);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: AppType.body,
      textTheme: text,
      scaffoldBackgroundColor: scheme.surface,
      splashFactory: InkSparkle.splashFactory,

      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.headlineSmall,
        systemOverlayStyle: isLight
            ? SystemUiOverlayStyle.dark
            : SystemUiOverlayStyle.light,
      ),

      cardTheme: CardThemeData(
        elevation: isLight ? 1 : 0,
        shadowColor: const Color(0x1A1B2340),
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: text.labelLarge?.copyWith(fontSize: 15.5),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          side: BorderSide(color: scheme.outlineVariant),
          textStyle: text.labelLarge,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(textStyle: text.labelLarge),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainer,
        hintStyle: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 68,
        indicatorColor: scheme.primary.withValues(alpha: 0.14),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? text.labelSmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                )
              : text.labelSmall,
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 23,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
      ),

      // Selected-state text colour (white on the solid accent fill) is set
      // per chip, not here — `ChipThemeData` has no per-selection-state label
      // style, only a flat default.
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainer,
        selectedColor: scheme.primary,
        side: BorderSide(color: scheme.outlineVariant),
        labelStyle: text.labelMedium!.copyWith(color: scheme.onSurface),
        shape: const StadiumBorder(),
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      ),

      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        linearTrackColor: scheme.surfaceContainerHigh,
        linearMinHeight: 6,
        circularTrackColor: scheme.surfaceContainerHigh,
      ),

      sliderTheme: SliderThemeData(
        trackHeight: 6,
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.surfaceContainerHigh,
        thumbColor: scheme.primary,
        overlayShape: SliderComponentShape.noOverlay,
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium,
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 3,
        focusElevation: 3,
        hoverElevation: 4,
        highlightElevation: 4,
        backgroundColor: scheme.primary,
        foregroundColor: Colors.white,
        extendedTextStyle: text.labelLarge?.copyWith(color: Colors.white),
        shape: const CircleBorder(),
      ),

      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        titleTextStyle: text.titleSmall,
        subtitleTextStyle: text.bodySmall,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),

      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          side: BorderSide(color: scheme.outlineVariant),
          selectedBackgroundColor: scheme.primary,
          selectedForegroundColor: Colors.white,
          textStyle: text.labelLarge,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}

/// Budget state colours, and the spacing scale.
///
/// Held outside the seeded scheme because they mean something specific rather
/// than being a decorative accent a future reseeding may change.
extension AppColors on ColorScheme {
  Color get healthy => brightness == Brightness.light
      ? const Color(0xFF3A9D68)
      : const Color(0xFF5FD891);

  Color get warning => brightness == Brightness.light
      ? const Color(0xFFC97F1E)
      : const Color(0xFFE8A33D);

  Color get exceeded => brightness == Brightness.light
      ? const Color(0xFFD64545)
      : const Color(0xFFF37272);

  /// The assistant surface. Distinct from [primary] and from every status
  /// colour, so guidance never reads as a call to action or a budget-state
  /// verdict the user must obey.
  Color get advisory => brightness == Brightness.light
      ? const Color(0xFF4C5FA8)
      : const Color(0xFFAAB4E6);

  Color statusColor(CategoryStatus status) => switch (status) {
    CategoryStatus.healthy => healthy,
    CategoryStatus.warning => warning,
    CategoryStatus.exceeded => exceeded,
  };

  /// A 12%-alpha wash of any colour, for tinted tiles that stay flat.
  Color tint(Color color) => color.withValues(alpha: 0.12);
}

/// The 4pt spacing scale. Named so layouts cannot drift into arbitrary numbers.
abstract final class Gap {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 28.0;

  static const h4 = SizedBox(height: xs);
  static const h8 = SizedBox(height: sm);
  static const h12 = SizedBox(height: md);
  static const h16 = SizedBox(height: lg);
  static const h20 = SizedBox(height: xl);
  static const h28 = SizedBox(height: xxl);

  static const w4 = SizedBox(width: xs);
  static const w8 = SizedBox(width: sm);
  static const w12 = SizedBox(width: md);
  static const w16 = SizedBox(width: lg);
}

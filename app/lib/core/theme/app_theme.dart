import 'package:budgetwise/core/theme/app_typography.dart';
import 'package:budgetwise_domain/budgetwise_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Modern flat, minimalist, Material 3.
///
/// "Flat" here is a set of rules, not a mood:
///
/// - **No elevation anywhere.** Separation comes from a 1px hairline border and
///   a surface step, never from a shadow. Shadows imply a z-axis this UI does
///   not have, and on a dark theme they read as smudges.
/// - **One accent colour**, used only where the eye must go. A dashboard where
///   six cards are all tinted has no hierarchy at all.
/// - **Generous radii (20–28)**, because bento tiles read as objects rather
///   than as regions of a page.
/// - **Semantic colour is reserved for budget state.** Green/amber/red mean
///   healthy/warning/exceeded and are used for nothing decorative, so a red
///   number on this screen always means the same thing.
abstract final class AppTheme {
  /// A restrained green. Money apps default to blue, which reads as banking;
  /// green here is about growth without being a "profit" colour.
  static const _seed = Color(0xFF1F7A5C);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isLight = brightness == Brightness.light;

    // Hand-tuned neutrals rather than the seeded ones. `fromSeed` tints every
    // surface toward the accent, which at scale makes the whole app look faintly
    // green — the opposite of minimal.
    final scheme =
        ColorScheme.fromSeed(seedColor: _seed, brightness: brightness).copyWith(
          surface: isLight ? const Color(0xFFFBFBFA) : const Color(0xFF0C0D0C),
          surfaceContainerLowest: isLight
              ? const Color(0xFFFFFFFF)
              : const Color(0xFF090A09),
          surfaceContainerLow: isLight
              ? const Color(0xFFFFFFFF)
              : const Color(0xFF131513),
          surfaceContainer: isLight
              ? const Color(0xFFF4F4F2)
              : const Color(0xFF171917),
          surfaceContainerHigh: isLight
              ? const Color(0xFFEDEDEA)
              : const Color(0xFF1D1F1D),
          surfaceContainerHighest: isLight
              ? const Color(0xFFE6E6E3)
              : const Color(0xFF232522),
          onSurface: isLight
              ? const Color(0xFF14161A)
              : const Color(0xFFF2F3F1),
          onSurfaceVariant: isLight
              ? const Color(0xFF6B7280)
              : const Color(0xFF9BA29B),
          outlineVariant: isLight
              ? const Color(0xFFE4E4E1)
              : const Color(0xFF262825),
        );

    final text = AppType.textTheme(scheme);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: AppType.family,
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

      // Cards carry a hairline instead of a shadow. This single choice is most
      // of what makes the UI read as flat.
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: text.labelLarge?.copyWith(fontSize: 15.5),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
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
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 68,
        indicatorColor: scheme.primary.withValues(alpha: 0.12),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? text.labelSmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
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

      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainer,
        selectedColor: scheme.primary.withValues(alpha: 0.14),
        side: BorderSide(color: scheme.outlineVariant),
        labelStyle: text.labelMedium!.copyWith(color: scheme.onSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
        backgroundColor: scheme.surface,
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
          borderRadius: BorderRadius.circular(26),
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
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        extendedTextStyle: text.labelLarge?.copyWith(color: scheme.onPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),

      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        titleTextStyle: text.titleSmall,
        subtitleTextStyle: text.bodySmall,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),

      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          side: BorderSide(color: scheme.outlineVariant),
          selectedBackgroundColor: scheme.primary.withValues(alpha: 0.14),
          selectedForegroundColor: scheme.primary,
          textStyle: text.labelLarge,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
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
      ? const Color(0xFF15803D)
      : const Color(0xFF4ADE80);

  Color get warning => brightness == Brightness.light
      ? const Color(0xFFB45309)
      : const Color(0xFFFBBF24);

  Color get exceeded => brightness == Brightness.light
      ? const Color(0xFFB91C1C)
      : const Color(0xFFF87171);

  /// The assistant surface. Distinct from [primary] so guidance never reads as
  /// a call to action the user must obey.
  Color get advisory => brightness == Brightness.light
      ? const Color(0xFF4F46E5)
      : const Color(0xFFA5B4FC);

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

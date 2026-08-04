import 'package:budgetwise/core/budget/budget_math.dart';
import 'package:flutter/material.dart';

/// The app's visual language.
///
/// One seed colour drives both schemes. The budget status colours are the
/// exception: green/amber/red carry meaning, so they are fixed rather than
/// derived, and each is paired with an explicit `on` colour that meets contrast
/// in both themes. A status the user cannot read is not a status.
abstract final class AppTheme {
  static const _seed = Color(0xFF1B6B4A);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
    );
  }
}

/// Semantic colours for budget state.
///
/// Held outside [ColorScheme] because they mean something specific — "you are
/// close to the limit" — rather than being a decorative accent that a future
/// reseeding is free to change.
extension BudgetColors on ColorScheme {
  Color get healthy => brightness == Brightness.light
      ? const Color(0xFF1E7A4C)
      : const Color(0xFF5FD39A);

  Color get warning => brightness == Brightness.light
      ? const Color(0xFFB26A00)
      : const Color(0xFFFFB74D);

  Color get exceeded => brightness == Brightness.light
      ? const Color(0xFFC0392B)
      : const Color(0xFFFF8A80);

  Color statusColor(CategoryStatus status) => switch (status) {
    CategoryStatus.healthy => healthy,
    CategoryStatus.warning => warning,
    CategoryStatus.exceeded => exceeded,
  };
}

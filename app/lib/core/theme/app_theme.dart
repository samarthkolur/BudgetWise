import 'package:budgetwise/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Dark, sharp-cornered, grey by default — "Obsidian", built from public
/// reporting on CRED's NeoPOP design system after a first re-skin attempt
/// (rounded, light, illustrated) went looking for "pop art meets
/// skeuomorphism" and found a carnival instead of a club. See the design
/// system entry in `CLAUDE.md` for the research and the before/after.
///
/// This supersedes the app's second design language (the Claude Design
/// prototype: warm cream, soft shadows, Space Grotesk). That system is
/// documented in git history; the short version of what changed and why:
///
/// - **Dark-only, not a theme toggle.** CRED ships dark-only by explicit
///   product decision, not omission, and that restraint is load-bearing —
///   see [theme]. There is no light variant any more.
/// - **Zero border-radius, everywhere, no exceptions.** Every card, button,
///   chip and sheet is a sharp rectangle. That single rule is most of the
///   visual signature; see [card].
/// - **Grey does the talking.** The canvas and almost every surface are
///   shades of near-black and grey. Colour is spent on exactly one or two
///   things per screen — never painted across a whole panel.
/// - **Semantic colour keeps its name, not its hue.** [AppColors.healthy],
///   [AppColors.warning], [AppColors.exceeded] and [AppColors.advisory] are
///   unchanged as concepts (and as call sites — nothing downstream of the
///   extension needed to change), only remapped to the new palette.
abstract final class AppTheme {
  // Canvas & surfaces.
  static const _bg = Color(0xFF0A0A0A);
  static const _surface = Color(0xFF141414);
  static const _surfaceAlt = Color(0xFF1B1B1B);
  static const _surfaceHigh = Color(0xFF232323);
  static const _surfaceHighest = Color(0xFF2E2E2E);
  // Bright enough to read as a deliberate outline against the near-black
  // surfaces it separates, not just a slightly-different shade of almost
  // nothing — the complaint was real: at #2B2B2B this was barely visible
  // against #0A0A0A/#141414, so every card, sheet and divider blended into
  // whatever was behind it instead of standing apart from it.
  static const _stroke = Color(0xFF47473F);
  static const _text = Color(0xFFF5F5F2);
  static const _textDim = Color(0xFFC9C9C4);
  static const _textMute = Color(0xFFA3A39D);

  // Voltages. Lime is the default interactive accent (primary); violet is
  // reserved for the one deliberate action per screen — see [AppColors].
  static const _lime = Color(0xFFD4FF3D);
  static const _violet = Color(0xFF7B5CFF);
  static const _amber = Color(0xFFFF8A3D);
  static const _red = Color(0xFFFF5C5C);

  static ThemeData theme() => _build();

  /// Cards never carry a soft shadow in Obsidian — separation is a 1px
  /// stroke, full stop. Kept as a method (rather than deleted outright) only
  /// because [card] still calls it internally; nothing outside this file
  /// should need it.
  static List<BoxShadow> cardShadow() => const [];

  /// The shared "card" decoration every custom card container in the app
  /// builds from: a surface colour, a hairline stroke, and nothing else.
  /// Sharp corners always — there is no `radius` parameter any more, because
  /// there is no case in this design where a card gets one.
  static BoxDecoration card(ColorScheme scheme, {Color? color, Color? tone}) =>
      BoxDecoration(
        color:
            color ??
            (tone == null
                ? scheme.surfaceContainerLow
                : Color.alphaBlend(
                    tone.withValues(alpha: 0.10),
                    scheme.surfaceContainerLow,
                  )),
        border: Border.all(
          color: tone == null
              ? scheme.outlineVariant
              : tone.withValues(alpha: 0.5),
        ),
        boxShadow: cardShadow(),
      );

  static ThemeData _build() {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: _lime,
          brightness: Brightness.dark,
        ).copyWith(
          primary: _lime,
          onPrimary: _bg,
          secondary: _violet,
          onSecondary: Colors.white,
          error: _red,
          onError: Colors.white,
          surface: _bg,
          surfaceContainerLowest: _bg,
          surfaceContainerLow: _surface,
          surfaceContainer: _surfaceAlt,
          surfaceContainerHigh: _surfaceHigh,
          surfaceContainerHighest: _surfaceHighest,
          onSurface: _text,
          onSurfaceVariant: _textMute,
          outline: _textDim,
          outlineVariant: _stroke,
        );

    final text = AppType.textTheme(scheme);
    const sharp = RoundedRectangleBorder();

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: AppType.body,
      textTheme: text,
      scaffoldBackgroundColor: scheme.surface,
      splashFactory: InkRipple.splashFactory,

      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.headlineSmall,
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: sharp.copyWith(
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),

      // Material's default disabled style is a low-alpha overlay meant for a
      // mid-tone surface; against this system's near-black canvas it reads
      // as nothing at all — a button a user cannot even tell is there to
      // wait for. Disabled state gets its own real colours instead of an
      // opacity trick, the same way every other state on a sharp-cornered
      // hairline surface in this system does.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          elevation: 0,
          shape: sharp,
          textStyle: text.labelLarge,
          disabledBackgroundColor: scheme.surfaceContainer,
          disabledForegroundColor: scheme.onSurfaceVariant,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          shape: sharp,
          side: BorderSide(color: scheme.outlineVariant),
          foregroundColor: scheme.onSurface,
          textStyle: text.labelLarge,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: sharp,
          textStyle: text.labelLarge,
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainer,
        hintStyle: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
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
        indicatorColor: Colors.transparent,
        indicatorShape: const Border(
          top: BorderSide(color: _lime, width: 2),
        ),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? text.labelSmall?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w600,
                )
              : text.labelSmall,
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 22,
            color: states.contains(WidgetState.selected)
                ? scheme.onSurface
                : scheme.onSurfaceVariant,
          ),
        ),
      ),

      // Selected-state text colour (near-black on the solid lime fill) is set
      // per chip, not here — `ChipThemeData` has no per-selection-state label
      // style, only a flat default.
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainer,
        selectedColor: scheme.primary,
        side: BorderSide(color: scheme.outlineVariant),
        labelStyle: text.labelMedium!.copyWith(color: scheme.onSurface),
        shape: sharp,
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
        linearMinHeight: 3,
        circularTrackColor: scheme.surfaceContainerHigh,
      ),

      sliderTheme: SliderThemeData(
        trackHeight: 2,
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.surfaceContainerHigh,
        thumbColor: scheme.primary,
        thumbShape: const RectangularSliderThumbShape(),
        overlayShape: SliderComponentShape.noOverlay,
      ),

      bottomSheetTheme: BottomSheetThemeData(
        // One step up from the canvas, not the same colour as it — a sheet
        // that matches the page behind it has no visible edge to separate
        // the two, which is exactly what was happening here.
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        showDragHandle: true,
        dragHandleColor: scheme.outlineVariant,
        shape: sharp,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: sharp.copyWith(
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
        shape: sharp,
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        backgroundColor: scheme.secondary,
        foregroundColor: scheme.onSecondary,
        extendedTextStyle: text.labelLarge?.copyWith(color: scheme.onSecondary),
        shape: sharp,
      ),

      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        titleTextStyle: text.titleSmall,
        subtitleTextStyle: text.bodySmall,
        shape: sharp,
      ),

      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          side: BorderSide(color: scheme.outlineVariant),
          selectedBackgroundColor: scheme.primary,
          selectedForegroundColor: scheme.onPrimary,
          textStyle: text.labelLarge,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          shape: sharp,
        ),
      ),
    );
  }
}

/// A rectangular slider thumb — [SliderThemeData] has no built-in shape that
/// isn't round, so this is the one unavoidable custom painter the zero-radius
/// rule requires.
class RectangularSliderThumbShape extends SliderComponentShape {
  const RectangularSliderThumbShape({this.width = 4, this.height = 20});

  final double width;
  final double height;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => Size(width, height);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final paint = Paint()..color = sliderTheme.thumbColor ?? Colors.white;
    canvas.drawRect(
      Rect.fromCenter(center: center, width: width, height: height),
      paint,
    );
  }
}

/// Budget state colours, and the spacing scale.
///
/// Held outside the seeded scheme because they mean something specific
/// rather than being a decorative accent a future reseeding may change. The
/// getter names are unchanged from the previous design system on purpose —
/// every call site across the app keeps working; only the hex values moved.
extension AppColors on ColorScheme {
  Color get healthy => AppTheme._lime;
  Color get warning => AppTheme._amber;
  Color get exceeded => AppTheme._red;

  /// The assistant surface. Distinct from [primary] (budget-state lime) and
  /// from every status colour, so guidance never reads as a call to action
  /// or a budget-state verdict the user must obey. Doubles as this system's
  /// "the one action" violet.
  Color get advisory => AppTheme._violet;

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

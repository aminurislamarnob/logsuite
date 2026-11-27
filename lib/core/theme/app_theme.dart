import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';
import 'app_palette.dart';

export 'app_palette.dart' show ModuleColors;

const _nativeE2e = bool.fromEnvironment('E2E_TEST');

/// Shape tokens for the coral rebrand. The reference design groups content into
/// large, softly rounded cards and uses full pills for anything tappable.
class AppRadii {
  const AppRadii._();

  /// Hero ink cards.
  static const hero = 28.0;

  /// Big section cards and grouped containers.
  static const card = 24.0;

  /// Stat tiles, list rows and other nested surfaces.
  static const tile = 20.0;

  /// Inputs, icon chips (44–48 square) and buttons.
  static const field = 16.0;

  /// Small icon chips (36–40 square).
  static const chipSmall = 12.0;

  /// Bottom sheets.
  static const sheet = 32.0;

  static const cardShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(card)),
  );
  static const tileShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(tile)),
  );
}

/// Elevation shadows for light mode. Dark mode separates surfaces by fill
/// alone and receives an empty list.
class AppShadows {
  const AppShadows._();

  static List<BoxShadow> card(Brightness brightness) =>
      brightness == Brightness.dark
      ? const []
      : const [
          BoxShadow(
            color: Color(0x0D1A1614),
            offset: Offset(0, 1),
            blurRadius: 2,
          ),
          BoxShadow(
            color: Color(0x0F1A1614),
            offset: Offset(0, 6),
            blurRadius: 20,
          ),
        ];

  static List<BoxShadow> circleButton(Brightness brightness) =>
      brightness == Brightness.dark
      ? const []
      : const [
          BoxShadow(
            color: Color(0x0D1A1614),
            offset: Offset(0, 1),
            blurRadius: 2,
          ),
          BoxShadow(
            color: Color(0x0F1A1614),
            offset: Offset(0, 4),
            blurRadius: 14,
          ),
        ];

  static List<BoxShadow> hero(Brightness brightness) =>
      brightness == Brightness.dark
      ? const []
      : const [
          BoxShadow(
            color: Color(0x381A1614),
            offset: Offset(0, 16),
            blurRadius: 40,
          ),
        ];

  static List<BoxShadow> navBar(Brightness brightness) =>
      brightness == Brightness.dark
      ? const []
      : const [
          BoxShadow(
            color: Color(0x471A1614),
            offset: Offset(0, 14),
            blurRadius: 36,
          ),
        ];

  static List<BoxShadow> composer(Brightness brightness) =>
      brightness == Brightness.dark
      ? const []
      : const [
          BoxShadow(
            color: Color(0x241A1614),
            offset: Offset(0, 14),
            blurRadius: 36,
          ),
        ];
}

/// Spacing tokens. Every screen lays itself out on these four numbers so the
/// edges line up from page to page: the top bar's circles, a list's cards and
/// a tab strip's first pill all start [gutter] in from the screen edge.
class AppSpacing {
  const AppSpacing._();

  /// The inset from the screen edge to page content, and the inset the top
  /// bar's action circles sit at.
  static const gutter = 20.0;

  /// The vertical gap between two sections on a page.
  static const section = 24.0;

  /// The gap between two cards stacked in a list.
  static const card = 10.0;

  /// The gap between two cards side by side in a grid or a horizontal rail.
  static const grid = 12.0;

  /// Clearance a scrolling page keeps under its last row for a floating
  /// action button, above the device's bottom inset.
  static const fabClearance = 96.0;

  /// The breathing room under a page's last row when nothing floats over it,
  /// above the device's bottom inset.
  static const pageEnd = 24.0;
}

/// Extra brand colours the [ColorScheme] has no slot for, hung off the theme so
/// widgets can read them without importing [AppColors] and hardcoding a mode.
@immutable
class BrandColors extends ThemeExtension<BrandColors> {
  /// The rotating pastel card fills.
  final List<Color> tints;

  /// The faintest grey: chart gridlines, progress tracks, dividers.
  final Color hairline;

  /// The page background behind the cards.
  final Color canvas;

  /// Card, row, input, and circle button surface fill.
  final Color surface;

  /// Primary text, ink hero cards, nav bar, primary buttons, selected segments.
  final Color ink;

  /// Full-screen dark surface (Focus, lock screen) in both light and dark.
  final Color inkDeep;

  /// Decorative only: chevrons, inactive icons, 20px+ numerals.
  final Color subtle;

  /// Foreground on [ink] (white in light, backgroundDark in dark).
  final Color onInk;

  /// Secondary text on [ink] / [heroSurface].
  final Color onInkMuted;

  /// Hero card fill ([ink] in light, raised surface in dark).
  final Color heroSurface;

  /// Empty progress bars, empty heatmap cells.
  final Color track;

  /// Background of segmented controls.
  final Color well;

  /// Unchecked checkbox and radio rings.
  final Color outlineIdle;

  /// The three status hues. Read these rather than [AppColors] directly: only
  /// the theme knows which brightness is in play, and the light variants on a
  /// charcoal page are the bug this extension exists to prevent.
  final Color success;
  final Color warning;
  final Color danger;

  /// One accent per feature module, so a note stays amber and a task stays
  /// indigo wherever they surface.
  final Color note;
  final Color medicine;
  final Color habit;
  final Color task;
  final Color expense;
  final Color focus;
  final Color drop;

  /// Four-role module & status palettes (accent, graphicOnTint, textOnTint,
  /// tintFill, onInk).
  final ModuleColors medicineRoles;
  final ModuleColors taskRoles;
  final ModuleColors habitRoles;
  final ModuleColors expenseRoles;
  final ModuleColors focusRoles;
  final ModuleColors noteRoles;
  final ModuleColors dropRoles;
  final ModuleColors successRoles;
  final ModuleColors warningRoles;
  final ModuleColors dangerRoles;

  const BrandColors({
    required this.tints,
    required this.hairline,
    required this.canvas,
    required this.surface,
    required this.ink,
    required this.inkDeep,
    required this.subtle,
    required this.onInk,
    required this.onInkMuted,
    required this.heroSurface,
    required this.track,
    required this.well,
    required this.outlineIdle,
    required this.success,
    required this.warning,
    required this.danger,
    required this.note,
    required this.medicine,
    required this.habit,
    required this.task,
    required this.expense,
    required this.focus,
    required this.drop,
    required this.medicineRoles,
    required this.taskRoles,
    required this.habitRoles,
    required this.expenseRoles,
    required this.focusRoles,
    required this.noteRoles,
    required this.dropRoles,
    required this.successRoles,
    required this.warningRoles,
    required this.dangerRoles,
  });

  /// Resolves the four-role palette for any module or status [accent].
  ModuleColors roleFor(Color accent) {
    if (accent == medicine) return medicineRoles;
    if (accent == task) return taskRoles;
    if (accent == habit) return habitRoles;
    if (accent == expense) return expenseRoles;
    if (accent == focus) return focusRoles;
    if (accent == note) return noteRoles;
    if (accent == drop) return dropRoles;
    if (accent == success) return successRoles;
    if (accent == warning) return warningRoles;
    if (accent == danger) return dangerRoles;
    final brightness = canvas.computeLuminance() < 0.2
        ? Brightness.dark
        : Brightness.light;
    return ModuleColors.derive(
      accent,
      onInk: accent,
      brightness: brightness,
      surface: surface,
    );
  }

  /// The pastel fill for the card at [index] in a row or grid.
  Color tint(int index) => tints[index % tints.length];

  /// The foreground for anything filled with an accent or status hue — a
  /// module glyph on its colour, a swipe action, the Focus timer's button.
  ///
  /// Not simply white. In light mode every accent is a mid-dark hue and white
  /// clears it; in dark mode the accents lift so they read on charcoal, and
  /// white on a lifted accent lands around 2:1. The page canvas is the other
  /// candidate: white itself in light, near-black in dark. Whichever contrasts
  /// more wins, so the rule holds for any accent a future palette brings.
  Color onAccent(Color accent) {
    final la = accent.computeLuminance();
    double ratio(Color c) {
      final l = c.computeLuminance();
      final hi = l > la ? l : la;
      final lo = l > la ? la : l;
      return (hi + 0.05) / (lo + 0.05);
    }

    return ratio(canvas) > ratio(Colors.white) ? canvas : Colors.white;
  }

  /// A reasonable stand-in derived from any [ThemeData], for the case where a
  /// widget is built under a theme that never registered the extension.
  factory BrandColors.fallback(ThemeData theme) {
    // The default palette, since a theme that never registered the extension
    // cannot say which one the user picked.
    final p = AppPalette.coral.spec(theme.brightness);
    return BrandColors(
      tints: p.tints,
      hairline: p.hairline,
      canvas: theme.scaffoldBackgroundColor,
      surface: p.surface,
      ink: p.ink,
      inkDeep: AppColors.inkDeep,
      subtle: p.subtle,
      onInk: p.onInk,
      onInkMuted: p.onInkMuted,
      heroSurface: p.heroSurface,
      track: p.track,
      well: p.well,
      outlineIdle: p.outlineIdle,
      success: p.success,
      warning: p.warning,
      danger: p.danger,
      note: p.note,
      medicine: p.medicine,
      habit: p.habit,
      task: p.task,
      expense: p.expense,
      focus: p.focus,
      drop: p.drop,
      medicineRoles: p.medicineRoles,
      taskRoles: p.taskRoles,
      habitRoles: p.habitRoles,
      expenseRoles: p.expenseRoles,
      focusRoles: p.focusRoles,
      noteRoles: p.noteRoles,
      dropRoles: p.dropRoles,
      successRoles: p.successRoles,
      warningRoles: p.warningRoles,
      dangerRoles: p.dangerRoles,
    );
  }

  @override
  BrandColors copyWith({
    List<Color>? tints,
    Color? hairline,
    Color? canvas,
    Color? surface,
    Color? ink,
    Color? inkDeep,
    Color? subtle,
    Color? onInk,
    Color? onInkMuted,
    Color? heroSurface,
    Color? track,
    Color? well,
    Color? outlineIdle,
    Color? success,
    Color? warning,
    Color? danger,
    Color? note,
    Color? medicine,
    Color? habit,
    Color? task,
    Color? expense,
    Color? focus,
    Color? drop,
    ModuleColors? medicineRoles,
    ModuleColors? taskRoles,
    ModuleColors? habitRoles,
    ModuleColors? expenseRoles,
    ModuleColors? focusRoles,
    ModuleColors? noteRoles,
    ModuleColors? dropRoles,
    ModuleColors? successRoles,
    ModuleColors? warningRoles,
    ModuleColors? dangerRoles,
  }) {
    return BrandColors(
      tints: tints ?? this.tints,
      hairline: hairline ?? this.hairline,
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      ink: ink ?? this.ink,
      inkDeep: inkDeep ?? this.inkDeep,
      subtle: subtle ?? this.subtle,
      onInk: onInk ?? this.onInk,
      onInkMuted: onInkMuted ?? this.onInkMuted,
      heroSurface: heroSurface ?? this.heroSurface,
      track: track ?? this.track,
      well: well ?? this.well,
      outlineIdle: outlineIdle ?? this.outlineIdle,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      note: note ?? this.note,
      medicine: medicine ?? this.medicine,
      habit: habit ?? this.habit,
      task: task ?? this.task,
      expense: expense ?? this.expense,
      focus: focus ?? this.focus,
      drop: drop ?? this.drop,
      medicineRoles: medicineRoles ?? this.medicineRoles,
      taskRoles: taskRoles ?? this.taskRoles,
      habitRoles: habitRoles ?? this.habitRoles,
      expenseRoles: expenseRoles ?? this.expenseRoles,
      focusRoles: focusRoles ?? this.focusRoles,
      noteRoles: noteRoles ?? this.noteRoles,
      dropRoles: dropRoles ?? this.dropRoles,
      successRoles: successRoles ?? this.successRoles,
      warningRoles: warningRoles ?? this.warningRoles,
      dangerRoles: dangerRoles ?? this.dangerRoles,
    );
  }

  @override
  BrandColors lerp(BrandColors? other, double t) {
    if (other == null) return this;
    return BrandColors(
      tints: [
        for (var i = 0; i < tints.length; i++)
          Color.lerp(tints[i], other.tints[i], t)!,
      ],
      hairline: Color.lerp(hairline, other.hairline, t)!,
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkDeep: Color.lerp(inkDeep, other.inkDeep, t)!,
      subtle: Color.lerp(subtle, other.subtle, t)!,
      onInk: Color.lerp(onInk, other.onInk, t)!,
      onInkMuted: Color.lerp(onInkMuted, other.onInkMuted, t)!,
      heroSurface: Color.lerp(heroSurface, other.heroSurface, t)!,
      track: Color.lerp(track, other.track, t)!,
      well: Color.lerp(well, other.well, t)!,
      outlineIdle: Color.lerp(outlineIdle, other.outlineIdle, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      note: Color.lerp(note, other.note, t)!,
      medicine: Color.lerp(medicine, other.medicine, t)!,
      habit: Color.lerp(habit, other.habit, t)!,
      task: Color.lerp(task, other.task, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
      focus: Color.lerp(focus, other.focus, t)!,
      drop: Color.lerp(drop, other.drop, t)!,
      medicineRoles: ModuleColors.lerp(medicineRoles, other.medicineRoles, t),
      taskRoles: ModuleColors.lerp(taskRoles, other.taskRoles, t),
      habitRoles: ModuleColors.lerp(habitRoles, other.habitRoles, t),
      expenseRoles: ModuleColors.lerp(expenseRoles, other.expenseRoles, t),
      focusRoles: ModuleColors.lerp(focusRoles, other.focusRoles, t),
      noteRoles: ModuleColors.lerp(noteRoles, other.noteRoles, t),
      dropRoles: ModuleColors.lerp(dropRoles, other.dropRoles, t),
      successRoles: ModuleColors.lerp(successRoles, other.successRoles, t),
      warningRoles: ModuleColors.lerp(warningRoles, other.warningRoles, t),
      dangerRoles: ModuleColors.lerp(dangerRoles, other.dangerRoles, t),
    );
  }
}

/// The resolved brand palette for one appearance.
///
/// Both the Material [ThemeData] and the forui `FThemeData` are built from an
/// instance of this, so a colour can only be changed in one place and the two
/// component systems cannot drift apart.
@immutable
class BrandTokens {
  final Brightness brightness;
  final AppPalette palette;
  final bool compact;
  final String locale;

  /// Body copy and headings.
  final Color text;

  /// Supporting copy, placeholder text, unselected icons.
  final Color muted;

  /// The page background.
  final Color background;

  /// Raised surfaces — dialogs, sheets, popovers.
  final Color surface;

  final Color primary;
  final Color onPrimary;
  final Color secondary;
  final Color error;

  /// Tints, hairline and canvas — the values with no [ColorScheme] slot.
  final BrandColors brand;

  const BrandTokens({
    required this.brightness,
    required this.palette,
    required this.compact,
    required this.locale,
    required this.text,
    required this.muted,
    required this.background,
    required this.surface,
    required this.primary,
    required this.onPrimary,
    required this.secondary,
    required this.error,
    required this.brand,
  });

  bool get isDark => brightness == Brightness.dark;

  /// The font family for [locale]. Bangla glyphs are absent from Bricolage
  /// Grotesque, so Bengali falls back to Hind Siliguri.
  String get fontFamily => _nativeE2e
      ? 'sans-serif'
      : (locale == 'bn'
                ? GoogleFonts.hindSiliguri()
                : GoogleFonts.bricolageGrotesque())
            .fontFamily!;
}

extension BrandTheme on BuildContext {
  /// The brand palette for the nearest [Theme].
  ///
  /// Falls back to a scheme-derived approximation rather than throwing, so a
  /// widget still renders under a plain [MaterialApp] — Flutter's own default
  /// themes, `showDialog` overrides and widget tests all supply one.
  BrandColors get brand {
    final theme = Theme.of(this);
    return theme.extension<BrandColors>() ?? BrandColors.fallback(theme);
  }

  /// The muted body-copy grey. Shorthand for the most-repeated lookup in the
  /// codebase.
  Color get muted => Theme.of(this).colorScheme.outline;

  /// The subtle caption / eyebrow grey from [BrandColors.subtle].
  Color get subtle => brand.subtle;
}

class AppTheme {
  const AppTheme._();

  /// Bangla glyphs are absent from Bricolage Grotesque, so the Bengali locale
  /// swaps in Hind Siliguri. Both are served through google_fonts.
  static TextTheme _textTheme(TextTheme base, Color body, String locale) {
    final themed = _nativeE2e
        ? base
        : locale == 'bn'
        ? GoogleFonts.hindSiliguriTextTheme(base)
        : GoogleFonts.bricolageGrotesqueTextTheme(base);
    return themed
        .apply(bodyColor: body, displayColor: body)
        .copyWith(
          // The design sets headings in heavy, tight-tracked weights and lets
          // the muted grey carry the supporting copy.
          displayLarge: themed.displayLarge?.copyWith(
            fontSize: 48,
            fontWeight: FontWeight.w800,
            letterSpacing: -2,
            color: body,
          ),
          displayMedium: themed.displayMedium?.copyWith(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.9,
            color: body,
          ),
          displaySmall: themed.displaySmall?.copyWith(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
            color: body,
          ),
          headlineMedium: themed.headlineMedium?.copyWith(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
            color: body,
          ),
          headlineSmall: themed.headlineSmall?.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: body,
          ),
          titleLarge: themed.titleLarge?.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: body,
          ),
          titleMedium: themed.titleMedium?.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: body,
          ),
          titleSmall: themed.titleSmall?.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: body,
          ),
          bodyLarge: themed.bodyLarge?.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: body,
          ),
          bodyMedium: themed.bodyMedium?.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: body,
          ),
          bodySmall: themed.bodySmall?.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: body,
          ),
          labelSmall: themed.labelSmall?.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: body,
          ),
        );
  }

  /// Resolves the brand palette for one appearance.
  ///
  /// This is the single place a brand colour is decided. `light()`, `dark()` and
  /// `brandForuiTheme()` all read from it.
  static BrandTokens tokens({
    required Brightness brightness,
    AppPalette palette = AppPalette.coral,
    bool compact = false,
    String locale = 'en',
  }) {
    final p = palette.spec(brightness);

    return BrandTokens(
      brightness: brightness,
      palette: palette,
      compact: compact,
      locale: locale,
      text: p.text,
      muted: p.muted,
      background: p.background,
      surface: p.surface,
      primary: p.primary,
      onPrimary: p.onPrimary,
      secondary: p.secondary,
      error: p.danger,
      brand: BrandColors(
        tints: p.tints,
        hairline: p.hairline,
        canvas: p.background,
        surface: p.surface,
        ink: p.ink,
        inkDeep: AppColors.inkDeep,
        subtle: p.subtle,
        onInk: p.onInk,
        onInkMuted: p.onInkMuted,
        heroSurface: p.heroSurface,
        track: p.track,
        well: p.well,
        outlineIdle: p.outlineIdle,
        success: p.success,
        warning: p.warning,
        danger: p.danger,
        note: p.note,
        medicine: p.medicine,
        habit: p.habit,
        task: p.task,
        expense: p.expense,
        focus: p.focus,
        drop: p.drop,
        medicineRoles: p.medicineRoles,
        taskRoles: p.taskRoles,
        habitRoles: p.habitRoles,
        expenseRoles: p.expenseRoles,
        focusRoles: p.focusRoles,
        noteRoles: p.noteRoles,
        dropRoles: p.dropRoles,
        successRoles: p.successRoles,
        warningRoles: p.warningRoles,
        dangerRoles: p.dangerRoles,
      ),
    );
  }

  static ThemeData light({
    AppPalette palette = AppPalette.coral,
    bool compact = false,
    String locale = 'en',
  }) {
    final t = tokens(
      brightness: Brightness.light,
      palette: palette,
      compact: compact,
      locale: locale,
    );
    return _build(
      t,
      ColorScheme.light(
        primary: t.primary,
        onPrimary: t.onPrimary,
        secondary: t.secondary,
        surface: t.surface,
        error: t.error,
        onSurface: t.text,
        outline: t.muted,
        // `surfaceContainer` is the pastel fill Material picks for grouped
        // content, so pointing it at the peach tint brands stock widgets too.
        surfaceContainer: t.brand.tints.first,
        surfaceContainerHighest: t.brand.tints[1],
      ),
    );
  }

  static ThemeData dark({
    AppPalette palette = AppPalette.coral,
    bool compact = false,
    String locale = 'en',
  }) {
    final t = tokens(
      brightness: Brightness.dark,
      palette: palette,
      compact: compact,
      locale: locale,
    );
    return _build(
      t,
      ColorScheme.dark(
        primary: t.primary,
        onPrimary: t.onPrimary,
        secondary: t.secondary,
        surface: t.surface,
        error: t.error,
        onSurface: t.text,
        outline: t.muted,
        surfaceContainer: t.brand.tints.first,
        surfaceContainerHighest: t.brand.tints.last,
      ),
    );
  }

  static ThemeData _build(BrandTokens t, ColorScheme scheme) {
    final brightness = t.brightness;
    final background = t.background;
    final surface = t.surface;
    final text = t.text;
    final muted = t.muted;
    final primary = t.primary;
    final onPrimary = t.onPrimary;
    final brand = t.brand;
    final compact = t.compact;
    final locale = t.locale;

    final base = brightness == Brightness.light
        ? ThemeData.light()
        : ThemeData.dark();
    final textTheme = _textTheme(base.textTheme, text, locale);

    OutlineInputBorder field(Color color, double width) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadii.field),
      borderSide: BorderSide(color: color, width: width),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
      textTheme: textTheme,
      extensions: [brand],
      splashFactory: InkSparkle.splashFactory,
      // Every push slides in from the trailing edge with the iOS parallax and
      // the interactive swipe-back, on every platform. Flutter only does this
      // on iOS and macOS by default; Android gets a zoom that reads as a
      // different app.
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          for (final platform in TargetPlatform.values)
            platform: const CupertinoPageTransitionsBuilder(),
        },
      ),
      dividerTheme: DividerThemeData(
        color: brand.hairline,
        space: 1,
        thickness: 1,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: text),
        titleTextStyle: textTheme.titleMedium?.copyWith(fontSize: 17),
      ),
      cardTheme: CardThemeData(
        color: brand.tints.first,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.tile),
        ),
        margin: EdgeInsets.zero,
      ),
      // No `chipTheme`: every chip is a `Pill` or `BrandChip` now, both of which
      // draw their own stadium. Same reason `elevatedButtonTheme` went.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: brand.tints.first,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: field(Colors.transparent, 0),
        enabledBorder: field(Colors.transparent, 0),
        focusedBorder: field(primary, 1.6),
        errorBorder: field(scheme.error, 1.2),
        focusedErrorBorder: field(scheme.error, 1.6),
        labelStyle: TextStyle(color: muted),
        hintStyle: TextStyle(color: muted),
        prefixIconColor: muted,
        suffixIconColor: muted,
      ),
      // No `elevatedButtonTheme`: zero call sites.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          side: BorderSide(color: brand.hairline),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: text),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        elevation: 6,
        shape: const CircleBorder(),
      ),
      // No `navigationBarTheme`: the shell uses `CurvedNavBar`, not
      // `NavigationBar`.
      listTileTheme: ListTileThemeData(
        iconColor: muted,
        textColor: text,
        titleTextStyle: textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
        subtitleTextStyle: textTheme.bodySmall?.copyWith(color: muted),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.field),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: brightness == Brightness.light
            ? const Color(0xFF1C1512)
            : brand.tints.first,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
        // The toast is dark in both themes, so its action takes the
        // palette's dark-mode primary whichever theme is live.
        actionTextColor: t.palette.spec(Brightness.dark).primary,
        insetPadding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.field),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: brand.hairline,
        circularTrackColor: brand.hairline,
        linearMinHeight: 8,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? brand.onInk
              : (brightness == Brightness.dark ? brand.onInkMuted : surface),
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? brand.ink : brand.well,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? brand.ink
              : muted.withValues(alpha: 0.4),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: primary,
        inactiveTrackColor: brand.hairline,
        thumbColor: Colors.white,
        overlayColor: primary.withValues(alpha: 0.12),
        trackHeight: 4,
      ),
      // No `tabBarTheme`: every tab strip is `FTabs` now, and this theme was
      // actively harmful — `TabBarThemeData.labelColor` takes precedence over
      // `labelStyle.color` inside Material's `TabBar`, which is what FTabs builds
      // on, so it silently overrode the branded forui tab colours.
      dialogTheme: DialogThemeData(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
        titleTextStyle: textTheme.titleLarge,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        showDragHandle: false,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadii.sheet),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// The logSuite palette, rebuilt around the coral fitness identity.
///
/// The design leans on one saturated accent (`#F15F43`) sitting on a pure white
/// page, with content grouped into large, barely-there pastel cards rather than
/// outlined boxes. Module colours were re-tinted into the same warm family so
/// six modules still read apart without any of them fighting the brand coral.
class AppColors {
  const AppColors._();

  // ---------------------------------------------------------------------------
  // Brand
  // ---------------------------------------------------------------------------

  /// The single brand accent: FABs, rings, active nav, primary buttons.
  ///
  /// Five percent below the `#FF6547` the design shipped with. The flagship
  /// module carries the brand, so this doubles as the medicine glyph drawn on
  /// a medicine card — and at the original value that pair sat at 2.70:1,
  /// under the 3:1 the contrast gate holds every accent to.
  static const coral = Color(0xFFF15F43);
  static const coralDeep = Color(0xFFE24E32);
  static const coralSoft = Color(0xFFFFAA99);

  /// The near-black that sits on coral. Dark mode always used it; light mode
  /// used white, at 2.91:1 — below AA for the label on a primary button.
  static const onCoral = Color(0xFF3A1206);

  // Light theme
  static const ink = Color(0xFF1A1614);
  static const inkDeep = backgroundDark;
  static const primaryLight = coral;
  static const successLight = Color(0xFF1F6B45);
  static const warningLight = Color(0xFF94540E);
  static const dangerLight = Color(0xFFB3261E);
  static const backgroundLight = Color(0xFFF4F1EE);
  static const surfaceLight = Color(0xFFFFFFFF);
  static const textLight = ink;
  static const mutedLight = Color(0xFF6B625C);
  static const subtleLight = Color(0xFF8C847F);
  static const onInkMuted = Color(0xFFB5ADA8);

  /// The faintest grey in the design — chart gridlines, inactive day labels,
  /// progress tracks. Too light for body copy.
  static const hairlineLight = Color(0xFFF0ECE8);
  static const trackLight = Color(0xFFEFEAE6);
  static const wellLight = Color(0xFFE8E3DF);
  static const outlineIdleLight = Color(0xFFD4CEC8);

  // Dark theme. The reference file is light-only, so the dark side keeps the
  // same coral on a warm-neutral charcoal rather than inventing a second hue.
  static const primaryDark = Color(0xFFFF7D63);
  static const successDark = Color(0xFF56CE8E);
  static const warningDark = Color(0xFFFFB95C);
  static const dangerDark = Color(0xFFFF6B6F);
  static const backgroundDark = Color(0xFF14100F);
  static const surfaceDark = Color(0xFF1F1A19);
  static const heroSurfaceDark = Color(0xFF2A2422);
  static const textDark = Color(0xFFF5EFED);
  static const mutedDark = Color(0xFFA79E9B);
  static const subtleDark = Color(0xFF736B67);
  static const hairlineDark = Color(0xFF2C2523);
  static const trackDark = Color(0xFF2C2523);
  static const wellDark = Color(0xFF26201E);
  static const outlineIdleDark = Color(0xFF4A423F);

  // ---------------------------------------------------------------------------
  // Card tints
  // ---------------------------------------------------------------------------

  /// The three pastel card fills lifted straight from the reference screens.
  /// They rotate across a row of cards to keep a grid from looking flat.
  static const tintPeach = Color(0xFFFFF4F2);
  static const tintApricot = Color(0xFFFFF8F2);
  static const tintCream = Color(0xFFFFFEF2);

  static const tints = <Color>[tintPeach, tintApricot, tintCream];

  /// The dark-mode stand-ins for [tints] — the same rotation, but as barely
  /// lifted surfaces so the cards stay readable on charcoal.
  static const tintsDark = <Color>[
    Color(0xFF2A2120),
    Color(0xFF272120),
    Color(0xFF262322),
  ];

  /// Picks a card tint for [index], wrapping around the rotation.
  static Color tint(int index, {Brightness brightness = Brightness.light}) {
    final table = brightness == Brightness.dark ? tintsDark : tints;
    return table[index % table.length];
  }

  // ---------------------------------------------------------------------------
  // Module accents
  // ---------------------------------------------------------------------------

  /// Habit shares a hue with success, and neither is held to a stricter bar
  /// than the other, so one value serves both.
  ///
  /// Note used to do the same with [warningLight] and paid for it: `warning`
  /// is drawn as 11px text on the medicine screen, so it carries the 4.5:1
  /// body-copy bar, while `note` is only ever an icon or a fill. Holding an
  /// icon to a text bar cost it a fifth of its brightness for nothing.
  static const noteAccent = Color(0xFFC38131); // amber
  static const medicineAccent = coral; // the flagship module carries the brand
  static const habitAccent = Color(0xFF2D8657); // moss green
  static const taskAccent = Color(0xFF5B7CE0); // muted indigo
  static const expenseAccent = Color(0xFF9A6DD7); // warm violet
  static const focusAccent = Color(0xFF349CA5); // teal
  static const dropAccent = Color(0xFF0284C7); // sky / sapphire blue

  /// The dark-mode twins. Note and habit share a hue with warning and success,
  /// so they reuse those already-tuned darks; the rest apply the same lift the
  /// existing pairs use — saturation x0.85, value x1.10 — which is what keeps a
  /// saturated light accent from vibrating against the charcoal page.
  static const noteAccentDark = warningDark;
  static const medicineAccentDark = primaryDark;
  static const habitAccentDark = successDark;
  static const taskAccentDark = Color(0xFF7E9CF6);
  static const expenseAccentDark = Color(0xFFB58DEC);
  static const focusAccentDark = Color(0xFF59C2CC);
  static const dropAccentDark = Color(0xFF38BDF8);

  /// A soft page-card fill derived from any accent, matching the density of the
  /// hand-picked [tints] so a module card sits happily next to a brand card.
  static Color wash(Color accent, {Brightness brightness = Brightness.light}) =>
      brightness == Brightness.dark
      ? Color.alphaBlend(accent.withValues(alpha: 0.14), surfaceDark)
      : Color.alphaBlend(accent.withValues(alpha: 0.07), Colors.white);

  // ---------------------------------------------------------------------------
  // Redesign module & status roles (Coral light)
  // ---------------------------------------------------------------------------

  // Medicine / brand
  static const medicineGraphicOnTint = coralDeep;
  static const medicineTextOnTint = Color(0xFFB23A1F);
  static const medicineTintFill = Color(0xFFFFE7E0);

  // Tasks
  static const taskGraphicOnTint = Color(0xFF4A67C4);
  static const taskTextOnTint = Color(0xFF3B4F8F);
  static const taskTintFill = Color(0xFFEAEFFD);

  // Habits
  static const habitGraphicOnTint = Color(0xFF2D8657);
  static const habitTextOnTint = Color(0xFF1F5E3D);
  static const habitTintFill = Color(0xFFE6F4EC);

  // Expenses
  static const expenseGraphicOnTint = Color(0xFF7E52BE);
  static const expenseTextOnTint = Color(0xFF6A41A8);
  static const expenseTintFill = Color(0xFFF4EEFB);

  // Focus
  static const focusGraphicOnTint = Color(0xFF2B8790);
  static const focusTextOnTint = Color(0xFF1F6A72);
  static const focusTintFill = Color(0xFFE6F4F5);

  // Notes
  static const noteGraphicOnTint = Color(0xFFA86C22);
  static const noteTextOnTint = Color(0xFF8A5A1F);
  static const noteTintFill = Color(0xFFFCF4E6);

  // Drop
  static const dropGraphicOnTint = Color(0xFF0274B0);
  static const dropTextOnTint = Color(0xFF02598A);
  static const dropTintFill = Color(0xFFE3F1FA);

  // Status roles (light)
  static const dangerTextOnTint = Color(0xFFB3261E);
  static const dangerTintFill = Color(0xFFFDECEA);
  static const warningGraphicOnTint = Color(0xFFB86E18);
  static const warningTextOnTint = Color(0xFFA35E12);
  static const warningTintFill = Color(0xFFFBF1E3);
  static const successTextOnTint = Color(0xFF1F6B45);
  static const successTintFill = Color(0xFFE6F4EC);
}

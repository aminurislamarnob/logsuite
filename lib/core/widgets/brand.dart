import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../utils/haptics.dart';

/// The signature pieces of the coral fitness identity.
///
/// Everything here reads its colours from the active [Theme] and the
/// [BrandColors] extension, so light, dark and high-contrast all stay legible
/// without any screen hardcoding a palette.

// ---------------------------------------------------------------------------
// Surfaces
// ---------------------------------------------------------------------------

/// The workhorse of the design: a large, softly rounded card on a barely-there
/// pastel fill, with no border and no shadow.
///
/// Pass [tintIndex] to rotate through the three brand pastels so a row of cards
/// does not read as one flat block, or [accent] to derive the fill from a
/// module colour instead.
/// Marks the subtree of a [TintCard].
///
/// A tile inside a card must not paint its own fill or outline — the card is
/// the surface, and a second one just inside its edge reads as a card within a
/// card. `BrandTile` reads this to know when to stand down.
class CardScope extends InheritedWidget {
  const CardScope({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CardScope>() != null;

  @override
  bool updateShouldNotify(CardScope old) => false;
}

class TintCard extends StatelessWidget {
  final Widget child;
  final int tintIndex;
  final Color? accent;
  final Color? fill;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const TintCard({
    super.key,
    required this.child,
    this.tintIndex = 0,
    this.accent,
    this.fill,
    this.padding = const EdgeInsets.all(20),
    this.radius = AppRadii.tile,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final background =
        fill ??
        (accent == null
            ? brand.tint(tintIndex)
            : brand.roleFor(accent!).tintFill);

    final corners = BorderRadius.circular(radius);
    final body = CardScope(
      child: Padding(padding: padding, child: child),
    );

    return FCard(
      // The tint rotation and the radius are brand decisions, so they are
      // passed explicitly rather than inherited from forui's card style —
      // which is a bordered, unfilled, small-radius surface.
      style: .delta(
        decoration: .boxDelta(
          color: background,
          borderRadius: corners,
          border: const Border(),
          boxShadow: AppShadows.card(theme.brightness),
        ),
        padding: .value(EdgeInsets.zero),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null && onLongPress == null
          ? body
          : FTappable(
              onPress: onTap == null
                  ? null
                  : () {
                      AppHaptics.tap();
                      onTap!();
                    },
              onLongPress: onLongPress == null
                  ? null
                  : () {
                      AppHaptics.medium();
                      onLongPress!();
                    },
              // A card is a surface, not a control; only the inner content
              // should announce itself.
              semanticsButton: false,
              child: body,
            ),
    );
  }
}

/// The thin outlined circle that holds the bell, close and settings glyphs in
/// the reference screens' top bars.
class CircleIconButton extends StatelessWidget {
  final HugeIconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final Color? color;

  /// Fills the circle with [color] and inverts the glyph, for the one primary
  /// action in a bar.
  final bool filled;

  /// Translucent white fill (`rgba(255,255,255,.08)`) with white icon, for
  /// buttons sitting on an ink hero card or dark surface.
  final bool onInk;

  /// Count drawn as a small accent badge, for the reminders button. Hidden
  /// when null or below 1.
  final int? badgeCount;

  const CircleIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.size = 44,
    this.color,
    this.filled = false,
    this.onInk = false,
    this.badgeCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final tone = color ?? brand.ink;

    final Color bg;
    final Color fg;
    final List<BoxShadow> shadows;
    if (onInk) {
      bg = Colors.white.withValues(alpha: 0.08);
      fg = Colors.white;
      shadows = const [];
    } else if (filled) {
      bg = tone;
      fg = brand.onAccent(tone);
      shadows = AppShadows.circleButton(theme.brightness);
    } else {
      bg = brand.surface;
      fg = tone;
      shadows = AppShadows.circleButton(theme.brightness);
    }

    final button = FTappable(
      key: tooltip == null
          ? null
          : ValueKey('button-${tooltip!.toLowerCase().replaceAll(' ', '-')}'),
      onPress: onPressed == null
          ? null
          : () {
              AppHaptics.tap();
              onPressed!();
            },
      semanticsLabel: tooltip,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: bg,
          shape: const CircleBorder(),
          shadows: shadows,
        ),
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // AppIcon centres the glyph inside these tight constraints rather
              // than letting the SVG stretch to fill them.
              Center(
                child: AppIcon(icon, size: size * 0.45, color: fg),
              ),
              if (badgeCount != null && badgeCount! > 0)
                Positioned(
                  top: 4,
                  right: 2,
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: brand.medicine,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: brand.surface, width: 2),
                    ),
                    child: Text(
                      badgeCount! > 9 ? '9+' : '$badgeCount',
                      style: TextStyle(
                        color: brand.onAccent(brand.medicine),
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    return tooltip == null
        ? button
        : FTooltip(
            tipBuilder: (_, _) => Text(tooltip!),
            semanticsLabel: tooltip,
            child: button,
          );
  }
}

/// The gap between adjacent [CircleIconButton]s in a header's action row.
const double actionGap = 8;

/// The gap between two cards stacked in a list.
///
/// A [TintCard] and a bare `BrandTile` both draw their own surface, so a column
/// of them with nothing between reads as one block rather than a list of rows.
/// The Bills, Loans and Reports lists arrived at 10 by hand; this is that
/// number, named, so every other list can agree with them.
const double cardGap = AppSpacing.card;

/// What sits under a scrolling page's last row, which decides how much room
/// the page leaves below it.
enum PageEnd {
  /// Nothing: the row only has to clear the home indicator.
  none,

  /// A [BrandFab] floats over the bottom-right corner.
  fab,

  /// The shell's [CurvedNavBar] is drawn over the page.
  navBar,
}

/// The padding a scrolling page applies to its list.
///
/// Every page pads its content [AppSpacing.gutter] from the sides — the same
/// inset the top bar's circles sit at — and reserves enough underneath its
/// last row to clear whatever floats over the page end, plus the device's
/// bottom inset. `FScaffold` applies no bottom safe area of its own, so a
/// constant here would either hide the last row under the home indicator or
/// waste a finger's height on a device without one.
EdgeInsets pageInsets(
  BuildContext context, {
  double top = 8,
  PageEnd end = PageEnd.none,
  double gutter = AppSpacing.gutter,
}) {
  final inset = MediaQuery.paddingOf(context).bottom;
  final clearance = switch (end) {
    PageEnd.none => AppSpacing.pageEnd,
    PageEnd.fab => AppSpacing.fabClearance,
    PageEnd.navBar => CurvedNavBar.barHeight + CurvedNavBar.overlap + 16,
  };
  return EdgeInsets.fromLTRB(gutter, top, gutter, clearance + inset);
}

/// Lets a horizontal rail scroll out under the page gutter.
///
/// A rail placed in a padded list is clipped at the padding, so its last card
/// is cut off a gutter's width short of the screen edge and there is no sign
/// that more follows. This lays the rail out at the full page width instead,
/// centred over its slot, so the rail can carry the gutter as its own scroll
/// padding: the first card lines up with the content above it and the rest run
/// off the screen edge, the way a rail on the App Store does.
///
/// Must sit inside a page padded [AppSpacing.gutter] on both sides. The
/// strip under the gutter is paint only: the page list still hit-tests its
/// rows at the padded width, so a card is tapped and dragged inside the
/// gutter, as before.
class GutterBleed extends StatelessWidget {
  final Widget child;

  const GutterBleed({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return OverflowBox(
      alignment: Alignment.center,
      minWidth: width,
      maxWidth: width,
      child: child,
    );
  }
}

/// The inset from a navigation drawer's edge to the cards inside it.
///
/// A drawer's list has no page padding of its own — the accent header is
/// full-bleed — so without this its rows sit against the panel edge with their
/// left corners cut off.
const double drawerGutter = 12;

/// The top bar used on pushed screens: a back/close circle, a 28/800
/// left-aligned title (with optional subtitle), and trailing action circles.
class BrandTopBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String? subtitle;

  /// Pass null on a root page, which has nothing to pop back to.
  final HugeIconData? leadingIcon;

  final VoidCallback? onLeading;
  final String? leadingTooltip;
  final HugeIconData? trailingIcon;
  final VoidCallback? onTrailing;
  final String? trailingTooltip;

  /// Extra trailing widgets, for the pages that carried several `AppBar.actions`.
  /// Rendered after [trailingIcon].
  final List<Widget> actions;

  /// Extra leading widgets, rendered after [leadingIcon] (e.g. drawer or filter shortcuts).
  final List<Widget> leadingActions;

  const BrandTopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.leadingIcon = AppIcons.close,
    this.onLeading,
    this.leadingTooltip,
    this.trailingIcon,
    this.onTrailing,
    this.trailingTooltip,
    this.actions = const [],
    this.leadingActions = const [],
  });

  @override
  Size get preferredSize => Size.fromHeight(subtitle == null ? 68 : 86);

  @override
  Widget build(BuildContext context) {
    final pop =
        onLeading ??
        () async {
          final popped = await Navigator.maybePop(context);
          if (!popped && context.mounted) {
            context.go('/dashboard');
          }
        };
    final theme = Theme.of(context);
    // A bar with no leading control is a tab root (Settings). Those titles
    // are 30/800/−0.9; a pushed screen keeps 28/800/−0.8.
    final isRoot = leadingIcon == null && leadingActions.isEmpty;
    final titleStyle = theme.textTheme.displaySmall?.copyWith(
      fontSize: isRoot ? 30 : 28,
      fontWeight: FontWeight.w800,
      letterSpacing: isRoot ? -0.9 : -0.8,
      height: 1.15,
    );

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          8,
          AppSpacing.gutter,
          8,
        ),
        child: Row(
          children: [
            if (leadingIcon != null) ...[
              CircleIconButton(
                icon: leadingIcon!,
                onPressed: pop,
                tooltip: leadingTooltip ?? 'Back',
              ),
              const SizedBox(width: 12),
            ],
            for (final leadingAction in leadingActions) ...[
              leadingAction,
              const SizedBox(width: actionGap),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: context.muted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailingIcon != null) ...[
              const SizedBox(width: actionGap),
              CircleIconButton(
                icon: trailingIcon!,
                onPressed: onTrailing,
                tooltip: trailingTooltip,
              ),
            ],
            for (final action in actions) ...[
              const SizedBox(width: actionGap),
              action,
            ],
          ],
        ),
      ),
    );
  }
}

/// The home-screen header: round avatar, greeting stacked over the date, and a
/// trailing circle of actions.
class GreetingHeader extends StatelessWidget {
  final String greeting;
  final String subtitle;

  /// Drawn on the gradient when there is no [photoPath]. Empty falls back to
  /// the app's own mark, for a user who has set neither photo nor name.
  final String initials;

  /// The user's photo, which replaces the gradient circle entirely.
  final String? photoPath;

  /// The circle's colour when there is no photo. Defaults to the brand, which
  /// is also what a person who never picked a colour resolves to — so the
  /// Settings card and this header show the same person the same way.
  final Color? color;

  final List<Widget> actions;
  final VoidCallback? onAvatarTap;

  const GreetingHeader({
    super.key,
    required this.greeting,
    required this.subtitle,
    this.initials = 'M',
    this.photoPath,
    this.color,
    this.actions = const [],
    this.onAvatarTap,
  });

  /// The ink circle standing in for a photo that is absent or unreadable.
  Widget _avatarFallback(BuildContext context) {
    final brand = context.brand;
    final bg = color ?? brand.ink;
    final fg = color == null ? brand.onInk : brand.onAccent(bg);
    return Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
      child: Text(
        initials.isEmpty ? 'mS' : initials,
        style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 17),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Resolved once: a path pointing at a file that is gone must fall back
    // rather than throw mid-build.
    final path = photoPath;
    final photo = path != null && File(path).existsSync() ? File(path) : null;
    return Row(
      children: [
        GestureDetector(
          onTap: onAvatarTap == null
              ? null
              : () {
                  AppHaptics.tap();
                  onAvatarTap!();
                },
          child: photo != null
              ? ClipOval(
                  child: Image.file(
                    photo,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    cacheWidth: (48 * MediaQuery.devicePixelRatioOf(context))
                        .round(),
                    errorBuilder: (context, _, _) => _avatarFallback(context),
                  ),
                )
              : _avatarFallback(context),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                subtitle.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: context.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                greeting,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                  height: 1.15,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        for (final (i, action) in actions.indexed) ...[
          if (i > 0) const SizedBox(width: actionGap),
          action,
        ],
      ],
    );
  }
}

/// The ink hero card: eyebrow, large numeral or headline, supporting line,
/// optional trailing ring/widget, and optional row of translucent sub-tiles.
class HeroBanner extends StatelessWidget {
  final String label;
  final String headline;
  final String footnote;
  final HugeIconData? icon;
  final Color accent;
  final VoidCallback? onTap;

  /// Optional large hero numeral (e.g. "7 of 14" or "৳18,450"). When provided,
  /// renders at 44/800/-2 above [footnote].
  final String? metric;

  /// Optional trailing widget (e.g. a [ProgressRing] with `onInk: true`).
  final Widget? trailing;

  /// Optional sub-tiles rendered in a row at the bottom of the hero card.
  final List<Widget> subTiles;

  const HeroBanner({
    super.key,
    required this.label,
    required this.headline,
    required this.footnote,
    this.icon,
    required this.accent,
    this.onTap,
    this.metric,
    this.trailing,
    this.subTiles = const [],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final isDark = theme.brightness == Brightness.dark;
    final primaryText = isDark ? brand.ink : brand.onInk;
    final eyebrowColor = brand.roleFor(accent).onInk;

    return Container(
      decoration: BoxDecoration(
        color: brand.heroSurface,
        borderRadius: BorderRadius.circular(AppRadii.hero),
        boxShadow: AppShadows.hero(theme.brightness),
      ),
      clipBehavior: Clip.antiAlias,
      child: FTappable(
        onPress: onTap == null
            ? null
            : () {
                AppHaptics.tap();
                onTap!();
              },
        semanticsButton: onTap != null,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: eyebrowColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (metric != null)
                          Text(
                            metric!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.displayLarge?.copyWith(
                              color: primaryText,
                              fontSize: 44,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -2,
                              height: 1.05,
                            ),
                          )
                        else
                          Text(
                            headline,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: primaryText,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                              letterSpacing: -0.5,
                            ),
                          ),
                        const SizedBox(height: 6),
                        Text(
                          footnote,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: brand.onInkMuted,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 14),
                    trailing!,
                  ] else if (icon != null) ...[
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 76,
                      height: 76,
                      child: AppIcon(
                        icon!,
                        size: 54,
                        color: eyebrowColor.withValues(alpha: 0.35),
                      ),
                    ),
                  ],
                ],
              ),
              if (subTiles.isNotEmpty) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    for (final (i, tile) in subTiles.indexed) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(AppRadii.field),
                          ),
                          child: tile,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A rounded label chip. Used for filters and tags.
///
/// Selected = ink fill with white/onInk text; unselected = white/surface with
/// a soft shadow.
class Pill extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final HugeIconData? icon;
  final VoidCallback? onTap;
  final bool onWell;

  const Pill({
    super.key,
    required this.label,
    required this.color,
    this.selected = false,
    this.icon,
    this.onTap,
    this.onWell = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final background = selected
        ? brand.ink
        : onWell
        ? Colors.transparent
        : brand.surface;
    final foreground = selected
        ? brand.onInk
        : onWell
        ? context.muted
        : brand.ink;
    return FTappable(
      onPress: onTap == null
          ? null
          : () {
              AppHaptics.selection();
              onTap!();
            },
      semanticsLabel: label,
      semanticsChecked: onTap == null ? null : selected,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 38),
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: background,
            shape: const StadiumBorder(),
            shadows: (selected || onWell)
                ? const []
                : AppShadows.circleButton(theme.brightness),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  AppIcon(icon!, size: 15, color: foreground),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One of the "My Plans" cards: a coloured glyph over a bold label and a muted
/// value. Sized to sit in a fixed-height row.
class PlanCard extends StatelessWidget {
  final HugeIconData icon;
  final String label;
  final String value;
  final Color accent;
  final int tintIndex;
  final VoidCallback? onTap;

  const PlanCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
    this.tintIndex = 0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TintCard(
      tintIndex: tintIndex,
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          AppIcon(icon, size: 28, color: accent),
          const SizedBox(height: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(fontSize: 15),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: context.muted,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Data display
// ---------------------------------------------------------------------------

/// The thick coral donut from the food-summary and running screens: a rounded
/// arc over a grey track, a dashed inner guide, and free-form centre content.
class ProgressRing extends StatelessWidget {
  /// 0..1. Values above 1 are clamped but recoloured to signal the overrun.
  final double value;
  final double size;
  final double thickness;
  final Color? color;
  final Widget? center;

  /// Draws the dashed inner circle from the reference design.
  final bool dashedGuide;

  /// Uses `rgba(255,255,255,.10)` as the track colour when rendered on an ink
  /// hero card.
  final bool onInk;

  const ProgressRing({
    super.key,
    required this.value,
    this.size = 92,
    this.thickness = 10,
    this.color,
    this.center,
    this.dashedGuide = false,
    this.onInk = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final over = value > 1.0;
    final tone = over
        ? theme.colorScheme.error
        : (color ?? theme.colorScheme.primary);
    final track = onInk ? Colors.white.withValues(alpha: 0.10) : brand.track;

    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeOutCubic,
        tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
        builder: (context, animated, child) {
          return CustomPaint(
            painter: _RingPainter(
              value: animated,
              color: tone,
              track: track,
              thickness: thickness,
              dashedGuide: dashedGuide,
            ),
            child: child,
          );
        },
        child: center == null
            ? null
            : Center(
                child: Padding(
                  padding: EdgeInsets.all(thickness + 10),
                  child: FittedBox(fit: BoxFit.scaleDown, child: center),
                ),
              ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double value;
  final Color color;
  final Color track;
  final double thickness;
  final bool dashedGuide;

  const _RingPainter({
    required this.value,
    required this.color,
    required this.track,
    required this.thickness,
    required this.dashedGuide,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final radius = (math.min(size.width, size.height) - thickness) / 2;
    final rect = Rect.fromCircle(center: centre, radius: radius);

    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawCircle(centre, radius, base);

    if (value > 0) {
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness
        ..strokeCap = StrokeCap.round
        ..color = color;
      canvas.drawArc(rect, -math.pi / 2, value * 2 * math.pi, false, arc);
    }

    if (dashedGuide) {
      final guideRadius = radius - thickness / 2 - 10;
      if (guideRadius > 8) {
        final dash = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = color.withValues(alpha: 0.45);
        // 60 short dashes reads as the fine dotted guide in the reference at
        // any ring size.
        const segments = 60;
        const step = 2 * math.pi / segments;
        for (var i = 0; i < segments; i++) {
          final from = i * step;
          canvas.drawArc(
            Rect.fromCircle(center: centre, radius: guideRadius),
            from,
            step * 0.5,
            false,
            dash,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value ||
      old.color != color ||
      old.track != track ||
      old.thickness != thickness ||
      old.dashedGuide != dashedGuide;
}

/// The smoothed area chart under "Activities": a soft spline over faint
/// gridlines, with an optional highlighted point and a drop line.
class SplineChart extends StatelessWidget {
  final List<double> values;
  final List<String> labels;
  final Color color;
  final int? highlight;
  final double height;

  /// Formats the four axis ticks. Defaults to whole numbers.
  final String Function(double)? formatTick;

  const SplineChart({
    super.key,
    required this.values,
    required this.labels,
    required this.color,
    this.highlight,
    this.height = 190,
    this.formatTick,
  });

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return SizedBox(height: height);
    return SizedBox(
      height: height,
      child: TweenAnimationBuilder<double>(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
        tween: Tween(begin: 0, end: 1),
        builder: (context, t, _) => CustomPaint(
          size: Size.infinite,
          painter: _SplinePainter(
            values: values,
            labels: labels,
            color: color,
            grid: context.brand.hairline,
            labelColor: context.muted,
            highlight: highlight,
            progress: t,
            formatTick: formatTick ?? (v) => v.round().toString(),
            textDirection: Directionality.of(context),
          ),
        ),
      ),
    );
  }
}

class _SplinePainter extends CustomPainter {
  final List<double> values;
  final List<String> labels;
  final Color color;
  final Color grid;
  final Color labelColor;
  final int? highlight;
  final double progress;
  final String Function(double) formatTick;
  final TextDirection textDirection;

  const _SplinePainter({
    required this.values,
    required this.labels,
    required this.color,
    required this.grid,
    required this.labelColor,
    required this.highlight,
    required this.progress,
    required this.formatTick,
    required this.textDirection,
  });

  static const _axisWidth = 34.0;
  static const _labelHeight = 22.0;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(
      _axisWidth,
      6,
      size.width,
      size.height - _labelHeight,
    );
    if (plot.width <= 0 || plot.height <= 0) return;

    var min = values.reduce(math.min);
    var max = values.reduce(math.max);
    if (max - min < 1e-9) {
      // A flat series would divide by zero; give it an arbitrary band so the
      // line lands in the middle of the plot.
      max = min + 1;
    }
    // Breathing room above and below so the curve never touches the frame.
    final pad = (max - min) * 0.15;
    min -= pad;
    max += pad;

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;

    for (var i = 0; i < 4; i++) {
      final t = i / 3;
      final y = plot.bottom - t * plot.height;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
      _text(
        canvas,
        formatTick(min + t * (max - min)),
        Offset(0, y - 8),
        labelColor,
        11,
      );
    }

    Offset pointAt(int i) {
      final x = values.length == 1
          ? plot.center.dx
          : plot.left + plot.width * (i / (values.length - 1));
      final y =
          plot.bottom -
          plot.height * ((values[i] - min) / (max - min)).clamp(0.0, 1.0);
      return Offset(x, y);
    }

    final points = [for (var i = 0; i < values.length; i++) pointAt(i)];

    // Vertical separators, one per sample, matching the reference grid.
    for (final p in points) {
      canvas.drawLine(
        Offset(p.dx, plot.top),
        Offset(p.dx, plot.bottom),
        gridPaint..color = grid,
      );
    }

    final path = _spline(points);

    // The fill is the curve closed down to the baseline.
    final fill = Path.from(path)
      ..lineTo(points.last.dx, plot.bottom)
      ..lineTo(points.first.dx, plot.bottom)
      ..close();
    canvas.save();
    canvas.clipRect(
      Rect.fromLTRB(
        plot.left,
        plot.top,
        plot.left + plot.width * progress,
        plot.bottom,
      ),
    );
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.35),
            color.withValues(alpha: 0.02),
          ],
        ).createShader(plot),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
    canvas.restore();

    // Day labels under each sample.
    for (var i = 0; i < points.length && i < labels.length; i++) {
      _text(
        canvas,
        labels[i],
        Offset(points[i].dx - 12, plot.bottom + 5),
        labelColor,
        12,
      );
    }

    final index = highlight;
    if (index != null &&
        index >= 0 &&
        index < points.length &&
        progress > 0.99) {
      final p = points[index];
      canvas.drawLine(
        p,
        Offset(p.dx, plot.bottom),
        Paint()
          ..color = labelColor.withValues(alpha: 0.5)
          ..strokeWidth = 1,
      );
      canvas.drawCircle(p, 8.5, Paint()..color = color.withValues(alpha: 0.25));
      canvas.drawCircle(p, 3.5, Paint()..color = color);
    }
  }

  /// A Catmull-Rom spline through [points], converted to cubic Béziers.
  Path _spline(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    if (points.length < 3) {
      for (final p in points.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      return path;
    }
    for (var i = 0; i < points.length - 1; i++) {
      final p0 = i == 0 ? points[0] : points[i - 1];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = i + 2 < points.length ? points[i + 2] : p2;
      path.cubicTo(
        p1.dx + (p2.dx - p0.dx) / 6,
        p1.dy + (p2.dy - p0.dy) / 6,
        p2.dx - (p3.dx - p1.dx) / 6,
        p2.dy - (p3.dy - p1.dy) / 6,
        p2.dx,
        p2.dy,
      );
    }
    return path;
  }

  void _text(Canvas canvas, String value, Offset at, Color color, double size) {
    TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(color: color, fontSize: size),
        ),
        textDirection: textDirection,
      )
      ..layout()
      ..paint(canvas, at);
  }

  @override
  bool shouldRepaint(_SplinePainter old) =>
      old.progress != progress ||
      old.highlight != highlight ||
      !listEquals(old.values, values) ||
      old.color != color;

  static bool listEquals(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// The horizontal date selector from the food-summary screen: rounded day cells
/// with the selected one filled in coral.
class DayStrip extends StatelessWidget {
  final DateTime selected;
  final ValueChanged<DateTime> onSelected;

  /// How many days to show, ending [trailingDays] after today.
  final int days;
  final int trailingDays;

  const DayStrip({
    super.key,
    required this.selected,
    required this.onSelected,
    this.days = 7,
    this.trailingDays = 3,
  });

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = today.subtract(Duration(days: days - 1 - trailingDays));

    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
        itemCount: days,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.card),
        itemBuilder: (context, i) {
          final day = start.add(Duration(days: i));
          final isSelected =
              day.year == selected.year &&
              day.month == selected.month &&
              day.day == selected.day;
          return _DayCell(
            day: day,
            weekday: _weekdays[day.weekday - 1],
            selected: isSelected,
            onTap: () => onSelected(day),
          );
        },
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  final DateTime day;
  final String weekday;
  final bool selected;
  final VoidCallback onTap;

  const _DayCell({
    required this.day,
    required this.weekday,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = selected ? Colors.white : theme.colorScheme.onSurface;
    return FTappable(
      onPress: () {
        AppHaptics.selection();
        onTap();
      },
      selected: selected,
      semanticsLabel: '${day.day} $weekday',
      semanticsChecked: selected,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.primary : context.brand.tint(0),
          borderRadius: BorderRadius.circular(AppRadii.field),
        ),
        child: SizedBox(
          width: 48,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                day.day.toString().padLeft(2, '0'),
                style: TextStyle(
                  color: foreground,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                weekday,
                style: TextStyle(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.9)
                      : context.muted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The metric trio under the running ring: a coral glyph over a bold value and
/// a muted caption.
class MetricColumn extends StatelessWidget {
  final HugeIconData icon;
  final String value;
  final String caption;
  final Color? color;

  const MetricColumn({
    super.key,
    required this.icon,
    required this.value,
    required this.caption,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = color ?? theme.colorScheme.primary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIcon(icon, size: 28, color: tone),
        const SizedBox(height: 14),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall?.copyWith(fontSize: 16),
        ),
        Text(
          caption,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: context.muted,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Navigation
// ---------------------------------------------------------------------------

/// The floating ink pill navigation bar: active tab shows icon + label inside
/// a translucent pill, inactive tabs show icon only, and [centerAction] sits
/// inline in the middle.
class CurvedNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onSelected;
  final List<CurvedNavItem> items;

  /// The circular `+` action in the centre of the pill.
  final Widget centerAction;

  const CurvedNavBar({
    super.key,
    required this.currentIndex,
    required this.onSelected,
    required this.items,
    required this.centerAction,
  });

  /// Vertical clearance above the bottom safe-area inset.
  static const overlap = 24.0;
  static const barHeight = 68.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final split = (items.length / 2).ceil();

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        0,
        AppSpacing.gutter,
        overlap + bottomInset,
      ),
      child: Container(
        height: barHeight,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: ShapeDecoration(
          color: brand.heroSurface,
          shape: const StadiumBorder(),
          shadows: AppShadows.navBar(theme.brightness),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i == split) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: centerAction,
                ),
              ],
              _NavButton(
                item: items[i],
                index: i,
                length: items.length,
                selected: i == currentIndex,
                onSelected: onSelected,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One destination in a [CurvedNavBar].
@immutable
class CurvedNavItem {
  final HugeIconData icon;
  final HugeIconData? selectedIcon;
  final String label;

  const CurvedNavItem({
    required this.icon,
    required this.label,
    this.selectedIcon,
  });
}

class _NavButton extends StatelessWidget {
  final CurvedNavItem item;
  final int index;
  final int length;
  final bool selected;
  final ValueChanged<int> onSelected;

  const _NavButton({
    required this.item,
    required this.index,
    required this.length,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    const activeFg = Colors.white;
    final inactiveFg = Colors.white.withValues(alpha: 0.55);

    return FBottomNavigationBarData(
      key: ValueKey('nav-${item.label.toLowerCase()}'),
      itemStyle: context.theme.bottomNavigationBarStyle.itemStyle,
      selected: selected,
      index: index,
      length: length,
      onChange: (idx) {
        AppHaptics.selection();
        onSelected(idx);
      },
      child: Semantics(
        label: '${item.label}, Tab ${index + 1} of $length',
        selected: selected,
        button: true,
        child: FTappable(
          onPress: () {
            AppHaptics.selection();
            onSelected(index);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            height: 46,
            padding: EdgeInsets.symmetric(horizontal: selected ? 14 : 12),
            decoration: ShapeDecoration(
              color: selected
                  ? Colors.white.withValues(alpha: 0.14)
                  : Colors.transparent,
              shape: const StadiumBorder(),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(
                  selected ? (item.selectedIcon ?? item.icon) : item.icon,
                  color: selected ? activeFg : inactiveFg,
                  size: 21,
                ),
                if (selected) ...[
                  const SizedBox(width: 7),
                  Text(
                    item.label,
                    style: const TextStyle(
                      color: activeFg,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

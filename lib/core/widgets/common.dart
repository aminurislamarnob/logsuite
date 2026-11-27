import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../utils/haptics.dart';
import 'brand.dart';

/// Shared presentational widgets. Everything here reads its colours from the
/// active [Theme] so light, dark and high-contrast all stay legible.

/// How a [BrandButton] reads.
enum BrandButtonKind { primary, outline, ghost, danger }

/// A button in the brand's shape.
///
/// forui's buttons are rounded rectangles; the brand makes everything tappable a
/// full pill. Rather than repeat that override at 50 call sites, screens use this
/// and never touch [FButton] directly.
class BrandButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final BrandButtonKind kind;
  final HugeIconData? icon;

  /// Whether the button stretches to its parent's width.
  final bool expand;

  final bool small;

  const BrandButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = BrandButtonKind.primary,
    this.icon,
    this.expand = true,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final (bg, fg, shadows) = switch (kind) {
      BrandButtonKind.primary => (brand.ink, brand.onInk, const <BoxShadow>[]),
      BrandButtonKind.outline => (
        brand.surface,
        brand.ink,
        AppShadows.circleButton(theme.brightness),
      ),
      BrandButtonKind.ghost => (
        Colors.transparent,
        brand.ink,
        const <BoxShadow>[],
      ),
      BrandButtonKind.danger => (
        brand.surface,
        brand.dangerRoles.textOnTint,
        AppShadows.circleButton(theme.brightness),
      ),
    };

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: small ? 42 : 54),
      child: FButton(
        onPress: onPressed == null
            ? null
            : () {
                if (kind == BrandButtonKind.danger) {
                  AppHaptics.heavy();
                } else {
                  AppHaptics.tap();
                }
                onPressed!();
              },
        variant: switch (kind) {
          BrandButtonKind.primary => .primary,
          BrandButtonKind.outline => .outline,
          BrandButtonKind.ghost => .ghost,
          BrandButtonKind.danger => .destructive,
        },
        size: small ? .sm : .md,
        mainAxisSize: expand ? .max : .min,
        // Applied to the base and every interaction variant, so hover and pressed
        // stay pills too.
        style: .delta(
          decoration: .delta([
            .all(
              DecorationDelta.shapeDelta(
                color: bg,
                shape: const StadiumBorder(),
                shadows: shadows,
              ),
            ),
          ]),
          contentStyle: .delta(
            padding: .add(EdgeInsets.symmetric(horizontal: small ? 6 : 10)),
            textStyle: .delta([
              .all(
                TextStyleDelta.delta(
                  color: fg,
                  fontWeight: FontWeight.w700,
                  fontSize: small ? 14 : 15,
                ),
              ),
            ]),
            iconStyle: .delta([.all(IconThemeDataDelta.delta(color: fg))]),
          ),
        ),
        prefix: icon == null ? null : AppIcon(icon!, size: 18, color: fg),
        child: Text(label),
      ),
    );
  }
}

/// The bold section title from the reference screens ("My Plans", "Activities"),
/// with an optional trailing text action.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsets padding;

  const SectionHeader(
    this.title, {
    super.key,
    this.actionLabel,
    this.onAction,
    this.padding = const EdgeInsets.only(bottom: 14),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontSize: 20,
                letterSpacing: -0.4,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (actionLabel != null)
            FButton(
              onPress: onAction == null
                  ? null
                  : () {
                      AppHaptics.tap();
                      onAction!();
                    },
              variant: .ghost,
              size: .sm,
              mainAxisSize: .min,
              // The coral is set on the Text rather than through the style so it
              // wins over the ghost variant's foreground, which is body colour.
              child: Text(
                actionLabel!,
                style: TextStyle(
                  color: context.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final HugeIconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final muted = theme.colorScheme.outline;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: brand.surface,
                borderRadius: BorderRadius.circular(AppRadii.card),
                boxShadow: AppShadows.card(theme.brightness),
              ),
              child: AppIcon(
                icon,
                size: 32,
                color: brand.roleFor(theme.colorScheme.primary).graphicOnTint,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: muted),
              ),
            ],
            if (actionLabel != null) ...[
              const SizedBox(height: 24),
              BrandButton(
                label: actionLabel!,
                onPressed: onAction,
                expand: false,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Renders the three states of an [AsyncValue]-backed list without every screen
/// re-implementing the same loading spinner and error text.
class AsyncSection extends StatelessWidget {
  final bool isLoading;
  final Object? error;
  final Widget child;

  const AsyncSection({
    super.key,
    required this.isLoading,
    required this.error,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: BrandSpinner()),
      );
    }
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            AppIcon(AppIcons.error, color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 12),
            Expanded(child: Text('Something went wrong: $error')),
          ],
        ),
      );
    }
    return child;
  }
}

/// A rounded stat tile used on the dashboard and in the insights reports.
///
/// The fill rotates through the brand pastels via [tintIndex] so a grid of
/// these reads like the "My Plans" row rather than a wall of identical boxes.
class StatTile extends StatelessWidget {
  final HugeIconData icon;
  final Color color;
  final String label;
  final String value;
  final String? sublabel;
  final VoidCallback? onTap;
  final int tintIndex;

  const StatTile({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.sublabel,
    this.onTap,
    this.tintIndex = 0,
  });

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.outline;
    final brand = context.brand;
    return TintCard(
      fill: brand.surface,
      tintIndex: tintIndex,
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              AppIcon(
                icon,
                size: 18,
                color: brand.roleFor(color).graphicOnTint,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: muted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                height: 1.1,
                letterSpacing: -0.6,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (sublabel != null)
            Flexible(
              child: Text(
                sublabel!,
                style: TextStyle(fontSize: 12, color: muted, height: 1.25),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}

/// GitHub-style contribution heatmap. [intensityFor] returns 0.0–1.0 for a day.
class ContributionHeatmap extends StatelessWidget {
  final int days;
  final DateTime? startDate;
  final DateTime? endDate;
  final Color color;
  final double Function(DateTime day) intensityFor;
  final void Function(DateTime day)? onTapDay;
  final double cell;

  const ContributionHeatmap({
    super.key,
    required this.color,
    required this.intensityFor,
    this.days = 119, // 17 weeks
    this.startDate,
    this.endDate,
    this.onTapDay,
    this.cell = 14,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final end = endDate == null
        ? today
        : DateTime(endDate!.year, endDate!.month, endDate!.day);
    final start = startDate != null
        ? DateTime(startDate!.year, startDate!.month, startDate!.day)
        : end.subtract(Duration(days: days - 1));
    final totalDays = (end.difference(start).inDays + 1).clamp(1, 3660);
    // Pad to the start of that week so columns line up as Mon–Sun.
    final leading = start.weekday - 1;
    final total = leading + totalDays;
    final weeks = (total / 7).ceil();
    final brand = context.brand;
    final base = brand.track;

    // Latest week at the right edge when there is more than fits, so the
    // present is what you land on; reading order from the left when it all
    // fits, so the grid does not hang off the far side of its own label.
    final width = weeks * (cell + 3);
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: width > constraints.maxWidth,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: List.generate(weeks, (w) {
            return Padding(
              padding: const EdgeInsets.only(right: 3),
              child: Column(
                children: List.generate(7, (d) {
                  final index = w * 7 + d - leading;
                  if (index < 0 || index >= totalDays) {
                    return SizedBox(height: cell + 3, width: cell);
                  }
                  final day = start.add(Duration(days: index));
                  final isToday = day == today;
                  final v = intensityFor(day).clamp(0.0, 1.0);
                  final fill = v == 0
                      ? base
                      : v < 0.34
                      ? color.withValues(alpha: 0.28)
                      : v < 0.67
                      ? color.withValues(alpha: 0.52)
                      : v < 0.9
                      ? color.withValues(alpha: 0.76)
                      : color;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: FTooltip(
                      tipBuilder: (_, _) =>
                          Text('${day.year}-${day.month}-${day.day}'),
                      semanticsLabel: '${day.year}-${day.month}-${day.day}',
                      child: GestureDetector(
                        onTap: onTapDay == null
                            ? null
                            : () {
                                AppHaptics.selection();
                                onTapDay!(day);
                              },
                        child: Container(
                          width: cell,
                          height: cell,
                          decoration: BoxDecoration(
                            color: fill,
                            borderRadius: BorderRadius.circular(5),
                            border: isToday
                                ? Border.all(color: brand.ink, width: 1.5)
                                : null,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            );
          }),
        ),
      ),
    );
  }
}

/// Labelled progress bar used for budgets, adherence and focus goals.
class LabeledProgress extends StatelessWidget {
  final String label;
  final String trailing;
  final double value; // 0..1, may exceed 1 to signal an overrun
  final Color color;

  const LabeledProgress({
    super.key,
    required this.label,
    required this.trailing,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final over = value > 1.0;
    final muted = Theme.of(context).colorScheme.outline;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(trailing, style: TextStyle(color: muted, fontSize: 13)),
          ],
        ),
        const SizedBox(height: 8),
        // The fill turns to the error colour once the value overruns.
        BrandProgressBar(
          value: value,
          semanticsLabel: label,
          color: over ? Theme.of(context).colorScheme.error : color,
        ),
      ],
    );
  }
}

/// Standard bottom-sheet chrome: grab handle, title and scroll-safe padding.
class SheetScaffold extends StatelessWidget {
  final String title;
  final Widget child;
  final List<Widget> actions;
  final Widget? bottomAction;
  final bool showClose;

  const SheetScaffold({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
    this.bottomAction,
    this.showClose = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.brand;
    return Material(
      type: MaterialType.transparency,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: brand.canvas,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadii.sheet),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: brand.outlineIdle,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.gutter,
                    16,
                    AppSpacing.gutter,
                    12,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.7,
                          ),
                        ),
                      ),
                      for (final action in actions) ...[
                        action,
                        const SizedBox(width: actionGap),
                      ],
                      if (showClose && actions.isEmpty)
                        CircleIconButton(
                          icon: AppIcons.close,
                          tooltip: 'Close',
                          size: 40,
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      AppSpacing.gutter,
                      0,
                      AppSpacing.gutter,
                      bottomAction == null ? 28 : 16,
                    ),
                    child: child,
                  ),
                ),
                if (bottomAction != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.gutter,
                      8,
                      AppSpacing.gutter,
                      20,
                    ),
                    child: bottomAction!,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// forui bridges
// ---------------------------------------------------------------------------
//
// Screens go through the wrappers below rather than calling forui directly, so a
// forui default can never quietly override a brand value in one corner of the
// app. Each one is a thin shim: forui supplies behaviour, the brand supplies the
// colours, shapes and spacing.

/// A page built on [FScaffold].
///
/// Adds three things [FScaffold] does not provide:
///
///  * **A [Material] ancestor.** `flutter_quill`, `flutter_slidable`,
///    [Dismissible], `PopupMenuButton` and `DataTable` all assert on one and
///    throw "No Material widget found" without it. Injecting it here once covers
///    every page rather than every call site.
///  * **The content icon size.** [FScaffold] installs an [IconTheme] from
///    `FStyle.iconStyle`, which is sized for forui's own chevrons and loaders
///    (20). Content glyphs expect Material's 24, so that default is restored.
///  * **A floating action slot**, which forui has no equivalent for.
class BrandScaffold extends StatelessWidget {
  final Widget child;
  final Widget? header;
  final Widget? footer;

  /// Rendered bottom-right over [child].
  final Widget? floatingAction;

  /// Whether [FScaffold] applies its own page padding. Off by default because
  /// the screens already pad themselves.
  final bool pad;

  final bool resizeToAvoidBottomInset;

  const BrandScaffold({
    super.key,
    required this.child,
    this.header,
    this.footer,
    this.floatingAction,
    this.pad = false,
    this.resizeToAvoidBottomInset = true,
  });

  @override
  Widget build(BuildContext context) {
    // Keep the Stack structure invariant whether or not [floatingAction] is
    // present so toggling a FAB (e.g. hiding it on a read-only tab) does not
    // unmount and reset state inside [child].
    final inset = MediaQuery.paddingOf(context).bottom;
    final body = Stack(
      children: [
        Positioned.fill(child: child),
        if (floatingAction != null)
          // FScaffold applies no bottom safe area, so the button has to clear
          // the home indicator itself. It sits on the page gutter so its right
          // edge lines up with the cards above it.
          Positioned(
            right: AppSpacing.gutter,
            bottom: 16 + inset,
            child: floatingAction!,
          ),
      ],
    );

    return FScaffold(
      // The page Material below covers [child] only. forui puts [header]
      // outside that boundary, so a TextField in the header (search) throws
      // "No Material widget found". Transparency supplies the ancestor
      // without painting over the scaffold.
      header: header == null
          ? null
          : Material(type: MaterialType.transparency, child: header),
      footer: footer,
      childPad: pad,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      child: IconTheme(
        data: IconThemeData(
          size: 24,
          color: Theme.of(context).colorScheme.onSurface,
        ),
        child: Material(color: context.brand.canvas, child: body),
      ),
    );
  }
}

/// A list row built on [FTile].
///
/// Mirrors the [ListTile] API the screens already use so the 60-odd call sites
/// read the same, and keeps the brand's row radius and muted subtitle.
class BrandTile extends StatelessWidget {
  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final bool enabled;
  final String? semanticsLabel;

  /// Tightens the row for long lists. forui gives every tile 14.5px above
  /// and below its content, so a stack of them reads as a column of islands;
  /// dense rows keep the horizontal inset and halve the vertical.
  final bool dense;

  const BrandTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.enabled = true,
    this.semanticsLabel,
    this.dense = false,
  });

  /// The content inset of a dense row; see [dense].
  static const densePadding = EdgeInsets.symmetric(horizontal: 15, vertical: 7);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final padding = dense
        ? const EdgeInsetsGeometryDelta.value(densePadding)
        : null;
    final slot = _TileSlot.of(context);
    final inCard = CardScope.of(context);
    // A tile paints its own card only when nothing else is one for it.
    final fills = slot.fills && !inCard;
    return FTile(
      title: title,
      subtitle: subtitle,
      prefix: leading,
      suffix: trailing,
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
      selected: selected,
      enabled: enabled,
      semanticsLabel: semanticsLabel,
      style: .delta(
        shape: RoundedRectangleBorder(borderRadius: slot.radius),
        backgroundColor: fills
            ? .delta([.all(brand.surface)])
            : .delta([.all(Colors.transparent)]),
        contentDecoration: .delta([
          .all(
            DecorationDelta.boxDelta(
              color: fills ? brand.surface : Colors.transparent,
              border: slot.border(brand.hairline, inCard: inCard),
              borderRadius: slot.radius,
              boxShadow: fills ? AppShadows.card(theme.brightness) : const [],
            ),
          ),
        ]),
        contentStyle: .delta(
          suffixedPadding: padding,
          unsuffixedPadding: padding,
          prefixIconStyle: .delta([
            .all(IconThemeDataDelta.delta(color: context.muted, size: 24)),
          ]),
        ),
      ),
    );
  }
}

/// Where a tile sits in a [TileGroup], which decides which corners it rounds.
enum TilePosition {
  /// Not in a group, or the only tile in one: rounds all four corners.
  only,
  first,
  middle,
  last;

  /// Whether the tile paints its own fill.
  ///
  /// A tile on its own is a card and fills itself. In a group the enclosing
  /// card is the card, so the tiles go transparent — otherwise a group sitting
  /// on a card of a different tint reads as a card inside a card, which is
  /// what the dashboard's tinted sections were showing.
  bool get fills => this == TilePosition.only;

  /// The edges this tile draws.
  ///
  /// A tile on its own is a card and outlines itself. In a group the enclosing
  /// card already draws the boundary, so a tile contributes nothing but the
  /// divider to the row below it — an outline here would sit just inside the
  /// card's own edge as a second, fainter rectangle.
  Border border(Color color, {bool inCard = false}) {
    final side = BorderSide(color: color);
    return switch (this) {
      // A lone tile outlines itself unless a card is already doing it.
      TilePosition.only =>
        inCard ? const Border() : Border.fromBorderSide(side),
      TilePosition.first || TilePosition.middle => Border(bottom: side),
      TilePosition.last => const Border(),
    };
  }

  /// A run of tiles reads as one card, so only the ends round. The outer
  /// corners take the card radius rather than the tile radius so a group
  /// sitting flush inside a [TintCard] meets its clip exactly instead of
  /// leaving a notch.
  BorderRadius get radius => switch (this) {
    TilePosition.only => BorderRadius.circular(AppRadii.field),
    TilePosition.first => const BorderRadius.vertical(
      top: Radius.circular(AppRadii.tile),
    ),
    TilePosition.middle => BorderRadius.zero,
    TilePosition.last => const BorderRadius.vertical(
      bottom: Radius.circular(AppRadii.tile),
    ),
  };
}

class _TileSlot extends InheritedWidget {
  final TilePosition position;

  const _TileSlot({required this.position, required super.child});

  static TilePosition of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_TileSlot>()?.position ??
      TilePosition.only;

  @override
  bool updateShouldNotify(_TileSlot old) => old.position != position;
}

/// A run of [BrandTile]s that reads as one card rather than a stack of islands.
///
/// Every tile draws its own rounded background, which is right for a tile on
/// its own and wrong for six in a row: the corners cut in at every boundary and
/// the group looks like separate cards that happen to touch. This rounds the
/// first tile's top, the last tile's bottom, and squares everything between.
///
/// Use it wherever tiles are stacked flush inside a [TintCard]. For tiles that
/// are meant to read as separate cards, with a gap between them, use
/// [TileColumn].
class TileGroup extends StatelessWidget {
  final List<Widget> children;

  const TileGroup({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final inCard = CardScope.of(context);
    final col = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, child) in children.indexed)
          _TileSlot(
            position: children.length == 1
                ? TilePosition.only
                : i == 0
                ? TilePosition.first
                : i == children.length - 1
                ? TilePosition.last
                : TilePosition.middle,
            child: child,
          ),
      ],
    );
    if (inCard || children.length <= 1) return col;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.brand.surface,
        borderRadius: BorderRadius.circular(AppRadii.tile),
        boxShadow: AppShadows.card(Theme.of(context).brightness),
      ),
      child: col,
    );
  }
}

/// A column of [BrandTile]s with [cardGap] between them.
///
/// A bare tile draws its own card, so a plain `Column` of them reads as one
/// block — the bug the Bills and Loans lists fixed by hand, repeated at every
/// menu sheet, picker and drawer in the app. Tiles grouped inside a [TintCard]
/// are a different thing: those are rows of one card and stay flush, so this is
/// for the stacks that are not.
class TileColumn extends StatelessWidget {
  final List<Widget> children;
  final CrossAxisAlignment crossAxisAlignment;
  final MainAxisSize mainAxisSize;

  const TileColumn({
    super.key,
    required this.children,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.mainAxisSize = MainAxisSize.max,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: crossAxisAlignment,
    mainAxisSize: mainAxisSize,
    children: [
      for (final (i, child) in children.indexed) ...[
        if (i > 0) const SizedBox(height: cardGap),
        child,
      ],
    ],
  );
}

/// A text input built on [FTextField].
///
/// The brand's fields are filled with the peach tint and rounded to
/// [AppRadii.field] rather than forui's bordered, unfilled default.
class BrandField extends StatefulWidget {
  /// Distance from the field's edge to a [prefix] or [suffix]. Matches the
  /// horizontal padding forui's `FTile` gives a [BrandTile]'s leading glyph.
  static const double affixInset = 15;

  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final String? helper;

  /// A validation message, shown in the error colour and switching the field to
  /// its error variant.
  final String? error;

  final int? maxLines;
  final int? minLines;
  final bool obscure;
  final bool autofocus;
  final bool enabled;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onSubmit;

  /// Called on every keystroke, like [TextField.onChanged].
  final ValueChanged<String>? onChanged;

  final Widget? prefix;
  final Widget? suffix;
  final FocusNode? focusNode;

  /// Overrides the input text's own style, for the one field that is a display
  /// figure rather than body copy — the expense sheet's amount.
  final TextStyle? textStyle;

  /// Drops the fill and the border, for a field that reads as a heading rather
  /// than an input — the note editor's title, which sits flush above the Quill
  /// body and would look boxed-in with the usual treatment.
  final bool bare;

  const BrandField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.helper,
    this.error,
    this.maxLines = 1,
    this.minLines,
    this.obscure = false,
    this.autofocus = false,
    this.enabled = true,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.onSubmit,
    this.onChanged,
    this.prefix,
    this.suffix,
    this.focusNode,
    this.textStyle,
    this.bare = false,
  });

  @override
  State<BrandField> createState() => _BrandFieldState();
}

class _BrandFieldState extends State<BrandField> {
  // forui only renders `FTextField.error` when the field is in the error
  // WidgetState; passing `error:` alone is inert. We drive that state from the
  // presence of an error message so a plain BrandField (no Form) still shows it.
  final WidgetStatesController _states = WidgetStatesController();

  @override
  void initState() {
    super.initState();
    _states.update(WidgetState.error, widget.error != null);
  }

  @override
  void didUpdateWidget(BrandField old) {
    super.didUpdateWidget(old);
    if (widget.error != old.error) {
      _states.update(WidgetState.error, widget.error != null);
    }
  }

  @override
  void dispose() {
    _states.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final flattened = brand.tints.toSet().length == 1;

    return FTextField(
      control: .managed(
        controller: widget.controller,
        onChange: widget.onChanged == null
            ? null
            : (v) => widget.onChanged!(v.text),
      ),
      statesController: _states,
      label: widget.label == null ? null : Text(widget.label!),
      hint: widget.hint,
      description: widget.helper == null ? null : Text(widget.helper!),
      error: widget.error == null ? null : Text(widget.error!),
      maxLines: widget.obscure ? 1 : widget.maxLines,
      minLines: widget.minLines,
      obscureText: widget.obscure,
      autofocus: widget.autofocus,
      enabled: widget.enabled,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      textCapitalization: widget.textCapitalization,
      inputFormatters: widget.inputFormatters,
      onSubmit: widget.onSubmit,
      // forui zeroes the field's leading contentPadding the moment a prefix
      // exists, and clears the prefix's minimum box, so an unwrapped prefix
      // sits flush against the border. The inset is the one `BrandTile` gives
      // its leading glyph, so a field's symbol lines up with the row icons
      // stacked under it; the trailing gap separates it from the text.
      prefixBuilder: widget.prefix == null
          ? null
          : (_, _, _) => Padding(
              padding: const EdgeInsetsDirectional.only(
                start: BrandField.affixInset,
                end: 8,
              ),
              child: widget.prefix!,
            ),
      // The same applies on the trailing edge.
      suffixBuilder: widget.suffix == null
          ? null
          : (_, _, _) => Padding(
              padding: const EdgeInsetsDirectional.only(
                start: 8,
                end: BrandField.affixInset,
              ),
              child: widget.suffix!,
            ),
      focusNode: widget.focusNode,
      style: .delta(
        contentPadding: widget.bare
            ? .value(const EdgeInsets.symmetric(vertical: 8))
            : null,
        contentTextStyle: widget.textStyle == null
            ? null
            : .delta([.all(TextStyleDelta.value(widget.textStyle!))]),
        // forui builds the hint from the theme's body style and never from
        // contentTextStyle, so a field that sets its own text size would show
        // a hint several sizes smaller than the text that replaces it.
        hintTextStyle: widget.textStyle == null
            ? null
            : .delta([
                .all(
                  TextStyleDelta.value(
                    widget.textStyle!.copyWith(color: context.muted),
                  ),
                ),
              ]),
        color: .delta([.all(widget.bare ? Colors.transparent : brand.surface)]),
        // White, radius 20, 56 high, 2 px ink outline when focused. A bare
        // field is a heading, so it keeps the theme's natural height.
        constraints: widget.bare ? null : const BoxConstraints(minHeight: 56),
        border: .delta([
          if (widget.bare)
            .all(InputBorder.none)
          else ...[
            .base(
              OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.tile),
                borderSide: flattened
                    ? BorderSide(
                        color: Theme.of(context).colorScheme.onSurface,
                        width: 1.2,
                      )
                    : BorderSide.none,
              ),
            ),
            .match(
              {FTextFieldVariant.focused},
              OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.tile),
                borderSide: BorderSide(color: brand.ink, width: 2),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

/// A dismissible label, replacing Material's [Chip] with `onDeleted`.
///
/// Shares [Pill]'s unselected look — hairline stadium on the canvas — with a
/// trailing close glyph, so a row of these matches the filter chips elsewhere.
class BrandChip extends StatelessWidget {
  final String label;
  final HugeIconData? icon;
  final VoidCallback? onRemove;

  const BrandChip({super.key, required this.label, this.icon, this.onRemove});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.brand;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 38),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: brand.surface,
          shape: const StadiumBorder(),
          shadows: AppShadows.circleButton(theme.brightness),
        ),
        child: Padding(
          padding: EdgeInsets.only(left: 14, right: onRemove == null ? 14 : 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                AppIcon(icon!, size: 14, color: brand.ink),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  color: brand.ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (onRemove != null) ...[
                const SizedBox(width: 4),
                CircleIconButton(
                  icon: AppIcons.close,
                  tooltip: 'Remove $label',
                  size: 28,
                  onPressed: onRemove,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A checkbox, replacing Material's [Checkbox].
///
/// [color] overrides the checked fill for callers that tick in a module accent
/// rather than the brand coral — the task subtask list is the one that does.
class BrandCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color? color;
  final String? semanticsLabel;

  const BrandCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.color,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final checkedFill = color ?? brand.success;
    final uncheckedBorder = color ?? brand.outlineIdle;
    return FCheckbox(
      value: value,
      onChange: onChanged == null
          ? null
          : (v) {
              v ? AppHaptics.success() : AppHaptics.selection();
              onChanged!(v);
            },
      semanticsLabel: semanticsLabel,
      style: .delta(
        size: 26,
        iconStyle: .delta([
          .all(IconThemeDataDelta.delta(color: Colors.white, size: 15)),
        ]),
        decoration: .delta([
          .base(
            DecorationDelta.shapeDelta(
              color: Colors.transparent,
              shape: CircleBorder(
                side: BorderSide(color: uncheckedBorder, width: 2.5),
              ),
            ),
          ),
          .match(
            {FCheckboxVariant.selected},
            DecorationDelta.shapeDelta(
              color: checkedFill,
              shape: const CircleBorder(),
            ),
          ),
        ]),
      ),
    );
  }
}

/// A busy indicator, replacing Material's [CircularProgressIndicator].
///
/// Every loading state in the app is this one ring at forui's derived size, so
/// the wrapper carries no knobs — a change of mind lands here, not in fifteen
/// screens.
class BrandSpinner extends StatelessWidget {
  const BrandSpinner({super.key});

  @override
  Widget build(BuildContext context) => const FCircularProgress();
}

/// A hairline rule, replacing Material's [Divider].
///
/// forui reads its colour and thickness from `FStyle`, which already carries
/// the brand hairline, so there is nothing to override here.
class BrandDivider extends StatelessWidget {
  const BrandDivider({super.key});

  @override
  Widget build(BuildContext context) => const FDivider();
}

/// A tap target, replacing [InkWell] and [GestureDetector].
///
/// forui supplies the hit test, focus ring and press haptics. Nothing is
/// restyled; this exists so a screen never has to reach for forui to make an
/// arbitrary widget tappable.
class BrandTappable extends StatelessWidget {
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final String? semanticsLabel;
  final Widget child;

  const BrandTappable({
    super.key,
    required this.onPressed,
    required this.child,
    this.onLongPress,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) => FTappable(
    onPress: onPressed == null
        ? null
        : () {
            AppHaptics.tap();
            onPressed!();
          },
    onLongPress: onLongPress == null
        ? null
        : () {
            AppHaptics.medium();
            onLongPress!();
          },
    semanticsLabel: semanticsLabel,
    child: child,
  );
}

/// A tooltip, replacing Material's [Tooltip].
///
/// Takes a message rather than forui's builder: every tip in the app is one
/// line of text. The `FTooltipGroup` in `main.dart` already keeps only one of
/// these open at a time.
class BrandTooltip extends StatelessWidget {
  final String message;
  final String? semanticsLabel;
  final Widget child;

  const BrandTooltip({
    super.key,
    required this.message,
    required this.child,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) => FTooltip(
    tipBuilder: (_, _) => Text(message),
    semanticsLabel: semanticsLabel,
    child: child,
  );
}

/// A progress bar, replacing Material's [LinearProgressIndicator].
///
/// forui's own bar is a squared-off fill on a filled track; the brand's is a
/// fully-rounded fill on a hairline one. [LabeledProgress] and the onboarding
/// step indicator differ only in height, so both come through here rather than
/// repeating the same three deltas.
class BrandProgressBar extends StatelessWidget {
  final double value; // 0..1; anything above is clamped
  final Color color;
  final double height;
  final String? semanticsLabel;

  const BrandProgressBar({
    super.key,
    required this.value,
    required this.color,
    this.height = 8,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) => FDeterminateProgress(
    value: value.clamp(0.0, 1.0),
    semanticsLabel: semanticsLabel,
    style: .delta(
      constraints: BoxConstraints.tightFor(height: height),
      trackDecoration: .boxDelta(
        color: context.brand.hairline,
        borderRadius: BorderRadius.circular(999),
      ),
      fillDecoration: .boxDelta(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
    ),
  );
}

/// A settings row with a trailing switch, replacing [SwitchListTile].
class BrandSwitchTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Widget? leading;

  const BrandSwitchTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    return BrandTile(
      leading: leading,
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      semanticsLabel: title,
      trailing: FSwitch(
        value: value,
        onChange: onChanged == null
            ? null
            : (v) {
                AppHaptics.selection();
                onChanged!(v);
              },
        semanticsLabel: title,
        style: .delta(
          trackColor: .delta([
            .base(context.brand.well),
            .match({FSwitchVariant.selected}, context.brand.ink),
          ]),
          thumbColor: .delta([
            .base(
              Theme.of(context).brightness == Brightness.dark
                  ? context.brand.onInkMuted
                  : context.brand.surface,
            ),
            .match({FSwitchVariant.selected}, context.brand.onInk),
          ]),
        ),
      ),
      onTap: onChanged == null ? null : () => onChanged!(!value),
    );
  }
}

/// A single-choice segmented control, replacing [SegmentedButton].
///
/// forui has no segmented button; [FSelectGroup] in its single-select mode is the
/// nearest equivalent and carries the same keyboard and semantics behaviour.
class BrandSegmented<T extends Object> extends StatelessWidget {
  final Map<T, String> options;
  final T selected;
  final ValueChanged<T> onSelected;

  /// Optional leading glyph per option, keyed the same way as [options].
  final Map<T, HugeIconData> icons;

  /// When true, stretches segments evenly across the full available width.
  final bool expand;

  const BrandSegmented({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.icons = const {},
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.brand;
    if (expand) {
      return Container(
        padding: const EdgeInsets.all(4),
        decoration: ShapeDecoration(
          color: brand.well,
          shape: const StadiumBorder(),
        ),
        child: Row(
          children: [
            for (final (i, entry) in options.entries.indexed) ...[
              if (i > 0) const SizedBox(width: 4),
              Expanded(
                child: FTappable(
                  onPress: () {
                    AppHaptics.selection();
                    onSelected(entry.key);
                  },
                  semanticsLabel: entry.value,
                  semanticsChecked: entry.key == selected,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 38),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: ShapeDecoration(
                      color: entry.key == selected
                          ? brand.ink
                          : Colors.transparent,
                      shape: const StadiumBorder(),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (icons[entry.key] != null) ...[
                          AppIcon(
                            icons[entry.key]!,
                            size: 15,
                            color: entry.key == selected
                                ? brand.onInk
                                : context.muted,
                          ),
                          const SizedBox(width: 6),
                        ],
                        Flexible(
                          child: Text(
                            entry.value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: entry.key == selected
                                  ? brand.onInk
                                  : context.muted,
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: ShapeDecoration(
        color: brand.well,
        shape: const StadiumBorder(),
      ),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final entry in options.entries)
            Pill(
              label: entry.value,
              icon: icons[entry.key],
              color: theme.colorScheme.primary,
              selected: entry.key == selected,
              onWell: true,
              onTap: () => onSelected(entry.key),
            ),
        ],
      ),
    );
  }
}

/// A collapsible row, replacing Material's `ExpansionTile`.
///
/// forui's `FAccordion` indents its title by nothing and takes no leading
/// glyph, so a bare one sitting in a card of [BrandTile]s reads as a different
/// widget: flush to the card edge, with a hole where every neighbour has an
/// icon. This matches [BrandTile]'s inset, 8px icon gap and muted 24px glyph so
/// the row lines up with the ones above it. The inset is 14, not 10: `FItem`
/// puts its content inside a 4px `FItemStyle.padding` before the content's own
/// 10px, and the accordion has no equivalent outer padding of its own.
class BrandAccordion extends StatefulWidget {
  final String title;
  final HugeIconData? leading;
  final Widget child;

  const BrandAccordion({
    super.key,
    required this.title,
    required this.child,
    this.leading,
  });

  @override
  State<BrandAccordion> createState() => _BrandAccordionState();
}

class _BrandAccordionState extends State<BrandAccordion> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) => FAccordion(
    // Lifted rather than managed. A managed `FAccordionItem` resets its reveal
    // animation to `initiallyExpanded` in `didChangeDependencies`, so anything
    // that changes an inherited widget above it snaps the panel shut —
    // flipping a switch *inside* the panel closed it under the user's finger.
    // With lifted state the item follows this flag instead of resetting.
    control: .lifted(
      expanded: (_) => _expanded,
      onChange: (_, expanded) {
        AppHaptics.selection();
        setState(() => _expanded = expanded);
      },
    ),
    style: .delta(
      titlePadding: EdgeInsetsGeometryDelta.value(
        const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      ),
      childPadding: EdgeInsetsGeometryDelta.value(
        const EdgeInsets.fromLTRB(14, 0, 14, 16),
      ),
    ),
    children: [
      FAccordionItem(
        title: Row(
          children: [
            if (widget.leading != null) ...[
              AppIcon(widget.leading!, size: 24, color: context.muted),
              const SizedBox(width: 8),
            ],
            Expanded(child: Text(widget.title)),
          ],
        ),
        child: widget.child,
      ),
    ],
  );
}

/// A tab strip plus its views, replacing Material's `TabBar` + `TabBarView`.
///
/// Renders the well inset by [AppSpacing.gutter] on each side (`06-medicine`,
/// `08-expenses`) and scrolls gracefully at larger text scales or locales.
class BrandTabs extends StatefulWidget {
  /// The tab labels, in order, mapped to the view each one shows.
  final Map<String, Widget> tabs;
  final ValueChanged<int>? onTabChanged;

  const BrandTabs({super.key, required this.tabs, this.onTabChanged});

  @override
  State<BrandTabs> createState() => _BrandTabsState();
}

class _BrandTabsState extends State<BrandTabs>
    with SingleTickerProviderStateMixin {
  late TabController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TabController(length: widget.tabs.length, vsync: this);
    _controller.addListener(_onTabChange);
  }

  void _onTabChange() {
    if (!_controller.indexIsChanging) {
      AppHaptics.selection();
      widget.onTabChanged?.call(_controller.index);
    }
  }

  @override
  void didUpdateWidget(BrandTabs old) {
    super.didUpdateWidget(old);
    if (old.tabs.length != widget.tabs.length) {
      _controller.removeListener(_onTabChange);
      _controller.dispose();
      _controller = TabController(length: widget.tabs.length, vsync: this);
      _controller.addListener(_onTabChange);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTabChange);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = context.theme.tabsStyle;
    final selectedStyle = style.labelTextStyle
        .resolve({FTabVariant.selected})
        .copyWith(fontSize: 13, fontWeight: FontWeight.w700);
    final unselectedStyle = style.labelTextStyle
        .resolve(const {})
        .copyWith(fontSize: 13, fontWeight: FontWeight.w600);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
          child: Container(
            width: double.infinity,
            decoration: style.decoration,
            clipBehavior: Clip.antiAlias,
            child: TabBar(
              controller: _controller,
              isScrollable: true,
              tabAlignment: TabAlignment.center,
              padding: style.padding,
              labelPadding: const EdgeInsets.symmetric(horizontal: 11),
              indicator: style.indicatorDecoration,
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelColor: selectedStyle.color,
              unselectedLabelColor: unselectedStyle.color,
              labelStyle: selectedStyle,
              unselectedLabelStyle: unselectedStyle,
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              splashFactory: NoSplash.splashFactory,
              tabs: [
                for (final label in widget.tabs.keys)
                  Tab(height: style.minHeight, text: label),
              ],
            ),
          ),
        ),
        SizedBox(height: style.spacing),
        Expanded(
          child: TabBarView(
            controller: _controller,
            children: [for (final child in widget.tabs.values) child],
          ),
        ),
      ],
    );
  }
}

/// An overflow menu, replacing Material's [PopupMenuButton].
///
/// The trigger is the same [CircleIconButton] used for every other row action,
/// so the affordance matches the rest of the app rather than Material's bare
/// icon and grey card.
class BrandMenuButton<T extends Object> extends StatelessWidget {
  /// The menu entries, in order, keyed by the value handed to [onSelected].
  final Map<T, String> items;
  final ValueChanged<T> onSelected;
  final HugeIconData icon;
  final String tooltip;

  const BrandMenuButton({
    super.key,
    required this.items,
    required this.onSelected,
    this.icon = AppIcons.moreVertical,
    this.tooltip = 'More',
  });

  @override
  Widget build(BuildContext context) => FPopoverMenu(
    menuBuilder: (context, controller, _) => [
      FItemGroup(
        children: [
          for (final entry in items.entries)
            FItem(
              title: Text(entry.value),
              // The menu does not dismiss itself on selection.
              onPress: () {
                AppHaptics.selection();
                controller.hide();
                onSelected(entry.key);
              },
            ),
        ],
      ),
    ],
    builder: (context, controller, _) => CircleIconButton(
      icon: icon,
      tooltip: tooltip,
      size: 40,
      onPressed: controller.toggle,
    ),
  );
}

/// The ink pill (or disc when [label] is omitted) that floats over a list,
/// replacing [FloatingActionButton].
class BrandFab extends StatelessWidget {
  final HugeIconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final String? label;
  final double size;

  const BrandFab({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.label,
    this.size = 54,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final extended = label != null && label!.isNotEmpty;
    return FTooltip(
      key: ValueKey('fab-${tooltip.toLowerCase().replaceAll(' ', '-')}'),
      tipBuilder: (_, _) => Text(tooltip),
      semanticsLabel: tooltip,
      child: FTappable(
        onPress: onPressed == null
            ? null
            : () {
                AppHaptics.medium();
                onPressed!();
              },
        semanticsLabel: tooltip,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: brand.ink,
            shape: extended ? const StadiumBorder() : const CircleBorder(),
            shadows: AppShadows.hero(theme.brightness),
          ),
          child: extended
              ? SizedBox(
                  height: size,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppIcon(icon, size: 20, color: brand.onInk),
                        const SizedBox(width: 8),
                        Text(
                          label!,
                          style: TextStyle(
                            color: brand.onInk,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : SizedBox(
                  width: size,
                  height: size,
                  child: AppIcon(icon, size: size * 0.42, color: brand.onInk),
                ),
        ),
      ),
    );
  }
}

/// Floating white composer pill: 62 high, text field plus a 46 round send
/// button (with optional leading actions such as mic or scan).
class FloatingComposer extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final VoidCallback onSubmit;
  final HugeIconData submitIcon;
  final String submitTooltip;
  final List<Widget> leadingActions;
  final FocusNode? focusNode;
  final bool enabled;

  const FloatingComposer({
    super.key,
    required this.controller,
    required this.hint,
    required this.onSubmit,
    this.submitIcon = AppIcons.add,
    this.submitTooltip = 'Add',
    this.leadingActions = const [],
    this.focusNode,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.brand;
    return Container(
      height: 62,
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: ShapeDecoration(
        color: brand.surface,
        shape: const StadiumBorder(),
        shadows: AppShadows.composer(theme.brightness),
      ),
      child: Row(
        children: [
          for (final action in leadingActions) ...[
            action,
            const SizedBox(width: 4),
          ],
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              enabled: enabled,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSubmit(),
              style: theme.textTheme.bodyLarge?.copyWith(color: brand.ink),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: context.muted,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FTooltip(
            tipBuilder: (_, _) => Text(submitTooltip),
            semanticsLabel: submitTooltip,
            child: FTappable(
              onPress: enabled
                  ? () {
                      AppHaptics.tap();
                      onSubmit();
                    }
                  : null,
              semanticsLabel: submitTooltip,
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: brand.ink,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: AppIcon(submitIcon, size: 20, color: brand.onInk),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A value slider built on [FSlider].
///
/// [FSlider] works in track percentages; the screens think in real ranges
/// (0.85–1.6 for text scale, 5–120 for a dose count), so the conversion lives
/// here rather than at each call site.
class BrandSlider extends StatefulWidget {
  final double value;
  final double min;
  final double max;

  /// Number of steps between [min] and [max]. Null for a continuous slider.
  final int? divisions;

  final ValueChanged<double> onChanged;

  const BrandSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
  });

  @override
  State<BrandSlider> createState() => _BrandSliderState();
}

class _BrandSliderState extends State<BrandSlider> {
  late FContinuousSliderController _controller;

  double get _fraction =>
      ((widget.value - widget.min) / (widget.max - widget.min)).clamp(0.0, 1.0);

  @override
  void initState() {
    super.initState();
    _controller = _build();
  }

  FContinuousSliderController _build() => FContinuousSliderController(
    value: FSliderValue(max: _fraction),
    stepPercentage: widget.divisions == null ? 0.05 : 1 / widget.divisions!,
  );

  @override
  void didUpdateWidget(BrandSlider old) {
    super.didUpdateWidget(old);
    // Rebuild the controller only when the value moved from outside, otherwise
    // dragging would fight its own state.
    if (old.value != widget.value &&
        (_controller.value.max - _fraction).abs() > 0.001) {
      _controller.dispose();
      _controller = _build();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FSlider(
      control: .managedContinuous(
        controller: _controller,
        onChange: (v) =>
            widget.onChanged(widget.min + v.max * (widget.max - widget.min)),
      ),
    );
  }
}

/// Picks a date, replacing `showDatePicker`.
///
/// forui's calendar is a widget rather than a modal, so it is hosted in the
/// brand's sheet. Tapping a day closes the sheet, matching the one-tap feel of
/// the Material picker rather than requiring a separate confirm.
Future<DateTime?> brandDatePicker(
  BuildContext context, {
  DateTime? initial,
  DateTime? first,
  DateTime? last,
  String title = 'Pick a date',
}) {
  final now = DateTime.now();
  return brandSheet<DateTime>(
    context: context,
    builder: (sheetContext) => SheetScaffold(
      title: title,
      child: FCalendar.grid(
        selectionControl: FDateSelectionControl.managedSingle(initial: initial),
        control: FGridCalendarControl(
          start: first ?? DateTime(now.year - 5),
          end: last ?? DateTime(now.year + 5),
          initial: initial ?? now,
        ),
        onDayPress: (day) {
          AppHaptics.selection();
          Navigator.of(sheetContext).pop(day);
        },
      ),
    ),
  );
}

/// Picks an inclusive date range, replacing `showDateRangePicker`.
///
/// Unlike [brandDatePicker] this cannot close on tap — a range needs two taps —
/// so it carries an explicit confirm, disabled until both ends are chosen.
Future<(DateTime, DateTime)?> brandDateRangePicker(
  BuildContext context, {
  required DateTime first,
  required DateTime last,
  (DateTime, DateTime)? initial,
  String title = 'Pick a range',
}) {
  var range = initial;
  return brandSheet<(DateTime, DateTime)>(
    context: context,
    builder: (sheetContext) => StatefulBuilder(
      builder: (_, setState) => SheetScaffold(
        title: title,
        actions: [
          BrandButton(
            label: 'Done',
            expand: false,
            onPressed: range == null
                ? null
                : () => Navigator.of(sheetContext).pop(range),
          ),
        ],
        child: FCalendar.grid(
          selectionControl: FDateSelectionControl.managedRange(
            initial: initial,
            onChange: (v) {
              AppHaptics.selection();
              setState(() => range = v);
            },
          ),
          control: FGridCalendarControl(
            start: first,
            end: last,
            initial: initial?.$1 ?? first,
          ),
        ),
      ),
    ),
  );
}

/// Picks a time of day, returning minutes past midnight.
///
/// forui's time picker is a wheel widget rather than a modal, so it is hosted in
/// the brand's own sheet with a confirm action.
Future<int?> brandTimePicker(
  BuildContext context, {
  required int initialMinutes,
  String title = 'Pick a time',
}) async {
  final controller = FTimePickerController(
    time: FTime(initialMinutes ~/ 60, initialMinutes % 60),
  );

  final result = await brandSheet<int>(
    context: context,
    builder: (sheetContext) => SheetScaffold(
      title: title,
      actions: [
        FButton(
          variant: .ghost,
          size: .sm,
          mainAxisSize: .min,
          onPress: () {
            AppHaptics.tap();
            Navigator.of(
              sheetContext,
            ).pop(controller.value.hour * 60 + controller.value.minute);
          },
          child: Text(
            'Done',
            style: TextStyle(
              color: Theme.of(sheetContext).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
      child: SizedBox(
        height: 220,
        child: FTimePicker(control: .managed(controller: controller)),
      ),
    ),
  );

  controller.dispose();
  return result;
}

/// Shows a bottom sheet with the brand's chrome.
///
/// forui caps a modal sheet at 9/16 of the screen by default; the editors here
/// are taller than that, so the cap is lifted and height is left to the content
/// the way `isScrollControlled` did.
Future<T?> brandSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool dismissible = true,
}) {
  return showFSheet<T>(
    context: context,
    // The shell's tab bar lives above the tab navigators, so a modal opened
    // in one would sit under it. The root navigator covers the whole screen.
    useRootNavigator: true,
    side: .btt,
    mainAxisMaxRatio: null,
    barrierDismissible: dismissible,
    builder: (sheetContext) {
      // showFSheet strips top MediaQuery.padding, so read viewPadding to keep
      // tall sheets clear of the status bar while leaving short sheets compact.
      final vp = MediaQuery.viewPaddingOf(sheetContext).top;
      final pad = MediaQuery.paddingOf(sheetContext).top;
      final topInset = vp > pad ? vp : pad;
      final screenH = MediaQuery.sizeOf(sheetContext).height;
      final content = builder(sheetContext);
      if (topInset <= 0 || screenH <= topInset + 8) return content;
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: screenH - topInset - 8),
        child: content,
      );
    },
  );
}

/// Slides a panel in from the leading edge, replacing Material's `Drawer`.
///
/// `Drawer` needs a `Scaffold` to host it and an app bar to offer the hamburger,
/// neither of which [BrandScaffold] provides. forui's `FSidebar` is a persistent
/// panel rather than a modal, so the drawer screens present their filter panel as
/// a left-hand sheet instead, opened from an explicit header button.
Future<T?> brandSideSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showFSheet<T>(
    context: context,
    useRootNavigator: true,
    side: .ltr,
    mainAxisMaxRatio: null,
    builder: builder,
  );
}

/// Shows a message. Replaces `ScaffoldMessenger.showSnackBar`.
///
/// Styled from the values the Material `snackBarTheme` used — a near-black slab
/// with a brand-coloured action — and aligned to the bottom so it lands where
/// the snack bar used to rather than in forui's default corner.
void brandToast(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 4),
}) {
  final theme = Theme.of(context);
  // The slab is dark in both themes, so the action wants the palette's
  // dark-mode primary. `snackBarTheme` already resolved exactly that.
  final action =
      theme.snackBarTheme.actionTextColor ?? theme.colorScheme.primary;

  showFToast(
    context: context,
    alignment: FToastAlignment.bottomCenter,
    duration: duration,
    title: Text(message),
    suffixBuilder: (actionLabel == null || onAction == null)
        ? null
        : (_, entry) => FButton(
            variant: .ghost,
            size: .sm,
            mainAxisSize: .min,
            onPress: () {
              AppHaptics.tap();
              entry.dismiss();
              onAction();
            },
            child: Text(
              actionLabel,
              style: TextStyle(color: action, fontWeight: FontWeight.w600),
            ),
          ),
  );
}

/// A dialog with arbitrary content. Replaces `showDialog` + `AlertDialog` for
/// the cases [brandConfirm] cannot cover — the ones whose body is a form.
///
/// [builder] gets the dialog's own context, so `Navigator.pop(context, value)`
/// inside it returns from this future.
Future<T?> brandDialog<T>(
  BuildContext context, {
  required String title,
  required WidgetBuilder builder,
  List<Widget> actions = const [],
  bool barrierDismissible = true,
}) => showFDialog<T>(
  context: context,
  useRootNavigator: true,
  barrierDismissible: barrierDismissible,
  builder: (context, style, animation) => FDialog(
    animation: animation,
    style: style,
    // FDialog hands over the bare surface — the content inset is the caller's
    // job, and forui's own `insetPadding` is the margin from the screen edge.
    // The dialog shrinks to clear the keyboard, so a form taller than what
    // is left scrolls inside the card rather than spilling out under it.
    builder: (context, _) => SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          builder(context),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 20),
            // Stacked rather than in a trailing row: the brand's buttons are
            // full-width pills, and a form dialog is narrow.
            for (final action in actions) ...[
              action,
              if (action != actions.last) const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    ),
  ),
);

/// Blocking PIN prompt shared by the app lock gate and locked notes. Returns
/// true only when [verify] accepts the entered PIN.
Future<bool> promptForPin(
  BuildContext context,
  bool Function(String pin) verify, {
  String title = 'Enter PIN',
}) async {
  final controller = TextEditingController();
  String? error;

  final ok = await brandDialog<bool>(
    context,
    title: title,
    // Tapping outside must not dismiss a lock prompt.
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (_, setState) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BrandField(
            controller: controller,
            autofocus: true,
            obscure: true,
            keyboardType: TextInputType.number,
            error: error,
          ),
          const SizedBox(height: 20),
          BrandButton(
            label: 'Unlock',
            onPressed: () {
              if (verify(controller.text)) {
                AppHaptics.success();
                Navigator.pop(dialogContext, true);
              } else {
                AppHaptics.error();
                setState(() => error = 'Incorrect PIN');
              }
            },
          ),
          const SizedBox(height: 8),
          BrandButton(
            label: 'Cancel',
            kind: BrandButtonKind.ghost,
            onPressed: () => Navigator.pop(dialogContext, false),
          ),
        ],
      ),
    ),
  );

  return ok == true;
}

/// A confirm/cancel dialog. Replaces `showDialog` + `AlertDialog`.
///
/// Returns true only when the confirming action is chosen.
Future<bool> brandConfirm(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = 'OK',
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final result = await showFDialog<bool>(
    context: context,
    useRootNavigator: true,
    builder: (context, style, animation) => FDialog(
      animation: animation,
      style: style,
      builder: (context, style) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: context.muted),
              ),
            ],
            const SizedBox(height: 20),
            BrandButton(
              label: confirmLabel,
              kind: destructive
                  ? BrandButtonKind.danger
                  : BrandButtonKind.primary,
              onPressed: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: 8),
            BrandButton(
              label: cancelLabel,
              kind: BrandButtonKind.ghost,
              onPressed: () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      ),
    ),
  );
  return result ?? false;
}

/// Small colour swatch picker used by habits, projects and categories.
class ColorPickerRow extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;

  /// The warm brand family. Existing rows may still hold a colour from the old
  /// indigo palette; those render fine, they just show as unselected here.
  static const palette = <int>[
    0xFFFF6547,
    0xFF3BB273,
    0xFFF2A03D,
    0xFFE5484D,
    0xFF9A6DD7,
    0xFF3AAFB9,
    0xFFE86FA0,
    0xFF6C6C6C,
  ];

  const ColorPickerRow({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: palette.map((c) {
        final isSel = c == selected;
        return GestureDetector(
          onTap: () {
            AppHaptics.selection();
            onChanged(c);
          },
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Color(c),
              shape: BoxShape.circle,
              border: Border.all(
                color: isSel
                    ? Theme.of(context).colorScheme.onSurface
                    : Colors.transparent,
                width: 2.5,
              ),
            ),
            child: isSel
                ? const AppIcon(AppIcons.check, size: 18, color: Colors.white)
                : null,
          ),
        );
      }).toList(),
    );
  }
}

/// Icon picker backed by one of the token maps in `AppIcons`.
class IconPickerRow extends StatelessWidget {
  final Map<String, HugeIconData> options;
  final String selected;
  final Color color;
  final ValueChanged<String> onChanged;

  const IconPickerRow({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: options.entries.map((e) {
        final isSel = e.key == selected;
        return GestureDetector(
          onTap: () {
            AppHaptics.selection();
            onChanged(e.key);
          },
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isSel
                  ? color.withValues(alpha: 0.18)
                  : context.brand.tint(0),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSel ? color : Colors.transparent,
                width: 2,
              ),
            ),
            child: AppIcon(
              e.value,
              size: 20,
              color: isSel ? color : Theme.of(context).colorScheme.outline,
            ),
          ),
        );
      }).toList(),
    );
  }
}

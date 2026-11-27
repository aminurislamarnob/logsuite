import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/settings/app_settings.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/common.dart';
import '../modules/modules_screen.dart';
import 'how_to_content.dart';

/// The short guides to the app, reached from Settings (`44-how-to.html`).
class HowToScreen extends ConsumerStatefulWidget {
  /// The [HowToGuide.id] to open on arrival. Unknown ids are ignored and the
  /// quick-start guide opens instead.
  final String? initialGuide;

  const HowToScreen({super.key, this.initialGuide});

  @override
  ConsumerState<HowToScreen> createState() => _HowToScreenState();
}

class _HowToScreenState extends ConsumerState<HowToScreen> {
  final Set<String> _open = {};
  final _keys = {for (final g in howToGuides) g.id: GlobalKey()};

  @override
  void initState() {
    super.initState();
    final initial = widget.initialGuide;
    final known = initial != null && _keys.containsKey(initial);
    _open.add(known ? initial : howToGuides.first.id);
    if (known) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(initial));
    }
  }

  Duration get _motion => MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 220);

  void _toggle(String id) {
    setState(() => _open.contains(id) ? _open.remove(id) : _open.add(id));
  }

  /// Opens [id] and brings it to the top of the page.
  void _jump(String id) {
    setState(() => _open.add(id));
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(id));
  }

  void _reveal(String id) {
    if (!mounted) return;
    final target = _keys[id]?.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(target, duration: _motion, curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return BrandScaffold(
      header: const BrandTopBar(
        title: 'How to',
        subtitle: 'Short guides for every part of the app',
        leadingIcon: AppIcons.back,
      ),
      child: SingleChildScrollView(
        padding: pageInsets(context, gutter: 0, end: PageEnd.none),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  for (final (i, guide) in howToGuides.indexed) ...[
                    if (i > 0) const SizedBox(width: 6),
                    _JumpPill(
                      key: Key('howto-jump-${guide.id}'),
                      label: guide.label,
                      dotColor: guide.module == null
                          ? null
                          : _accentFor(context, guide),
                      selected: _open.contains(guide.id),
                      onTap: () => _jump(guide.id),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final guide in howToGuides)
                    Padding(
                      key: _keys[guide.id],
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _GuideCard(
                        key: Key('howto-card-${guide.id}'),
                        guide: guide,
                        accent: _accentFor(context, guide),
                        open: _open.contains(guide.id),
                        enabled:
                            guide.module == null ||
                            settings.isEnabled(guide.module!),
                        motion: _motion,
                        onToggle: () => _toggle(guide.id),
                        onOpen: guide.module == null
                            ? null
                            : () => context.push(guide.module!.route),
                        onTurnOn: guide.module == null
                            ? null
                            : () => notifier.toggleModule(guide.module!, true),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A module guide wears its module's colour; an app-wide one wears the brand.
  static Color _accentFor(BuildContext context, HowToGuide guide) {
    final module = guide.module;
    return module == null
        ? Theme.of(context).colorScheme.primary
        : ModulesScreen.accentFor(context.brand, module);
  }
}

class _JumpPill extends StatelessWidget {
  final String label;
  final Color? dotColor;
  final bool selected;
  final VoidCallback onTap;

  const _JumpPill({
    super.key,
    required this.label,
    required this.dotColor,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return BrandTappable(
      onPressed: onTap,
      child: Container(
        height: 38,
        padding: EdgeInsets.symmetric(horizontal: selected ? 14 : 12),
        decoration: BoxDecoration(
          color: selected ? brand.ink : brand.surface,
          borderRadius: BorderRadius.circular(19),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dotColor != null && !selected) ...[
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: selected ? brand.onInk : context.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuideCard extends StatelessWidget {
  final HowToGuide guide;
  final Color accent;
  final bool open;

  /// Whether the guide's module is switched on. Always true for a guide
  /// without a module.
  final bool enabled;

  final Duration motion;
  final VoidCallback onToggle;
  final VoidCallback? onOpen;
  final VoidCallback? onTurnOn;

  const _GuideCard({
    super.key,
    required this.guide,
    required this.accent,
    required this.open,
    required this.enabled,
    required this.motion,
    required this.onToggle,
    required this.onOpen,
    required this.onTurnOn,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final theme = Theme.of(context);
    final muted = context.muted;
    final isQuickStart = guide.id == 'start';
    final isModule = guide.module != null;
    final roles = brand.roleFor(accent);

    final chipBg = isQuickStart
        ? brand.ink
        : isModule
        ? roles.tintFill
        : brand.hairline;
    final chipIconColor = isQuickStart
        ? brand.medicineRoles.onInk
        : isModule
        ? roles.graphicOnTint
        : brand.ink;

    return Container(
      decoration: BoxDecoration(
        color: enabled ? brand.surface : brand.well,
        borderRadius: BorderRadius.circular(AppRadii.card),
        boxShadow: enabled ? AppShadows.card(theme.brightness) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BrandTappable(
            onPressed: onToggle,
            semanticsLabel: '${guide.title}, ${open ? 'collapse' : 'expand'}',
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: enabled ? chipBg : brand.surface,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: AppIcon(
                      guide.icon,
                      color: enabled ? chipIconColor : context.subtle,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                guide.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            if (!enabled) ...[
                              const SizedBox(width: 8),
                              _Badge('Off', color: muted),
                            ],
                          ],
                        ),
                        const SizedBox(height: 1),
                        Text(
                          guide.tagline,
                          style: TextStyle(fontSize: 12.5, color: muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: motion,
                    child: AppIcon(
                      AppIcons.chevronDown,
                      size: 18,
                      color: muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: motion,
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: open
                ? _GuideBody(
                    guide: guide,
                    accent: accent,
                    enabled: enabled,
                    onOpen: onOpen,
                    onTurnOn: onTurnOn,
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _GuideBody extends StatelessWidget {
  final HowToGuide guide;
  final Color accent;
  final bool enabled;
  final VoidCallback? onOpen;
  final VoidCallback? onTurnOn;

  const _GuideBody({
    required this.guide,
    required this.accent,
    required this.enabled,
    required this.onOpen,
    required this.onTurnOn,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final muted = context.muted;
    final module = guide.module;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, step) in guide.steps.indexed)
            Padding(
              padding: EdgeInsets.only(
                bottom: i == guide.steps.length - 1 ? 0 : 14,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: brand.hairline,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        color: brand.ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          step.action,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          step.detail,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (guide.tips.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: brand.noteRoles.tintFill,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'GOOD TO KNOW',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                      color: brand.noteRoles.textOnTint,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final (i, tip) in guide.tips.indexed)
                    Padding(
                      padding: EdgeInsets.only(
                        bottom: i == guide.tips.length - 1 ? 0 : 8,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 5,
                            height: 5,
                            margin: const EdgeInsets.only(top: 7),
                            decoration: BoxDecoration(
                              color: brand.noteRoles.graphicOnTint,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              tip,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.4,
                                color: brand.ink,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (module != null) ...[
            const SizedBox(height: 14),
            if (enabled)
              Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: BrandButton(
                    label: 'Open ${module.label}',
                    kind: BrandButtonKind.outline,
                    icon: AppIcons.chevronRight,
                    expand: false,
                    small: true,
                    onPressed: onOpen,
                  ),
                ),
              )
            else
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text(
                    'Switched off in Settings.',
                    style: TextStyle(fontSize: 12.5, color: muted),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: BrandButton(
                      label: 'Turn on',
                      kind: BrandButtonKind.primary,
                      expand: false,
                      small: true,
                      onPressed: onTurnOn,
                    ),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}

/// A small outlined tag, for the "Off" mark on a switched-off module's card.
class _Badge extends StatelessWidget {
  final String label;
  final Color color;

  const _Badge(this.label, {required this.color});

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: ShapeDecoration(
      shape: StadiumBorder(
        side: BorderSide(color: color.withValues(alpha: 0.6)),
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    ),
  );
}

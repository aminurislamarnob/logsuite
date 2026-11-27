import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/settings/app_settings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/widgets/common.dart';
import '../../medicine/providers/medicine_provider.dart';
import '../../medicine/repository/medicine_repository.dart';

class MedicineHeroCard extends ConsumerStatefulWidget {
  final bool isLocked;

  const MedicineHeroCard({super.key, required this.isLocked});

  @override
  ConsumerState<MedicineHeroCard> createState() => _MedicineHeroCardState();
}

class _MedicineHeroCardState extends ConsumerState<MedicineHeroCard>
    with TickerProviderStateMixin {
  int? _lastTakenDoseId;
  String? _lastTakenName;
  int _popTick = 0;

  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _pulseCtrl.stop();
    } else if (!_pulseCtrl.isAnimating) {
      _pulseCtrl.repeat();
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final roles = brand.medicineRoles;

    if (widget.isLocked) {
      return Container(
        key: const ValueKey('module-medicine'),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: brand.heroSurface,
          borderRadius: BorderRadius.circular(AppRadii.hero),
          boxShadow: AppShadows.hero(theme.brightness),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: brand.medicine.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: AppIcon(AppIcons.lock, size: 15, color: roles.onInk),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'MEDICINE · LOCKED',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                    color: roles.onInk,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'Doses are hidden',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Unlock Medicine to view and take today\'s doses.',
              style: TextStyle(fontSize: 14, color: brand.onInkMuted),
            ),
            const SizedBox(height: 16),
            _HeroActionPill(
              label: 'Unlock to see doses',
              icon: AppIcons.lock,
              primary: true,
              onTap: () {
                AppHaptics.tap();
                context.push(AppModule.medicine.route);
              },
            ),
          ],
        ),
      );
    }

    final doses = ref.watch(todayDoseViewsProvider).valueOrNull ?? const [];
    final now = DateTime.now();
    final takenCount = doses.where((d) => d.status == DoseStatus.taken).length;
    final pending = doses.where((d) => d.status == DoseStatus.pending).toList()
      ..sort((a, b) => a.at.compareTo(b.at));
    final dueNow = pending.where((d) => !d.at.isAfter(now)).firstOrNull;
    final nextPending = dueNow ?? pending.firstOrNull;

    final eyebrow = dueNow != null
        ? 'MEDICINE · DUE NOW'
        : 'MEDICINE · ALL CAUGHT UP';
    final countLabel = doses.isEmpty
        ? 'No doses today'
        : '$takenCount of ${doses.length} taken';

    final String title;
    final String subtitle;
    if (nextPending != null && dueNow != null) {
      title = nextPending.medicine.name;
      final meal = nextPending.mealLabel.isEmpty
          ? ''
          : ' · ${nextPending.mealLabel}';
      subtitle =
          '${nextPending.dosageLabel}$meal · was due ${Fmt.time(nextPending.at)}';
    } else if (nextPending != null) {
      title = 'Next at ${Fmt.time(nextPending.at)}';
      final meal = nextPending.mealLabel.isEmpty
          ? ''
          : ' · ${nextPending.mealLabel}';
      subtitle =
          '${nextPending.medicine.name} · ${nextPending.dosageLabel}$meal';
    } else if (doses.isEmpty) {
      title = 'All clear today';
      subtitle = AppModule.medicine.blurb;
    } else {
      title = 'All doses taken';
      subtitle = 'Every scheduled dose is complete for today.';
    }

    final displayDoses = _sliceSixDoses(doses);
    final showUndoState = _lastTakenDoseId != null && dueNow == null;

    return Container(
      key: const ValueKey('module-medicine'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: brand.heroSurface,
        borderRadius: BorderRadius.circular(AppRadii.hero),
        boxShadow: AppShadows.hero(theme.brightness),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: brand.medicine.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: AppIcon(
                    AppIcons.medicine,
                    size: 16,
                    color: roles.onInk,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  eyebrow,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                    color: roles.onInk,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                countLabel,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: brand.onInkMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.7,
              height: 1.1,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14, color: brand.onInkMuted),
          ),
          if (displayDoses.isNotEmpty) ...[
            const SizedBox(height: 16),
            _DoseRail(
              doses: displayDoses,
              now: now,
              medicineColor: brand.medicine,
              heroSurface: brand.heroSurface,
              onInk: roles.onInk,
              muted: brand.onInkMuted,
              pulseAnim: _pulseCtrl,
              poppedDoseId: _lastTakenDoseId,
              popTick: _popTick,
            ),
          ],
          const SizedBox(height: 16),
          if (showUndoState)
            Row(
              children: [
                Expanded(
                  child: _HeroActionPill(
                    label: 'Undo',
                    primary: false,
                    onTap: () => _undoTaken(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _HeroActionPill(
                    label: 'Open Medicine',
                    primary: true,
                    onTap: () {
                      AppHaptics.tap();
                      context.push(AppModule.medicine.route);
                    },
                  ),
                ),
              ],
            )
          else if (dueNow != null)
            Row(
              children: [
                Expanded(
                  child: _HeroActionPill(
                    label: 'Take now',
                    icon: AppIcons.check,
                    primary: true,
                    onTap: () => _takeDose(dueNow),
                  ),
                ),
                const SizedBox(width: 10),
                _HeroActionPill(
                  label: 'Schedule',
                  primary: false,
                  expand: false,
                  onTap: () {
                    AppHaptics.tap();
                    context.push(AppModule.medicine.route);
                  },
                ),
              ],
            )
          else
            _HeroActionPill(
              label: 'Open Medicine',
              primary: true,
              onTap: () {
                AppHaptics.tap();
                context.push(AppModule.medicine.route);
              },
            ),
        ],
      ),
    );
  }

  List<DoseView> _sliceSixDoses(List<DoseView> doses) {
    if (doses.length <= 6) return doses;
    final firstPending = doses.indexWhere(
      (d) => d.status == DoseStatus.pending,
    );
    if (firstPending < 0) {
      return doses.sublist(doses.length - 6);
    }
    final start = math.min(firstPending, doses.length - 6);
    return doses.sublist(start, start + 6);
  }

  Future<void> _takeDose(DoseView view) async {
    AppHaptics.tap();
    final repo = ref.read(medicineRepositoryProvider);
    setState(() {
      _lastTakenDoseId = view.dose.id;
      _lastTakenName = view.medicine.name;
      _popTick++;
    });
    await repo.setDoseStatus(view.dose.id, DoseStatus.taken);
    if (!mounted) return;
    brandToast(
      context,
      '${view.medicine.name} taken',
      actionLabel: 'Undo',
      onAction: () async {
        await repo.setDoseStatus(view.dose.id, DoseStatus.pending);
        if (mounted) {
          setState(() {
            if (_lastTakenDoseId == view.dose.id) {
              _lastTakenDoseId = null;
              _lastTakenName = null;
            }
          });
        }
      },
    );
  }

  Future<void> _undoTaken() async {
    final id = _lastTakenDoseId;
    if (id == null) return;
    AppHaptics.tap();
    final name = _lastTakenName ?? 'Dose';
    setState(() {
      _lastTakenDoseId = null;
      _lastTakenName = null;
    });
    await ref
        .read(medicineRepositoryProvider)
        .setDoseStatus(id, DoseStatus.pending);
    if (mounted) {
      brandToast(context, '$name marked pending.');
    }
  }
}

class _DoseRail extends StatelessWidget {
  final List<DoseView> doses;
  final DateTime now;
  final Color medicineColor;
  final Color heroSurface;
  final Color onInk;
  final Color muted;
  final Animation<double> pulseAnim;
  final int? poppedDoseId;
  final int popTick;

  const _DoseRail({
    required this.doses,
    required this.now,
    required this.medicineColor,
    required this.heroSurface,
    required this.onInk,
    required this.muted,
    required this.pulseAnim,
    required this.poppedDoseId,
    required this.popTick,
  });

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return Semantics(
      label: "Today's doses",
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < doses.length; i++) ...[
            if (i > 0)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 13),
                  child: Container(
                    height: 2,
                    color:
                        doses[i - 1].status == DoseStatus.taken &&
                            doses[i].status == DoseStatus.taken
                        ? medicineColor
                        : Colors.white.withValues(alpha: 0.18),
                  ),
                ),
              ),
            _DoseDot(
              view: doses[i],
              isDueNow:
                  doses[i].status == DoseStatus.pending &&
                  !doses[i].at.isAfter(now),
              medicineColor: medicineColor,
              heroSurface: heroSurface,
              onInk: onInk,
              muted: muted,
              pulseAnim: pulseAnim,
              shouldPop: poppedDoseId == doses[i].dose.id,
              popTick: popTick,
              reduceMotion: reduceMotion,
            ),
          ],
        ],
      ),
    );
  }
}

class _DoseDot extends StatelessWidget {
  final DoseView view;
  final bool isDueNow;
  final Color medicineColor;
  final Color heroSurface;
  final Color onInk;
  final Color muted;
  final Animation<double> pulseAnim;
  final bool shouldPop;
  final int popTick;
  final bool reduceMotion;

  const _DoseDot({
    required this.view,
    required this.isDueNow,
    required this.medicineColor,
    required this.heroSurface,
    required this.onInk,
    required this.muted,
    required this.pulseAnim,
    required this.shouldPop,
    required this.popTick,
    required this.reduceMotion,
  });

  @override
  Widget build(BuildContext context) {
    final isTaken = view.status == DoseStatus.taken;
    final stateLabel = isTaken
        ? 'taken'
        : isDueNow
        ? 'due now'
        : 'later';

    Widget dot;
    if (isTaken) {
      dot = Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(color: medicineColor, shape: BoxShape.circle),
        child: const Center(
          child: AppIcon(AppIcons.check, size: 14, color: Colors.white),
        ),
      );
      if (shouldPop && !reduceMotion) {
        dot = _PopDot(popTick: popTick, child: dot);
      }
    } else if (isDueNow) {
      dot = AnimatedBuilder(
        animation: pulseAnim,
        builder: (context, child) {
          final p = reduceMotion ? 0.0 : pulseAnim.value;
          return Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              if (!reduceMotion && p > 0)
                Container(
                  width: 28 + 14 * p,
                  height: 28 + 14 * p,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: medicineColor.withValues(alpha: (1 - p) * 0.55),
                      width: 2,
                    ),
                  ),
                ),
              child!,
            ],
          );
        },
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: heroSurface,
            shape: BoxShape.circle,
            border: Border.all(color: medicineColor, width: 2.5),
          ),
        ),
      );
    } else {
      dot = Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: heroSurface,
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.22),
            width: 2,
          ),
        ),
      );
    }

    return Semantics(
      label: '${view.medicine.name} at ${Fmt.time(view.at)}, $stateLabel',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          dot,
          const SizedBox(height: 6),
          Text(
            Fmt.time(view.at),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isDueNow
                  ? onInk
                  : (isTaken ? Colors.white.withValues(alpha: 0.85) : muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _PopDot extends StatefulWidget {
  final int popTick;
  final Widget child;

  const _PopDot({required this.popTick, required this.child});

  @override
  State<_PopDot> createState() => _PopDotState();
}

class _PopDotState extends State<_PopDot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 0.6,
          end: 1.25,
        ).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 55,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.25,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 45,
      ),
    ]).animate(_ctrl);
    _ctrl.forward();
  }

  @override
  void didUpdateWidget(covariant _PopDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.popTick != oldWidget.popTick) {
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ScaleTransition(scale: _scale, child: widget.child);
}

class _HeroActionPill extends StatelessWidget {
  final String label;
  final HugeIconData? icon;
  final bool primary;
  final bool expand;
  final VoidCallback onTap;

  const _HeroActionPill({
    required this.label,
    this.icon,
    required this.primary,
    this.expand = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = primary ? Colors.white : Colors.white.withValues(alpha: 0.10);
    final fg = primary ? AppColors.ink : Colors.white;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        padding: expand ? null : const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(26),
        ),
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              AppIcon(icon!, size: 18, color: fg),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: primary ? 16 : 15,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

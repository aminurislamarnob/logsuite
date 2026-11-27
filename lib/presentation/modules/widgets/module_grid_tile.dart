import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/app_settings.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/haptics.dart';
import '../../drop/providers/drop_provider.dart';
import '../../expenses/providers/expenses_provider.dart';
import '../../focus/providers/focus_provider.dart';
import '../../habits/providers/habits_provider.dart';
import '../../notes/providers/notes_provider.dart';
import '../../tasks/providers/tasks_provider.dart';

class ModuleGridTile extends ConsumerStatefulWidget {
  final AppModule module;
  final HugeIconData icon;
  final Color accent;
  final int index;
  final bool isLocked;
  final VoidCallback onTap;
  final VoidCallback onQuickAction;

  const ModuleGridTile({
    super.key,
    required this.module,
    required this.icon,
    required this.accent,
    required this.index,
    required this.isLocked,
    required this.onTap,
    required this.onQuickAction,
  });

  @override
  ConsumerState<ModuleGridTile> createState() => _ModuleGridTileState();
}

class _ModuleGridTileState extends ConsumerState<ModuleGridTile>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;
  bool _entered = false;
  late final AnimationController _enterCtrl;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _enterCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    final curved = CurvedAnimation(
      parent: _enterCtrl,
      curve: Curves.easeOutCubic,
    );
    _opacity = curved;
    _slide = Tween<Offset>(
      begin: const Offset(0, 14),
      end: Offset.zero,
    ).animate(curved);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_entered) return;
    _entered = true;
    if (MediaQuery.of(context).disableAnimations) {
      _enterCtrl.value = 1.0;
      return;
    }
    final delay = Duration(milliseconds: widget.index * 55);
    if (delay == Duration.zero) {
      _enterCtrl.forward();
    } else {
      Future<void>.delayed(delay, () {
        if (mounted) _enterCtrl.forward();
      });
    }
  }

  @override
  void dispose() {
    _enterCtrl.dispose();
    super.dispose();
  }

  String _quickActionSemantics(AppModule m) => switch (m) {
    AppModule.tasks => 'New task',
    AppModule.habits => 'Log a habit',
    AppModule.expenses => 'New expense',
    AppModule.focus => 'Start a focus session',
    AppModule.notes => 'New note',
    AppModule.drop => 'New drop',
    AppModule.medicine => 'Log dose',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final roles = brand.roleFor(widget.accent);
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    final Widget content = widget.isLocked
        ? _buildLockedContent(brand)
        : _buildLiveContent(context, brand, roles, reduceMotion);

    final tile = AnimatedScale(
      scale: (!reduceMotion && _pressed) ? 0.97 : 1.0,
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 170),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: brand.surface,
            borderRadius: BorderRadius.circular(AppRadii.card),
            boxShadow: AppShadows.card(theme.brightness),
          ),
          child: Stack(
            children: [
              Semantics(
                button: true,
                label: widget.isLocked
                    ? '${widget.module.label}, locked. Unlock to open'
                    : 'Open ${widget.module.label}',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (_) => setState(() => _pressed = true),
                  onTapUp: (_) => setState(() => _pressed = false),
                  onTapCancel: () => setState(() => _pressed = false),
                  onTap: () {
                    AppHaptics.tap();
                    widget.onTap();
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: content,
                  ),
                ),
              ),
              if (!widget.isLocked)
                Positioned(
                  top: 16,
                  right: 16,
                  child: Semantics(
                    button: true,
                    label: _quickActionSemantics(widget.module),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        AppHaptics.tap();
                        widget.onQuickAction();
                      },
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: Align(
                          alignment: Alignment.topRight,
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: roles.tintFill,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: AppIcon(
                                widget.module == AppModule.focus
                                    ? AppIcons.play
                                    : AppIcons.add,
                                size: 16,
                                color: roles.graphicOnTint,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    if (reduceMotion) {
      return KeyedSubtree(
        key: ValueKey('module-${widget.module.name}'),
        child: tile,
      );
    }

    return KeyedSubtree(
      key: ValueKey('module-${widget.module.name}'),
      child: AnimatedBuilder(
        animation: _enterCtrl,
        builder: (context, child) => Opacity(
          opacity: _opacity.value,
          child: Transform.translate(offset: _slide.value, child: child),
        ),
        child: tile,
      ),
    );
  }

  Widget _buildLockedContent(BrandColors brand) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: brand.canvas,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: AppIcon(widget.icon, size: 20, color: context.muted),
              ),
            ),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: brand.ink,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: AppIcon(AppIcons.lock, size: 14, color: brand.onInk),
              ),
            ),
          ],
        ),
        Text(
          'Locked',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.7,
            color: context.muted,
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.module.label,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
                color: brand.ink,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              'Tap to unlock',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: context.muted),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLiveContent(
    BuildContext context,
    BrandColors brand,
    ModuleColors roles,
    bool reduceMotion,
  ) {
    final data = _readTileData(context, brand, roles);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Leading 40x40 icon chip (top-right 36x36 quick action is positioned in Stack)
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: roles.tintFill,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(
            child: AppIcon(widget.icon, size: 20, color: roles.graphicOnTint),
          ),
        ),
        const SizedBox(height: 12),

        // Big figure + unit
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                data.figure,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.7,
                  color: brand.ink,
                ),
              ),
            ),
            if (data.unit != null) ...[
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  data.unit!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.muted,
                  ),
                ),
              ),
            ],
          ],
        ),

        if (data.progress != null) ...[
          const SizedBox(height: 10),
          _AnimatedTileBar(
            value: data.progress!,
            trackColor: roles.tintFill,
            fillColor: roles.graphicOnTint,
            delay: Duration(milliseconds: 200 + widget.index * 55),
            reduceMotion: reduceMotion,
          ),
        ] else if (data.peekText != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: roles.tintFill,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              data.peekText!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: roles.textOnTint,
              ),
            ),
          ),
        ],

        const SizedBox(height: 12),

        // Name + 1-line subtitle
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.module.label,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
                color: brand.ink,
              ),
            ),
            if (data.subtitle != null) ...[
              const SizedBox(height: 1),
              Text(
                data.subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: data.subtitleDanger
                      ? FontWeight.w600
                      : FontWeight.w400,
                  color: data.subtitleDanger
                      ? brand.dangerRoles.textOnTint
                      : context.muted,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  ({
    String figure,
    String? unit,
    double? progress,
    String? peekText,
    String? subtitle,
    bool subtitleDanger,
  })
  _readTileData(BuildContext context, BrandColors brand, ModuleColors roles) {
    final settings = ref.watch(settingsProvider);
    switch (widget.module) {
      case AppModule.tasks:
        final tasks = ref.watch(todayTasksProvider).valueOrNull ?? const [];
        final stats = ref.watch(taskStatsProvider(7)).valueOrNull;
        final total = tasks.length;
        final done = tasks.where((t) => t.isCompleted).length;
        final open = total - done;
        final overdue = stats?.overdue ?? 0;
        final sub = overdue > 0
            ? '$overdue overdue · $open left'
            : (total == 0 ? widget.module.blurb : 'All done today');
        return (
          figure: '$done',
          unit: 'of $total done',
          progress: total == 0 ? 0.0 : (done / total).clamp(0.0, 1.0),
          peekText: null,
          subtitle: sub,
          subtitleDanger: overdue > 0,
        );
      case AppModule.habits:
        final habits = ref.watch(habitsListProvider).valueOrNull ?? const [];
        final logs = ref.watch(todayHabitLogsProvider).valueOrNull ?? const {};
        final done = habits.where((h) {
          final a = logs[h.id] ?? 0;
          return h.goalType == 0
              ? a >= (h.targetAmount <= 0 ? 1.0 : h.targetAmount)
              : a <= h.targetAmount;
        }).length;
        return (
          figure: '$done',
          unit: habits.isEmpty ? null : 'of ${habits.length} today',
          progress: habits.isEmpty
              ? 0.0
              : (done / habits.length).clamp(0.0, 1.0),
          peekText: null,
          subtitle: habits.isEmpty ? widget.module.blurb : null,
          subtitleDanger: false,
        );
      case AppModule.expenses:
        final recent =
            ref.watch(recentExpensesProvider).valueOrNull ?? const [];
        final spentToday = recent
            .where((e) => e.kind == 0 && Fmt.isSameDay(e.date, DateTime.now()))
            .fold<double>(0, (a, e) => a + e.amount);
        return (
          figure: Fmt.compactMoney(spentToday, settings.currencySymbol),
          unit: null,
          progress: null,
          peekText: null,
          subtitle: spentToday == 0 ? 'Nothing spent today' : 'Spent today',
          subtitleDanger: false,
        );
      case AppModule.focus:
        final stats = ref.watch(focusStatsProvider).valueOrNull;
        final goal = ref.watch(focusGoalProvider);
        final mins = (stats?.today ?? Duration.zero).inMinutes;
        return (
          figure: '${mins}m',
          unit: goal > 0 ? 'of ${Fmt.durationFromMinutes(goal)}' : null,
          progress: goal > 0 ? (mins / goal).clamp(0.0, 1.0) : null,
          peekText: null,
          subtitle: null,
          subtitleDanger: false,
        );
      case AppModule.notes:
        final notes = ref.watch(recentNotesProvider).valueOrNull ?? const [];
        final peek = notes
            .where((n) => !n.isLocked && n.title.trim().isNotEmpty)
            .firstOrNull
            ?.title
            .trim();
        return (
          figure: '${notes.length}',
          unit: notes.length == 1 ? 'note' : 'notes',
          progress: null,
          peekText: peek,
          subtitle: notes.isEmpty
              ? widget.module.blurb
              : 'Edited ${Fmt.relativeDay(notes.first.updatedAt)}',
          subtitleDanger: false,
        );
      case AppModule.drop:
        final unread = ref.watch(unreadDropsCountProvider).valueOrNull ?? 0;
        return (
          figure: '$unread',
          unit: 'unread',
          progress: null,
          peekText: null,
          subtitle: 'Links and clips',
          subtitleDanger: false,
        );
      case AppModule.medicine:
        return (
          figure: '0',
          unit: null,
          progress: null,
          peekText: null,
          subtitle: widget.module.blurb,
          subtitleDanger: false,
        );
    }
  }
}

class _AnimatedTileBar extends StatefulWidget {
  final double value;
  final Color trackColor;
  final Color fillColor;
  final Duration delay;
  final bool reduceMotion;

  const _AnimatedTileBar({
    required this.value,
    required this.trackColor,
    required this.fillColor,
    required this.delay,
    required this.reduceMotion,
  });

  @override
  State<_AnimatedTileBar> createState() => _AnimatedTileBarState();
}

class _AnimatedTileBarState extends State<_AnimatedTileBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.reduceMotion) {
      _ctrl.value = 1.0;
    } else if (_ctrl.status == AnimationStatus.dismissed) {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _ctrl.forward();
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 6,
      decoration: BoxDecoration(
        color: widget.trackColor,
        borderRadius: BorderRadius.circular(3),
      ),
      alignment: Alignment.centerLeft,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final t = widget.reduceMotion
              ? 1.0
              : Curves.easeOutCubic.transform(_ctrl.value);
          return FractionallySizedBox(
            widthFactor: (widget.value * t).clamp(0.0, 1.0),
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                color: widget.fillColor,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          );
        },
      ),
    );
  }
}

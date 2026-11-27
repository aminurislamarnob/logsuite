import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/app_database.dart';
import '../../core/services/notification_service.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/common.dart';
import 'habits_screen.dart';
import 'providers/habits_provider.dart';
import 'repository/habit_repository.dart';
import 'utils/habit_detail_stats.dart';
import 'utils/habit_stats.dart';
import 'widgets/habit_analytics_cards.dart';
import 'widgets/habit_detail_motion.dart';
import 'widgets/habit_today_card.dart';

enum _HabitMenuAction { archive, delete }

class HabitDetailScreen extends ConsumerStatefulWidget {
  final int habitId;

  const HabitDetailScreen({super.key, required this.habitId});

  @override
  ConsumerState<HabitDetailScreen> createState() => _HabitDetailScreenState();
}

class _HabitDetailScreenState extends ConsumerState<HabitDetailScreen> {
  HabitRange _range = HabitRange.days30;
  DateTime _selectedDay = Fmt.dateOnly(DateTime.now());
  bool _editingToday = false;
  final Set<DateTime> _editedPastDays = {};
  DateTime? _lastPoppedDay;
  int _popTick = 0;
  bool _popScheduled = false;

  @override
  Widget build(BuildContext context) {
    final habitsAsync = ref.watch(habitsListProvider);
    final fallbackHabitAsync = ref.watch(habitProvider(widget.habitId));
    final logsAsync = ref.watch(habitLogsProvider(widget.habitId));

    Habit? habit = habitsAsync.valueOrNull
        ?.where((h) => h.id == widget.habitId)
        .firstOrNull;
    habit ??= fallbackHabitAsync.valueOrNull;

    if (habit == null) {
      final stillLoading =
          habitsAsync.isLoading || fallbackHabitAsync.isLoading;
      if (stillLoading) {
        return const BrandScaffold(child: Center(child: BrandSpinner()));
      }
      if (!_popScheduled) {
        _popScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && context.canPop()) context.pop();
        });
      }
      return const BrandScaffold(child: SizedBox.shrink());
    }

    final currentHabit = habit;
    final logs = logsAsync.valueOrNull ?? const <HabitLog>[];
    final stats = HabitStats.compute(currentHabit, logs);
    final today = Fmt.dateOnly(DateTime.now());
    final ageDays = today
        .difference(Fmt.dateOnly(currentHabit.createdAt))
        .inDays;
    final show90Days = ageDays >= 31;
    final activeRange = (!show90Days && _range == HabitRange.days90)
        ? HabitRange.days30
        : _range;

    final detail = HabitDetailStats.compute(
      habit: currentHabit,
      byDay: stats.byDay,
      today: today,
      range: activeRange,
      currentStreak: stats.currentStreak,
    );

    final theme = Theme.of(context);
    final brand = context.brand;
    final habitColor = Color(currentHabit.color);
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    final reminderLabel = currentHabit.reminderMinutes == null
        ? ''
        : ' · reminder ${Fmt.minutesOfDay(currentHabit.reminderMinutes!)}';
    final subtitle = '${habitFrequencyLabel(currentHabit)}$reminderLabel';

    var cardIndex = 0;

    return BrandScaffold(
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            12,
            AppSpacing.gutter,
            32 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            // 6.1 Header bar
            Row(
              children: [
                CircleIconButton(
                  icon: AppIcons.back,
                  tooltip: 'Back to habits',
                  onPressed: () {
                    if (context.canPop()) context.pop();
                  },
                ),
                const Spacer(),
                CircleIconButton(
                  icon: AppIcons.edit,
                  tooltip: 'Edit habit',
                  onPressed: () =>
                      HabitEditorSheet.show(context, habit: currentHabit),
                ),
                const SizedBox(width: 8),
                BrandMenuButton<_HabitMenuAction>(
                  icon: AppIcons.moreHorizontal,
                  tooltip: 'More: archive or delete',
                  items: const {
                    _HabitMenuAction.archive: 'Archive habit',
                    _HabitMenuAction.delete: 'Delete habit',
                  },
                  onSelected: (action) {
                    if (action == _HabitMenuAction.archive) {
                      _archiveHabit(currentHabit);
                    } else {
                      _deleteHabit(currentHabit);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Habit identity row
            StaggeredEntrance(
              index: cardIndex++,
              child: Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: habitColor,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: theme.brightness == Brightness.dark
                          ? null
                          : [
                              BoxShadow(
                                color: habitColor.withValues(alpha: 0.28),
                                offset: const Offset(0, 10),
                                blurRadius: 24,
                              ),
                            ],
                    ),
                    child: Center(
                      child: AppIcon(
                        AppIcons.habitIcons[currentHabit.icon] ??
                            AppIcons.habits,
                        size: 30,
                        color: brand.onAccent(habitColor),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          currentHabit.name,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.8,
                            height: 1.05,
                            color: brand.ink,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          style: TextStyle(fontSize: 14, color: context.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // 6.2 Today card (dark hero)
            StaggeredEntrance(
              index: cardIndex++,
              child: HabitTodayCard(
                habit: currentHabit,
                todayAmount: stats.todayAmount,
                currentStreak: stats.currentStreak,
                bestStreak: stats.bestStreak,
                milestone: detail.milestone,
                isEditing: _editingToday,
                onStartEdit: () => setState(() {
                  _editingToday = true;
                  _selectedDay = today;
                }),
                onCancelEdit: () => setState(() => _editingToday = false),
                onSaveAmount: (amount) async {
                  setState(() {
                    _editingToday = false;
                    _lastPoppedDay = today;
                    _popTick++;
                  });
                  await ref
                      .read(habitRepositoryProvider)
                      .setDayAmount(currentHabit.id, today, amount);
                },
                onAddDelta: (delta) async {
                  setState(() {
                    _lastPoppedDay = today;
                    _popTick++;
                  });
                  await ref
                      .read(habitRepositoryProvider)
                      .addToDay(currentHabit.id, delta, day: today);
                },
              ),
            ),
            const SizedBox(height: 18),

            // 6.3 Range tabs
            StaggeredEntrance(
              index: cardIndex++,
              child: HabitRangeTabs(
                selected: activeRange,
                show90Days: show90Days,
                onChanged: (next) => setState(() => _range = next),
              ),
            ),
            const SizedBox(height: 14),

            // 6.4 Three stat tiles
            StaggeredEntrance(
              index: cardIndex++,
              child: _RangeTransition(
                rangeKey: activeRange.name,
                reduceMotion: reduceMotion,
                child: HabitStatTiles(
                  habit: currentHabit,
                  detail: detail,
                  currentStreak: stats.currentStreak,
                  bestStreak: stats.bestStreak,
                  bestStreakEnd: stats.bestStreakEnd,
                ),
              ),
            ),
            const SizedBox(height: 14),

            // 6.5 Activity card
            StaggeredEntrance(
              index: cardIndex++,
              child: _RangeTransition(
                rangeKey: activeRange.name,
                reduceMotion: reduceMotion,
                child: HabitActivityCard(
                  habit: currentHabit,
                  detail: detail,
                  selectedDay: _selectedDay,
                  editedPastDays: _editedPastDays,
                  lastPoppedDay: _lastPoppedDay,
                  popTick: _popTick,
                  onSelectDay: (d) => setState(() => _selectedDay = d),
                  onEditToday: () => setState(() {
                    _editingToday = true;
                    _selectedDay = today;
                  }),
                  onSavePastDay: (day, amount) async {
                    final date = Fmt.dateOnly(day);
                    setState(() {
                      if (!Fmt.isSameDay(date, today)) {
                        _editedPastDays.add(date);
                      }
                      _lastPoppedDay = date;
                      _popTick++;
                    });
                    final repo = ref.read(habitRepositoryProvider);
                    if (amount > 0 &&
                        date.isBefore(Fmt.dateOnly(currentHabit.createdAt))) {
                      await repo.updateHabit(
                        currentHabit.id,
                        HabitsCompanion(createdAt: drift.Value(date)),
                      );
                    }
                    await repo.setDayAmount(currentHabit.id, date, amount);
                  },
                ),
              ),
            ),

            // 6.6 Insight card
            if (detail.showInsight) ...[
              const SizedBox(height: 14),
              StaggeredEntrance(
                index: cardIndex++,
                child: _RangeTransition(
                  rangeKey: activeRange.name,
                  reduceMotion: reduceMotion,
                  child: HabitInsightCard(
                    habit: currentHabit,
                    detail: detail,
                    onChangeReminder: () =>
                        HabitEditorSheet.show(context, habit: currentHabit),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 14),

            // 6.7 Getting steadier? (trend)
            StaggeredEntrance(
              index: cardIndex++,
              child: _RangeTransition(
                rangeKey: activeRange.name,
                reduceMotion: reduceMotion,
                child: HabitTrendCard(habit: currentHabit, detail: detail),
              ),
            ),

            const SizedBox(height: 18),

            // 6.8 Footer
            StaggeredEntrance(
              index: cardIndex++,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  BrandButton(
                    label: 'Archive habit',
                    icon: AppIcons.archive,
                    kind: BrandButtonKind.outline,
                    onPressed: () => _archiveHabit(currentHabit),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Started ${Fmt.dayMonth(currentHabit.createdAt)} · '
                    'Archived habits keep their history.\n'
                    'Delete is in the ⋯ menu.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: context.muted,
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

  Future<void> _archiveHabit(Habit habit) async {
    final repo = ref.read(habitRepositoryProvider);
    final notifier = ref.read(notificationServiceProvider);
    await repo.updateHabit(
      habit.id,
      const HabitsCompanion(isArchived: drift.Value(true)),
    );
    await notifier.cancelHabitNudge(habit.id);
    if (!mounted) return;
    brandToast(
      context,
      'Archived',
      actionLabel: 'Undo',
      onAction: () async {
        await repo.updateHabit(
          habit.id,
          const HabitsCompanion(isArchived: drift.Value(false)),
        );
        if (habit.reminderMinutes != null) {
          await notifier.scheduleHabitNudge(
            habitId: habit.id,
            habitName: habit.name,
            minutesFromMidnight: habit.reminderMinutes!,
          );
        }
      },
    );
    if (context.canPop()) context.pop();
  }

  Future<void> _deleteHabit(Habit habit) async {
    final confirmed = await brandConfirm(
      context,
      destructive: true,
      title: 'Delete this habit?',
      message: "Its history is deleted too. This can't be undone.",
      confirmLabel: 'Delete',
    );
    if (!confirmed || !mounted) return;
    final repo = ref.read(habitRepositoryProvider);
    final notifier = ref.read(notificationServiceProvider);
    await repo.deleteHabit(habit.id);
    await notifier.cancelHabitNudge(habit.id);
    if (mounted && context.canPop()) context.pop();
  }
}

class _RangeTransition extends StatelessWidget {
  final String rangeKey;
  final bool reduceMotion;
  final Widget child;

  const _RangeTransition({
    required this.rangeKey,
    required this.reduceMotion,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (reduceMotion) return child;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.03),
            end: Offset.zero,
          ).animate(anim),
          child: child,
        ),
      ),
      child: KeyedSubtree(key: ValueKey(rangeKey), child: child),
    );
  }
}

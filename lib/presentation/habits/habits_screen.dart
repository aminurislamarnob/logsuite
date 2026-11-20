import 'dart:math' as math;

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/app_database.dart';
import '../../core/services/notification_service.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/common.dart';
import 'providers/habits_provider.dart';
import 'repository/habit_repository.dart';
import 'utils/habit_stats.dart';

bool _isHabitScheduledOn(Habit habit, DateTime day) {
  if (habit.frequencyType == 1) {
    return (habit.weekdayMask & (1 << (day.weekday - 1))) != 0;
  }
  return true;
}

bool _isHabitDoneOn(Habit habit, HabitStats stats, DateTime day) {
  final date = Fmt.dateOnly(day);
  final amount = stats.byDay[date] ?? 0;
  if (habit.goalType == 1) {
    // For a reduce habit, staying at or under the limit on a day at/after creation counts.
    if (date.isBefore(Fmt.dateOnly(habit.createdAt))) return false;
    return amount <= habit.targetAmount;
  }
  final target = habit.targetAmount <= 0 ? 1.0 : habit.targetAmount;
  return amount >= target;
}

String _weekdayMaskLabel(int mask) {
  const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  if (mask == 127) return 'Daily';
  if (mask == 31) return 'Weekdays';
  final active = <String>[];
  for (var i = 0; i < 7; i++) {
    if ((mask & (1 << i)) != 0) active.add(names[i]);
  }
  return active.isEmpty ? 'Custom' : active.join(' · ');
}

String _habitFrequencyLabel(Habit habit) => switch (habit.frequencyType) {
  1 => _weekdayMaskLabel(habit.weekdayMask),
  2 => '${habit.timesPerWeek}x / week',
  _ => 'Daily',
};

class HabitsScreen extends ConsumerWidget {
  const HabitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habitsAsync = ref.watch(habitsListProvider);
    final caffeine = ref.watch(caffeineTodayProvider).valueOrNull ?? 0;
    final cost = ref.watch(habitCostTodayProvider).valueOrNull ?? 0;
    final currency = ref.watch(settingsProvider).currencySymbol;
    final brand = context.brand;

    return BrandScaffold(
      header: BrandTopBar(
        title: 'Habits',
        leadingIcon: AppIcons.back,
        actions: [
          CircleIconButton(
            icon: AppIcons.barChart,
            tooltip: 'Stats',
            size: 44,
            onPressed: () => context.go('/insights'),
          ),
          CircleIconButton(
            icon: AppIcons.add,
            tooltip: 'Add habit',
            size: 44,
            filled: true,
            color: brand.ink,
            onPressed: () => HabitEditorSheet.show(context),
          ),
        ],
      ),
      child: habitsAsync.when(
        data: (habits) {
          if (habits.isEmpty) {
            return EmptyState(
              icon: AppIcons.habits,
              title: 'No habits yet',
              message: 'Track water, coffee, exercise — anything you repeat.',
              actionLabel: 'Add a habit',
              onAction: () => HabitEditorSheet.show(context),
            );
          }
          return ListView(
            padding: pageInsets(context, top: 12),
            children: [
              _HabitsHeroCard(habits: habits),
              const SizedBox(height: 16),
              if (caffeine > 0 || cost > 0) ...[
                Row(
                  children: [
                    if (caffeine > 0)
                      Expanded(
                        child: StatTile(
                          icon: AppIcons.quick,
                          color: brand.warning,
                          label: 'Caffeine today',
                          value: '${caffeine.toStringAsFixed(0)} mg',
                          sublabel: caffeine > 400 ? 'Above 400mg guide' : null,
                        ),
                      ),
                    if (caffeine > 0 && cost > 0)
                      const SizedBox(width: AppSpacing.grid),
                    if (cost > 0)
                      Expanded(
                        child: StatTile(
                          icon: AppIcons.savings,
                          color: brand.expense,
                          label: 'Habit spend today',
                          value: Fmt.money(cost, currency),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              for (final h in habits) ...[
                _HabitCard(habit: h),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 6),
              _FourWeeksSummaryCard(habits: habits),
            ],
          );
        },
        loading: () => const Center(child: BrandSpinner()),
        error: (e, _) =>
            EmptyState(icon: AppIcons.error, title: 'Error', message: '$e'),
      ),
    );
  }
}

/// Ink hero card (`05-habits.html` lines 28-48): TODAY `X of Y`, best streak
/// badge on right, and 7-day mini rings row at the bottom.
class _HabitsHeroCard extends ConsumerWidget {
  final List<Habit> habits;

  const _HabitsHeroCard({required this.habits});

  static const _dayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final isDark = theme.brightness == Brightness.dark;
    final primaryText = isDark ? brand.ink : brand.onInk;
    final today = Fmt.dateOnly(DateTime.now());

    final statsByHabit = <int, HabitStats>{
      for (final h in habits)
        h.id:
            ref.watch(habitStatsProvider(h.id)).valueOrNull ?? HabitStats.empty,
    };

    var doneToday = 0;
    var bestStreak = 0;
    for (final h in habits) {
      final s = statsByHabit[h.id]!;
      if (_isHabitDoneOn(h, s, today)) doneToday++;
      if (s.bestStreak > bestStreak) bestStreak = s.bestStreak;
      if (s.currentStreak > bestStreak) bestStreak = s.currentStreak;
    }

    final last7Days = [
      for (var i = 6; i >= 0; i--) today.subtract(Duration(days: i)),
    ];

    double fractionForDay(DateTime day) {
      var scheduled = 0;
      var completed = 0;
      for (final h in habits) {
        if (!_isHabitScheduledOn(h, day)) continue;
        scheduled++;
        final s = statsByHabit[h.id]!;
        if (_isHabitDoneOn(h, s, day)) completed++;
      }
      return scheduled == 0 ? 0.0 : (completed / scheduled).clamp(0.0, 1.0);
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      decoration: BoxDecoration(
        color: brand.heroSurface,
        borderRadius: BorderRadius.circular(AppRadii.hero),
        boxShadow: AppShadows.hero(theme.brightness),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TODAY',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: brand.habitRoles.onInk,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '$doneToday',
                        style: TextStyle(
                          fontSize: 44,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -2,
                          height: 1.0,
                          color: primaryText,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'of ${habits.length}',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: brand.onInkMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppIcon(
                        AppIcons.streak,
                        size: 18,
                        color: brand.noteRoles.onInk,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$bestStreak',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                          color: primaryText,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'best streak',
                    style: TextStyle(fontSize: 12, color: brand.onInkMuted),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              for (final day in last7Days)
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final isToday = Fmt.isSameDay(day, today);
                      final letter = _dayLetters[day.weekday - 1];
                      final ratio = fractionForDay(day);
                      return Column(
                        children: [
                          Text(
                            letter,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isToday
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                              color: isToday ? primaryText : brand.onInkMuted,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              if (isToday)
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.08),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ProgressRing(
                                value: ratio,
                                size: 36,
                                thickness: 5,
                                color: brand.habit,
                                onInk: true,
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HabitCard extends ConsumerWidget {
  final Habit habit;
  const _HabitCard({required this.habit});

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(habitStatsProvider(habit.id));
    final stats = statsAsync.valueOrNull ?? HabitStats.empty;
    final theme = Theme.of(context);
    final brand = context.brand;
    final color = Color(habit.color);
    final roles = brand.roleFor(color);
    final repo = ref.read(habitRepositoryProvider);
    final isReduce = habit.goalType == 1;
    final over = stats.overLimit(habit);
    final today = Fmt.dateOnly(DateTime.now());
    final isMultiUnit = habit.targetAmount > 1 && !isReduce;
    final doneToday = isReduce
        ? (stats.todayAmount > 0 && !over)
        : (stats.todayAmount >=
              (habit.targetAmount <= 0 ? 1.0 : habit.targetAmount));

    final progress = habit.targetAmount <= 0
        ? (stats.todayAmount > 0 ? 1.0 : 0.0)
        : (stats.todayAmount / habit.targetAmount).clamp(0.0, 1.0);

    // Recent scheduled days for the segmented mini bar (`05-habits.html`).
    final recentScheduledDays = <DateTime>[];
    for (var i = 6; i >= 0; i--) {
      final d = today.subtract(Duration(days: i));
      if (_isHabitScheduledOn(habit, d)) {
        recentScheduledDays.add(d);
      }
    }

    Future<void> onActionTap() async {
      if (doneToday && !isMultiUnit && !isReduce) {
        AppHaptics.selection();
        await repo.setDayAmount(habit.id, today, 0);
        return;
      }
      await repo.addToDay(habit.id, 1);
      if (!context.mounted) return;
      final next = stats.todayAmount + 1;
      if (isReduce && next > habit.targetAmount) {
        AppHaptics.warning();
        brandToast(
          context,
          'That is ${next.toStringAsFixed(0)} today — '
          'your limit is ${habit.targetAmount.toStringAsFixed(0)}.',
        );
      } else if (!isReduce &&
          habit.targetAmount > 0 &&
          stats.todayAmount < habit.targetAmount &&
          next >= habit.targetAmount) {
        AppHaptics.success();
      } else {
        AppHaptics.tap();
      }
    }

    return TintCard(
      fill: brand.surface,
      radius: 22,
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      onTap: () => _openDetail(context),
      onLongPress: () => HabitEditorSheet.show(context, habit: habit),
      child: Row(
        children: [
          // 46x46 radius 16 tinted icon chip (`05-habits.html`)
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: roles.tintFill,
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: AppIcon(
              AppIcons.habit(habit.icon),
              color: roles.graphicOnTint,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        habit.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: brand.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (isMultiUnit && !doneToday)
                      Text(
                        '${_trim(stats.todayAmount)} / ${_trim(habit.targetAmount)}'
                        '${habit.unit == null ? '' : ' ${habit.unit}'}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.outline,
                        ),
                      )
                    else if (habit.frequencyType == 1 &&
                        habit.weekdayMask != 127)
                      Text(
                        _weekdayMaskLabel(habit.weekdayMask),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.outline,
                        ),
                      )
                    else if (stats.currentStreak > 0)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppIcon(
                            AppIcons.streak,
                            size: 12,
                            color: brand.warningRoles.graphicOnTint,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '${stats.currentStreak}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: brand.warningRoles.textOnTint,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 7),
                if (isMultiUnit && !doneToday)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 150),
                    child: Container(
                      height: 5,
                      decoration: BoxDecoration(
                        color: brand.track,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: progress,
                        child: Container(
                          height: 5,
                          decoration: BoxDecoration(
                            color: over ? brand.danger : roles.graphicOnTint,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final d in recentScheduledDays)
                        Container(
                          width: 16,
                          height: 5,
                          decoration: BoxDecoration(
                            color: _isHabitDoneOn(habit, stats, d)
                                ? brand.habit
                                : brand.track,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // 48x48 right action circle (`05-habits.html` lines 57, 66, 75)
          BrandTappable(
            onPressed: onActionTap,
            semanticsLabel: doneToday
                ? '${habit.name} done, tap to undo'
                : isMultiUnit
                ? 'Add ${habit.unit ?? 'one'}'
                : 'Mark ${habit.name} done',
            child: doneToday
                ? Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: brand.habit,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const AppIcon(
                      AppIcons.check,
                      size: 22,
                      color: Colors.white,
                    ),
                  )
                : (isMultiUnit || isReduce)
                ? Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: over ? brand.dangerRoles.tintFill : roles.tintFill,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: AppIcon(
                      AppIcons.add,
                      size: 22,
                      color: over
                          ? brand.dangerRoles.textOnTint
                          : roles.textOnTint,
                    ),
                  )
                : Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: brand.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: brand.outlineIdle, width: 2.5),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _openDetail(BuildContext context) {
    brandSheet(
      context: context,
      builder: (_) => _HabitDetailSheet(habit: habit),
    );
  }

  /// Bulk back-fill: tapping a heatmap cell edits that day's amount.
  static Future<void> editDay(
    BuildContext context,
    WidgetRef ref,
    Habit habit,
    DateTime day,
    HabitStats stats,
  ) async {
    final controller = TextEditingController(
      text: _trim(stats.byDay[Fmt.dateOnly(day)] ?? 0),
    );
    final result = await brandDialog<String>(
      context,
      title: Fmt.dayMonthYear(day),
      builder: (dialogContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BrandField(
            controller: controller,
            label: 'Amount',
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            suffix: habit.unit == null ? null : Text(habit.unit!),
          ),
          const SizedBox(height: 20),
          BrandButton(
            label: 'Save',
            onPressed: () => Navigator.pop(dialogContext, controller.text),
          ),
          const SizedBox(height: 8),
          BrandButton(
            label: 'Cancel',
            kind: BrandButtonKind.ghost,
            onPressed: () => Navigator.pop(dialogContext),
          ),
        ],
      ),
    );
    if (result == null) return;
    final amount = double.tryParse(result.trim());
    if (amount == null) return;
    await ref.read(habitRepositoryProvider).setDayAmount(habit.id, day, amount);
  }
}

/// Bottom `4 WEEKS` summary card (`05-habits.html` lines 96-102).
class _FourWeeksSummaryCard extends ConsumerWidget {
  final List<Habit> habits;

  const _FourWeeksSummaryCard({required this.habits});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final today = Fmt.dateOnly(DateTime.now());

    final statsByHabit = <int, HabitStats>{
      for (final h in habits)
        h.id:
            ref.watch(habitStatsProvider(h.id)).valueOrNull ?? HabitStats.empty,
    };

    final days28 = [
      for (var i = 27; i >= 0; i--) today.subtract(Duration(days: i)),
    ];

    var totalScheduled = 0;
    var totalDone = 0;
    final daySucceeded = <bool>[];

    for (final d in days28) {
      var schedOnDay = 0;
      var doneOnDay = 0;
      for (final h in habits) {
        if (!_isHabitScheduledOn(h, d)) continue;
        schedOnDay++;
        if (_isHabitDoneOn(h, statsByHabit[h.id]!, d)) {
          doneOnDay++;
        }
      }
      totalScheduled += schedOnDay;
      totalDone += doneOnDay;
      daySucceeded.add(schedOnDay > 0 && doneOnDay >= (schedOnDay / 2).ceil());
    }

    final pct = totalScheduled == 0
        ? 0
        : ((totalDone / totalScheduled) * 100).round();

    Widget buildRow(int startIdx) {
      return Row(
        children: [
          for (var i = 0; i < 14; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: Builder(
                builder: (context) {
                  final idx = startIdx + i;
                  final isToday = idx == 27;
                  final done = daySucceeded[idx];
                  if (isToday && !done) {
                    return Container(
                      height: 14,
                      decoration: BoxDecoration(
                        color: brand.surface,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: brand.habit, width: 2),
                      ),
                    );
                  }
                  return Container(
                    height: 14,
                    decoration: BoxDecoration(
                      color: done ? brand.habit : brand.track,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: AppShadows.card(theme.brightness),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '4 WEEKS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: brand.subtle,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$pct%',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                  color: brand.ink,
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              children: [buildRow(0), const SizedBox(height: 4), buildRow(14)],
            ),
          ),
        ],
      ),
    );
  }
}

/// Habit detail bottom sheet (`23-habit-detail.html`).
class _HabitDetailSheet extends ConsumerWidget {
  final Habit habit;
  const _HabitDetailSheet({required this.habit});

  static const _monthShort = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats =
        ref.watch(habitStatsProvider(habit.id)).valueOrNull ?? HabitStats.empty;
    final currency = ref.watch(settingsProvider).currencySymbol;
    final theme = Theme.of(context);
    final brand = context.brand;
    final muted = theme.colorScheme.outline;
    final isDark = theme.brightness == Brightness.dark;
    final primaryOnHero = isDark ? brand.ink : brand.onInk;
    final color = Color(habit.color);
    final roles = brand.roleFor(color);
    final today = Fmt.dateOnly(DateTime.now());
    final doneToday = _isHabitDoneOn(habit, stats, today);

    // Compute week, month, and all-time scheduled/completed day counts.
    final weekStart = Fmt.startOfWeek(today);
    var weekDone = 0;
    var weekSched = 0;
    for (
      var d = weekStart;
      !d.isAfter(today);
      d = d.add(const Duration(days: 1))
    ) {
      if (_isHabitScheduledOn(habit, d)) {
        weekSched++;
        if (_isHabitDoneOn(habit, stats, d)) weekDone++;
      }
    }

    final monthStart = Fmt.startOfMonth(today);
    var monthDone = 0;
    var monthSched = 0;
    for (
      var d = monthStart;
      !d.isAfter(today);
      d = d.add(const Duration(days: 1))
    ) {
      if (_isHabitScheduledOn(habit, d)) {
        monthSched++;
        if (_isHabitDoneOn(habit, stats, d)) monthDone++;
      }
    }

    var allTimeDone = 0;
    final createdDate = Fmt.dateOnly(habit.createdAt);
    for (
      var d = createdDate;
      !d.isAfter(today);
      d = d.add(const Duration(days: 1))
    ) {
      if (_isHabitScheduledOn(habit, d) && _isHabitDoneOn(habit, stats, d)) {
        allTimeDone++;
      }
    }

    // 5 month labels spanning the last 17 weeks.
    final monthLabels = <String>[];
    for (var i = 4; i >= 0; i--) {
      final m = DateTime(today.year, today.month - i, 1);
      monthLabels.add(_monthShort[(m.month - 1) % 12]);
    }

    final subtitleParts = <String>[
      _habitFrequencyLabel(habit),
      if (habit.reminderMinutes != null)
        'reminder ${Fmt.minutesOfDay(habit.reminderMinutes!)}',
    ];

    final todayStatus = doneToday
        ? 'done today'
        : stats.todayAmount > 0
        ? '${_HabitCard._trim(stats.todayAmount)} / ${_HabitCard._trim(habit.targetAmount)}'
              '${habit.unit == null ? '' : ' ${habit.unit}'} today'
        : 'not logged today';

    final streakNote = [
      if (stats.currentStreak >= stats.bestStreak && stats.currentStreak > 0)
        'Your best yet'
      else
        'Best ${stats.bestStreak} days',
      todayStatus,
    ].join(' · ');

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
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              10,
              AppSpacing.gutter,
              24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: brand.outlineIdle,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Header row (`23-habit-detail.html` lines 27-34)
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: roles.tintFill,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      alignment: Alignment.center,
                      child: AppIcon(
                        AppIcons.habit(habit.icon),
                        size: 26,
                        color: roles.graphicOnTint,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            habit.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.6,
                              height: 1.1,
                              color: brand.ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitleParts.join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, color: muted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    CircleIconButton(
                      icon: AppIcons.close,
                      tooltip: 'Close',
                      size: 44,
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Ink streak hero card (`23-habit-detail.html` lines 36-46)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: brand.heroSurface,
                    borderRadius: BorderRadius.circular(AppRadii.hero),
                    boxShadow: AppShadows.hero(theme.brightness),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'CURRENT STREAK',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: brand.habitRoles.onInk,
                                letterSpacing: 1.0,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                AppIcon(
                                  AppIcons.streak,
                                  size: 26,
                                  color: brand.noteRoles.onInk,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '${stats.currentStreak}',
                                  style: TextStyle(
                                    fontSize: 48,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -2,
                                    height: 1.0,
                                    color: primaryOnHero,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'days',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: brand.onInkMuted,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              streakNote,
                              style: TextStyle(
                                fontSize: 13,
                                color: brand.onInkMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 88,
                        height: 88,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            ProgressRing(
                              value: stats.completionRate,
                              size: 88,
                              thickness: 10,
                              color: brand.habitRoles.onInk,
                              onInk: true,
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  Fmt.percent(stats.completionRate),
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.5,
                                    height: 1.1,
                                    color: primaryOnHero,
                                  ),
                                ),
                                Text(
                                  'KEPT',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    color: brand.onInkMuted,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Three stat cards row (`This week`, `This month`, `All time`)
                Row(
                  children: [
                    Expanded(
                      child: _detailStatCard(
                        context: context,
                        label: 'This week',
                        value: '$weekDone',
                        suffix: ' of $weekSched',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _detailStatCard(
                        context: context,
                        label: 'This month',
                        value: '$monthDone',
                        suffix: ' of $monthSched',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _detailStatCard(
                        context: context,
                        label: 'All time',
                        value: '$allTimeDone',
                        suffix: ' days',
                      ),
                    ),
                  ],
                ),

                if (habit.costPerUnit != null) ...[
                  const SizedBox(height: 12),
                  StatTile(
                    icon: AppIcons.savings,
                    color: brand.expense,
                    label: 'Cost this month',
                    value: Fmt.money(stats.costThisMonth(habit), currency),
                    sublabel:
                        '${Fmt.money(habit.costPerUnit!, currency)} per ${habit.unit ?? 'unit'}',
                  ),
                ],
                const SizedBox(height: 14),

                // Last 17 weeks heatmap card (`23-habit-detail.html` lines 54-76)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: brand.surface,
                    borderRadius: BorderRadius.circular(AppRadii.card),
                    boxShadow: AppShadows.card(theme.brightness),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'LAST 17 WEEKS',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: muted,
                              letterSpacing: 0.8,
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Missed',
                                style: TextStyle(fontSize: 11, color: muted),
                              ),
                              const SizedBox(width: 4),
                              _legendCell(brand.track),
                              const SizedBox(width: 4),
                              _legendCell(color.withValues(alpha: 0.28)),
                              const SizedBox(width: 4),
                              _legendCell(color.withValues(alpha: 0.62)),
                              const SizedBox(width: 4),
                              _legendCell(color),
                              const SizedBox(width: 4),
                              Text(
                                'Full',
                                style: TextStyle(fontSize: 11, color: muted),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 7 * 17.0,
                        child: ContributionHeatmap(
                          color: color,
                          intensityFor: (day) => stats.intensityOn(day, habit),
                          onTapDay: (day) => _HabitCard.editDay(
                            context,
                            ref,
                            habit,
                            day,
                            stats,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          for (final m in monthLabels)
                            Text(
                              m,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: muted,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // Bottom action row (`Delete habit` circle + `Edit habit` pill)
                Row(
                  children: [
                    CircleIconButton(
                      icon: AppIcons.delete,
                      tooltip: 'Delete habit',
                      size: 54,
                      color: brand.danger,
                      onPressed: () async {
                        await ref
                            .read(habitRepositoryProvider)
                            .deleteHabit(habit.id);
                        await ref
                            .read(notificationServiceProvider)
                            .cancelHabitNudge(habit.id);
                        if (context.mounted) Navigator.pop(context);
                      },
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: BrandButton(
                        label: 'Edit habit',
                        icon: AppIcons.edit,
                        onPressed: () {
                          Navigator.pop(context);
                          HabitEditorSheet.show(context, habit: habit);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailStatCard({
    required BuildContext context,
    required String label,
    required String value,
    required String suffix,
  }) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final muted = theme.colorScheme.outline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppShadows.card(theme.brightness),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: muted,
            ),
          ),
          const SizedBox(height: 2),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: brand.ink,
                  ),
                ),
                TextSpan(
                  text: suffix,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: muted,
                  ),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _legendCell(Color color) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

/// Create/edit form covering goal type, frequency, unit, cost and reminders
/// (`22-habit-editor.html`).
class HabitEditorSheet extends ConsumerStatefulWidget {
  final Habit? habit;
  const HabitEditorSheet({super.key, this.habit});

  static Future<void> show(BuildContext context, {Habit? habit}) {
    return brandSheet(
      context: context,
      builder: (_) => HabitEditorSheet(habit: habit),
    );
  }

  @override
  ConsumerState<HabitEditorSheet> createState() => _HabitEditorSheetState();
}

class _HabitEditorSheetState extends ConsumerState<HabitEditorSheet> {
  late final TextEditingController _name;
  late final TextEditingController _unit;
  late final TextEditingController _target;
  late final TextEditingController _cost;
  late final TextEditingController _caffeine;

  String _icon = 'water';
  int? _color;
  int _goalType = 0;
  int _frequencyType = 0;
  int _weekdayMask = 127;
  int _timesPerWeek = 7;
  int? _reminderMinutes;
  bool _showIconPicker = false;

  bool get _isEditing => widget.habit != null;

  @override
  void initState() {
    super.initState();
    final h = widget.habit;
    _name = TextEditingController(text: h?.name ?? '');
    _unit = TextEditingController(text: h?.unit ?? '');
    _target = TextEditingController(
      text: h == null ? '1' : _HabitCard._trim(h.targetAmount),
    );
    _cost = TextEditingController(
      text: h?.costPerUnit == null ? '' : '${h!.costPerUnit}',
    );
    _caffeine = TextEditingController(
      text: h?.caffeineMgPerUnit == null ? '' : '${h!.caffeineMgPerUnit}',
    );
    if (h != null) {
      _icon = h.icon;
      _color = h.color;
      _goalType = h.goalType;
      _frequencyType = h.frequencyType;
      _weekdayMask = h.weekdayMask;
      _timesPerWeek = h.timesPerWeek;
      _reminderMinutes = h.reminderMinutes;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _unit.dispose();
    _target.dispose();
    _cost.dispose();
    _caffeine.dispose();
    super.dispose();
  }

  int _resolvedColor(BrandColors brand) => _color ?? brand.habit.toARGB32();

  void _applyPreset(
    ({
      String name,
      String icon,
      int color,
      String unit,
      int goalType,
      double target,
      double? caffeine,
    })
    p,
  ) {
    setState(() {
      _name.text = p.name;
      _icon = p.icon;
      _color = p.color;
      _unit.text = p.unit;
      _goalType = p.goalType;
      _target.text = _HabitCard._trim(p.target);
      _caffeine.text = p.caffeine == null ? '' : '${p.caffeine}';
    });
  }

  void _stepTarget(int delta) {
    final current = double.tryParse(_target.text.trim()) ?? 1;
    final minVal = _goalType == 1 ? 0.0 : 1.0;
    final next = math.max(minVal, current + delta);
    AppHaptics.selection();
    setState(() {
      _target.text = _HabitCard._trim(next);
    });
  }

  Future<void> _editUnitAndGoalDialog() async {
    final targetCtrl = TextEditingController(text: _target.text);
    final unitCtrl = TextEditingController(text: _unit.text);
    final saved = await brandDialog<bool>(
      context,
      title: _goalType == 0 ? 'Daily goal & unit' : 'Daily limit & unit',
      builder: (dialogContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BrandField(
            controller: targetCtrl,
            label: _goalType == 0 ? 'Daily goal' : 'Daily limit',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 12),
          BrandField(
            controller: unitCtrl,
            label: 'Unit',
            hint: 'glasses, pages, cups…',
          ),
          const SizedBox(height: 20),
          BrandButton(
            label: 'Done',
            onPressed: () => Navigator.pop(dialogContext, true),
          ),
        ],
      ),
    );
    if (saved == true && mounted) {
      setState(() {
        _target.text = targetCtrl.text.trim().isEmpty
            ? '1'
            : targetCtrl.text.trim();
        _unit.text = unitCtrl.text.trim();
      });
    }
  }

  Future<void> _editOptionalTrackingDialog(String currency) async {
    final costCtrl = TextEditingController(text: _cost.text);
    final cafCtrl = TextEditingController(text: _caffeine.text);
    final saved = await brandDialog<bool>(
      context,
      title: 'Optional tracking',
      builder: (dialogContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BrandField(
            controller: costCtrl,
            label: 'Cost per unit',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            prefix: Text(currency),
          ),
          const SizedBox(height: 12),
          BrandField(
            controller: cafCtrl,
            label: 'Caffeine per unit',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            suffix: const Text('mg'),
          ),
          const SizedBox(height: 20),
          BrandButton(
            label: 'Done',
            onPressed: () => Navigator.pop(dialogContext, true),
          ),
        ],
      ),
    );
    if (saved == true && mounted) {
      setState(() {
        _cost.text = costCtrl.text.trim();
        _caffeine.text = cafCtrl.text.trim();
      });
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;

    final brand = context.brand;
    final companion = HabitsCompanion(
      name: drift.Value(name),
      icon: drift.Value(_icon),
      color: drift.Value(_resolvedColor(brand)),
      unit: drift.Value(_unit.text.trim().isEmpty ? null : _unit.text.trim()),
      goalType: drift.Value(_goalType),
      targetAmount: drift.Value(double.tryParse(_target.text.trim()) ?? 1.0),
      frequencyType: drift.Value(_frequencyType),
      weekdayMask: drift.Value(_weekdayMask),
      timesPerWeek: drift.Value(_timesPerWeek),
      costPerUnit: drift.Value(double.tryParse(_cost.text.trim())),
      caffeineMgPerUnit: drift.Value(double.tryParse(_caffeine.text.trim())),
      reminderMinutes: drift.Value(_reminderMinutes),
    );

    final repo = ref.read(habitRepositoryProvider);
    final notifier = ref.read(notificationServiceProvider);

    final id = _isEditing
        ? widget.habit!.id
        : await repo.createHabit(companion);
    if (_isEditing) await repo.updateHabit(id, companion);

    if (_reminderMinutes != null) {
      await notifier.scheduleHabitNudge(
        habitId: id,
        habitName: name,
        minutesFromMidnight: _reminderMinutes!,
      );
    } else {
      await notifier.cancelHabitNudge(id);
    }

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final muted = theme.colorScheme.outline;
    final currency = ref.watch(settingsProvider).currencySymbol;
    final activeColorInt = _resolvedColor(brand);
    final activeColor = Color(activeColorInt);
    final activeRoles = brand.roleFor(activeColor);

    final swatches = <Color>[
      brand.habit,
      brand.focus,
      brand.task,
      brand.expense,
      brand.medicine,
      brand.note,
    ];

    final costSummary = [
      if (_cost.text.trim().isNotEmpty) '$currency${_cost.text.trim()}',
      if (_caffeine.text.trim().isNotEmpty) '${_caffeine.text.trim()} mg',
    ].join(' · ');

    return SheetScaffold(
      title: _isEditing ? 'Edit habit' : 'New habit',
      bottomAction: BrandButton(label: 'Save habit', onPressed: _save),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Presets strip (`22-habit-editor.html` lines 29-38)
          if (!_isEditing) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'START FROM A PRESET',
                style: TextStyle(
                  color: muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: HabitRepository.presets
                    .map(
                      (p) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Pill(
                          label: p.name,
                          selected: _name.text.trim() == p.name,
                          color: theme.colorScheme.primary,
                          onTap: () => _applyPreset(p),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Icon + Habit name card (`22-habit-editor.html` lines 40-44)
          Container(
            padding: const EdgeInsets.fromLTRB(10, 10, 16, 10),
            decoration: BoxDecoration(
              color: brand.surface,
              borderRadius: BorderRadius.circular(22),
              boxShadow: AppShadows.card(theme.brightness),
            ),
            child: Row(
              children: [
                BrandTappable(
                  onPressed: () =>
                      setState(() => _showIconPicker = !_showIconPicker),
                  semanticsLabel: 'Change icon',
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: activeRoles.tintFill,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.center,
                    child: AppIcon(
                      AppIcons.habit(_icon),
                      size: 24,
                      color: activeRoles.graphicOnTint,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _name,
                    autofocus: !_isEditing,
                    textCapitalization: TextCapitalization.sentences,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                      color: brand.ink,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Habit name',
                      hintStyle: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                        color: muted,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Build / Reduce segmented control (`22-habit-editor.html` lines 46-49)
          Container(
            height: 48,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: brand.well,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                Expanded(
                  child: BrandTappable(
                    onPressed: () {
                      AppHaptics.selection();
                      setState(() => _goalType = 0);
                    },
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _goalType == 0 ? brand.ink : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Build · do more',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: _goalType == 0
                              ? FontWeight.w700
                              : FontWeight.w600,
                          color: _goalType == 0 ? brand.onInk : muted,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: BrandTappable(
                    onPressed: () {
                      AppHaptics.selection();
                      setState(() => _goalType = 1);
                    },
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _goalType == 1 ? brand.ink : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Reduce · do less',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: _goalType == 1
                              ? FontWeight.w700
                              : FontWeight.w600,
                          color: _goalType == 1 ? brand.onInk : muted,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Frequency & Daily goal card (`22-habit-editor.html` lines 51-63)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: brand.surface,
              borderRadius: BorderRadius.circular(22),
              boxShadow: AppShadows.card(theme.brightness),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    for (final (freq, label) in const [
                      (0, 'Daily'),
                      (1, 'Weekdays'),
                      (2, 'X / week'),
                    ]) ...[
                      if (freq > 0) const SizedBox(width: 8),
                      Expanded(
                        child: Builder(
                          builder: (context) {
                            final isSel = _frequencyType == freq;
                            return BrandTappable(
                              onPressed: () {
                                AppHaptics.selection();
                                setState(() => _frequencyType = freq);
                              },
                              child: Container(
                                height: 44,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: isSel
                                      ? brand.habitRoles.tintFill
                                      : brand.canvas,
                                  borderRadius: BorderRadius.circular(22),
                                  border: isSel
                                      ? Border.all(color: brand.habit, width: 2)
                                      : null,
                                ),
                                child: Text(
                                  label,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: isSel
                                        ? FontWeight.w700
                                        : FontWeight.w600,
                                    color: isSel
                                        ? brand.habitRoles.textOnTint
                                        : muted,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
                if (_frequencyType == 1) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: List.generate(7, (i) {
                      const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
                      final on = (_weekdayMask & (1 << i)) != 0;
                      return Pill(
                        label: labels[i],
                        selected: on,
                        color: theme.colorScheme.primary,
                        onTap: () {
                          final v = !on;
                          setState(() {
                            _weekdayMask = v
                                ? _weekdayMask | (1 << i)
                                : _weekdayMask & ~(1 << i);
                          });
                        },
                      );
                    }),
                  ),
                ],
                if (_frequencyType == 2) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(
                        '$_timesPerWeek times per week',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Expanded(
                        child: BrandSlider(
                          value: _timesPerWeek.toDouble(),
                          min: 1,
                          max: 7,
                          divisions: 6,
                          onChanged: (v) =>
                              setState(() => _timesPerWeek = v.round()),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: BrandTappable(
                        onPressed: _editUnitAndGoalDialog,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _goalType == 0 ? 'Daily goal' : 'Daily limit',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: brand.ink,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              'Unit: ${_unit.text.trim().isEmpty ? 'times' : _unit.text.trim()}',
                              style: TextStyle(fontSize: 12, color: muted),
                            ),
                          ],
                        ),
                      ),
                    ),
                    BrandTappable(
                      onPressed: () => _stepTarget(-1),
                      semanticsLabel: 'One less',
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: brand.canvas,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Container(
                          width: 14,
                          height: 2.5,
                          decoration: BoxDecoration(
                            color: brand.ink,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    BrandTappable(
                      onPressed: _editUnitAndGoalDialog,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 34),
                        child: Text(
                          _target.text,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6,
                            color: brand.ink,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    BrandTappable(
                      onPressed: () => _stepTarget(1),
                      semanticsLabel: 'One more',
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: brand.ink,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: AppIcon(
                          AppIcons.add,
                          size: 18,
                          color: brand.onInk,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Daily reminder & Cost per unit card (`22-habit-editor.html` lines 65-77)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: brand.surface,
              borderRadius: BorderRadius.circular(22),
              boxShadow: AppShadows.card(theme.brightness),
            ),
            child: Column(
              children: [
                Container(
                  height: 56,
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: brand.hairline)),
                  ),
                  child: Row(
                    children: [
                      AppIcon(
                        AppIcons.notifications,
                        size: 20,
                        color: brand.habitRoles.graphicOnTint,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Daily reminder',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: brand.ink,
                          ),
                        ),
                      ),
                      if (_reminderMinutes != null) ...[
                        BrandTappable(
                          onPressed: () async {
                            final minutes = await brandTimePicker(
                              context,
                              initialMinutes: _reminderMinutes!,
                              title: 'Daily reminder',
                            );
                            if (minutes != null) {
                              setState(() => _reminderMinutes = minutes);
                            }
                          },
                          child: Container(
                            height: 36,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: brand.canvas,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              Fmt.minutesOfDay(_reminderMinutes!),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: brand.ink,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      BrandTappable(
                        semanticsLabel: 'Daily reminder',
                        onPressed: () async {
                          AppHaptics.selection();
                          if (_reminderMinutes != null) {
                            setState(() => _reminderMinutes = null);
                          } else {
                            setState(() => _reminderMinutes = 10 * 60);
                          }
                        },
                        child: Container(
                          width: 52,
                          height: 32,
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: _reminderMinutes != null
                                ? brand.habit
                                : brand.well,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          alignment: _reminderMinutes != null
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: theme.brightness == Brightness.dark
                                  ? (_reminderMinutes != null
                                        ? Colors.white
                                        : brand.onInkMuted)
                                  : brand.surface,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                BrandTappable(
                  onPressed: () => _editOptionalTrackingDialog(currency),
                  child: SizedBox(
                    height: 56,
                    child: Row(
                      children: [
                        AppIcon(
                          AppIcons.expenses,
                          size: 20,
                          color: brand.expenseRoles.graphicOnTint,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Cost per unit',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: brand.ink,
                                ),
                              ),
                              Text(
                                'Optional — shows what the habit costs you',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: muted),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          costSummary.isEmpty ? 'Off' : costSummary,
                          style: TextStyle(fontSize: 14, color: muted),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Appearance card (`22-habit-editor.html` lines 79-90)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: brand.surface,
              borderRadius: BorderRadius.circular(22),
              boxShadow: AppShadows.card(theme.brightness),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'APPEARANCE',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: muted,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final swatch in swatches)
                      Builder(
                        builder: (context) {
                          final swatchInt = swatch.toARGB32();
                          final isSel = swatchInt == activeColorInt;
                          return GestureDetector(
                            onTap: () {
                              AppHaptics.selection();
                              setState(() => _color = swatchInt);
                            },
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: swatch,
                                shape: BoxShape.circle,
                                boxShadow: isSel
                                    ? [
                                        BoxShadow(
                                          color: brand.surface,
                                          spreadRadius: 3,
                                        ),
                                        BoxShadow(
                                          color: brand.ink,
                                          spreadRadius: 5,
                                        ),
                                      ]
                                    : null,
                              ),
                            ),
                          );
                        },
                      ),
                    BrandTappable(
                      onPressed: () =>
                          setState(() => _showIconPicker = !_showIconPicker),
                      semanticsLabel: 'Change icon',
                      child: Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: brand.canvas,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'Icon',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: brand.ink,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_showIconPicker) ...[
                  const SizedBox(height: 14),
                  IconPickerRow(
                    options: AppIcons.habitIcons,
                    selected: _icon,
                    color: activeColor,
                    onChanged: (i) => setState(() => _icon = i),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

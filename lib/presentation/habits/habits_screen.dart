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
    var overToday = 0;
    var bestStreak = 0;
    String? bestStreakHabit;
    for (final h in habits) {
      final s = statsByHabit[h.id]!;
      if (_isHabitDoneOn(h, s, today)) doneToday++;
      if (s.overLimit(h)) overToday++;
      final habitBest = s.bestStreak > s.currentStreak
          ? s.bestStreak
          : s.currentStreak;
      if (habitBest > bestStreak) {
        bestStreak = habitBest;
        bestStreakHabit = h.name;
      }
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
                    "TODAY'S PASSED",
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
                  if (overToday > 0) ...[
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppIcon(
                          AppIcons.warning,
                          size: 13,
                          color: brand.dangerRoles.onInk,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          overToday == 1
                              ? '1 over limit'
                              : '$overToday over limit',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: brand.dangerRoles.onInk,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
              Flexible(
                child: Column(
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
                      bestStreakHabit != null
                          ? 'Best streak · $bestStreakHabit'
                          : 'Best streak',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: brand.onInkMuted),
                    ),
                  ],
                ),
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

    final progress = habit.targetAmount <= 0
        ? (stats.todayAmount > 0 ? 1.0 : 0.0)
        : (stats.todayAmount / habit.targetAmount).clamp(0.0, 1.0);

    Future<void> onActionTap() async {
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
                    if (over) ...[
                      AppIcon(
                        AppIcons.warning,
                        size: 13,
                        color: brand.dangerRoles.textOnTint,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Over ${_trim(stats.todayAmount)}/${_trim(habit.targetAmount)}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: brand.dangerRoles.textOnTint,
                        ),
                      ),
                    ] else
                      Text(
                        '${_trim(stats.todayAmount)} / ${_trim(habit.targetAmount)}'
                        '${habit.unit == null ? '' : ' ${habit.unit}'}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.outline,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 7),
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
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // 48x48 right action circle (`05-habits.html` lines 57, 66, 75)
          BrandTappable(
            onPressed: onActionTap,
            semanticsLabel: 'Add ${habit.unit ?? 'one'}',
            child: Container(
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
                color: over ? brand.dangerRoles.textOnTint : roles.textOnTint,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openDetail(BuildContext context) {
    context.push('/habits/${habit.id}');
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

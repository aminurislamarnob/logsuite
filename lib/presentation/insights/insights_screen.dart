import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/settings/app_settings.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/common.dart';
import '../expenses/providers/expenses_provider.dart';
import '../focus/providers/focus_provider.dart';
import '../habits/providers/habits_provider.dart';
import '../habits/utils/habit_stats.dart';
import '../medicine/providers/medicine_provider.dart';
import '../tasks/providers/tasks_provider.dart';

/// Cross-module insights (`12-insights.html`): Week / 30-day toggle, ink hero
/// card with 7-day bar chart and 3 sub-tiles, 2×2 module tint grid, "Money
/// this month" category breakdown card, and 5-week completion heatmap card.
class InsightsScreen extends ConsumerStatefulWidget {
  const InsightsScreen({super.key});

  @override
  ConsumerState<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends ConsumerState<InsightsScreen> {
  int _days = 7;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final currency = settings.currencySymbol;
    final theme = Theme.of(context);

    final taskStats = ref.watch(taskStatsProvider(_days)).valueOrNull;
    final taskStatsForCompare = _days == 7
        ? ref.watch(taskStatsProvider(14)).valueOrNull
        : null;
    final doseStats = settings.isEnabled(AppModule.medicine)
        ? ref.watch(takenDosesByDayProvider(_days == 7 ? 14 : 30)).valueOrNull
        : null;
    final focusStats = ref.watch(focusStatsProvider).valueOrNull;
    final adherence = ref.watch(adherenceProvider).valueOrNull;
    final report = ref.watch(monthReportProvider).valueOrNull;
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const [];
    final habits = ref.watch(habitsListProvider).valueOrNull ?? const [];
    final habitMetPerDay = <DateTime, int>{};
    if (settings.isEnabled(AppModule.habits)) {
      for (final h in habits) {
        final stats = ref.watch(habitStatsProvider(h.id)).valueOrNull;
        if (stats == null) continue;
        for (final entry in stats.byDay.entries) {
          final met = h.goalType == 0
              ? entry.value >= h.targetAmount
              : entry.value <= h.targetAmount;
          if (met) {
            habitMetPerDay[entry.key] = (habitMetPerDay[entry.key] ?? 0) + 1;
          }
        }
      }
    }

    return BrandScaffold(
      header: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            12,
            AppSpacing.gutter,
            8,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Insights',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.displayMedium?.copyWith(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.9,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              BrandSegmented<int>(
                options: const {7: 'Week', 30: '30 days'},
                selected: _days,
                onSelected: (d) => setState(() => _days = d),
              ),
            ],
          ),
        ),
      ),
      child: ListView(
        padding: pageInsets(context, top: 8, end: PageEnd.navBar),
        children: [
          _HeroInsightsCard(
            days: _days,
            taskStats: taskStats,
            compareStats: taskStatsForCompare,
            focusStats: focusStats,
            doseStats: doseStats,
            habitMetPerDay: habitMetPerDay,
          ),
          const SizedBox(height: 14),
          _ModuleTintGrid(
            days: _days,
            settings: settings,
            taskStats: taskStats,
            focusStats: focusStats,
            adherence: adherence,
            habitsCount: habits.length,
          ),
          if (settings.isEnabled(AppModule.expenses) && report != null) ...[
            const SizedBox(height: 14),
            _MoneyMonthCard(
              report: report,
              categories: categories,
              currency: currency,
            ),
          ],
          if (settings.isEnabled(AppModule.tasks) && taskStats != null) ...[
            const SizedBox(height: 14),
            _CompletionHeatmapCard(taskStats: taskStats),
          ],
          if (settings.isEnabled(AppModule.habits) && habits.isNotEmpty) ...[
            const SizedBox(height: 18),
            const SectionHeader('Habits'),
            ...habits.map((h) => _HabitInsightRow(habitId: h.id)),
          ],
        ],
      ),
    );
  }
}

/// Compact percent on the ink hero (`12-insights.html`). Hidden by the caller
/// when the previous week has nothing to compare against.
class _WeekDeltaBadge extends StatelessWidget {
  final int percent;

  const _WeekDeltaBadge({required this.percent});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final tone = percent < 0 ? brand.dangerRoles.onInk : brand.habitRoles.onInk;
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (percent != 0) ...[
            AppIcon(
              percent > 0 ? AppIcons.trendUp : AppIcons.trendDown,
              size: 12,
              color: tone,
            ),
            const SizedBox(width: 4),
          ],
          Text(
            '${percent.abs()}%',
            style: TextStyle(
              color: tone,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroInsightsCard extends StatelessWidget {
  final int days;
  final TaskStats? taskStats;
  final TaskStats? compareStats;
  final FocusStats? focusStats;
  final Map<DateTime, int>? doseStats;
  final Map<DateTime, int> habitMetPerDay;

  const _HeroInsightsCard({
    required this.days,
    required this.taskStats,
    required this.compareStats,
    required this.focusStats,
    required this.doseStats,
    required this.habitMetPerDay,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryText = isDark ? brand.ink : brand.onInk;

    final today = Fmt.dateOnly(DateTime.now());
    final weekDays = [
      for (var i = 6; i >= 0; i--) today.subtract(Duration(days: i)),
    ];
    int seriesOn(TaskStats? stats, DateTime day) =>
        (stats?.perDay[day] ?? 0) +
        (doseStats?[day] ?? 0) +
        (habitMetPerDay[day] ?? 0) +
        ((focusStats?.byDay[day] ?? Duration.zero).inMinutes > 0 ? 1 : 0);

    final counts = [for (final d in weekDays) seriesOn(taskStats, d)];
    final maxCount = counts.fold<int>(0, math.max);
    final bestIdx = maxCount > 0 ? counts.indexOf(maxCount) : -1;
    final bestDayLabel = bestIdx >= 0
        ? _weekdayFull(weekDays[bestIdx].weekday)
        : '—';

    final totalDone = [
      for (var i = days - 1; i >= 0; i--) today.subtract(Duration(days: i)),
    ].fold<int>(0, (sum, day) => sum + seriesOn(taskStats, day));

    final int? versusLastWeek = compareStats == null
        ? null
        : () {
            final previous = [
              for (var i = 13; i >= 7; i--) today.subtract(Duration(days: i)),
            ].fold<int>(0, (sum, day) => sum + seriesOn(compareStats, day));
            if (previous == 0) return null;
            final current = weekDays.fold<int>(
              0,
              (sum, day) => sum + seriesOn(compareStats, day),
            );
            return (((current - previous) / previous) * 100).round();
          }();
    final peakHour = focusStats?.bestHour == null
        ? '—'
        : Fmt.minutesOfDay(focusStats!.bestHour! * 60);
    final openTasks = taskStats?.open ?? 0;
    final stillOpen = openTasks == 1 ? '1 task' : '$openTasks tasks';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: brand.heroSurface,
        borderRadius: BorderRadius.circular(AppRadii.hero),
        boxShadow: AppShadows.hero(theme.brightness),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      days == 7 ? 'THIS WEEK' : 'LAST 30 DAYS',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: brand.medicineRoles.onInk,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          '$totalDone',
                          style: TextStyle(
                            color: primaryText,
                            fontSize: 48,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -2,
                            height: 1.0,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            totalDone == 1 ? 'thing done' : 'things done',
                            style: TextStyle(
                              color: brand.onInkMuted,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (versusLastWeek != null) ...[
                const SizedBox(width: 8),
                _WeekDeltaBadge(percent: versusLastWeek),
              ],
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 92,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < weekDays.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final isToday = i == weekDays.length - 1;
                        final isBest = i == bestIdx && !isToday;
                        final ratio = maxCount == 0
                            ? 0.18
                            : (counts[i] / maxCount).clamp(0.18, 1.0);
                        final barColor = isToday
                            ? brand.medicineRoles.onInk
                            : isBest
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.16);
                        return Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: FractionallySizedBox(
                                  heightFactor: ratio,
                                  widthFactor: 1,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: barColor,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              Fmt.weekday(weekDays[i]).substring(0, 1),
                              style: TextStyle(
                                color: isBest ? Colors.white : brand.onInkMuted,
                                fontSize: 11,
                                fontWeight: isBest || isToday
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _HeroStatBox(label: 'Best day', value: bestDayLabel),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _HeroStatBox(label: 'Peak hour', value: peakHour),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _HeroStatBox(label: 'Still open', value: stillOpen),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _weekdayFull(int w) => const [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ][(w - 1).clamp(0, 6)];
}

class _HeroStatBox extends StatelessWidget {
  final String label;
  final String value;

  const _HeroStatBox({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final primaryText = Theme.of(context).brightness == Brightness.dark
        ? brand.ink
        : brand.onInk;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: brand.onInkMuted, fontSize: 11),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: primaryText,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModuleTintGrid extends ConsumerWidget {
  final int days;
  final AppSettings settings;
  final TaskStats? taskStats;
  final FocusStats? focusStats;
  final AdherenceStats? adherence;
  final int habitsCount;

  const _ModuleTintGrid({
    required this.days,
    required this.settings,
    required this.taskStats,
    required this.focusStats,
    required this.adherence,
    required this.habitsCount,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final cards = <Widget>[];

    if (settings.isEnabled(AppModule.tasks) && taskStats != null) {
      final total = taskStats!.completed + taskStats!.open;
      final ratio = total == 0 ? 0.0 : taskStats!.completed / total;
      cards.add(
        _TintMetricCard(
          roles: brand.taskRoles,
          eyebrow: 'Tasks',
          number: '${taskStats!.completed}',
          unit: ' done',
          progress: ratio,
          footer: Text.rich(
            TextSpan(
              style: TextStyle(fontSize: 12, color: brand.taskRoles.textOnTint),
              children: [
                TextSpan(text: '${taskStats!.open} open'),
                if (taskStats!.overdue > 0) ...[
                  const TextSpan(text: ' · '),
                  TextSpan(
                    text: '${taskStats!.overdue} overdue',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: brand.dangerRoles.textOnTint,
                    ),
                  ),
                ],
              ],
            ),
          ),
          onTap: () => context.push('/tasks'),
        ),
      );
    }

    if (settings.isEnabled(AppModule.habits)) {
      final habits = ref.watch(habitsListProvider).valueOrNull ?? const [];
      final logs = ref.watch(todayHabitLogsProvider).valueOrNull ?? const {};
      final done = habits.where((h) {
        final a = logs[h.id] ?? 0;
        return h.goalType == 0 ? a >= h.targetAmount : a <= h.targetAmount;
      }).length;
      final ratio = habits.isEmpty ? 0.0 : done / habits.length;
      cards.add(
        _TintMetricCard(
          roles: brand.habitRoles,
          eyebrow: 'Habits',
          number: '${(ratio * 100).round()}',
          unit: '% kept',
          progress: ratio,
          footer: Text(
            '$done of ${habits.length} today',
            style: TextStyle(fontSize: 12, color: brand.habitRoles.textOnTint),
          ),
          onTap: () => context.push('/habits'),
        ),
      );
    }

    if (settings.isEnabled(AppModule.medicine) && adherence != null) {
      final pct = (adherence!.monthly * 100).round();
      cards.add(
        _TintMetricCard(
          roles: brand.medicineRoles,
          eyebrow: 'Medicine adherence',
          number: '$pct',
          unit: '% on time',
          progress: adherence!.monthly.clamp(0.0, 1.0),
          footer: Text(
            adherence!.totalMisses == 0
                ? 'No missed doses'
                : '${adherence!.totalMisses} missed in 30d',
            style: TextStyle(
              fontSize: 12,
              color: brand.medicineRoles.textOnTint,
            ),
          ),
          onTap: () => context.push('/medicine'),
        ),
      );
    }

    if (settings.isEnabled(AppModule.focus) && focusStats != null) {
      final mins = focusStats!.week.inMinutes;
      final hrs = mins ~/ 60;
      final rem = mins % 60;
      final numStr = hrs > 0 ? '${hrs}h $rem' : '$rem';
      final goal = ref.watch(focusGoalProvider) * 7;
      final ratio = goal <= 0 ? 0.0 : (mins / goal).clamp(0.0, 1.0);
      cards.add(
        _TintMetricCard(
          roles: brand.focusRoles,
          eyebrow: 'Focus',
          number: numStr,
          unit: 'm',
          progress: ratio,
          footer: Text(
            '${focusStats!.sessionsToday} ${focusStats!.sessionsToday == 1 ? 'session' : 'sessions'} today',
            style: TextStyle(fontSize: 12, color: brand.focusRoles.textOnTint),
          ),
          onTap: () => context.push('/focus'),
        ),
      );
    }

    if (cards.isEmpty) return const SizedBox.shrink();

    final rows = <Widget>[];
    for (var i = 0; i < cards.length; i += 2) {
      if (i > 0) rows.add(const SizedBox(height: 12));
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: cards[i]),
              const SizedBox(width: 12),
              Expanded(
                child: i + 1 < cards.length
                    ? cards[i + 1]
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}

class _TintMetricCard extends StatelessWidget {
  final ModuleColors roles;
  final String eyebrow;
  final String number;
  final String unit;
  final double progress;
  final Widget footer;
  final VoidCallback onTap;

  const _TintMetricCard({
    required this.roles,
    required this.eyebrow,
    required this.number,
    required this.unit,
    required this.progress,
    required this.footer,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return TintCard(
      fill: roles.tintFill,
      radius: 22,
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            eyebrow,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: roles.textOnTint,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                number,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                  height: 1.0,
                  color: brand.ink,
                ),
              ),
              Flexible(
                child: Text(
                  unit,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: roles.textOnTint,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 6,
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                backgroundColor: brand.surface,
                valueColor: AlwaysStoppedAnimation<Color>(roles.graphicOnTint),
              ),
            ),
          ),
          const SizedBox(height: 8),
          footer,
        ],
      ),
    );
  }
}

class _MoneyMonthCard extends StatelessWidget {
  final MonthReport report;
  final List<dynamic> categories;
  final String currency;

  const _MoneyMonthCard({
    required this.report,
    required this.categories,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final entries = report.byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = entries.take(3).toList();
    final othersSum = entries
        .skip(3)
        .fold<double>(0, (acc, e) => acc + e.value);
    final shades = [
      brand.expenseRoles.graphicOnTint,
      brand.expense.withValues(alpha: 0.75),
      brand.expense.withValues(alpha: 0.50),
      brand.expense.withValues(alpha: 0.25),
    ];

    return TintCard(
      fill: brand.surface,
      radius: AppRadii.card,
      padding: const EdgeInsets.all(18),
      onTap: () => context.push('/expenses'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MONEY THIS MONTH',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: context.muted,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.end,
                      children: [
                        Text(
                          Fmt.money(report.expense, currency),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Text(
                            'spent',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: context.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Open',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: brand.expenseRoles.textOnTint,
                ),
              ),
            ],
          ),
          if (report.expense > 0 && top.isNotEmpty) ...[
            const SizedBox(height: 14),
            SizedBox(
              height: 12,
              child: Row(
                children: [
                  for (var i = 0; i < top.length; i++) ...[
                    if (i > 0) const SizedBox(width: 3),
                    Expanded(
                      flex: math.max(
                        1,
                        ((top[i].value / report.expense) * 100).round(),
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          color: shades[i],
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ],
                  if (othersSum > 0) ...[
                    const SizedBox(width: 3),
                    Expanded(
                      flex: math.max(
                        1,
                        ((othersSum / report.expense) * 100).round(),
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          color: shades[3],
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            for (var i = 0; i < top.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              Builder(
                builder: (context) {
                  final catName =
                      categories
                          .where((c) => c.id == top[i].key)
                          .map((c) => c.name as String)
                          .firstOrNull ??
                      'Other';
                  return Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: shades[i],
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          catName,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                      Text(
                        Fmt.money(top[i].value, currency),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
            if (othersSum > 0) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: shades[3],
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${entries.length - 3} others',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                  Text(
                    Fmt.money(othersSum, currency),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _CompletionHeatmapCard extends StatelessWidget {
  final TaskStats taskStats;

  const _CompletionHeatmapCard({required this.taskStats});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final today = Fmt.dateOnly(DateTime.now());
    final days = [
      for (var i = 34; i >= 0; i--) today.subtract(Duration(days: i)),
    ];
    final roles = brand.medicineRoles;

    Color cellColor(int n) {
      if (n <= 0) return brand.track;
      if (n == 1) return roles.graphicOnTint.withValues(alpha: 0.30);
      if (n <= 3) return roles.graphicOnTint.withValues(alpha: 0.62);
      return roles.graphicOnTint;
    }

    return TintCard(
      fill: brand.surface,
      radius: AppRadii.card,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  'COMPLETION HEATMAP',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: context.muted,
                    letterSpacing: 0.8,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Less',
                      style: TextStyle(fontSize: 11, color: context.muted),
                    ),
                    const SizedBox(width: 4),
                    for (final n in [0, 1, 2, 4]) ...[
                      Container(
                        width: 10,
                        height: 10,
                        margin: const EdgeInsets.symmetric(horizontal: 1.5),
                        decoration: BoxDecoration(
                          color: cellColor(n),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ],
                    const SizedBox(width: 4),
                    Text(
                      'More',
                      style: TextStyle(fontSize: 11, color: context.muted),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          GridView.builder(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 5,
              crossAxisSpacing: 5,
              mainAxisExtent: 22,
            ),
            itemCount: days.length,
            itemBuilder: (context, i) {
              final d = days[i];
              final isToday = d == today;
              final count = taskStats.perDay[d] ?? 0;
              return Container(
                decoration: BoxDecoration(
                  color: isToday && count == 0
                      ? brand.surface
                      : cellColor(count),
                  borderRadius: BorderRadius.circular(7),
                  border: isToday
                      ? Border.all(color: brand.ink, width: 2)
                      : null,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _HabitInsightRow extends ConsumerWidget {
  final int habitId;
  const _HabitInsightRow({required this.habitId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habits = ref.watch(habitsListProvider).valueOrNull ?? const [];
    final habit = habits.where((h) => h.id == habitId).firstOrNull;
    final logs = ref.watch(habitLogsProvider(habitId)).valueOrNull ?? const [];
    if (habit == null) return const SizedBox.shrink();

    final stats = HabitStats.compute(habit, logs);
    final rate = stats.completionRate;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TintCard(
        fill: context.brand.surface,
        padding: const EdgeInsets.all(14),
        child: LabeledProgress(
          label: habit.name,
          trailing:
              '${Fmt.percent(rate)} · ${stats.currentStreak}d streak (best ${stats.bestStreak}d)',
          value: rate,
          color: Color(habit.color),
        ),
      ),
    );
  }
}

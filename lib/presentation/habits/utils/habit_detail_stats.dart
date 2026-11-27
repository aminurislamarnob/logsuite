import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/formatters.dart';

/// How a habit is logged and evaluated on the detail screen.
enum HabitKind { amount, yesNo, reduce }

/// History range shown by the detail screen's analytics cards.
enum HabitRange { days30, days90, allTime }

/// Status of a single calendar day for a habit.
enum HabitDayStatus { done, partly, missed, notTracked, future }

/// Direction of the 7-day rolling completion trend.
enum TrendVerdict { trendingUp, steady, slipping }

/// Detects the UI variant for [habit] from its database columns.
HabitKind habitKindOf(Habit habit) {
  if (habit.goalType == 1) return HabitKind.reduce;
  if (habit.unit == null && habit.targetAmount <= 1) return HabitKind.yesNo;
  return HabitKind.amount;
}

/// Whether [habit] is scheduled on [day] according to its frequency settings.
bool isHabitScheduledOn(Habit habit, DateTime day) {
  if (habit.frequencyType == 1) {
    return (habit.weekdayMask & (1 << (day.weekday - 1))) != 0;
  }
  return true;
}

/// Whether [habit] counts as completed on [day] given [byDay] log totals.
bool isHabitDoneOn(Habit habit, Map<DateTime, double> byDay, DateTime day) {
  final date = Fmt.dateOnly(day);
  final amount = byDay[date] ?? 0;
  if (habit.goalType == 1) {
    if (date.isBefore(Fmt.dateOnly(habit.createdAt))) return false;
    return amount <= habit.targetAmount;
  }
  final target = habit.targetAmount <= 0 ? 1.0 : habit.targetAmount;
  return amount >= target;
}

String weekdayMaskLabel(int mask) {
  const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  if (mask == 127) return 'Daily';
  if (mask == 31) return 'Weekdays';
  final active = <String>[];
  for (var i = 0; i < 7; i++) {
    if ((mask & (1 << i)) != 0) active.add(names[i]);
  }
  return active.isEmpty ? 'Custom' : active.join(' · ');
}

String habitFrequencyLabel(Habit habit) => switch (habit.frequencyType) {
  1 => weekdayMaskLabel(habit.weekdayMask),
  2 => '${habit.timesPerWeek}x / week',
  _ => 'Every day',
};

/// Formats a numeric amount without trailing `.0` when whole.
String trimHabitAmount(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// Quick-add increments for an amount habit (`round(target/4)` and `round(target/2)`).
List<int> quickAddAmounts(double target) {
  final effective = target <= 0 ? 1.0 : target;
  final small = math.max(1, (effective / 4).round());
  final large = math.max(1, (effective / 2).round());
  if (small == large) return [small];
  return [small, large];
}

@immutable
class StreakMilestone {
  final int prevMilestone;
  final int nextMilestone;
  final int daysToGo;
  final double progress;

  const StreakMilestone({
    required this.prevMilestone,
    required this.nextMilestone,
    required this.daysToGo,
    required this.progress,
  });

  static const milestones = [7, 14, 30, 60, 100, 365];

  static StreakMilestone forStreak(int streak) {
    final s = math.max(0, streak);
    var prev = 0;
    for (final m in milestones) {
      if (s < m) {
        final span = m - prev;
        final progress = span <= 0 ? 0.0 : ((s - prev) / span).clamp(0.0, 1.0);
        return StreakMilestone(
          prevMilestone: prev,
          nextMilestone: m,
          daysToGo: m - s,
          progress: progress,
        );
      }
      prev = m;
    }
    return const StreakMilestone(
      prevMilestone: 100,
      nextMilestone: 365,
      daysToGo: 0,
      progress: 1.0,
    );
  }
}

@immutable
class WeekdayRate {
  /// 1 = Monday .. 7 = Sunday.
  final int weekday;
  final int done;
  final int tracked;

  const WeekdayRate({
    required this.weekday,
    required this.done,
    required this.tracked,
  });

  double get rate => tracked == 0 ? 0 : done / tracked;
}

@immutable
class RollingPoint {
  final DateTime day;
  final double rate;

  const RollingPoint({required this.day, required this.rate});
}

@immutable
class HabitDayInfo {
  final DateTime day;
  final HabitDayStatus status;
  final double amount;

  const HabitDayInfo({
    required this.day,
    required this.status,
    required this.amount,
  });
}

@immutable
class HabitDetailStats {
  final HabitRange range;
  final DateTime rangeStart;
  final DateTime effectiveStart;
  final DateTime today;
  final int doneCount;
  final int trackedCount;

  /// Null when there are no tracked days in the range.
  final double? completionRate;

  /// Null when [range] is [HabitRange.allTime] or the previous period starts
  /// before the habit's creation date, or had 0 tracked days.
  final double? prevCompletionRate;
  final bool prevPeriodStartsBeforeCreation;

  final double totalAmount;
  final double dailyAverage;
  final int daysInRange;

  final Map<DateTime, HabitDayInfo> dayInfos;
  final List<WeekdayRate> weekdayRates;
  final WeekdayRate? weakestWeekday;
  final WeekdayRate? bestWeekday;
  final bool hasWeakSpot;
  final bool showInsight;

  final List<RollingPoint> rollingSeries;
  final TrendVerdict trendVerdict;
  final bool showTrendChart;

  final StreakMilestone milestone;

  const HabitDetailStats({
    required this.range,
    required this.rangeStart,
    required this.effectiveStart,
    required this.today,
    required this.doneCount,
    required this.trackedCount,
    required this.completionRate,
    required this.prevCompletionRate,
    required this.prevPeriodStartsBeforeCreation,
    required this.totalAmount,
    required this.dailyAverage,
    required this.daysInRange,
    required this.dayInfos,
    required this.weekdayRates,
    required this.weakestWeekday,
    required this.bestWeekday,
    required this.hasWeakSpot,
    required this.showInsight,
    required this.rollingSeries,
    required this.trendVerdict,
    required this.showTrendChart,
    required this.milestone,
  });

  int get completionPercent =>
      completionRate == null ? 0 : (completionRate! * 100).round();

  int? get prevCompletionPercent =>
      prevCompletionRate == null ? null : (prevCompletionRate! * 100).round();

  /// Computes every derived metric shown on `HabitDetailScreen`.
  static HabitDetailStats compute({
    required Habit habit,
    required Map<DateTime, double> byDay,
    required DateTime today,
    required HabitRange range,
    required int currentStreak,
  }) {
    final todayDay = Fmt.dateOnly(today);
    final createdDay = Fmt.dateOnly(habit.createdAt);
    final kind = habitKindOf(habit);
    final target = habit.targetAmount <= 0 ? 1.0 : habit.targetAmount;

    final DateTime rangeStart = switch (range) {
      HabitRange.days30 => todayDay.subtract(const Duration(days: 29)),
      HabitRange.days90 => todayDay.subtract(const Duration(days: 89)),
      HabitRange.allTime =>
        createdDay.isAfter(todayDay) ? todayDay : createdDay,
    };

    final effectiveStart = rangeStart.isBefore(createdDay)
        ? (createdDay.isAfter(todayDay) ? todayDay : createdDay)
        : rangeStart;

    bool isDone(DateTime d) => isHabitDoneOn(habit, byDay, d);
    bool isTrackedDay(DateTime d) =>
        !d.isBefore(createdDay) &&
        !d.isAfter(todayDay) &&
        isHabitScheduledOn(habit, d);

    final todayDone = isDone(todayDay);

    // Per-day status map for the visible range (and any padded grid days).
    final dayInfos = <DateTime, HabitDayInfo>{};
    HabitDayInfo infoFor(DateTime d) {
      final date = Fmt.dateOnly(d);
      final amount = byDay[date] ?? 0;
      if (date.isAfter(todayDay)) {
        return HabitDayInfo(
          day: date,
          status: HabitDayStatus.future,
          amount: 0,
        );
      }
      if (date.isBefore(createdDay) || !isHabitScheduledOn(habit, date)) {
        return HabitDayInfo(
          day: date,
          status: HabitDayStatus.notTracked,
          amount: amount,
        );
      }
      if (isDone(date)) {
        return HabitDayInfo(
          day: date,
          status: HabitDayStatus.done,
          amount: amount,
        );
      }
      if (kind == HabitKind.amount && amount > 0 && amount < target) {
        return HabitDayInfo(
          day: date,
          status: HabitDayStatus.partly,
          amount: amount,
        );
      }
      return HabitDayInfo(
        day: date,
        status: HabitDayStatus.missed,
        amount: amount,
      );
    }

    var cursor = rangeStart;
    while (!cursor.isAfter(todayDay)) {
      dayInfos[cursor] = infoFor(cursor);
      cursor = cursor.add(const Duration(days: 1));
    }

    // Completion & weekday rates (today excluded until done).
    var doneCount = 0;
    var trackedCount = 0;
    final weekdayDone = List<int>.filled(8, 0);
    final weekdayTracked = List<int>.filled(8, 0);

    cursor = effectiveStart;
    while (!cursor.isAfter(todayDay)) {
      final includeToday = !Fmt.isSameDay(cursor, todayDay) || todayDone;
      if (includeToday && isTrackedDay(cursor)) {
        trackedCount++;
        weekdayTracked[cursor.weekday]++;
        if (isDone(cursor)) {
          doneCount++;
          weekdayDone[cursor.weekday]++;
        }
      }
      cursor = cursor.add(const Duration(days: 1));
    }

    final completionRate = trackedCount == 0 ? null : doneCount / trackedCount;

    // Previous period comparison.
    double? prevCompletionRate;
    var prevStartsBeforeCreation = false;
    if (range != HabitRange.allTime) {
      final spanDays = range == HabitRange.days30 ? 30 : 90;
      final prevEnd = rangeStart.subtract(const Duration(days: 1));
      final prevStart = rangeStart.subtract(Duration(days: spanDays));
      if (prevStart.isBefore(createdDay)) {
        prevStartsBeforeCreation = true;
      } else {
        var prevDone = 0;
        var prevTracked = 0;
        var p = prevStart;
        while (!p.isAfter(prevEnd)) {
          if (isTrackedDay(p)) {
            prevTracked++;
            if (isDone(p)) prevDone++;
          }
          p = p.add(const Duration(days: 1));
        }
        if (prevTracked > 0) {
          prevCompletionRate = prevDone / prevTracked;
        }
      }
    }

    // Total & daily average (includes today).
    var totalAmount = 0.0;
    cursor = effectiveStart;
    while (!cursor.isAfter(todayDay)) {
      totalAmount += byDay[cursor] ?? 0;
      cursor = cursor.add(const Duration(days: 1));
    }
    final daysInRange = math.max(
      1,
      todayDay.difference(effectiveStart).inDays + 1,
    );
    final dailyAverage = totalAmount / daysInRange;

    // Weekday insight.
    final weekdayRates = [
      for (var wd = 1; wd <= 7; wd++)
        WeekdayRate(
          weekday: wd,
          done: weekdayDone[wd],
          tracked: weekdayTracked[wd],
        ),
    ];
    final activeWeekdays = weekdayRates.where((w) => w.tracked > 0).toList();
    WeekdayRate? weakest;
    WeekdayRate? best;
    if (activeWeekdays.isNotEmpty) {
      weakest = activeWeekdays.reduce((a, b) => a.rate <= b.rate ? a : b);
      best = activeWeekdays.reduce((a, b) => a.rate >= b.rate ? a : b);
    }
    final hasWeakSpot =
        weakest != null &&
        best != null &&
        weakest.rate < 0.75 &&
        (best.rate - weakest.rate) >= 0.15 - 1e-9;
    final showInsight = habit.frequencyType != 2 && trackedCount >= 14;

    // 7-day rolling series for each tracked day in the range (excluding
    // unfinished today).
    final rollingSeries = <RollingPoint>[];
    cursor = effectiveStart;
    while (!cursor.isAfter(todayDay)) {
      final includeToday = !Fmt.isSameDay(cursor, todayDay) || todayDone;
      if (includeToday && isTrackedDay(cursor)) {
        var wDone = 0;
        var wTracked = 0;
        for (var offset = 6; offset >= 0; offset--) {
          final w = cursor.subtract(Duration(days: offset));
          final wInclude = !Fmt.isSameDay(w, todayDay) || todayDone;
          if (wInclude && isTrackedDay(w)) {
            wTracked++;
            if (isDone(w)) wDone++;
          }
        }
        rollingSeries.add(
          RollingPoint(
            day: cursor,
            rate: wTracked == 0 ? 0.0 : wDone / wTracked,
          ),
        );
      }
      cursor = cursor.add(const Duration(days: 1));
    }

    var trendVerdict = TrendVerdict.steady;
    if (rollingSeries.length >= 2) {
      final mid = rollingSeries.length ~/ 2;
      final firstHalf = rollingSeries.sublist(0, mid);
      final secondHalf = rollingSeries.sublist(mid);
      final firstMean =
          firstHalf.fold(0.0, (s, p) => s + p.rate) / firstHalf.length;
      final secondMean =
          secondHalf.fold(0.0, (s, p) => s + p.rate) / secondHalf.length;
      final diff = secondMean - firstMean;
      if (diff > 0.05) {
        trendVerdict = TrendVerdict.trendingUp;
      } else if (diff < -0.05) {
        trendVerdict = TrendVerdict.slipping;
      }
    }

    return HabitDetailStats(
      range: range,
      rangeStart: rangeStart,
      effectiveStart: effectiveStart,
      today: todayDay,
      doneCount: doneCount,
      trackedCount: trackedCount,
      completionRate: completionRate,
      prevCompletionRate: prevCompletionRate,
      prevPeriodStartsBeforeCreation: prevStartsBeforeCreation,
      totalAmount: totalAmount,
      dailyAverage: dailyAverage,
      daysInRange: daysInRange,
      dayInfos: dayInfos,
      weekdayRates: weekdayRates,
      weakestWeekday: weakest,
      bestWeekday: best,
      hasWeakSpot: hasWeakSpot,
      showInsight: showInsight,
      rollingSeries: rollingSeries,
      trendVerdict: trendVerdict,
      showTrendChart: trackedCount >= 7 && rollingSeries.isNotEmpty,
      milestone: StreakMilestone.forStreak(currentStreak),
    );
  }
}

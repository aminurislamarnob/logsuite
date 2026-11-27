import 'package:flutter_test/flutter_test.dart';
import 'package:logsuite/core/database/app_database.dart';
import 'package:logsuite/presentation/habits/utils/habit_detail_stats.dart';

Habit _habit({
  int goalType = 0,
  double target = 20,
  String? unit = 'pages',
  int frequencyType = 0,
  int weekdayMask = 127,
  int timesPerWeek = 7,
  required DateTime createdAt,
}) {
  return Habit(
    id: 1,
    name: 'Test Habit',
    icon: 'reading',
    color: 0xFF2D8657,
    unit: unit,
    goalType: goalType,
    targetAmount: target,
    frequencyType: frequencyType,
    weekdayMask: weekdayMask,
    timesPerWeek: timesPerWeek,
    isArchived: false,
    createdAt: createdAt,
  );
}

void main() {
  final today = DateTime(2026, 11, 17); // Tuesday
  DateTime ago(int days) => today.subtract(Duration(days: days));

  group('completion', () {
    test('excludes an unfinished today and includes a finished one', () {
      final habit = _habit(target: 20, createdAt: ago(4));
      final byDay = {
        ago(4): 20.0,
        ago(3): 20.0,
        ago(2): 20.0,
        ago(1): 0.0,
        today: 12.0, // unfinished
      };

      final unfinished = HabitDetailStats.compute(
        habit: habit,
        byDay: byDay,
        today: today,
        range: HabitRange.days30,
        currentStreak: 0,
      );
      // 4 past days tracked (ago4..ago1), 3 done.
      expect(unfinished.trackedCount, 4);
      expect(unfinished.doneCount, 3);
      expect(unfinished.completionPercent, 75);

      final finished = HabitDetailStats.compute(
        habit: habit,
        byDay: {...byDay, today: 20.0},
        today: today,
        range: HabitRange.days30,
        currentStreak: 1,
      );
      // 5 days tracked (ago4..today), 4 done.
      expect(finished.trackedCount, 5);
      expect(finished.doneCount, 4);
      expect(finished.completionPercent, 80);
    });

    test('previous-period comparison covers up, down, same, and new habit', () {
      // New habit: created 40 days ago, 30-day previous range starts 60 days ago
      final newHabit = _habit(target: 1, unit: null, createdAt: ago(40));
      final newStats = HabitDetailStats.compute(
        habit: newHabit,
        byDay: {ago(1): 1.0},
        today: today,
        range: HabitRange.days30,
        currentStreak: 0,
      );
      expect(newStats.prevPeriodStartsBeforeCreation, isTrue);
      expect(newStats.prevCompletionPercent, isNull);

      // Old habit (created 90 days ago)
      final oldHabit = _habit(target: 1, unit: null, createdAt: ago(90));
      final prevDays = <DateTime, double>{
        for (var i = 30; i <= 59; i++)
          if (i % 2 == 0) ago(i): 1.0, // 15/30 = 50%
      };

      // Up: current 20/29 > 50%
      final upStats = HabitDetailStats.compute(
        habit: oldHabit,
        byDay: {...prevDays, for (var i = 1; i <= 20; i++) ago(i): 1.0},
        today: today,
        range: HabitRange.days30,
        currentStreak: 0,
      );
      expect(upStats.prevPeriodStartsBeforeCreation, isFalse);
      expect(upStats.prevCompletionPercent, 50);
      expect(upStats.completionPercent, greaterThan(50));

      // Down: current 5/29 < 50%
      final downStats = HabitDetailStats.compute(
        habit: oldHabit,
        byDay: {...prevDays, for (var i = 1; i <= 5; i++) ago(i): 1.0},
        today: today,
        range: HabitRange.days30,
        currentStreak: 0,
      );
      expect(downStats.prevCompletionPercent, 50);
      expect(downStats.completionPercent, lessThan(50));

      // Same: 15/30 with today done == 50%
      final sameStats = HabitDetailStats.compute(
        habit: oldHabit,
        byDay: {...prevDays, for (var i = 0; i < 15; i++) ago(i): 1.0},
        today: today,
        range: HabitRange.days30,
        currentStreak: 0,
      );
      expect(sameStats.prevCompletionPercent, 50);
      expect(sameStats.completionPercent, 50);
    });
  });

  group('day statuses', () {
    test('days before createdAt and unscheduled weekdays are never missed', () {
      // Only Mondays scheduled (bit 0 = 1)
      final habit = _habit(
        target: 1,
        unit: null,
        frequencyType: 1,
        weekdayMask: 1,
        createdAt: ago(5),
      );
      final stats = HabitDetailStats.compute(
        habit: habit,
        byDay: const {},
        today: today, // Tuesday
        range: HabitRange.days30,
        currentStreak: 0,
      );

      // Before createdAt
      expect(stats.dayInfos[ago(10)]?.status, HabitDayStatus.notTracked);
      // Wednesday (ago(6)) before createdAt -> notTracked
      expect(stats.dayInfos[ago(6)]?.status, HabitDayStatus.notTracked);
      // Sunday (ago(2)) after createdAt, not scheduled -> notTracked
      expect(stats.dayInfos[ago(2)]?.status, HabitDayStatus.notTracked);
      // Monday (ago(1)) after createdAt, scheduled, unlogged -> missed
      expect(stats.dayInfos[ago(1)]?.status, HabitDayStatus.missed);
    });

    test(
      'partly vs done vs missed for amount habits and reduce-habit success',
      () {
        final amountHabit = _habit(target: 20, createdAt: ago(5));
        final amountStats = HabitDetailStats.compute(
          habit: amountHabit,
          byDay: {ago(3): 25, ago(2): 10, ago(1): 0},
          today: today,
          range: HabitRange.days30,
          currentStreak: 0,
        );
        expect(amountStats.dayInfos[ago(3)]?.status, HabitDayStatus.done);
        expect(amountStats.dayInfos[ago(2)]?.status, HabitDayStatus.partly);
        expect(amountStats.dayInfos[ago(1)]?.status, HabitDayStatus.missed);

        final reduceHabit = _habit(
          goalType: 1,
          target: 2,
          unit: 'cups',
          createdAt: ago(5),
        );
        final reduceStats = HabitDetailStats.compute(
          habit: reduceHabit,
          byDay: {ago(2): 2, ago(1): 3},
          today: today,
          range: HabitRange.days30,
          currentStreak: 0,
        );
        expect(reduceStats.dayInfos[ago(3)]?.status, HabitDayStatus.done);
        expect(reduceStats.dayInfos[ago(2)]?.status, HabitDayStatus.done);
        expect(reduceStats.dayInfos[ago(1)]?.status, HabitDayStatus.missed);
      },
    );
  });

  group('insight, rolling trend, and milestones', () {
    test('weekday insight threshold (< 75% and >= 15 points behind best)', () {
      // 28 past days = 4 of each weekday.
      // Make Saturdays 2/4 (50%), all others 4/4 (100%).
      final habit = _habit(target: 1, unit: null, createdAt: ago(30));
      final byDay = <DateTime, double>{};
      for (var i = 1; i <= 29; i++) {
        final d = ago(i);
        if (d.weekday == DateTime.saturday) {
          if (i <= 14) byDay[d] = 1; // 2 of 4 Saturdays
        } else {
          byDay[d] = 1;
        }
      }
      final weakStats = HabitDetailStats.compute(
        habit: habit,
        byDay: byDay,
        today: today,
        range: HabitRange.days30,
        currentStreak: 0,
      );
      expect(weakStats.showInsight, isTrue);
      expect(weakStats.hasWeakSpot, isTrue);
      expect(weakStats.weakestWeekday?.weekday, DateTime.saturday);

      // Now make Saturdays 3/4 (75%) -> not under 75%
      final steadyByDay = <DateTime, double>{
        for (var i = 1; i <= 29; i++) ago(i): 1.0,
      };
      // Drop just one Saturday
      final firstSat = List.generate(
        29,
        (i) => ago(i + 1),
      ).firstWhere((d) => d.weekday == DateTime.saturday);
      steadyByDay.remove(firstSat);

      final steadyStats = HabitDetailStats.compute(
        habit: habit,
        byDay: steadyByDay,
        today: today,
        range: HabitRange.days30,
        currentStreak: 0,
      );
      expect(steadyStats.hasWeakSpot, isFalse);
    });

    test('rolling series length and values on a small fixture', () {
      final habit = _habit(target: 1, unit: null, createdAt: ago(8));
      // 8 past days (ago8..ago1), today unfinished -> 8 points
      final byDay = {
        ago(8): 1.0,
        ago(7): 0.0,
        ago(6): 1.0,
        ago(5): 1.0,
        ago(4): 1.0,
        ago(3): 1.0,
        ago(2): 1.0,
        ago(1): 1.0,
      };
      final stats = HabitDetailStats.compute(
        habit: habit,
        byDay: byDay,
        today: today,
        range: HabitRange.days30,
        currentStreak: 6,
      );
      expect(stats.showTrendChart, isTrue);
      expect(stats.rollingSeries.length, 8);
      // Day 0 (ago8): 1/1 = 1.0
      expect(stats.rollingSeries[0].rate, closeTo(1.0, 0.001));
      // Day 1 (ago7): 1/2 = 0.5
      expect(stats.rollingSeries[1].rate, closeTo(0.5, 0.001));
      // Day 7 (ago1): window ago7..ago1 -> 6/7
      expect(stats.rollingSeries[7].rate, closeTo(6 / 7, 0.001));
    });

    test('milestones: 0 -> 7, 21 -> 30 (9 to go), 30 -> 60', () {
      final m0 = StreakMilestone.forStreak(0);
      expect(m0.nextMilestone, 7);
      expect(m0.daysToGo, 7);
      expect(m0.progress, 0.0);

      final m21 = StreakMilestone.forStreak(21);
      expect(m21.nextMilestone, 30);
      expect(m21.daysToGo, 9);
      expect(m21.progress, closeTo(7 / 16, 0.001));

      final m30 = StreakMilestone.forStreak(30);
      expect(m30.nextMilestone, 60);
      expect(m30.daysToGo, 30);
      expect(m30.progress, 0.0);
    });
  });
}

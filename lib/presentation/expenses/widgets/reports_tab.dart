import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/people/person_avatar.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/brand.dart';
import '../../../core/widgets/common.dart';
import '../providers/expenses_provider.dart';
import '../repository/expense_repository.dart';
import 'month_stepper.dart';

class ReportsTab extends ConsumerStatefulWidget {
  const ReportsTab({super.key});

  @override
  ConsumerState<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends ConsumerState<ReportsTab> {
  bool _showIncome = false;

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(settingsProvider).currencySymbol;
    final reportAsync = ref.watch(monthReportProvider);
    final monthTxs =
        ref.watch(monthTransactionsProvider).valueOrNull ?? const [];
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const [];
    final trend = ref.watch(monthlyTrendProvider).valueOrNull ?? const [];
    final byPerson = ref.watch(spendByPersonProvider).valueOrNull ?? const [];
    final month = ref.watch(reportMonthProvider);

    return ListView(
      padding: pageInsets(context, top: 12, end: PageEnd.none),
      children: [
        const MonthStepper(),
        const SizedBox(height: 12),
        reportAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: BrandSpinner()),
          ),
          error: (e, _) => Text('$e'),
          data: (report) {
            if (report.expense == 0 && report.income == 0) {
              return const EmptyState(
                icon: AppIcons.barChart,
                title: 'Nothing recorded this month',
              );
            }

            final Map<int?, double> activeMap;
            final double activeTotal;
            if (_showIncome) {
              final map = <int?, double>{};
              for (final r in monthTxs.where((t) => t.kind == TxKind.income)) {
                map[r.categoryId] = (map[r.categoryId] ?? 0) + r.amount;
              }
              activeMap = map;
              activeTotal = report.income;
            } else {
              activeMap = report.byCategory;
              activeTotal = report.expense;
            }

            final slices = activeMap.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value));

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CategoryBreakdownCard(
                  slices: slices,
                  categories: categories,
                  total: activeTotal,
                  currency: currency,
                  showIncome: _showIncome,
                  onToggleType: (inc) => setState(() => _showIncome = inc),
                ),
                if (report.byDay.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _DailySpendingCard(
                    byDay: report.byDay,
                    month: month,
                    totalExpense: report.expense,
                    currency: currency,
                  ),
                ],
                if (byPerson.length > 1) ...[
                  const SizedBox(height: 14),
                  _PersonSpendingCard(
                    byPerson: byPerson,
                    totalExpense: report.expense,
                    currency: currency,
                  ),
                ],
                if (trend.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _SixMonthTrendCard(
                    trend: trend,
                    netThisMonth: report.net,
                    selectedMonth: month,
                    currency: currency,
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _CategoryBreakdownCard extends StatelessWidget {
  final List<MapEntry<int?, double>> slices;
  final List<dynamic> categories;
  final double total;
  final String currency;
  final bool showIncome;
  final ValueChanged<bool> onToggleType;

  const _CategoryBreakdownCard({
    required this.slices,
    required this.categories,
    required this.total,
    required this.currency,
    required this.showIncome,
    required this.onToggleType,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final muted = theme.colorScheme.outline;
    final roles = showIncome ? brand.habitRoles : brand.expenseRoles;

    Color shadeFor(int index, int? categoryId) {
      final t = (index * 0.20).clamp(0.0, 0.72);
      return Color.lerp(roles.graphicOnTint, roles.tintFill, t)!;
    }

    String nameFor(int? id) {
      for (final c in categories) {
        if (c.id == id) return c.name as String;
      }
      return 'Uncategorised';
    }

    return Container(
      padding: const EdgeInsets.all(18),
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
                showIncome ? 'INCOME BY CATEGORY' : 'SPENDING BY CATEGORY',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: muted,
                  letterSpacing: 0.8,
                ),
              ),
              Container(
                height: 32,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: brand.hairline,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _MiniSegmentButton(
                      label: 'Expense',
                      selected: !showIncome,
                      onTap: () => onToggleType(false),
                    ),
                    _MiniSegmentButton(
                      label: 'Income',
                      selected: showIncome,
                      onTap: () => onToggleType(true),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (slices.isEmpty || total <= 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                showIncome
                    ? 'No income recorded this month.'
                    : 'No expenses recorded this month.',
                style: TextStyle(color: muted, fontSize: 14),
              ),
            )
          else ...[
            // Stacked category breakdown bar
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: SizedBox(
                height: 10,
                child: Row(
                  children: [
                    for (final (i, entry) in slices.indexed) ...[
                      if (i > 0) const SizedBox(width: 2),
                      Expanded(
                        flex: math.max(
                          1,
                          ((entry.value / total) * 1000).round(),
                        ),
                        child: Container(color: shadeFor(i, entry.key)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 124,
                  height: 124,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PieChart(
                        PieChartData(
                          centerSpaceRadius: 42,
                          sectionsSpace: 2,
                          startDegreeOffset: -90,
                          sections: [
                            for (final (i, entry) in slices.take(6).indexed)
                              PieChartSectionData(
                                color: shadeFor(i, entry.key),
                                value: entry.value,
                                radius: 16,
                                showTitle: false,
                              ),
                          ],
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Total',
                            style: TextStyle(fontSize: 11, color: muted),
                          ),
                          Text(
                            Fmt.compactMoney(total, currency),
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                              color: brand.ink,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    children: [
                      for (final (i, entry) in slices.indexed) ...[
                        if (i > 0) const SizedBox(height: 8),
                        Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: shadeFor(i, entry.key),
                                borderRadius: BorderRadius.circular(5),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                nameFor(entry.key),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: brand.ink,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              Fmt.money(entry.value, currency),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: brand.ink,
                              ),
                            ),
                            SizedBox(
                              width: 36,
                              child: Text(
                                Fmt.percent(entry.value / total),
                                textAlign: TextAlign.right,
                                style: TextStyle(fontSize: 12, color: muted),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
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

class _MiniSegmentButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _MiniSegmentButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final muted = Theme.of(context).colorScheme.outline;
    return BrandTappable(
      onPressed: onTap,
      semanticsLabel: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? brand.ink : Colors.transparent,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            color: selected ? brand.onInk : muted,
          ),
        ),
      ),
    );
  }
}

class _DailySpendingCard extends StatelessWidget {
  final Map<DateTime, double> byDay;
  final DateTime month;
  final double totalExpense;
  final String currency;

  const _DailySpendingCard({
    required this.byDay,
    required this.month,
    required this.totalExpense,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final muted = theme.colorScheme.outline;

    final daysInMonth = DateUtils.getDaysInMonth(month.year, month.month);
    final maxSpend = byDay.values.fold<double>(0, math.max);
    final now = DateTime.now();
    final isCurrentMonth = month.year == now.year && month.month == now.month;
    final elapsedDays = isCurrentMonth
        ? now.day.clamp(1, daysInMonth)
        : daysInMonth;
    final avgPerDay = totalExpense / elapsedDays;

    return Container(
      padding: const EdgeInsets.all(18),
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
                'DAILY SPENDING',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: muted,
                  letterSpacing: 0.8,
                ),
              ),
              Text(
                'Avg ${Fmt.compactMoney(avgPerDay, currency)}/day',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 96,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var d = 1; d <= daysInMonth; d++) ...[
                  if (d > 1) const SizedBox(width: 2),
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final date = DateTime(month.year, month.month, d);
                        final amount = byDay[date] ?? 0;
                        final fraction = maxSpend <= 0
                            ? 0.0
                            : (amount / maxSpend).clamp(0.06, 1.0);
                        final isPeak = amount > 0 && amount == maxSpend;
                        return Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: FractionallySizedBox(
                                  heightFactor: amount <= 0 ? 0.06 : fraction,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: amount <= 0
                                          ? brand.track
                                          : isPeak
                                          ? brand.expenseRoles.graphicOnTint
                                          : brand.expenseRoles.accent
                                                .withValues(alpha: 0.45),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ),
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
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('1', style: TextStyle(fontSize: 10, color: muted)),
              Text('15', style: TextStyle(fontSize: 10, color: muted)),
              Text(
                '$daysInMonth',
                style: TextStyle(fontSize: 10, color: muted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PersonSpendingCard extends StatelessWidget {
  final List<({dynamic person, double amount})> byPerson;
  final double totalExpense;
  final String currency;

  const _PersonSpendingCard({
    required this.byPerson,
    required this.totalExpense,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final muted = theme.colorScheme.outline;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        boxShadow: AppShadows.card(theme.brightness),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SPENDING BY PERSON',
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: muted,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 12),
          for (final (i, entry) in byPerson.indexed) ...[
            if (i > 0) const SizedBox(height: 12),
            Builder(
              builder: (context) {
                final p = entry.person;
                final isSelf = p.isSelf as bool;
                final name = isSelf ? 'Me' : (p.name as String);
                final initials = Fmt.initials(p.name as String);
                final share = totalExpense <= 0
                    ? 0.0
                    : (entry.amount / totalExpense).clamp(0.0, 1.0);
                final pColor = personColor(context, p.color as int);
                final pRoles = brand.roleFor(pColor);
                final barColor = Color.lerp(
                  brand.expenseRoles.graphicOnTint,
                  brand.expenseRoles.tintFill,
                  (i * 0.25).clamp(0.0, 0.65),
                )!;

                return Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isSelf ? brand.ink : pRoles.tintFill,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        initials.isEmpty ? 'M' : initials,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: isSelf ? brand.onInk : pRoles.textOnTint,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                name,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: brand.ink,
                                ),
                              ),
                              Text(
                                Fmt.money(entry.amount, currency),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: brand.ink,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          BrandProgressBar(
                            value: share,
                            height: 6,
                            color: barColor,
                            semanticsLabel: name,
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _SixMonthTrendCard extends StatelessWidget {
  final List<({DateTime month, double income, double expense})> trend;
  final double netThisMonth;
  final DateTime selectedMonth;
  final String currency;

  const _SixMonthTrendCard({
    required this.trend,
    required this.netThisMonth,
    required this.selectedMonth,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final muted = theme.colorScheme.outline;
    final maxExpense = trend.fold<double>(
      0,
      (prev, e) => math.max(prev, e.expense),
    );
    final netPositive = netThisMonth >= 0;

    return Container(
      padding: const EdgeInsets.all(18),
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
                'LAST 6 MONTHS',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: muted,
                  letterSpacing: 0.8,
                ),
              ),
              RichText(
                text: TextSpan(
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 13,
                    color: muted,
                  ),
                  children: [
                    const TextSpan(text: 'Net this month '),
                    TextSpan(
                      text:
                          '${netPositive ? '+ ' : '− '}${Fmt.money(netThisMonth.abs(), currency)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: netPositive
                            ? brand.successRoles.textOnTint
                            : brand.dangerRoles.textOnTint,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final (i, item) in trend.indexed) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final isCurrent =
                            item.month.year == selectedMonth.year &&
                            item.month.month == selectedMonth.month;
                        final fraction = maxExpense <= 0
                            ? 0.08
                            : (item.expense / maxExpense).clamp(0.08, 1.0);
                        final monthLabel = Fmt.monthYear(
                          item.month,
                        ).split(' ').first.substring(0, 3);
                        return Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              Fmt.compactMoney(item.expense, ''),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: isCurrent
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                color: isCurrent ? brand.ink : muted,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Expanded(
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: FractionallySizedBox(
                                  heightFactor: fraction,
                                  child: Container(
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      color: isCurrent
                                          ? brand.expenseRoles.graphicOnTint
                                          : brand.expenseRoles.tintFill,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              monthLabel,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: isCurrent
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                color: isCurrent ? brand.ink : muted,
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
        ],
      ),
    );
  }
}

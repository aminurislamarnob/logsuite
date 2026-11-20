import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/app_settings.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/brand.dart';
import '../../../core/widgets/common.dart';
import '../providers/expenses_provider.dart';
import '../repository/expense_repository.dart';
import 'expense_entry_sheet.dart';
import 'month_stepper.dart';

/// Caps for one month. A month starts empty and is filled either by setting
/// caps or by copying the last month that had any.
class BudgetsTab extends ConsumerWidget {
  const BudgetsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(settingsProvider).currencySymbol;
    final progress = ref.watch(budgetProgressProvider);
    final uncapped = ref.watch(uncappedSpendingProvider).valueOrNull;
    final month = ref.watch(reportMonthProvider);

    return progress.when(
      loading: () => const Center(child: BrandSpinner()),
      error: (e, _) => Text('$e'),
      data: (rows) {
        final overall = rows
            .where((r) => r.budget.categoryId == null)
            .firstOrNull;
        final categoryRows = rows
            .where((r) => r.budget.categoryId != null)
            .toList();

        return ListView(
          padding: pageInsets(context, top: 12, end: PageEnd.fab),
          children: [
            const MonthStepper(),
            const SizedBox(height: 12),
            if (rows.isEmpty)
              _EmptyMonth(
                onSet: () => _editBudget(context, ref),
                uncapped: uncapped,
                currency: currency,
                onCap: (slice) => _cap(context, ref, slice),
              )
            else ...[
              _OverallBudgetHero(
                overall: overall,
                categoryRows: categoryRows,
                month: month,
                currency: currency,
                onTap: () => _editBudget(context, ref, existing: overall),
                onDeleteOverall: overall == null
                    ? null
                    : () => ref
                          .read(expenseRepositoryProvider)
                          .deleteBudget(overall.budget.id),
              ),
              const SizedBox(height: 14),
              if (categoryRows.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: context.brand.surface,
                    borderRadius: BorderRadius.circular(AppRadii.card),
                    boxShadow: AppShadows.card(Theme.of(context).brightness),
                  ),
                  child: Column(
                    children: [
                      for (final (i, p) in categoryRows.indexed) ...[
                        if (i > 0)
                          Divider(
                            height: 1,
                            thickness: 1,
                            color: context.brand.hairline,
                          ),
                        _BudgetRow(
                          progress: p,
                          month: month,
                          currency: currency,
                          onEdit: () => _editBudget(context, ref, existing: p),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              // Every taka the caps above do not cover, so a tab of full bars
              // can never stand for a month that quietly emptied.
              if (uncapped != null) ...[
                _NotBudgeted(
                  uncapped: uncapped,
                  currency: currency,
                  onCap: (slice) => _cap(context, ref, slice),
                ),
                const SizedBox(height: 6),
              ],
              BrandButton(
                label: 'Add a budget',
                icon: AppIcons.add,
                onPressed: () => _editBudget(context, ref),
              ),
            ],
          ],
        );
      },
    );
  }

  /// Acts on one line of the not-budgeted breakdown.
  ///
  /// A category can be capped on the spot. An expense saved without one has
  /// nothing to cap, so that line opens the transactions instead — giving them
  /// a category is the step that has to come first.
  Future<void> _cap(
    BuildContext context,
    WidgetRef ref,
    UncappedSlice slice,
  ) async {
    if (slice.isUncategorised) return _UncategorisedSheet.show(context);
    return _editBudget(
      context,
      ref,
      presetCategoryId: slice.categoryId,
      presetAmount: slice.amount,
    );
  }

  /// Sets a cap for the viewed month, or edits [existing].
  ///
  /// [presetCategoryId] and [presetAmount] arrive from the not-budgeted
  /// breakdown, which knows both the category to cap and what it has already
  /// cost — the obvious opening offer for the cap.
  Future<void> _editBudget(
    BuildContext context,
    WidgetRef ref, {
    BudgetProgress? existing,
    int? presetCategoryId,
    double? presetAmount,
  }) async {
    final month = ref.read(reportMonthProvider);
    final categories = ref.read(categoriesProvider).valueOrNull ?? const [];
    final preset = existing?.budget.amount ?? presetAmount;
    final controller = TextEditingController(
      text: preset == null ? '' : Fmt.amountInput(preset),
    );
    int? categoryId = existing?.budget.categoryId ?? presetCategoryId;

    final saved = await brandSheet<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => SheetScaffold(
          title: existing == null
              ? 'Set budget · ${Fmt.monthYear(month)}'
              : 'Edit budget · ${Fmt.monthYear(month)}',
          actions: [
            BrandButton(
              label: 'Save',
              kind: BrandButtonKind.ghost,
              expand: false,
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BrandField(
                controller: controller,
                label: 'Monthly amount',
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              const SizedBox(height: 16),
              const Text('Applies to'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Pill(
                    label: 'Overall',
                    selected: categoryId == null,
                    color: Theme.of(context).colorScheme.primary,
                    onTap: () => setState(() => categoryId = null),
                  ),
                  ...categories
                      .where((c) => !c.isIncome)
                      .map(
                        (c) => Pill(
                          label: c.name,
                          icon: AppIcons.category(c.icon),
                          selected: categoryId == c.id,
                          color: Theme.of(context).colorScheme.primary,
                          onTap: () => setState(() => categoryId = c.id),
                        ),
                      ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    final amount = double.tryParse(controller.text.trim());
    if (saved != true || amount == null || amount <= 0) return;
    final repo = ref.read(expenseRepositoryProvider);
    // Moving a cap to another category is a different cap, so the old row
    // goes rather than leaving two caps on one month.
    if (existing != null && existing.budget.categoryId != categoryId) {
      await repo.deleteBudget(existing.budget.id);
    }
    await repo.setBudget(amount: amount, categoryId: categoryId, month: month);
  }
}

/// Ink hero card at the top of the Budgets tab showing the overall budget (or
/// the sum of category caps when no overall cap is set) with a progress ring.
class _OverallBudgetHero extends StatelessWidget {
  final BudgetProgress? overall;
  final List<BudgetProgress> categoryRows;
  final DateTime month;
  final String currency;
  final VoidCallback onTap;
  final VoidCallback? onDeleteOverall;

  const _OverallBudgetHero({
    required this.overall,
    required this.categoryRows,
    required this.month,
    required this.currency,
    required this.onTap,
    this.onDeleteOverall,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final isDark = theme.brightness == Brightness.dark;
    final onHero = isDark ? brand.ink : brand.onInk;

    final totalBudget =
        overall?.budget.amount ??
        categoryRows.fold<double>(0, (s, r) => s + r.budget.amount);
    final totalSpent =
        overall?.spent ?? categoryRows.fold<double>(0, (s, r) => s + r.spent);
    final remaining = totalBudget - totalSpent;
    final fraction = totalBudget <= 0 ? 0.0 : totalSpent / totalBudget;

    final now = DateTime.now();
    final isCurrentMonth = month.year == now.year && month.month == now.month;
    final daysInMonth = DateUtils.getDaysInMonth(month.year, month.month);
    final remainingDays = isCurrentMonth
        ? (daysInMonth - now.day + 1).clamp(1, daysInMonth)
        : daysInMonth;
    final perDay = remaining > 0 ? remaining / remainingDays : 0.0;

    final (String badgeText, Color badgeFg) = fraction > 1.0
        ? ('Over budget', brand.dangerRoles.onInk)
        : fraction >= 0.8
        ? ('Almost there', brand.warningRoles.onInk)
        : ('On track', brand.successRoles.onInk);

    final ringColor = fraction > 1.0
        ? brand.dangerRoles.onInk
        : fraction >= 0.8
        ? brand.warningRoles.onInk
        : brand.expenseRoles.onInk;

    return BrandTappable(
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: brand.heroSurface,
          borderRadius: BorderRadius.circular(AppRadii.hero),
          boxShadow: AppShadows.hero(theme.brightness),
        ),
        child: Row(
          children: [
            ProgressRing(
              value: fraction,
              size: 92,
              thickness: 10,
              color: ringColor,
              onInk: true,
              center: Text(
                Fmt.percent(fraction),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: onHero,
                ),
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        overall != null ? 'OVERALL' : 'TOTAL BUDGETED',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: brand.expenseRoles.onInk,
                          letterSpacing: 1.0,
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            height: 24,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: badgeFg.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              badgeText,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: badgeFg,
                              ),
                            ),
                          ),
                          if (onDeleteOverall != null) ...[
                            const SizedBox(width: 6),
                            CircleIconButton(
                              icon: AppIcons.delete,
                              tooltip: 'Delete overall budget',
                              size: 28,
                              onInk: true,
                              onPressed: onDeleteOverall,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  RichText(
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.8,
                        height: 1.1,
                        color: remaining >= 0
                            ? onHero
                            : brand.dangerRoles.onInk,
                      ),
                      children: [
                        TextSpan(
                          text: '${Fmt.money(remaining.abs(), currency)} ',
                        ),
                        TextSpan(
                          text: remaining >= 0 ? 'left' : 'over',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0,
                            color: brand.onInkMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${Fmt.money(totalSpent, currency)} of ${Fmt.money(totalBudget, currency)}'
                    '${remaining > 0 ? ' · ${Fmt.money(perDay, currency)} a day' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: brand.onInkMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The empty state for a month with no caps yet, offering to copy the last
/// month that had some.
class _EmptyMonth extends ConsumerWidget {
  final VoidCallback onSet;
  final String currency;
  final ValueChanged<UncappedSlice> onCap;

  /// The month's spending, when there is some. With no caps at all every taka
  /// of it is unbudgeted, and someone reading an empty budgets tab has already
  /// spent the money — so this is the moment the figure is worth the most.
  final UncappedSpending? uncapped;

  const _EmptyMonth({
    required this.onSet,
    required this.currency,
    required this.onCap,
    required this.uncapped,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(reportMonthProvider);
    final repo = ref.watch(expenseRepositoryProvider);

    return FutureBuilder<DateTime?>(
      future: repo.latestBudgetMonthBefore(month),
      builder: (context, snapshot) {
        final previous = snapshot.data;
        return Column(
          children: [
            EmptyState(
              icon: AppIcons.pieChart,
              title: 'No budgets for ${Fmt.monthYear(month)}',
              message: 'Cap a category or your whole month.',
              actionLabel: 'Set a budget',
              onAction: onSet,
            ),
            if (previous != null) ...[
              const SizedBox(height: 8),
              BrandButton(
                label: "Copy ${Fmt.monthYear(previous)}'s budgets",
                kind: BrandButtonKind.ghost,
                onPressed: () async {
                  final copied = await repo.copyBudgets(
                    from: previous,
                    to: month,
                  );
                  if (context.mounted && copied == 0) {
                    brandToast(context, 'Nothing to copy.');
                  }
                },
              ),
            ],
            if (uncapped != null) ...[
              const SizedBox(height: 24),
              _NotBudgeted(
                uncapped: uncapped!,
                currency: currency,
                onCap: onCap,
                headline:
                    '${Fmt.money(uncapped!.total, currency)} spent, '
                    'none of it budgeted',
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Everything this month's caps do not cover.
///
/// Deliberately not a progress bar: there is no cap here, so there is no
/// fraction to draw and nothing honest to fill. It reports a figure and the
/// categories behind it, each of which can become a cap.
class _NotBudgeted extends ConsumerStatefulWidget {
  final UncappedSpending uncapped;
  final String currency;
  final ValueChanged<UncappedSlice> onCap;

  /// Replaces the default "Not budgeted" heading on the empty month, where the
  /// figure is the whole of the month's spending rather than a remainder.
  final String? headline;

  const _NotBudgeted({
    required this.uncapped,
    required this.currency,
    required this.onCap,
    this.headline,
  });

  /// How many shares are worth naming before the rest collapses. The biggest
  /// three are where capping actually pays.
  static const _visible = 3;

  @override
  ConsumerState<_NotBudgeted> createState() => _NotBudgetedState();
}

class _NotBudgetedState extends ConsumerState<_NotBudgeted> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final slices = widget.uncapped.slices;
    final muted = theme.colorScheme.outline;

    // A month that has ended is a record, not a call to act, so it reports the
    // same figure without the warning colour.
    final month = ref.watch(reportMonthProvider);
    final past = month.isBefore(Fmt.startOfMonth(DateTime.now()));
    final accent = past ? muted : brand.warning;

    final shown = _expanded
        ? slices
        : slices.take(_NotBudgeted._visible).toList();
    final hidden = slices.length - shown.length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
            child: Row(
              children: [
                if (!past) ...[
                  AppIcon(AppIcons.warning, size: 16, color: accent),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    widget.headline ?? 'Not budgeted',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
                  ),
                ),
                if (widget.headline == null)
                  Text(
                    '${Fmt.money(widget.uncapped.total, widget.currency)} uncapped',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: accent,
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 2, 8, 2),
            decoration: BoxDecoration(
              color: brand.surface,
              borderRadius: BorderRadius.circular(22),
              boxShadow: AppShadows.card(theme.brightness),
            ),
            child: Column(
              children: [
                for (final (i, slice) in shown.indexed) ...[
                  if (i > 0)
                    Divider(height: 1, thickness: 1, color: brand.hairline),
                  BrandTappable(
                    onPressed: () => widget.onCap(slice),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              slice.label,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: brand.ink,
                              ),
                            ),
                          ),
                          Text(
                            Fmt.money(slice.amount, widget.currency),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: brand.ink,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            height: 36,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            alignment: Alignment.center,
                            child: Text(
                              slice.isUncategorised
                                  ? 'Categorise'
                                  : 'Set a budget',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: brand.expenseRoles.textOnTint,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (hidden > 0 || _expanded)
            Align(
              alignment: Alignment.centerLeft,
              child: BrandButton(
                label: _expanded ? 'Show less' : '+ $hidden more',
                kind: BrandButtonKind.ghost,
                small: true,
                expand: false,
                onPressed: () => setState(() => _expanded = !_expanded),
              ),
            ),
        ],
      ),
    );
  }
}

/// The month's expenses that were saved without a category.
///
/// They count toward what is not budgeted but cannot be capped, so this offers
/// the step that unblocks that: open one and give it a category.
class _UncategorisedSheet extends ConsumerWidget {
  const _UncategorisedSheet();

  static Future<void> show(BuildContext context) =>
      brandSheet(context: context, builder: (_) => const _UncategorisedSheet());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(settingsProvider).currencySymbol;
    final rows = ref.watch(monthTransactionsProvider).valueOrNull ?? const [];
    final muted = Theme.of(context).colorScheme.outline;
    final uncategorised = rows
        .where((t) => t.kind == TxKind.expense && t.categoryId == null)
        .toList();

    return SheetScaffold(
      title: 'Uncategorised',
      child: uncategorised.isEmpty
          ? const EmptyState(
              icon: AppIcons.checkCircle,
              title: 'All categorised',
              message: 'Every expense this month has a category.',
            )
          : TileColumn(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final tx in uncategorised)
                  BrandTile(
                    dense: true,
                    leading: AppIcon(AppIcons.info, color: muted, size: 20),
                    title: Text(
                      tx.note?.isNotEmpty == true ? tx.note! : 'Expense',
                    ),
                    subtitle: Text(
                      Fmt.dayMonthYear(tx.date),
                      style: TextStyle(fontSize: 11, color: muted),
                    ),
                    trailing: Text(
                      Fmt.money(tx.amount, currency),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      ExpenseEntrySheet.edit(context, tx);
                    },
                  ),
              ],
            ),
    );
  }
}

class _BudgetRow extends ConsumerWidget {
  final BudgetProgress progress;
  final DateTime month;
  final String currency;
  final VoidCallback onEdit;

  const _BudgetRow({
    required this.progress,
    required this.month,
    required this.currency,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = progress;
    final brand = context.brand;
    final muted = Theme.of(context).colorScheme.outline;

    final tierColor = switch (p.alertTier) {
      100 => brand.danger,
      80 => brand.warningRoles.graphicOnTint,
      _ => brand.expenseRoles.graphicOnTint,
    };

    final now = DateTime.now();
    final isCurrentMonth = month.year == now.year && month.month == now.month;
    final daysInMonth = DateUtils.getDaysInMonth(month.year, month.month);
    final daysLeft = isCurrentMonth ? (daysInMonth - now.day).clamp(0, 31) : 0;

    final String statusText;
    final Color statusColor;
    final FontWeight statusWeight;
    if (p.remaining < 0) {
      statusText = '${Fmt.money(-p.remaining, currency)} over';
      statusColor = brand.dangerRoles.textOnTint;
      statusWeight = FontWeight.w700;
    } else if (p.alertTier >= 80) {
      statusText = 'Almost there · ${Fmt.money(p.remaining, currency)} left';
      statusColor = brand.warningRoles.textOnTint;
      statusWeight = FontWeight.w700;
    } else {
      statusText =
          '${Fmt.money(p.remaining, currency)} left'
          '${isCurrentMonth && daysLeft > 0 ? ' · $daysLeft days to go' : ''}';
      statusColor = muted;
      statusWeight = FontWeight.w500;
    }

    return BrandTappable(
      onPressed: onEdit,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(
                    p.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: brand.ink,
                    ),
                  ),
                ),
                RichText(
                  text: TextSpan(
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: brand.ink,
                    ),
                    children: [
                      TextSpan(text: Fmt.money(p.spent, currency)),
                      TextSpan(
                        text: ' / ${Fmt.money(p.budget.amount, currency)}',
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            BrandProgressBar(
              value: p.fraction,
              height: 8,
              color: tierColor,
              semanticsLabel: p.label,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: statusWeight,
                      color: statusColor,
                    ),
                  ),
                ),
                CircleIconButton(
                  icon: AppIcons.edit,
                  tooltip: 'Edit',
                  size: 32,
                  onPressed: onEdit,
                ),
                const SizedBox(width: 4),
                CircleIconButton(
                  icon: AppIcons.delete,
                  tooltip: 'Delete',
                  size: 32,
                  onPressed: () => ref
                      .read(expenseRepositoryProvider)
                      .deleteBudget(p.budget.id),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

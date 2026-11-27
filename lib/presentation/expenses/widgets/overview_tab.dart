import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/people/people_repository.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/widgets/brand.dart';
import '../../../core/widgets/common.dart';
import '../providers/expenses_provider.dart';
import '../repository/expense_repository.dart';
import '../utils/expense_reminders.dart';
import 'accounts_sheet.dart';
import 'expense_entry_sheet.dart';

class OverviewTab extends ConsumerWidget {
  const OverviewTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(settingsProvider).currencySymbol;
    final recent = ref.watch(recentExpensesProvider);
    final overall = ref.watch(currentOverallBudgetProvider).valueOrNull;
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];
    final recurring = ref.watch(recurringProvider).valueOrNull ?? const [];
    final dueBill = recurring.where((b) {
      final days = Fmt.dateOnly(
        b.nextDueDate,
      ).difference(Fmt.dateOnly(DateTime.now())).inDays;
      return days <= 7;
    }).firstOrNull;

    return ListView(
      padding: pageInsets(context, top: 14, end: PageEnd.fab),
      children: [
        _SummaryCard(overall: overall),
        const SizedBox(height: 14),
        _AccountsStrip(accounts: accounts, currency: currency),
        const SizedBox(height: 18),
        recent.when(
          data: (rows) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(
                'Recent',
                actionLabel: rows.isEmpty ? null : 'All ${rows.length}',
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              ),
              if (rows.isEmpty)
                const EmptyState(
                  icon: AppIcons.bills,
                  title: 'No transactions yet',
                  message: 'Tap Add to record your first one.',
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: context.brand.surface,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: AppShadows.card(Theme.of(context).brightness),
                  ),
                  child: Column(
                    children: [
                      for (final (i, tx) in rows.indexed) ...[
                        if (i > 0)
                          Divider(
                            height: 1,
                            thickness: 1,
                            color: context.brand.hairline,
                          ),
                        _TxTile(tx: tx),
                      ],
                    ],
                  ),
                ),
            ],
          ),
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: BrandSpinner()),
          ),
          error: (e, _) => Text('$e'),
        ),
        if (dueBill != null) ...[
          const SizedBox(height: 14),
          _DueBillBanner(bill: dueBill, currency: currency),
        ],
      ],
    );
  }
}

/// Ink hero card showing spent this month, optional budget pace bar, and
/// three translucent sub-tiles (Income, Left to spend / Net, Per day).
class _SummaryCard extends ConsumerWidget {
  final BudgetProgress? overall;

  const _SummaryCard({required this.overall});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final isDark = theme.brightness == Brightness.dark;
    final onHero = isDark ? brand.ink : brand.onInk;

    final currency = ref.watch(settingsProvider).currencySymbol;
    final report = ref.watch(currentMonthReportProvider).valueOrNull;
    final spent = report?.expense ?? 0;

    final now = DateTime.now();
    final daysInMonth = DateUtils.getDaysInMonth(now.year, now.month);
    final dayFraction = (now.day / daysInMonth).clamp(0.0, 1.0);
    final elapsedDays = now.day.clamp(1, daysInMonth);
    final remainingDays = (daysInMonth - now.day + 1).clamp(1, daysInMonth);

    final budget = overall;
    final change = report?.changeVsPrevious;
    final changeLabel = change == null
        ? null
        : '${change >= 0 ? '+' : ''}${(change * 100).toStringAsFixed(0)}% vs last mo';

    final (String statusLabel, Color statusFg) = budget == null
        ? ('', brand.successRoles.onInk)
        : budget.fraction > 1.0
        ? ('Over budget', brand.dangerRoles.onInk)
        : (budget.alertTier >= 80 || budget.fraction > dayFraction + 0.15)
        ? ('Watch pace', brand.warningRoles.onInk)
        : ('On track', brand.successRoles.onInk);

    final barColor = budget == null
        ? brand.expenseRoles.onInk
        : budget.alertTier >= 100
        ? brand.dangerRoles.onInk
        : budget.alertTier >= 80
        ? brand.warningRoles.onInk
        : brand.expenseRoles.onInk;

    final middleLabel = budget != null ? 'Left to spend' : 'Net';
    final middleValue = budget != null
        ? Fmt.compactMoney(budget.remaining, currency)
        : (report == null ? '—' : Fmt.compactMoney(report.net, currency));

    final perDayValue = budget != null
        ? Fmt.compactMoney(
            budget.remaining > 0 ? budget.remaining / remainingDays : 0,
            currency,
          )
        : (report == null
              ? '—'
              : Fmt.compactMoney(spent / elapsedDays, currency));

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
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
                      'SPENT THIS MONTH',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: brand.expenseRoles.onInk,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      Fmt.money(spent, currency),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.displayLarge?.copyWith(
                        fontSize: 44,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -2.0,
                        height: 1.0,
                        color: onHero,
                      ),
                    ),
                  ],
                ),
              ),
              if (budget != null)
                Container(
                  height: 28,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: statusFg.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: statusFg,
                    ),
                  ),
                )
              else if (changeLabel != null)
                Container(
                  height: 28,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    changeLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: brand.onInkMuted,
                    ),
                  ),
                ),
            ],
          ),
          if (budget != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              height: 16,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Container(
                    height: 10,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: budget.fraction.clamp(0.0, 1.0),
                    child: Container(
                      height: 10,
                      decoration: BoxDecoration(
                        color: barColor,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment(dayFraction * 2 - 1, 0),
                    child: Container(
                      width: 2,
                      height: 16,
                      decoration: BoxDecoration(
                        color: onHero,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${Fmt.percent(budget.fraction)} of ${Fmt.money(budget.budget.amount, currency)} budget',
                  style: TextStyle(fontSize: 12, color: brand.onInkMuted),
                ),
                Text(
                  'Day ${now.day} of $daysInMonth',
                  style: TextStyle(fontSize: 12, color: brand.onInkMuted),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _HeroSubTile(
                  label: 'Income',
                  value: report == null
                      ? '—'
                      : Fmt.compactMoney(report.income, currency),
                  onHero: onHero,
                  muted: brand.onInkMuted,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _HeroSubTile(
                  label: middleLabel,
                  value: middleValue,
                  onHero: onHero,
                  muted: brand.onInkMuted,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _HeroSubTile(
                  label: 'Per day',
                  value: perDayValue,
                  onHero: onHero,
                  muted: brand.onInkMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroSubTile extends StatelessWidget {
  final String label;
  final String value;
  final Color onHero;
  final Color muted;

  const _HeroSubTile({
    required this.label,
    required this.value,
    required this.onHero,
    required this.muted,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppRadii.field),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: muted),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: onHero,
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontal row of white account mini-cards; tapping opens [AccountsSheet].
class _AccountsStrip extends StatelessWidget {
  final List<Account> accounts;
  final String currency;

  const _AccountsStrip({required this.accounts, required this.currency});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final muted = theme.colorScheme.outline;

    if (accounts.isEmpty) {
      return BrandTappable(
        onPressed: () => AccountsSheet.show(context),
        semanticsLabel: 'Accounts',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: brand.surface,
            borderRadius: BorderRadius.circular(18),
            boxShadow: AppShadows.card(theme.brightness),
          ),
          child: Row(
            children: [
              AppIcon(AppIcons.expenses, size: 18, color: brand.ink),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Manage accounts',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: brand.ink,
                  ),
                ),
              ),
              AppIcon(AppIcons.chevronRight, size: 18, color: muted),
            ],
          ),
        ),
      );
    }

    Widget buildCard(Account a) {
      return BrandTappable(
        onPressed: () => AccountsSheet.show(context),
        semanticsLabel: '${a.name} ${Fmt.money(a.balance, currency)}',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: brand.surface,
            borderRadius: BorderRadius.circular(18),
            boxShadow: AppShadows.card(theme.brightness),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                a.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: muted,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                Fmt.compactMoney(a.balance, currency),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: brand.ink,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (accounts.length <= 4) {
      return Row(
        children: [
          for (final (i, a) in accounts.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: buildCard(a)),
          ],
        ],
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (i, a) in accounts.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 86),
              child: buildCard(a),
            ),
          ],
        ],
      ),
    );
  }
}

class _DueBillBanner extends ConsumerWidget {
  final RecurringExpense bill;
  final String currency;

  const _DueBillBanner({required this.bill, required this.currency});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final roles = brand.warningRoles;
    final repo = ref.read(expenseRepositoryProvider);
    final reminders = ref.read(expenseRemindersProvider);

    final days = Fmt.dateOnly(
      bill.nextDueDate,
    ).difference(Fmt.dateOnly(DateTime.now())).inDays;
    final dueLabel = days < 0
        ? 'overdue'
        : days == 0
        ? 'due today'
        : days == 1
        ? 'due tomorrow'
        : 'due in $days days';

    return BrandTappable(
      onPressed: () async {
        final next = await repo.payRecurring(bill);
        await reminders.syncBill(next);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: roles.tintFill,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            AppIcon(AppIcons.bills, size: 20, color: roles.textOnTint),
            const SizedBox(width: 12),
            Expanded(
              child: RichText(
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: brand.ink,
                  ),
                  children: [
                    TextSpan(text: '${bill.name} $dueLabel '),
                    TextSpan(
                      text: '· ${Fmt.money(bill.amount, currency)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: roles.textOnTint,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Pay',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: roles.textOnTint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TxTile extends ConsumerWidget {
  final Expense tx;
  const _TxTile({required this.tx});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final currency = ref.watch(settingsProvider).currencySymbol;
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const [];
    final accounts = ref.watch(allAccountsProvider).valueOrNull ?? const [];
    final cat = categories.where((c) => c.id == tx.categoryId).firstOrNull;
    final account = accounts.where((a) => a.id == tx.accountId).firstOrNull;
    final people = ref.watch(peopleProvider).valueOrNull ?? const [];
    final person = people.where((p) => p.id == tx.personId).firstOrNull;
    final loans = ref.watch(loansProvider).valueOrNull ?? const [];
    final loan = loans.where((l) => l.id == tx.loanId).firstOrNull;
    final muted = Theme.of(context).colorScheme.outline;

    // Money coming in: income, a loan taken, or a lent loan being repaid.
    final inbound = switch (tx.kind) {
      TxKind.income || TxKind.borrow => true,
      TxKind.repayment => loan?.direction != LoanDirection.borrowed,
      _ => false,
    };
    final isLoan = TxKind.isLoan(tx.kind);

    final roles = switch (tx.kind) {
      TxKind.income => brand.habitRoles,
      TxKind.transfer => brand.taskRoles,
      _ when isLoan => brand.taskRoles,
      _ => brand.expenseRoles,
    };
    final icon = switch (tx.kind) {
      TxKind.income => AppIcons.arrowUp,
      TxKind.transfer => AppIcons.transfer,
      TxKind.lend => AppIcons.arrowUp,
      TxKind.borrow => AppIcons.arrowDown,
      TxKind.repayment => inbound ? AppIcons.arrowDown : AppIcons.arrowUp,
      _ => AppIcons.category(cat?.icon ?? 'other'),
    };
    final sign = tx.kind == TxKind.transfer ? '' : (inbound ? '+ ' : '− ');
    final fallbackTitle = switch (tx.kind) {
      TxKind.income => cat?.name ?? 'Income',
      TxKind.transfer => 'Transfer',
      TxKind.lend => 'Lent',
      TxKind.borrow => 'Borrowed',
      TxKind.repayment => inbound ? 'Repayment received' : 'Repayment made',
      _ => cat?.name ?? 'Expense',
    };

    final subtitleParts = <String>[
      if (cat != null && !isLoan && tx.kind != TxKind.transfer) cat.name,
      if (account != null) account.name,
      Fmt.relativeDay(tx.date),
      if (person != null && !person.isSelf) person.name,
    ];

    final isLoanPrincipal = TxKind.isLoanPrincipal(tx.kind);
    final isLoanRow = tx.loanId != null;

    return Dismissible(
      key: ValueKey('tx-${tx.id}'),
      direction: isLoanPrincipal
          ? DismissDirection.none
          : DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: brand.danger,
          borderRadius: BorderRadius.circular(16),
        ),
        child: AppIcon(AppIcons.delete, color: brand.onAccent(brand.danger)),
      ),
      onDismissed: (_) {
        AppHaptics.heavy();
        _delete(context, ref);
      },
      child: BrandTappable(
        onPressed: isLoanRow ? null : () => ExpenseEntrySheet.edit(context, tx),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: roles.tintFill,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: AppIcon(icon, color: roles.graphicOnTint, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tx.note?.isNotEmpty == true && !isLoan
                          ? tx.note!
                          : fallbackTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: brand.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitleParts.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$sign${Fmt.money(tx.amount, currency)}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: inbound ? brand.successRoles.textOnTint : brand.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Deletes the row, offering to put it back — id and all, so a receipt or
  /// loan link survives the round trip.
  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(expenseRepositoryProvider);
    final reminders = ref.read(expenseRemindersProvider);
    final deleted = await repo.deleteTransaction(tx.id);
    if (deleted == null) return;
    final loanId = deleted.loanId;
    if (loanId != null) await reminders.syncLoan(loanId);
    if (!context.mounted) return;
    brandToast(
      context,
      'Transaction deleted',
      actionLabel: 'Undo',
      onAction: () async {
        await repo.restoreTransaction(deleted);
        if (loanId != null) await reminders.syncLoan(loanId);
      },
    );
  }
}

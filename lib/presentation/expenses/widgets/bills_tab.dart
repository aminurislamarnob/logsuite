import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/brand.dart';
import '../../../core/widgets/common.dart';
import '../providers/expenses_provider.dart';
import '../repository/expense_repository.dart';
import '../utils/expense_reminders.dart';
import 'expense_entry_sheet.dart';

class BillsTab extends ConsumerWidget {
  const BillsTab({super.key});

  static double _monthlyEquivalent(RecurringExpense b) => switch (b.period) {
    'daily' => b.amount * 30,
    'weekly' => b.amount * 52 / 12,
    'yearly' => b.amount / 12,
    _ => b.amount,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final muted = theme.colorScheme.outline;
    final currency = ref.watch(settingsProvider).currencySymbol;
    final bills = ref.watch(recurringProvider);
    final accounts = ref.watch(allAccountsProvider).valueOrNull ?? const [];

    return bills.when(
      loading: () => const Center(child: BrandSpinner()),
      error: (e, _) => Text('$e'),
      data: (rows) {
        if (rows.isEmpty) {
          return EmptyState(
            icon: AppIcons.calendarRepeat,
            title: 'No bills or subscriptions',
            message: 'Track rent, internet, Netflix — anything recurring.',
            actionLabel: 'Add a bill',
            onAction: () => ExpenseEntrySheet.show(
              context,
              kind: ExpenseEntrySheet.billMode,
            ),
          );
        }

        final now = Fmt.dateOnly(DateTime.now());
        final endOfMonth = Fmt.dateOnly(Fmt.endOfMonth(now));
        final dueThisMonth = rows.where((b) {
          final due = Fmt.dateOnly(b.nextDueDate);
          return !due.isAfter(endOfMonth);
        }).toList();
        final dueSoonTotal = dueThisMonth.fold<double>(
          0,
          (sum, b) => sum + b.amount,
        );
        final monthlyTotal = rows.fold<double>(
          0,
          (sum, b) => sum + _monthlyEquivalent(b),
        );

        final regularBills = rows.where((b) => !b.isSubscription).toList();
        final subscriptions = rows.where((b) => b.isSubscription).toList();

        return ListView(
          padding: pageInsets(context, top: 14, end: PageEnd.fab),
          children: [
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: brand.surface,
                      borderRadius: BorderRadius.circular(AppRadii.tile),
                      boxShadow: AppShadows.card(theme.brightness),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Due this month',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: muted,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          Fmt.money(dueSoonTotal, currency),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6,
                            color: brand.ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${dueThisMonth.length == 1 ? '1 bill' : '${dueThisMonth.length} bills'} unpaid',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: brand.expenseRoles.tintFill,
                      borderRadius: BorderRadius.circular(AppRadii.tile),
                      boxShadow: AppShadows.card(theme.brightness),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Monthly total',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: brand.expenseRoles.textOnTint,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          Fmt.money(monthlyTotal, currency),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6,
                            color: brand.ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          rows.length == 1
                              ? '1 recurring bill'
                              : '${rows.length} bills & subscriptions',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: brand.expenseRoles.textOnTint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (regularBills.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Text(
                  dueThisMonth.any((b) => !b.isSubscription)
                      ? 'DUE SOON'
                      : 'BILLS',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: muted,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              for (final b in regularBills)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _BillCard(
                    bill: b,
                    account: accounts
                        .where((a) => a.id == b.accountId)
                        .firstOrNull,
                    currency: currency,
                  ),
                ),
            ],
            if (subscriptions.isNotEmpty) ...[
              if (regularBills.isNotEmpty) const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Text(
                  'SUBSCRIPTIONS',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: muted,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              for (final b in subscriptions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _BillCard(
                    bill: b,
                    account: accounts
                        .where((a) => a.id == b.accountId)
                        .firstOrNull,
                    currency: currency,
                  ),
                ),
            ],
            const SizedBox(height: 6),
            Center(
              child: BrandButton(
                label: 'Add a bill',
                icon: AppIcons.add,
                expand: false,
                onPressed: () => ExpenseEntrySheet.show(
                  context,
                  kind: ExpenseEntrySheet.billMode,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BillCard extends ConsumerWidget {
  final RecurringExpense bill;
  final Account? account;
  final String currency;

  const _BillCard({
    required this.bill,
    required this.account,
    required this.currency,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final muted = theme.colorScheme.outline;
    final repo = ref.read(expenseRepositoryProvider);
    final reminders = ref.read(expenseRemindersProvider);

    final dueInDays = Fmt.dateOnly(
      bill.nextDueDate,
    ).difference(Fmt.dateOnly(DateTime.now())).inDays;
    final overdue = dueInDays < 0;

    final chipRoles = overdue ? brand.dangerRoles : brand.expenseRoles;
    final periodLabel = bill.period[0].toUpperCase() + bill.period.substring(1);

    final subtitle = overdue
        ? 'Overdue · due ${Fmt.relativeDay(bill.nextDueDate)}'
        : '$periodLabel · due ${Fmt.relativeDay(bill.nextDueDate)}'
              '${account == null ? '' : ' · ${account!.name}'}';

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(22),
        border: overdue ? Border.all(color: brand.danger, width: 2) : null,
        boxShadow: AppShadows.card(theme.brightness),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: chipRoles.tintFill,
              borderRadius: BorderRadius.circular(15),
            ),
            child: AppIcon(
              bill.isSubscription ? AppIcons.subscription : AppIcons.bills,
              size: 22,
              color: overdue ? chipRoles.textOnTint : chipRoles.graphicOnTint,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bill.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: brand.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: overdue ? FontWeight.w700 : FontWeight.w500,
                    color: overdue ? brand.dangerRoles.textOnTint : muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            Fmt.money(bill.amount, currency),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: brand.ink,
            ),
          ),
          const SizedBox(width: 10),
          BrandTappable(
            onPressed: () async {
              final next = await repo.payRecurring(bill);
              await reminders.syncBill(next);
            },
            semanticsLabel: 'Pay ${bill.name}',
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: ShapeDecoration(
                color: brand.ink,
                shape: const StadiumBorder(),
              ),
              child: Text(
                'Pay',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: brand.onInk,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          CircleIconButton(
            icon: AppIcons.delete,
            tooltip: 'Delete',
            size: 36,
            onPressed: () async {
              await repo.deleteRecurring(bill.id);
              await reminders.cancelBill(bill.id);
            },
          ),
        ],
      ),
    );
  }
}

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
import '../utils/expense_reminders.dart';
import 'loan_sheet.dart';

/// Money lent and borrowed. The principal and every repayment are real
/// ledger rows, so balances stay right while none of it counts as spending.
class LoansTab extends ConsumerStatefulWidget {
  const LoansTab({super.key});

  @override
  ConsumerState<LoansTab> createState() => _LoansTabState();
}

class _LoansTabState extends ConsumerState<LoansTab> {
  int? _directionFilter;
  bool _showSettled = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final muted = theme.colorScheme.outline;
    final currency = ref.watch(settingsProvider).currencySymbol;
    final rows = ref.watch(loanRowsProvider);
    final totals = ref.watch(loanTotalsProvider).valueOrNull;

    return rows.when(
      loading: () => const Center(child: BrandSpinner()),
      error: (e, _) => Text('$e'),
      data: (loans) {
        if (loans.isEmpty) {
          return EmptyState(
            icon: AppIcons.transfer,
            title: 'No loans',
            message: 'Track what you lent out and what you owe.',
            actionLabel: 'Add a loan',
            onAction: () => LoanSheet.show(context),
          );
        }

        final allOpen = loans.where((r) => !r.isSettled).toList();
        final open = _directionFilter == null
            ? allOpen
            : allOpen
                  .where((r) => r.loan.direction == _directionFilter)
                  .toList();
        final settled = loans.where((r) => r.isSettled).toList();

        final lentPeople = allOpen
            .where((r) => r.isLent)
            .map((r) => r.loan.personId)
            .toSet()
            .length;
        final borrowedPeople = allOpen
            .where((r) => !r.isLent)
            .map((r) => r.loan.personId)
            .toSet()
            .length;

        return ListView(
          padding: pageInsets(context, top: 14, end: PageEnd.fab),
          children: [
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: brand.habitRoles.tintFill,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: AppShadows.card(theme.brightness),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            AppIcon(
                              AppIcons.arrowDown,
                              size: 14,
                              color: brand.habitRoles.textOnTint,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Owed to me',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: brand.habitRoles.textOnTint,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          Fmt.money(totals?.owedToMe ?? 0, currency),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.8,
                            height: 1.1,
                            color: brand.ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          lentPeople == 1 ? '1 person' : '$lentPeople people',
                          style: TextStyle(
                            fontSize: 12,
                            color: brand.habitRoles.textOnTint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: brand.warningRoles.tintFill,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: AppShadows.card(theme.brightness),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            AppIcon(
                              AppIcons.arrowUp,
                              size: 14,
                              color: brand.warningRoles.textOnTint,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'I owe',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: brand.warningRoles.textOnTint,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          Fmt.money(totals?.iOwe ?? 0, currency),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.8,
                            height: 1.1,
                            color: brand.ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          borrowedPeople == 1
                              ? '1 person'
                              : '$borrowedPeople people',
                          style: TextStyle(
                            fontSize: 12,
                            color: brand.warningRoles.textOnTint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _DirectionFilterBar(
              selected: _directionFilter,
              onSelected: (v) => setState(() => _directionFilter = v),
            ),
            const SizedBox(height: 14),
            for (final r in open)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _LoanCard(row: r, currency: currency),
              ),
            if (settled.isNotEmpty) ...[
              const SizedBox(height: 2),
              BrandTappable(
                onPressed: () => setState(() => _showSettled = !_showSettled),
                child: Container(
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: brand.well,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      AppIcon(AppIcons.check, size: 18, color: muted),
                      const SizedBox(width: 12),
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: brand.ink,
                            ),
                            children: [
                              const TextSpan(text: 'Settled '),
                              TextSpan(
                                text:
                                    '· ${settled.length == 1 ? '1 loan' : '${settled.length} loans'}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      AppIcon(
                        _showSettled
                            ? AppIcons.chevronDown
                            : AppIcons.chevronRight,
                        size: 16,
                        color: muted,
                      ),
                    ],
                  ),
                ),
              ),
              if (_showSettled) ...[
                const SizedBox(height: 10),
                for (final r in settled)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _LoanCard(row: r, currency: currency),
                  ),
              ],
              const SizedBox(height: 12),
            ],
            Center(
              child: BrandButton(
                label: 'Add a loan',
                icon: AppIcons.add,
                expand: false,
                onPressed: () => LoanSheet.show(context),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DirectionFilterBar extends StatelessWidget {
  final int? selected;
  final ValueChanged<int?> onSelected;

  const _DirectionFilterBar({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final muted = theme.colorScheme.outline;
    final options = <(int?, String)>[
      (null, 'All'),
      (LoanDirection.lent, 'Lent'),
      (LoanDirection.borrowed, 'Borrowed'),
    ];

    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: brand.well,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          for (final (value, label) in options)
            Expanded(
              child: BrandTappable(
                onPressed: () => onSelected(value),
                semanticsLabel: label,
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected == value
                        ? brand.surface
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: selected == value
                        ? AppShadows.circleButton(theme.brightness)
                        : const [],
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected == value
                          ? FontWeight.w700
                          : FontWeight.w600,
                      color: selected == value ? brand.ink : muted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LoanCard extends ConsumerWidget {
  final LoanRow row;
  final String currency;

  const _LoanCard({required this.row, required this.currency});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final muted = theme.colorScheme.outline;
    final days = row.dueInDays;
    final overdue = !row.isSettled && days != null && days < 0;

    final avatarRoles = row.isLent ? brand.taskRoles : brand.medicineRoles;
    final statusRoles = overdue
        ? brand.dangerRoles
        : (row.isLent ? brand.habitRoles : brand.warningRoles);

    final personName = row.person?.name ?? (row.isLent ? 'Lent' : 'Borrowed');
    final initials = Fmt.initials(personName);

    final statusLine = [
      row.isLent ? 'Lent' : 'Borrowed',
      if (row.isSettled)
        'Settled'
      else if (row.loan.dueDate != null)
        'due ${Fmt.relativeDay(row.loan.dueDate!)}',
    ].join(' · ');

    final progressLine = [
      'Repaid ${Fmt.money(row.repaid, currency)}',
      if (row.person != null && row.person!.relation.isNotEmpty)
        row.person!.relation,
      if (row.loan.note?.isNotEmpty == true) row.loan.note!,
    ].join(' · ');

    final fraction = row.loan.principal <= 0
        ? 0.0
        : (row.repaid / row.loan.principal).clamp(0.0, 1.0);

    return Container(
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
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: avatarRoles.tintFill,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  initials.isEmpty ? (row.isLent ? 'L' : 'B') : initials,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: avatarRoles.textOnTint,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      personName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: brand.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      statusLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: row.isSettled ? muted : statusRoles.textOnTint,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    Fmt.money(
                      row.isSettled ? row.loan.principal : row.outstanding,
                      currency,
                    ),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                      color: brand.ink,
                    ),
                  ),
                  if (!row.isSettled)
                    Text(
                      'of ${Fmt.money(row.loan.principal, currency)}',
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          BrandProgressBar(
            value: fraction,
            height: 8,
            color: statusRoles.graphicOnTint,
            semanticsLabel: 'Repaid',
          ),
          const SizedBox(height: 6),
          Text(
            progressLine,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: muted),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              if (!row.isSettled) ...[
                Expanded(
                  child: BrandButton(
                    label: row.isLent ? 'Repayment received' : 'Repay',
                    small: true,
                    onPressed: () => RepaySheet.show(context, row),
                  ),
                ),
                const SizedBox(width: 8),
              ] else
                const Spacer(),
              CircleIconButton(
                icon: AppIcons.delete,
                tooltip: 'Delete',
                size: 42,
                onPressed: () => _delete(context, ref),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await brandConfirm(
      context,
      title: 'Delete this loan?',
      message:
          'Its principal and repayments are removed and the accounts '
          'get their money back.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (ok) {
      await ref.read(expenseRepositoryProvider).deleteLoan(row.loan.id);
      await ref.read(expenseRemindersProvider).cancelLoan(row.loan.id);
    }
  }
}

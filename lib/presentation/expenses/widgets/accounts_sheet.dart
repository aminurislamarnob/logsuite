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

/// Every account with its balance, plus the tools to add, edit, archive and
/// transfer money between them. Archived accounts keep their history and drop
/// out of the total.
class AccountsSheet extends ConsumerStatefulWidget {
  const AccountsSheet({super.key});

  static Future<void> show(BuildContext context) =>
      brandSheet(context: context, builder: (_) => const AccountsSheet());

  @override
  ConsumerState<AccountsSheet> createState() => _AccountsSheetState();
}

class _AccountsSheetState extends ConsumerState<AccountsSheet> {
  final _transferAmount = TextEditingController();
  int? _fromId;
  int? _toId;
  bool _showArchived = false;

  @override
  void dispose() {
    _transferAmount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final muted = theme.colorScheme.outline;
    final currency = ref.watch(settingsProvider).currencySymbol;
    final accounts = ref.watch(allAccountsProvider).valueOrNull ?? const [];
    final active = accounts.where((a) => !a.isArchived).toList();
    final archived = accounts.where((a) => a.isArchived).toList();
    final total = active.fold<double>(0, (sum, a) => sum + a.balance);

    if (active.length >= 2) {
      if (_fromId == null || !active.any((a) => a.id == _fromId)) {
        _fromId = active.first.id;
      }
      if (_toId == null ||
          _toId == _fromId ||
          !active.any((a) => a.id == _toId)) {
        _toId = active.firstWhere((a) => a.id != _fromId).id;
      }
    }

    return SheetScaffold(
      title: 'Accounts',
      actions: [
        CircleIconButton(
          icon: AppIcons.add,
          tooltip: 'Add account',
          size: 40,
          onPressed: () => _editAccount(context, ref),
        ),
        CircleIconButton(
          icon: AppIcons.close,
          tooltip: 'Close',
          size: 40,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RichText(
            text: TextSpan(
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 14,
                color: muted,
              ),
              children: [
                const TextSpan(text: 'Total '),
                TextSpan(
                  text: Fmt.money(total, currency),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: brand.ink,
                  ),
                ),
                TextSpan(text: ' across ${active.length}'),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (active.isNotEmpty)
            Container(
              padding: const EdgeInsets.fromLTRB(14, 2, 6, 2),
              decoration: BoxDecoration(
                color: brand.surface,
                borderRadius: BorderRadius.circular(AppRadii.card),
                boxShadow: AppShadows.card(theme.brightness),
              ),
              child: Column(
                children: [
                  for (final (i, a) in active.indexed) ...[
                    if (i > 0)
                      Divider(height: 1, thickness: 1, color: brand.hairline),
                    _AccountRow(
                      account: a,
                      currency: currency,
                      isDefault: i == 0,
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: BrandTappable(
                  onPressed: () => _editAccount(context, ref),
                  semanticsLabel: 'Add account',
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: brand.outlineIdle, width: 1.5),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AppIcon(AppIcons.add, size: 18, color: brand.ink),
                        const SizedBox(width: 6),
                        Text(
                          'Add account',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: brand.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (archived.isNotEmpty) ...[
                const SizedBox(width: 8),
                BrandTappable(
                  onPressed: () =>
                      setState(() => _showArchived = !_showArchived),
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _showArchived ? brand.well : Colors.transparent,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Text(
                      'Archived · ${archived.length}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: muted,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (archived.isNotEmpty && _showArchived) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 2, 6, 2),
              decoration: BoxDecoration(
                color: brand.surface,
                borderRadius: BorderRadius.circular(AppRadii.card),
                boxShadow: AppShadows.card(theme.brightness),
              ),
              child: Column(
                children: [
                  for (final (i, a) in archived.indexed) ...[
                    if (i > 0)
                      Divider(height: 1, thickness: 1, color: brand.hairline),
                    _AccountRow(
                      account: a,
                      currency: currency,
                      isDefault: false,
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (active.length >= 2) ...[
            const SizedBox(height: 16),
            _TransferHeroCard(
              accounts: active,
              fromId: _fromId!,
              toId: _toId!,
              currency: currency,
              amountController: _transferAmount,
              onCycleFrom: () {
                final idx = active.indexWhere((a) => a.id == _fromId);
                final next = active[(idx + 1) % active.length];
                setState(() {
                  if (next.id == _toId) _toId = _fromId;
                  _fromId = next.id;
                });
              },
              onCycleTo: () {
                final idx = active.indexWhere((a) => a.id == _toId);
                final next = active[(idx + 1) % active.length];
                setState(() {
                  if (next.id == _fromId) _fromId = _toId;
                  _toId = next.id;
                });
              },
              onSwap: () => setState(() {
                final tmp = _fromId;
                _fromId = _toId;
                _toId = tmp;
              }),
              onTransfer: () => _submitTransfer(context),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _submitTransfer(BuildContext context) async {
    final amount = double.tryParse(_transferAmount.text.trim());
    if (amount == null || amount <= 0) {
      brandToast(context, 'Enter an amount to transfer.');
      return;
    }
    if (_fromId == null || _toId == null || _fromId == _toId) return;

    await ref
        .read(expenseRepositoryProvider)
        .addTransaction(
          amount: amount,
          accountId: _fromId!,
          transferAccountId: _toId,
          kind: TxKind.transfer,
        );
    _transferAmount.clear();
    if (context.mounted) {
      FocusScope.of(context).unfocus();
      brandToast(context, 'Transfer recorded');
    }
  }
}

/// Creates an account, or edits [account] when given.
Future<void> _editAccount(
  BuildContext context,
  WidgetRef ref, {
  Account? account,
}) async {
  final name = TextEditingController(text: account?.name ?? '');
  final balance = TextEditingController();
  var type = account?.type ?? 'cash';
  var color = account?.color ?? context.brand.expense.toARGB32();

  final saved = await brandDialog<bool>(
    context,
    title: account == null ? 'New account' : 'Edit account',
    builder: (dialogContext) => StatefulBuilder(
      builder: (_, setState) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BrandField(controller: name, label: 'Name', autofocus: true),
          if (account == null) ...[
            const SizedBox(height: 12),
            BrandField(
              controller: balance,
              label: 'Opening balance',
              hint: '0',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in AppIcons.accountIcons.keys)
                Pill(
                  label: _typeLabel(t),
                  icon: AppIcons.account(t),
                  selected: type == t,
                  color: Theme.of(dialogContext).colorScheme.primary,
                  onTap: () => setState(() => type = t),
                ),
            ],
          ),
          const SizedBox(height: 16),
          ColorPickerRow(
            selected: color,
            onChanged: (c) => setState(() => color = c),
          ),
          const SizedBox(height: 20),
          BrandButton(
            label: account == null ? 'Create' : 'Save',
            onPressed: () => Navigator.pop(dialogContext, true),
          ),
          const SizedBox(height: 8),
          BrandButton(
            label: 'Cancel',
            kind: BrandButtonKind.ghost,
            onPressed: () => Navigator.pop(dialogContext, false),
          ),
        ],
      ),
    ),
  );

  if (saved != true || name.text.trim().isEmpty) return;
  final repo = ref.read(expenseRepositoryProvider);
  if (account == null) {
    await repo.createAccount(
      name.text.trim(),
      type,
      double.tryParse(balance.text.trim()) ?? 0,
      color,
    );
  } else {
    await repo.updateAccount(
      account.id,
      name: name.text.trim(),
      type: type,
      color: color,
    );
  }
}

String _typeLabel(String type) => switch (type) {
  'bkash' => 'bKash',
  'nagad' => 'Nagad',
  'rocket' => 'Rocket',
  _ => type[0].toUpperCase() + type.substring(1),
};

class _AccountRow extends ConsumerWidget {
  final Account account;
  final String currency;
  final bool isDefault;

  const _AccountRow({
    required this.account,
    required this.currency,
    required this.isDefault,
  });

  static ModuleColors _rolesFor(BrandColors brand, String type) =>
      switch (type) {
        'cash' => brand.habitRoles,
        'bank' || 'card' => brand.taskRoles,
        'bkash' || 'nagad' || 'rocket' => brand.expenseRoles,
        _ => brand.noteRoles,
      };

  static String _subtitleFor(String type, {required bool isDefault}) {
    if (isDefault && type == 'cash') return 'Default for new expenses';
    return switch (type) {
      'cash' => 'Cash wallet',
      'bkash' || 'nagad' || 'rocket' => 'Mobile wallet',
      'bank' => 'Bank account',
      'card' => 'Card',
      _ => 'Account',
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final repo = ref.read(expenseRepositoryProvider);
    final muted = Theme.of(context).colorScheme.outline;
    final roles = _rolesFor(brand, account.type);

    return BrandTappable(
      onPressed: () => _editAccount(context, ref, account: account),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: account.isArchived ? brand.track : roles.tintFill,
                borderRadius: BorderRadius.circular(14),
              ),
              child: AppIcon(
                AppIcons.account(account.type),
                size: 20,
                color: account.isArchived ? muted : roles.graphicOnTint,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    account.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: account.isArchived ? muted : brand.ink,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    account.isArchived
                        ? 'Archived'
                        : _subtitleFor(account.type, isDefault: isDefault),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              Fmt.money(account.balance, currency),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: account.isArchived ? muted : brand.ink,
              ),
            ),
            const SizedBox(width: 4),
            CircleIconButton(
              icon: account.isArchived ? AppIcons.unarchive : AppIcons.archive,
              tooltip: account.isArchived ? 'Restore' : 'Archive',
              size: 36,
              onPressed: () =>
                  repo.setAccountArchived(account.id, !account.isArchived),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransferHeroCard extends StatelessWidget {
  final List<Account> accounts;
  final int fromId;
  final int toId;
  final String currency;
  final TextEditingController amountController;
  final VoidCallback onCycleFrom;
  final VoidCallback onCycleTo;
  final VoidCallback onSwap;
  final VoidCallback onTransfer;

  const _TransferHeroCard({
    required this.accounts,
    required this.fromId,
    required this.toId,
    required this.currency,
    required this.amountController,
    required this.onCycleFrom,
    required this.onCycleTo,
    required this.onSwap,
    required this.onTransfer,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final isDark = theme.brightness == Brightness.dark;
    final onHero = isDark ? brand.ink : brand.onInk;

    final from = accounts.firstWhere(
      (a) => a.id == fromId,
      orElse: () => accounts.first,
    );
    final to = accounts.firstWhere(
      (a) => a.id == toId,
      orElse: () => accounts.last,
    );

    Widget buildSlot(String label, Account acc, VoidCallback onTap) {
      return Expanded(
        child: BrandTappable(
          onPressed: onTap,
          semanticsLabel: '$label ${acc.name}',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 11, color: brand.onInkMuted),
                ),
                const SizedBox(height: 2),
                Text(
                  acc.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: onHero,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  Fmt.money(acc.balance, currency),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: brand.onInkMuted),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: brand.heroSurface,
        borderRadius: BorderRadius.circular(26),
        boxShadow: AppShadows.hero(theme.brightness),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TRANSFER',
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: brand.expenseRoles.onInk,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              buildSlot('From', from, onCycleFrom),
              const SizedBox(width: 8),
              BrandTappable(
                onPressed: onSwap,
                semanticsLabel: 'Swap accounts',
                child: Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: brand.expenseRoles.onInk,
                    shape: BoxShape.circle,
                  ),
                  child: AppIcon(
                    AppIcons.transfer,
                    size: 18,
                    color: brand.heroSurface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              buildSlot('To', to, onCycleTo),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: Row(
                    children: [
                      Text(
                        currency,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: brand.onInkMuted,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          controller: amountController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: onHero,
                          ),
                          decoration: InputDecoration(
                            hintText: '0',
                            hintStyle: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: brand.onInkMuted,
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
              ),
              const SizedBox(width: 10),
              BrandTappable(
                onPressed: onTransfer,
                semanticsLabel: 'Transfer',
                child: Container(
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: onHero,
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: Text(
                    'Transfer',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: brand.heroSurface,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

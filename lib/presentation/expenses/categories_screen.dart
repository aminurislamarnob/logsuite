import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/common.dart';
import 'providers/expenses_provider.dart';
import 'repository/expense_repository.dart';

/// Rename, recolour, re-icon, reorder and remove categories. The seeded
/// defaults are no different from the ones you add.
class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  bool _income = false;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final muted = Theme.of(context).colorScheme.outline;
    final currency = ref.watch(settingsProvider).currencySymbol;
    final all = ref.watch(categoriesProvider).valueOrNull ?? const [];
    final shown = all.where((c) => c.isIncome == _income).toList();
    final report = ref.watch(currentMonthReportProvider).valueOrNull;
    final monthName = Fmt.monthYear(DateTime.now()).split(' ').first;

    return BrandScaffold(
      header: BrandTopBar(
        title: 'Categories',
        leadingIcon: AppIcons.back,
        actions: [
          _HeaderTypeToggle(
            income: _income,
            onChanged: (v) => setState(() => _income = v),
          ),
        ],
      ),
      floatingAction: BrandFab(
        icon: AppIcons.add,
        label: 'New',
        tooltip: 'New category',
        onPressed: () => CategoryEditor.show(context, ref, isIncome: _income),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter + 4,
              4,
              AppSpacing.gutter,
              10,
            ),
            child: Text(
              '${shown.length == 1 ? '1 category' : '${shown.length} categories'} · drag to reorder'
              '${_income ? '' : ' · spend is for $monthName'}',
              style: TextStyle(fontSize: 13, color: muted),
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
              decoration: BoxDecoration(
                color: brand.surface,
                borderRadius: BorderRadius.circular(AppRadii.card),
                boxShadow: AppShadows.card(Theme.of(context).brightness),
              ),
              clipBehavior: Clip.antiAlias,
              child: ReorderableListView.builder(
                padding: EdgeInsets.fromLTRB(
                  0,
                  4,
                  0,
                  AppSpacing.fabClearance +
                      MediaQuery.paddingOf(context).bottom,
                ),
                buildDefaultDragHandles: false,
                itemCount: shown.length,
                onReorderStart: (_) => AppHaptics.medium(),
                onReorderItem: (from, to) => _reorder(all, shown, from, to),
                itemBuilder: (context, i) {
                  final cat = shown[i];
                  final spend = _income
                      ? 0.0
                      : (report?.byCategory[cat.id] ?? 0.0);
                  return _CategoryRow(
                    key: ValueKey('cat-${cat.id}'),
                    category: cat,
                    index: i,
                    showDivider: i < shown.length - 1,
                    spend: spend,
                    showSpend: !_income,
                    currency: currency,
                    onDelete: () => _delete(cat, shown),
                  );
                },
              ),
            ),
          ),
          SizedBox(height: MediaQuery.paddingOf(context).bottom + 20),
        ],
      ),
    );
  }

  /// Reorders within the visible group; the other group keeps its order
  /// after it, since the two are never shown together.
  Future<void> _reorder(
    List<ExpenseCategory> all,
    List<ExpenseCategory> shown,
    int from,
    int to,
  ) async {
    AppHaptics.selection();
    final moved = [...shown];
    moved.insert(to, moved.removeAt(from));
    final rest = all.where((c) => c.isIncome != _income);
    await ref
        .read(expenseRepositoryProvider)
        .reorderCategories([...moved, ...rest].map((c) => c.id).toList());
  }

  Future<void> _delete(
    ExpenseCategory category,
    List<ExpenseCategory> siblings,
  ) async {
    final repo = ref.read(expenseRepositoryProvider);
    final count = await repo.categoryTransactionCount(category.id);
    if (!mounted) return;

    if (count == 0) {
      final ok = await brandConfirm(
        context,
        title: 'Delete ${category.name}?',
        confirmLabel: 'Delete',
        destructive: true,
      );
      if (ok) await repo.deleteCategory(category.id);
      return;
    }

    final options = siblings.where((c) => c.id != category.id).toList();
    if (options.isEmpty) {
      brandToast(context, 'Add another category to move these into first.');
      return;
    }
    var target =
        (options.where((c) => c.name == 'Other').firstOrNull ?? options.first)
            .id;

    final move = await brandDialog<bool>(
      context,
      title: 'Delete ${category.name}',
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Move ${count == 1 ? '1 transaction' : '$count transactions'} to',
              style: TextStyle(
                color: Theme.of(dialogContext).colorScheme.outline,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in options)
                  Pill(
                    label: c.name,
                    icon: AppIcons.category(c.icon),
                    selected: target == c.id,
                    color: Theme.of(dialogContext).colorScheme.primary,
                    onTap: () => setState(() => target = c.id),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            BrandButton(
              label: 'Move and delete',
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
    if (move == true) {
      await repo.deleteCategory(category.id, reassignTo: target);
    }
  }
}

class _HeaderTypeToggle extends StatelessWidget {
  final bool income;
  final ValueChanged<bool> onChanged;

  const _HeaderTypeToggle({required this.income, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final muted = Theme.of(context).colorScheme.outline;

    Widget pill(String label, bool value) {
      final selected = income == value;
      return BrandTappable(
        onPressed: () => onChanged(value),
        semanticsLabel: label,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? brand.ink : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              color: selected ? brand.onInk : muted,
            ),
          ),
        ),
      );
    }

    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: brand.well,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [pill('Expense', false), pill('Income', true)],
      ),
    );
  }
}

class _CategoryRow extends ConsumerWidget {
  final ExpenseCategory category;
  final int index;
  final bool showDivider;
  final double spend;
  final bool showSpend;
  final String currency;
  final VoidCallback onDelete;

  const _CategoryRow({
    super.key,
    required this.category,
    required this.index,
    required this.showDivider,
    required this.spend,
    required this.showSpend,
    required this.currency,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final muted = Theme.of(context).colorScheme.outline;
    final color = Color(category.color);
    final roles = brand.roleFor(color);
    final isFallback = category.name == 'Other';

    return Material(
      color: brand.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BrandTappable(
            onPressed: () =>
                CategoryEditor.show(context, ref, category: category),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: roles.tintFill,
                      borderRadius: BorderRadius.circular(AppRadii.chipSmall),
                    ),
                    child: AppIcon(
                      AppIcons.category(category.icon),
                      color: roles.graphicOnTint,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          category.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: brand.ink,
                          ),
                        ),
                        if (isFallback)
                          Text(
                            'Fallback category',
                            style: TextStyle(fontSize: 11, color: muted),
                          ),
                      ],
                    ),
                  ),
                  if (showSpend) ...[
                    Text(
                      spend > 0 ? Fmt.money(spend, currency) : 'No spend',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: spend > 0
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: spend > 0 ? brand.ink : muted,
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  CircleIconButton(
                    icon: AppIcons.delete,
                    tooltip: 'Delete',
                    size: 36,
                    onPressed: onDelete,
                  ),
                  ReorderableDragStartListener(
                    index: index,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: AppIcon(
                        AppIcons.gripVertical,
                        size: 18,
                        color: brand.subtle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (showDivider)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Divider(height: 1, thickness: 1, color: brand.hairline),
            ),
        ],
      ),
    );
  }
}

/// The create / edit dialog, shared with the entry sheet's quick-add.
class CategoryEditor {
  CategoryEditor._();

  /// Returns the id of the created or edited category, or null if dismissed.
  static Future<int?> show(
    BuildContext context,
    WidgetRef ref, {
    ExpenseCategory? category,
    bool isIncome = false,
  }) async {
    final name = TextEditingController(text: category?.name ?? '');
    var icon = category?.icon ?? 'other';
    var color = category?.color ?? context.brand.expense.toARGB32();

    final saved = await brandDialog<bool>(
      context,
      title: category == null ? 'New category' : 'Edit category',
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BrandField(controller: name, label: 'Name', autofocus: true),
            const SizedBox(height: 16),
            ColorPickerRow(
              selected: color,
              onChanged: (c) => setState(() => color = c),
            ),
            const SizedBox(height: 16),
            _IconGrid(
              selected: icon,
              color: Color(color),
              onChanged: (t) => setState(() => icon = t),
            ),
            const SizedBox(height: 20),
            BrandButton(
              label: category == null ? 'Create' : 'Save',
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

    if (saved != true || name.text.trim().isEmpty) return null;
    final repo = ref.read(expenseRepositoryProvider);
    if (category == null) {
      return repo.createCategory(
        name.text.trim(),
        icon,
        color,
        isIncome: isIncome,
      );
    }
    await repo.updateCategory(
      category.id,
      name: name.text.trim(),
      icon: icon,
      color: color,
    );
    return category.id;
  }
}

/// Every token in [AppIcons.categoryIcons], as a scrolling grid of circles.
class _IconGrid extends StatelessWidget {
  final String selected;
  final Color color;
  final ValueChanged<String> onChanged;

  const _IconGrid({
    required this.selected,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.outline;
    return SizedBox(
      height: 160,
      child: GridView.count(
        padding: EdgeInsets.zero,
        crossAxisCount: 6,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        children: [
          for (final entry in AppIcons.categoryIcons.entries)
            GestureDetector(
              onTap: () {
                AppHaptics.selection();
                onChanged(entry.key);
              },
              child: Container(
                decoration: BoxDecoration(
                  color: entry.key == selected
                      ? color
                      : color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: AppIcon(
                    entry.value,
                    size: 18,
                    color: entry.key == selected
                        ? context.brand.onAccent(color)
                        : muted,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

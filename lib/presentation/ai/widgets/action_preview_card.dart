import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ai/ai_action.dart';
import '../../../core/ai/ai_client.dart';
import '../../../core/ai/ai_command_executor.dart';
import '../../../core/ai/ai_drafts.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/widgets/brand.dart';
import '../../../core/widgets/common.dart';
import '../../expenses/widgets/expense_entry_sheet.dart';
import '../../habits/providers/habits_provider.dart';
import '../../habits/repository/habit_repository.dart';
import '../../medicine/widgets/medicine_editor_sheet.dart';
import '../../tasks/widgets/task_editor_sheet.dart';

/// One parsed entry, before it is saved.
///
/// Tapping opens the module's own editor prefilled, so anything the parser
/// got wrong is fixed in the same form the user would have typed into. The
/// card then shows as saved with an "Open" pill.
class ActionPreviewCard extends ConsumerWidget {
  final ActionPreview preview;
  final SavedItem? saved;
  final VoidCallback onRemove;
  final ValueChanged<SavedItem> onSaved;

  const ActionPreviewCard({
    super.key,
    required this.preview,
    required this.saved,
    required this.onRemove,
    required this.onSaved,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final draft = preview.draft;
    final kind = draft.kind;
    final accent = kind.color(brand);
    final roles = brand.roleFor(accent);
    final currency = ref.watch(settingsProvider).currencySymbol;
    final isSaved = saved != null;
    final blocked = preview.blocked;
    final hasWarnings = preview.warnings.isNotEmpty;

    final eyebrowLabel = kind == AiActionKind.addMedicine
        ? 'MEDICINE COURSE'
        : kind.label.toUpperCase();

    final summaryParts = draft
        .summary(currency)
        .split(' · ')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final card = BrandTappable(
      onPressed: isSaved
          ? () => context.push(saved!.route, extra: saved!.extra)
          : blocked
          ? null
          : () {
              AppHaptics.tap();
              _edit(context, ref);
            },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: brand.surface,
          borderRadius: BorderRadius.circular(22),
          border: hasWarnings
              ? Border.all(color: brand.warningRoles.graphicOnTint, width: 2)
              : null,
          boxShadow: AppShadows.card(theme.brightness),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: roles.tintFill,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: AppIcon(
                    kind.icon,
                    color: roles.graphicOnTint,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        eyebrowLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                          color: roles.textOnTint,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              draft.title,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 17,
                                letterSpacing: -0.2,
                                color: brand.ink,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isSaved)
                            AppIcon(
                              AppIcons.checkCircle,
                              color: brand.success,
                              size: 18,
                            ),
                        ],
                      ),
                      if (summaryParts.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            for (final part in summaryParts)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: brand.canvas,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  part,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: context.muted,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (isSaved)
                  Pill(
                    label: 'Open',
                    color: accent,
                    selected: true,
                    onTap: () =>
                        context.push(saved!.route, extra: saved!.extra),
                  )
                else ...[
                  if (!blocked)
                    Text(
                      'Edit',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: roles.textOnTint,
                      ),
                    ),
                  const SizedBox(width: 4),
                  CircleIconButton(
                    icon: AppIcons.close,
                    tooltip: 'Remove',
                    size: 36,
                    onPressed: onRemove,
                  ),
                ],
              ],
            ),
            if (hasWarnings || blocked) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: blocked
                      ? brand.dangerRoles.tintFill
                      : brand.warningRoles.tintFill,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    AppIcon(
                      AppIcons.warning,
                      size: 16,
                      color: blocked
                          ? brand.dangerRoles.graphicOnTint
                          : brand.warningRoles.graphicOnTint,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        blocked
                            ? 'Cannot save — ${preview.warnings.isEmpty ? 'missing required data' : preview.warnings.join(' · ')}'
                            : preview.warnings.join(' · '),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: blocked
                              ? brand.dangerRoles.textOnTint
                              : brand.warningRoles.textOnTint,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: blocked ? Opacity(opacity: 0.6, child: card) : card,
    );
  }

  /// Opens the native editor for this draft. The sheets pop with the saved
  /// id; the note and focus paths save first, because their editors are a
  /// full screen and a running timer respectively.
  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final draft = preview.draft;
    final executor = ref.read(aiCommandExecutorProvider);
    try {
      switch (draft) {
        case TaskDraft d:
          final id = await TaskEditorSheet.show(context, draft: d);
          if (id != null) {
            onSaved(
              SavedItem(
                kind: d.kind,
                id: id,
                title: d.title,
                route: AppModule.tasks.route,
              ),
            );
          }
        case ExpenseDraft d:
          final id = await ExpenseEntrySheet.show(
            context,
            kind: d.txKind,
            note: d.note,
            amount: d.amount,
            categoryId: d.categoryId,
            accountId: d.accountId,
            personId: d.personId,
            date: d.date,
          );
          if (id != null) {
            onSaved(
              SavedItem(
                kind: d.kind,
                id: id,
                title: d.title,
                route: AppModule.expenses.route,
              ),
            );
          }
        case MedicineDraft d:
          final id = await MedicineEditorSheet.show(context, draft: d);
          if (id != null) {
            onSaved(
              SavedItem(
                kind: d.kind,
                id: id,
                title: d.name,
                route: AppModule.medicine.route,
              ),
            );
          }
        case NoteDraft d:
          final item = await executor.save(d);
          onSaved(item);
          if (context.mounted) context.push(item.route, extra: item.extra);
        case HabitLogDraft d:
          final item = await _pickHabit(context, ref, d);
          if (item != null) onSaved(item);
        case FocusDraft d:
          final item = await executor.save(d);
          onSaved(item);
          if (context.mounted) context.push(item.route);
        default:
          break;
      }
    } on AiException catch (e) {
      if (context.mounted) brandToast(context, e.message);
    }
  }

  /// Re-targets a habit log, mirroring the Quick Add picker.
  Future<SavedItem?> _pickHabit(
    BuildContext context,
    WidgetRef ref,
    HabitLogDraft d,
  ) async {
    final habits = ref.read(habitsListProvider).valueOrNull ?? const [];
    if (habits.isEmpty) {
      brandToast(context, 'No habits yet — add one first.');
      return null;
    }
    return brandSheet<SavedItem>(
      context: context,
      builder: (sheetContext) => SheetScaffold(
        title: 'Log which habit?',
        child: TileColumn(
          children: habits.map((h) {
            return BrandTile(
              leading: AppIcon(AppIcons.habit(h.icon), color: Color(h.color)),
              title: Text(h.name),
              subtitle: Text(
                '+${d.amount % 1 == 0 ? d.amount.toInt() : d.amount}'
                '${h.unit == null ? '' : ' ${h.unit}'}',
                style: const TextStyle(fontSize: 11),
              ),
              selected: h.id == d.habitId,
              onTap: () async {
                await ref
                    .read(habitRepositoryProvider)
                    .addToDay(h.id, d.amount);
                if (sheetContext.mounted) {
                  Navigator.pop(
                    sheetContext,
                    SavedItem(
                      kind: d.kind,
                      id: h.id,
                      title: h.name,
                      route: AppModule.habits.route,
                    ),
                  );
                }
              },
            );
          }).toList(),
        ),
      ),
    );
  }
}

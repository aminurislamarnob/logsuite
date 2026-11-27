import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/settings/app_settings.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/common.dart';
import '../expenses/repository/expense_repository.dart';
import '../expenses/widgets/expense_entry_sheet.dart';
import '../habits/providers/habits_provider.dart';
import '../habits/repository/habit_repository.dart';
import '../medicine/providers/medicine_provider.dart';
import '../medicine/repository/medicine_repository.dart';
import '../notes/notes_screen.dart' show newNoteFlow;
import '../tasks/widgets/task_editor_sheet.dart';
import '../ai/widgets/document_source_sheet.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reduceMotion = ref.watch(settingsProvider).reduceMotion;

    // A tab change is a short crossfade and nothing more. iOS switches tabs
    // without moving the content, and a slide reads as a push, which it is
    // not. The fade runs on a controller rather than by re-keying the shell:
    // a new key re-inflates every branch subtree on each tap, which is the
    // stutter a tab bar must never have.
    final body = _TabFade(
      index: navigationShell.currentIndex,
      enabled: !reduceMotion,
      child: navigationShell,
    );

    // The bar is stacked over the body rather than placed in FScaffold's footer
    // slot: it draws its own background, floats the action button above the
    // notch, and the body has to show through that notch. That is Material's
    // `extendBody`, which FScaffold has no equivalent for — a footer would push
    // the body up instead. Screens already reserve bottom padding for the bar.
    return BrandScaffold(
      child: Stack(
        children: [
          Positioned.fill(child: body),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: CurvedNavBar(
              currentIndex: navigationShell.currentIndex,
              onSelected: (i) => navigationShell.goBranch(
                i,
                initialLocation: i == navigationShell.currentIndex,
              ),
              centerAction: QuickAddButton(
                onPressed: () => showQuickAdd(context, ref),
                // A hold has no visible acknowledgement of its own, so
                // BrandTappable gives a medium impact before the assistant slides in.
                onLongPress: () => context.push('/assistant'),
              ),
              items: const [
                CurvedNavItem(
                  icon: AppIcons.home,
                  selectedIcon: AppIcons.home,
                  label: 'Today',
                ),
                CurvedNavItem(
                  icon: AppIcons.modules,
                  selectedIcon: AppIcons.modules,
                  label: 'Modules',
                ),
                CurvedNavItem(
                  icon: AppIcons.insights,
                  selectedIcon: AppIcons.insights,
                  label: 'Insights',
                ),
                CurvedNavItem(
                  icon: AppIcons.settings,
                  selectedIcon: AppIcons.settings,
                  label: 'Settings',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Crossfades the shell body when [index] changes, without rebuilding it.
class _TabFade extends StatefulWidget {
  final int index;
  final bool enabled;
  final Widget child;

  const _TabFade({
    required this.index,
    required this.enabled,
    required this.child,
  });

  @override
  State<_TabFade> createState() => _TabFadeState();
}

class _TabFadeState extends State<_TabFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    value: 1,
  );
  late final Animation<double> _opacity = _controller.drive(
    // From a dim, not from nothing: the page was already there, it only
    // changed.
    Tween(begin: 0.55, end: 1.0).chain(CurveTween(curve: Curves.easeOut)),
  );

  @override
  void didUpdateWidget(_TabFade old) {
    super.didUpdateWidget(old);
    if (widget.enabled && old.index != widget.index) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _opacity, child: widget.child);
}

/// The round coral `+` inline in the floating ink pill bar.
///
/// A long press goes straight to the voice assistant: the button is on every
/// tab, so it is the one place a spoken command is always one gesture away.
class QuickAddButton extends StatelessWidget {
  final VoidCallback onPressed;
  final VoidCallback? onLongPress;

  const QuickAddButton({super.key, required this.onPressed, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return BrandTooltip(
      message: onLongPress == null ? 'Quick add' : 'Quick add · hold to speak',
      semanticsLabel: 'Quick add',
      child: BrandTappable(
        onPressed: onPressed,
        onLongPress: onLongPress,
        semanticsLabel: 'Quick add',
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: primary,
            shape: const CircleBorder(),
            shadows: [
              BoxShadow(
                color: primary.withValues(alpha: 0.36),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const SizedBox(
            width: 50,
            height: 50,
            child: AppIcon(AppIcons.add, color: Colors.white, size: 26),
          ),
        ),
      ),
    );
  }
}

/// The Quick Add sheet (`02-quick-add.png`). Every entry here is a real action,
/// and the frequent ones (log habit, mark dose) complete in a single extra tap.
Future<void> showQuickAdd(BuildContext context, WidgetRef ref) {
  final settings = ref.read(settingsProvider);

  return brandSheet(
    context: context,
    builder: (sheetContext) => _QuickAddSheetContent(
      settings: settings,
      parentContext: context,
      ref: ref,
    ),
  );
}

class _QuickAddSheetContent extends StatefulWidget {
  final AppSettings settings;
  final BuildContext parentContext;
  final WidgetRef ref;

  const _QuickAddSheetContent({
    required this.settings,
    required this.parentContext,
    required this.ref,
  });

  @override
  State<_QuickAddSheetContent> createState() => _QuickAddSheetContentState();
}

class _QuickAddSheetContentState extends State<_QuickAddSheetContent> {
  final _textController = TextEditingController();

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _openAssistant([String? initialText]) {
    final text = (initialText ?? _textController.text).trim();
    Navigator.pop(context);
    widget.parentContext.push('/assistant', extra: text.isEmpty ? null : text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final settings = widget.settings;
    final parentContext = widget.parentContext;
    final ref = widget.ref;

    final entries =
        <({HugeIconData icon, Color color, String label, VoidCallback onTap})>[
          if (settings.isEnabled(AppModule.tasks))
            (
              icon: AppIcons.tasks,
              color: brand.task,
              label: 'Task',
              onTap: () {
                Navigator.pop(context);
                runModuleQuickAction(parentContext, ref, AppModule.tasks);
              },
            ),
          if (settings.isEnabled(AppModule.expenses))
            (
              icon: AppIcons.expenses,
              color: brand.expense,
              label: 'Expense',
              onTap: () {
                Navigator.pop(context);
                runModuleQuickAction(parentContext, ref, AppModule.expenses);
              },
            ),
          if (settings.isEnabled(AppModule.habits))
            (
              icon: AppIcons.habits,
              color: brand.habit,
              label: 'Habit',
              onTap: () {
                Navigator.pop(context);
                runModuleQuickAction(parentContext, ref, AppModule.habits);
              },
            ),
          if (settings.isEnabled(AppModule.medicine))
            (
              icon: AppIcons.medicine,
              color: brand.medicine,
              label: 'Medicine',
              onTap: () {
                Navigator.pop(context);
                runModuleQuickAction(parentContext, ref, AppModule.medicine);
              },
            ),
          if (settings.isEnabled(AppModule.notes))
            (
              icon: AppIcons.notes,
              color: brand.note,
              label: 'Note',
              onTap: () {
                Navigator.pop(context);
                runModuleQuickAction(parentContext, ref, AppModule.notes);
              },
            ),
          if (settings.isEnabled(AppModule.focus))
            (
              icon: AppIcons.focus,
              color: brand.focus,
              label: 'Focus',
              onTap: () {
                Navigator.pop(context);
                runModuleQuickAction(parentContext, ref, AppModule.focus);
              },
            ),
          if (settings.isEnabled(AppModule.drop))
            (
              icon: AppIcons.inbox,
              color: brand.drop,
              label: 'Drop',
              onTap: () {
                Navigator.pop(context);
                runModuleQuickAction(parentContext, ref, AppModule.drop);
              },
            ),
          if (settings.isEnabled(AppModule.expenses))
            (
              icon: AppIcons.transfer,
              color: brand.ink,
              label: 'Transfer',
              onTap: () {
                Navigator.pop(context);
                ExpenseEntrySheet.show(parentContext, kind: TxKind.transfer);
              },
            ),
        ];

    return SheetScaffold(
      title: 'Add',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: brand.heroSurface,
              borderRadius: BorderRadius.circular(AppRadii.card),
              boxShadow: AppShadows.hero(theme.brightness),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AppIcon(
                      AppIcons.sparkle,
                      size: 16,
                      color: brand.medicineRoles.onInk,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'SAY IT OR TYPE IT',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: brand.medicineRoles.onInk,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _textController,
                  minLines: 2,
                  maxLines: 3,
                  textInputAction: TextInputAction.send,
                  onSubmitted: _openAssistant,
                  style: TextStyle(
                    color: theme.brightness == Brightness.dark
                        ? brand.ink
                        : Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                  decoration: InputDecoration(
                    hintText:
                        'Lunch 200 taka with bKash, or call the doctor at 5',
                    hintStyle: TextStyle(
                      color: brand.onInkMuted,
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    CircleIconButton(
                      icon: AppIcons.camera,
                      tooltip: 'Scan a document',
                      onInk: true,
                      onPressed: () async {
                        Navigator.pop(context);
                        final fromCamera = await showDocumentSourceSheet(
                          parentContext,
                        );
                        if (fromCamera != null && parentContext.mounted) {
                          parentContext.push('/assistant', extra: fromCamera);
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    CircleIconButton(
                      icon: AppIcons.mic,
                      tooltip: 'Speak a command',
                      onInk: true,
                      onPressed: () => _openAssistant(''),
                    ),
                    const Spacer(),
                    BrandTappable(
                      onPressed: () => _openAssistant(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        decoration: ShapeDecoration(
                          color: theme.brightness == Brightness.dark
                              ? brand.ink
                              : Colors.white,
                          shape: const StadiumBorder(),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Ask assistant',
                              style: TextStyle(
                                color: theme.brightness == Brightness.dark
                                    ? brand.onInk
                                    : brand.ink,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(width: 6),
                            AppIcon(
                              AppIcons.chevronRight,
                              size: 16,
                              color: theme.brightness == Brightness.dark
                                  ? brand.onInk
                                  : brand.ink,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (entries.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              'OR PICK ONE',
              style: theme.textTheme.labelSmall?.copyWith(
                color: context.muted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 12),
            GridView.count(
              padding: EdgeInsets.zero,
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.86,
              children: [
                for (final e in entries)
                  _QuickPickTile(
                    icon: e.icon,
                    color: e.color,
                    label: e.label,
                    onTap: e.onTap,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _QuickPickTile extends StatelessWidget {
  final HugeIconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _QuickPickTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final roles = brand.roleFor(color);
    return BrandTappable(
      onPressed: onTap,
      semanticsLabel: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
        decoration: BoxDecoration(
          color: brand.surface,
          borderRadius: BorderRadius.circular(AppRadii.tile),
          boxShadow: AppShadows.card(theme.brightness),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: roles.tintFill,
                shape: BoxShape.circle,
              ),
              child: AppIcon(icon, size: 20, color: roles.graphicOnTint),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: brand.ink,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Runs the quick-add action for [module], shared by Quick add and Modules.
void runModuleQuickAction(
  BuildContext context,
  WidgetRef ref,
  AppModule module,
) {
  switch (module) {
    case AppModule.tasks:
      TaskEditorSheet.show(context);
    case AppModule.expenses:
      ExpenseEntrySheet.show(context);
    case AppModule.habits:
      _showHabitPicker(context, ref);
    case AppModule.medicine:
      _showDosePicker(context, ref);
    case AppModule.notes:
      newNoteFlow(context, ref);
    case AppModule.focus:
      context.push('/focus');
    case AppModule.drop:
      context.push('/drop');
  }
}

/// Second tap of the 2-tap habit log.
Future<void> _showHabitPicker(BuildContext context, WidgetRef ref) async {
  final habits = ref.read(habitsListProvider).valueOrNull ?? const [];
  if (habits.isEmpty) {
    brandToast(context, 'No habits yet — add one first.');
    return;
  }

  await brandSheet(
    context: context,
    builder: (sheetContext) => SheetScaffold(
      title: 'Log a habit',
      child: TileColumn(
        children: habits.map((h) {
          return BrandTile(
            leading: AppIcon(AppIcons.habit(h.icon), color: Color(h.color)),
            title: Text(h.name),
            subtitle: h.unit == null
                ? null
                : Text('+1 ${h.unit}', style: const TextStyle(fontSize: 11)),
            trailing: AppIcon(AppIcons.addCircle, color: Color(h.color)),
            onTap: () async {
              await ref.read(habitRepositoryProvider).addToDay(h.id, 1);
              if (sheetContext.mounted) Navigator.pop(sheetContext);
              if (context.mounted) {
                brandToast(context, 'Logged ${h.name}.');
              }
            },
          );
        }).toList(),
      ),
    ),
  );
}

/// Second tap of the 2-tap dose log.
Future<void> _showDosePicker(BuildContext context, WidgetRef ref) async {
  final doses = (ref.read(todayDoseViewsProvider).valueOrNull ?? const [])
      .where((d) => d.status == DoseStatus.pending)
      .toList();

  if (doses.isEmpty) {
    brandToast(context, 'No pending doses today.');
    return;
  }

  await brandSheet(
    context: context,
    builder: (sheetContext) => SheetScaffold(
      title: 'Mark taken',
      child: TileColumn(
        children: doses.map((v) {
          return BrandTile(
            leading: AppIcon(
              AppIcons.medicineForm(v.medicine.form),
              color: context.brand.medicine,
            ),
            title: Text(v.medicine.name),
            subtitle: Text(
              '${v.dosageLabel}${v.mealLabel.isEmpty ? '' : ' · ${v.mealLabel}'}',
              style: const TextStyle(fontSize: 11),
            ),
            trailing: const AppIcon(AppIcons.checkCircle),
            onTap: () async {
              await ref
                  .read(medicineRepositoryProvider)
                  .setDoseStatus(v.dose.id, DoseStatus.taken);
              if (sheetContext.mounted) Navigator.pop(sheetContext);
              if (context.mounted) {
                brandToast(context, '${v.medicine.name} marked taken.');
              }
            },
          );
        }).toList(),
      ),
    ),
  );
}

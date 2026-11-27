import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/settings/app_settings.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/common.dart';
import '../drop/providers/drop_provider.dart';
import '../expenses/providers/expenses_provider.dart';
import '../focus/providers/focus_provider.dart';
import '../habits/providers/habits_provider.dart';
import '../medicine/providers/medicine_provider.dart';
import '../medicine/repository/medicine_repository.dart';
import '../notes/providers/notes_provider.dart';
import '../tasks/providers/tasks_provider.dart';

class ModulesScreen extends ConsumerWidget {
  const ModulesScreen({super.key});

  /// Icon and accent colour for each module, shared with onboarding.
  static (HugeIconData, Color) metaFor(BuildContext context, AppModule m) =>
      (_icons[m]!, accentFor(context.brand, m));

  static const _icons = <AppModule, HugeIconData>{
    AppModule.notes: AppIcons.notes,
    AppModule.medicine: AppIcons.medicine,
    AppModule.habits: AppIcons.habits,
    AppModule.tasks: AppIcons.tasks,
    AppModule.expenses: AppIcons.expenses,
    AppModule.focus: AppIcons.focus,
    AppModule.drop: AppIcons.inbox,
  };

  /// The accent the active palette gives [m].
  static Color accentFor(BrandColors brand, AppModule m) => switch (m) {
    AppModule.notes => brand.note,
    AppModule.medicine => brand.medicine,
    AppModule.habits => brand.habit,
    AppModule.tasks => brand.task,
    AppModule.expenses => brand.expense,
    AppModule.focus => brand.focus,
    AppModule.drop => brand.drop,
  };

  void _showEditSheet(BuildContext context, WidgetRef ref) {
    brandSheet(
      context: context,
      builder: (_) => Consumer(
        builder: (context, ref, _) {
          final settings = ref.watch(settingsProvider);
          final notifier = ref.read(settingsProvider.notifier);
          return SheetScaffold(
            title: 'Choose modules',
            child: TileGroup(
              children: [
                for (final m in AppModule.values)
                  BrandSwitchTile(
                    title: m.label,
                    subtitle: m.blurb,
                    value: settings.isEnabled(m),
                    onChanged: (v) => notifier.toggleModule(m, v),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final brand = context.brand;
    final theme = Theme.of(context);
    final enabled = AppModule.values.where(settings.isEnabled).toList();
    final disabled = AppModule.values
        .where((m) => !settings.isEnabled(m))
        .toList();

    final hasMedicineHero = enabled.contains(AppModule.medicine);
    final gridModules = hasMedicineHero
        ? enabled.where((m) => m != AppModule.medicine).toList()
        : enabled;

    return BrandScaffold(
      header: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            12,
            AppSpacing.gutter,
            8,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Modules',
                      style: theme.textTheme.displayMedium?.copyWith(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.9,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${enabled.length} on · hold a card to switch off',
                      style: TextStyle(color: context.muted, fontSize: 14),
                    ),
                  ],
                ),
              ),
              BrandTappable(
                onPressed: () => _showEditSheet(context, ref),
                semanticsLabel: 'Choose modules',
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.center,
                  decoration: ShapeDecoration(
                    color: brand.surface,
                    shape: const StadiumBorder(),
                    shadows: AppShadows.circleButton(theme.brightness),
                  ),
                  child: Text(
                    'Edit',
                    style: TextStyle(
                      color: brand.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      child: enabled.isEmpty
          ? const EmptyState(
              icon: AppIcons.modules,
              title: 'Everything is switched off',
              message: 'Turn a module back on below to start using it.',
            )
          : ListView(
              padding: pageInsets(context, top: 8, end: PageEnd.navBar),
              children: [
                if (hasMedicineHero) ...[
                  _MedicineHeroCard(
                    onTap: () => context.push(AppModule.medicine.route),
                    onLongPress: () {
                      AppHaptics.medium();
                      ref
                          .read(settingsProvider.notifier)
                          .toggleModule(AppModule.medicine, false);
                    },
                  ),
                  const SizedBox(height: AppSpacing.grid),
                ],
                GridView.count(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  crossAxisSpacing: AppSpacing.grid,
                  mainAxisSpacing: AppSpacing.grid,
                  childAspectRatio: 1.12,
                  children: [
                    for (var i = 0; i < gridModules.length; i++)
                      Builder(
                        builder: (context) {
                          final m = gridModules[i];
                          final (icon, color) = metaFor(context, m);
                          return _ModuleCard(
                            module: m,
                            icon: icon,
                            color: color,
                            tintIndex: i,
                            onTap: () => context.push(m.route),
                          );
                        },
                      ),
                  ],
                ),
                if (disabled.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.section),
                  const SectionHeader('Switched off'),
                  ...disabled.map((m) {
                    final (icon, _) = metaFor(context, m);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: cardGap),
                      child: TintCard(
                        fill: brand.surface,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 4,
                        ),
                        child: BrandTile(
                          leading: AppIcon(icon, color: context.muted),
                          title: Text(m.label),
                          subtitle: Text(
                            m.blurb,
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: BrandButton(
                            label: 'Turn on',
                            kind: BrandButtonKind.ghost,
                            expand: false,
                            onPressed: () => ref
                                .read(settingsProvider.notifier)
                                .toggleModule(m, true),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ],
            ),
    );
  }
}

class _MedicineHeroCard extends ConsumerWidget {
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _MedicineHeroCard({required this.onTap, required this.onLongPress});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final roles = brand.medicineRoles;
    final doses = ref.watch(todayDoseViewsProvider).valueOrNull ?? const [];
    final taken = doses.where((d) => d.status == DoseStatus.taken).length;
    final nextPending = doses
        .where((d) => d.status == DoseStatus.pending)
        .firstOrNull;
    final subtitle = nextPending != null
        ? '${nextPending.medicine.name} due at ${Fmt.time(nextPending.dose.scheduledTime)}'
        : doses.isEmpty
        ? AppModule.medicine.blurb
        : 'All doses taken for today';

    return GestureDetector(
      key: const ValueKey('module-medicine'),
      onLongPress: onLongPress,
      child: TintCard(
        accent: brand.medicine,
        radius: 26,
        padding: const EdgeInsets.all(18),
        onTap: onTap,
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: brand.surface,
                borderRadius: BorderRadius.circular(18),
              ),
              child: AppIcon(
                AppIcons.medicine,
                size: 26,
                color: roles.graphicOnTint,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Medicine',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: roles.textOnTint,
                    ),
                  ),
                ],
              ),
            ),
            if (doses.isNotEmpty) ...[
              const SizedBox(width: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '$taken',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                    ),
                  ),
                  Text(
                    '/${doses.length}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: roles.textOnTint,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ModuleCard extends ConsumerWidget {
  final AppModule module;
  final HugeIconData icon;
  final Color color;
  final int tintIndex;
  final VoidCallback onTap;

  const _ModuleCard({
    required this.module,
    required this.icon,
    required this.color,
    required this.tintIndex,
    required this.onTap,
  });

  ({Widget? badge, String subtitle}) _liveMeta(
    BuildContext context,
    WidgetRef ref,
    ModuleColors roles,
  ) {
    final brand = context.brand;
    final settings = ref.watch(settingsProvider);
    switch (module) {
      case AppModule.tasks:
        final tasks = ref.watch(todayTasksProvider).valueOrNull ?? const [];
        final stats = ref.watch(taskStatsProvider(7)).valueOrNull;
        final open = tasks.where((t) => !t.isCompleted).length;
        final overdue = stats?.overdue ?? 0;
        final badge = overdue > 0
            ? DecoratedBox(
                decoration: ShapeDecoration(
                  color: brand.surface,
                  shape: const StadiumBorder(),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  child: Text(
                    '$overdue overdue',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: brand.dangerRoles.textOnTint,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              )
            : tasks.isNotEmpty
            ? Text(
                '${tasks.length - open}/${tasks.length}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              )
            : null;
        return (
          badge: badge,
          subtitle: open == 0 ? 'All done today' : '$open left today',
        );
      case AppModule.habits:
        final habits = ref.watch(habitsListProvider).valueOrNull ?? const [];
        final logs = ref.watch(todayHabitLogsProvider).valueOrNull ?? const {};
        final done = habits.where((h) {
          final a = logs[h.id] ?? 0;
          return h.goalType == 0 ? a >= h.targetAmount : a <= h.targetAmount;
        }).length;
        return (
          badge: habits.isEmpty
              ? null
              : Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '$done',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                      TextSpan(
                        text: '/${habits.length}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: roles.textOnTint,
                        ),
                      ),
                    ],
                  ),
                ),
          subtitle: habits.isEmpty
              ? module.blurb
              : '$done of ${habits.length} today',
        );
      case AppModule.expenses:
        final recent =
            ref.watch(recentExpensesProvider).valueOrNull ?? const [];
        final spentToday = recent
            .where((e) => e.kind == 0 && Fmt.isSameDay(e.date, DateTime.now()))
            .fold<double>(0, (a, e) => a + e.amount);
        return (
          badge: Text(
            Fmt.compactMoney(spentToday, settings.currencySymbol),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
          subtitle: spentToday == 0 ? 'Nothing spent today' : 'Spent today',
        );
      case AppModule.focus:
        final stats = ref.watch(focusStatsProvider).valueOrNull;
        final goal = ref.watch(focusGoalProvider);
        final mins = (stats?.today ?? Duration.zero).inMinutes;
        final pct = goal > 0 ? ((mins / goal) * 100).round() : 0;
        return (
          badge: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$mins',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                TextSpan(
                  text: 'm',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: roles.textOnTint,
                  ),
                ),
              ],
            ),
          ),
          subtitle: goal > 0
              ? 'Goal ${Fmt.durationFromMinutes(goal)} · $pct% there'
              : module.blurb,
        );
      case AppModule.notes:
        final notes = ref.watch(recentNotesProvider).valueOrNull ?? const [];
        return (
          badge: notes.isEmpty
              ? null
              : Text(
                  '${notes.length}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
          subtitle: notes.isEmpty
              ? module.blurb
              : 'Edited ${Fmt.relativeDay(notes.first.updatedAt)}',
        );
      case AppModule.drop:
        final unread = ref.watch(unreadDropsCountProvider).valueOrNull ?? 0;
        return (
          badge: unread > 0
              ? DecoratedBox(
                  decoration: ShapeDecoration(
                    color: brand.surface,
                    shape: const StadiumBorder(),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    child: Text(
                      '$unread unread',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: roles.textOnTint,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                )
              : null,
          subtitle: 'Links and clips',
        );
      case AppModule.medicine:
        return (badge: null, subtitle: module.blurb);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final roles = brand.roleFor(color);
    final meta = _liveMeta(context, ref, roles);

    return GestureDetector(
      key: ValueKey('module-${module.name}'),
      onLongPress: () {
        AppHaptics.medium();
        ref.read(settingsProvider.notifier).toggleModule(module, false);
      },
      child: TintCard(
        accent: color,
        onTap: onTap,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: brand.surface,
                    borderRadius: BorderRadius.circular(AppRadii.field),
                  ),
                  child: AppIcon(icon, color: roles.graphicOnTint, size: 22),
                ),
                if (meta.badge != null) ...[
                  const SizedBox(width: 8),
                  Flexible(child: meta.badge!),
                ],
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  module.label,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  meta.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: roles.textOnTint),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

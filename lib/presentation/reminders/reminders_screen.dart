import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/settings/app_settings.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/common.dart';
import '../expenses/providers/expenses_provider.dart';
import '../habits/repository/habit_repository.dart';
import '../medicine/providers/medicine_provider.dart';
import '../medicine/repository/medicine_repository.dart';
import '../medicine/utils/after_opening_expiry.dart';
import '../modules/modules_screen.dart';
import '../notes/repository/note_repository.dart';
import '../tasks/repository/task_repository.dart';

/// One row in the unified reminders inbox.
class ReminderItem {
  final String title;
  final String subtitle;
  final DateTime at;
  final HugeIconData icon;
  final String route;

  /// Which module this reminder came from. The accent is resolved from the
  /// active palette at render time — this provider has no context, and pinning
  /// a colour here would freeze it to whichever palette was live at build.
  final AppModule module;

  /// A colour of the item's own, for the one case that has one: a habit
  /// carries a user-picked colour that outranks the module accent.
  final Color? colorOverride;

  const ReminderItem({
    required this.title,
    required this.subtitle,
    required this.at,
    required this.icon,
    required this.module,
    required this.route,
    this.colorOverride,
  });

  /// The accent to draw this reminder with.
  Color accent(BrandColors brand) =>
      colorOverride ?? ModulesScreen.accentFor(brand, module);
}

/// Collects every scheduled reminder across modules into one chronological
/// list — the spec's "cross-module reminders inbox".
final remindersProvider = FutureProvider<List<ReminderItem>>((ref) async {
  final settings = ref.watch(settingsProvider);
  final items = <ReminderItem>[];

  if (settings.isEnabled(AppModule.medicine)) {
    // Re-evaluate whenever medicines change (added, edited, bottle opened).
    ref.watch(medicinesProvider);
    final doses = await ref
        .watch(medicineRepositoryProvider)
        .upcomingDoses(limit: 20);
    final meds = {
      for (final m in await ref.watch(medicineRepositoryProvider).medicines())
        m.id: m,
    };
    for (final d in doses) {
      final med = meds[d.medicineId];
      if (med == null) continue;
      items.add(
        ReminderItem(
          title: med.name,
          subtitle: 'Dose · ${med.dosage.toStringAsFixed(0)} ${med.dosageUnit}',
          at: d.scheduledTime,
          icon: AppIcons.medicine,
          module: AppModule.medicine,
          route: '/medicine',
        ),
      );
    }
    final now = DateTime.now();
    for (final m in meds.values) {
      if (!m.isActive) continue;
      final expiry = AfterOpeningStatus.ofMedicine(m);
      if (!expiry.alertsEnabled) continue;
      final useBy = expiry.useByDate!;
      final preAt = expiry.preExpiryAlertAt;
      final lead = expiry.effectiveLeadDays;
      if (preAt != null && lead != null && preAt.isAfter(now)) {
        final timing = lead == 1 ? 'tomorrow' : 'in ${lead}d';
        items.add(
          ReminderItem(
            title: m.name,
            subtitle: 'Expires $timing · use by ${Fmt.dayMonth(useBy)}',
            at: preAt,
            icon: AppIcons.medicineForm(m.form),
            module: AppModule.medicine,
            route: '/medicine',
          ),
        );
      }
      final expiryAt = expiry.expiryDayAlertAt;
      if (expiryAt != null && expiryAt.isAfter(now)) {
        items.add(
          ReminderItem(
            title: m.name,
            subtitle: 'Expires today · discard bottle',
            at: expiryAt,
            icon: AppIcons.medicineForm(m.form),
            module: AppModule.medicine,
            route: '/medicine',
          ),
        );
      }
    }
  }

  if (settings.isEnabled(AppModule.tasks)) {
    final tasks = await ref.watch(taskRepositoryProvider).tasksWithReminders();
    for (final t in tasks) {
      items.add(
        ReminderItem(
          title: t.title,
          subtitle: 'Task reminder',
          at: t.reminderTime!,
          icon: AppIcons.checkCircle,
          module: AppModule.tasks,
          route: '/tasks',
        ),
      );
    }
  }

  if (settings.isEnabled(AppModule.notes)) {
    final notes = await ref.watch(noteRepositoryProvider).notesWithReminders();
    for (final n in notes) {
      items.add(
        ReminderItem(
          title: n.title,
          subtitle: 'Note reminder',
          at: n.reminderAt!,
          icon: AppIcons.notes,
          module: AppModule.notes,
          route: '/notes',
        ),
      );
    }
  }

  if (settings.isEnabled(AppModule.habits)) {
    final habits = await ref
        .watch(habitRepositoryProvider)
        .habitsWithReminders();
    final today = Fmt.dateOnly(DateTime.now());
    for (final h in habits) {
      var when = today.add(Duration(minutes: h.reminderMinutes!));
      if (when.isBefore(DateTime.now())) {
        when = when.add(const Duration(days: 1));
      }
      items.add(
        ReminderItem(
          title: h.name,
          subtitle: 'Daily habit nudge',
          at: when,
          icon: AppIcons.habits,
          module: AppModule.habits,
          colorOverride: Color(h.color),
          route: '/habits',
        ),
      );
    }
  }

  if (settings.isEnabled(AppModule.expenses)) {
    final loans = await ref.watch(loanRowsProvider.future);
    for (final l in loans) {
      final due = l.loan.dueDate;
      if (l.isSettled || due == null) continue;
      items.add(
        ReminderItem(
          title: l.person == null
              ? (l.isLent ? 'Loan due' : 'Repayment due')
              : l.isLent
              ? '${l.person!.name} owes you ${settings.currencySymbol}${l.outstanding.toStringAsFixed(0)}'
              : 'You owe ${l.person!.name} ${settings.currencySymbol}${l.outstanding.toStringAsFixed(0)}',
          subtitle: l.isLent ? 'Repayment due' : 'Loan due',
          at: due,
          icon: AppIcons.transfer,
          module: AppModule.expenses,
          route: '/expenses',
        ),
      );
    }

    final bills = await ref.watch(recurringProvider.future);
    for (final b in bills) {
      items.add(
        ReminderItem(
          title:
              '${b.name} · ${settings.currencySymbol}${b.amount.toStringAsFixed(0)}',
          subtitle: 'Bill due',
          at: b.nextDueDate,
          icon: AppIcons.bills,
          module: AppModule.expenses,
          route: '/expenses',
        ),
      );
    }
  }

  items.sort((a, b) => a.at.compareTo(b.at));
  return items;
});

class RemindersScreen extends ConsumerWidget {
  const RemindersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reminders = ref.watch(remindersProvider);
    final settings = ref.watch(settingsProvider);
    final brand = context.brand;
    final theme = Theme.of(context);
    final itemsCount = reminders.valueOrNull?.length ?? 0;

    return BrandScaffold(
      header: BrandTopBar(
        title: 'Reminders',
        subtitle: '$itemsCount scheduled',
        leadingIcon: AppIcons.back,
        actions: [
          CircleIconButton(
            icon: AppIcons.settings,
            tooltip: 'Notification settings',
            onPressed: () => context.go('/settings'),
          ),
        ],
      ),
      child: reminders.when(
        data: (items) {
          if (items.isEmpty) {
            return const EmptyState(
              icon: AppIcons.notifications,
              title: 'Nothing scheduled',
              message:
                  'Dose times, task reminders, habit nudges and bill due dates '
                  'all show up here.',
            );
          }

          final today = Fmt.dateOnly(DateTime.now());
          final tomorrow = today.add(const Duration(days: 1));
          final todayItems = <ReminderItem>[];
          final tomorrowItems = <ReminderItem>[];
          final laterItems = <ReminderItem>[];

          for (final r in items) {
            final day = Fmt.dateOnly(r.at);
            if (day.isAtSameMomentAs(today) || day.isBefore(today)) {
              todayItems.add(r);
            } else if (day.isAtSameMomentAs(tomorrow)) {
              tomorrowItems.add(r);
            } else {
              laterItems.add(r);
            }
          }

          final sections = <(String, List<ReminderItem>, bool)>[
            if (todayItems.isNotEmpty) ('TODAY', todayItems, false),
            if (tomorrowItems.isNotEmpty) ('TOMORROW', tomorrowItems, false),
            if (laterItems.isNotEmpty) ('LATER', laterItems, true),
          ];

          return ListView(
            padding: pageInsets(context, top: 8),
            children: [
              if (settings.dndEnabled) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: brand.well,
                    borderRadius: BorderRadius.circular(AppRadii.field),
                  ),
                  child: Row(
                    children: [
                      AppIcon(AppIcons.sleep, size: 16, color: context.muted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Quiet ${Fmt.minutesOfDay(settings.dndStartMinutes)} – '
                          '${Fmt.minutesOfDay(settings.dndEndMinutes)} · medicine still rings',
                          style: TextStyle(fontSize: 13, color: context.muted),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              for (final (heading, group, showDate) in sections) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
                  child: Text(
                    heading,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: context.muted,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: brand.surface,
                    borderRadius: BorderRadius.circular(AppRadii.tile),
                    boxShadow: AppShadows.card(theme.brightness),
                  ),
                  child: Column(
                    children: [
                      for (final (idx, r) in group.indexed)
                        _ReminderRow(
                          item: r,
                          showDate: showDate,
                          showDivider: idx < group.length - 1,
                          onTap: () => context.push(r.route),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ],
          );
        },
        loading: () => const Center(child: BrandSpinner()),
        error: (e, _) =>
            EmptyState(icon: AppIcons.error, title: 'Error', message: '$e'),
      ),
    );
  }
}

class _ReminderRow extends StatelessWidget {
  final ReminderItem item;
  final bool showDate;
  final bool showDivider;
  final VoidCallback onTap;

  const _ReminderRow({
    required this.item,
    required this.showDate,
    required this.showDivider,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final accent = item.accent(brand);
    final roles = brand.roleFor(accent);
    final trailingText = showDate ? Fmt.dayMonth(item.at) : Fmt.time(item.at);

    return BrandTappable(
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: showDivider
              ? Border(bottom: BorderSide(color: brand.hairline))
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: roles.tintFill,
                borderRadius: BorderRadius.circular(14),
              ),
              child: AppIcon(item.icon, size: 20, color: roles.graphicOnTint),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: context.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              trailingText,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

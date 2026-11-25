import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/app_database.dart';
import '../../core/people/people_repository.dart';
import '../../core/people/person_avatar.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/common.dart';
import '../ai/widgets/document_source_sheet.dart';
import '../drop/providers/drop_provider.dart';
import '../expenses/providers/expenses_provider.dart';
import '../focus/providers/focus_provider.dart';
import '../habits/providers/habits_provider.dart';
import '../habits/repository/habit_repository.dart';
import '../habits/utils/habit_stats.dart';
import '../medicine/medicine_screen.dart' show DoseTile;
import '../medicine/providers/medicine_provider.dart';
import '../medicine/repository/medicine_repository.dart';
import '../medicine/utils/after_opening_expiry.dart';
import '../notes/providers/notes_provider.dart';
import '../notes/repository/note_repository.dart';
import '../reminders/reminders_screen.dart';
import '../settings/people_screen.dart';
import '../tasks/providers/tasks_provider.dart';
import '../tasks/repository/task_repository.dart';
import '../tasks/widgets/task_tile.dart';

/// Today (`01-today.png`): greeting header, ink hero card with day timeline and
/// module sub-tiles, AI add bar, "Up next", then per-module sections in
/// [AppSettings.dashboardOrder].
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  String? _selectedModule;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final brand = context.brand;
    final self = ref.watch(selfProvider);
    final reminders = ref.watch(remindersProvider).valueOrNull ?? const [];
    final today = Fmt.dateOnly(DateTime.now());
    final dueReminders = reminders
        .where((item) => !Fmt.dateOnly(item.at).isAfter(today))
        .length;

    final builders = <String, Widget Function()>{
      'medicine': () => const _MedicineWidget(),
      'tasks': () => const _TasksWidget(),
      'habits': () => const _HabitsWidget(),
      'expenses': () => const _ExpensesWidget(),
      'focus': () => const _FocusWidget(),
      'notes': () => const _NotesWidget(),
      'drop': () => const _DropWidget(),
    };

    final ordered = settings.dashboardOrder
        .where((key) => builders.containsKey(key))
        .where((key) => settings.enabledModules.any((m) => m.name == key))
        .toList();

    final activeKey =
        ordered.contains(_selectedModule) ? _selectedModule : ordered.firstOrNull;

    return BrandScaffold(
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: pageInsets(context, top: 12, end: PageEnd.navBar),
          children: [
            GreetingHeader(
              greeting: Fmt.greeting(),
              subtitle: Fmt.headerDate(DateTime.now()),
              initials: Fmt.initials(self?.name ?? ''),
              photoPath: self?.photoPath,
              color: self == null || self.color == personColorSeed
                  ? null
                  : Color(self.color),
              onAvatarTap: self == null
                  ? null
                  : () => PersonEditor.show(context, ref, person: self),
              actions: [
                CircleIconButton(
                  icon: AppIcons.search,
                  tooltip: 'Search everything',
                  onPressed: () => context.push('/search'),
                ),
                CircleIconButton(
                  icon: AppIcons.notifications,
                  tooltip: 'Reminders',
                  badgeCount: dueReminders,
                  onPressed: () => context.push('/reminders'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const _TodayHeroCard(),
            const SizedBox(height: 14),
            const _TodayAddBar(),
            const SizedBox(height: 16),
            if (ordered.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: EmptyState(
                  icon: AppIcons.modules,
                  title: 'No modules enabled',
                  message: 'Turn some on in Settings to fill your dashboard.',
                ),
              )
            else if (activeKey != null) ...[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: [
                    for (final (i, key) in ordered.indexed) ...[
                      if (i > 0) const SizedBox(width: 8),
                      _buildModuleTab(brand, key, key == activeKey),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              builders[activeKey]!(),
            ],
            const SizedBox(height: 18),
            const _UpNextSection(),
            const SizedBox(height: 18),
            const _ActivityChart(),
          ],
        ),
      ),
    );
  }

  Widget _buildModuleTab(BrandColors brand, String key, bool selected) {
    final module = AppModule.values.firstWhere((m) => m.name == key);
    final (icon, color) = switch (module) {
      AppModule.medicine => (AppIcons.medicine, brand.medicine),
      AppModule.tasks => (AppIcons.tasks, brand.task),
      AppModule.habits => (AppIcons.habits, brand.habit),
      AppModule.expenses => (AppIcons.expenses, brand.expense),
      AppModule.focus => (AppIcons.focus, brand.focus),
      AppModule.notes => (AppIcons.notes, brand.note),
      AppModule.drop => (AppIcons.inbox, brand.drop),
    };
    return Pill(
      label: module.label,
      icon: icon,
      color: color,
      selected: selected,
      onTap: () {
        AppHaptics.selection();
        setState(() => _selectedModule = key);
      },
    );
  }
}

class _TodayHeroCard extends ConsumerWidget {
  const _TodayHeroCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final settings = ref.watch(settingsProvider);
    final isDark = theme.brightness == Brightness.dark;
    final primaryText = isDark ? brand.ink : brand.onInk;

    final tasks = settings.isEnabled(AppModule.tasks)
        ? (ref.watch(todayTasksProvider).valueOrNull ?? const <Task>[])
        : const <Task>[];
    final doses = settings.isEnabled(AppModule.medicine)
        ? (ref.watch(todayDoseViewsProvider).valueOrNull ?? const <DoseView>[])
        : const <DoseView>[];
    final habits = settings.isEnabled(AppModule.habits)
        ? (ref.watch(habitsListProvider).valueOrNull ?? const <Habit>[])
        : const <Habit>[];
    final habitLogs = settings.isEnabled(AppModule.habits)
        ? (ref.watch(todayHabitLogsProvider).valueOrNull ??
              const <int, double>{})
        : const <int, double>{};
    final focusStats = settings.isEnabled(AppModule.focus)
        ? ref.watch(focusStatsProvider).valueOrNull
        : null;
    final recentExpenses = settings.isEnabled(AppModule.expenses)
        ? (ref.watch(recentExpensesProvider).valueOrNull ?? const <Expense>[])
        : const <Expense>[];
    final noteCount = settings.isEnabled(AppModule.notes)
        ? (ref.watch(activeNoteCountProvider).valueOrNull ?? 0)
        : 0;
    final unreadDrops = settings.isEnabled(AppModule.drop)
        ? (ref.watch(unreadDropsCountProvider).valueOrNull ?? 0)
        : 0;

    final tasksDone = tasks.where((t) => t.isCompleted).length;
    final dosesDone = doses.where((d) => d.status == DoseStatus.taken).length;
    final habitsDone = habits.where((h) {
      final amount = habitLogs[h.id] ?? 0;
      return h.goalType == 0
          ? amount >= h.targetAmount
          : amount <= h.targetAmount;
    }).length;

    final totalCount = tasks.length + doses.length + habits.length;
    final doneCount = tasksDone + dosesDone + habitsDone;
    final progress = totalCount == 0 ? 0.0 : doneCount / totalCount;
    final remaining = totalCount - doneCount;
    final habitsLeft = habits.length - habitsDone;

    // Next upcoming timed item for the supporting line. "All caught up" only
    // when every counted item is done — an open habit is still today's work.
    final now = DateTime.now();
    final nextDose = doses
        .where((d) => d.status == DoseStatus.pending)
        .firstOrNull;
    final nextTask = tasks.where((t) => !t.isCompleted).firstOrNull;
    final nextLine = nextDose != null
        ? (!nextDose.dose.scheduledTime.isAfter(
                now.add(const Duration(minutes: 15)),
              )
              ? 'Due now · ${Fmt.time(nextDose.dose.scheduledTime)}'
              : 'Next up at ${Fmt.time(nextDose.dose.scheduledTime)}')
        : nextTask != null
        ? (nextTask.hasDueTime && nextTask.dueDate != null
              ? (nextTask.dueDate!.isBefore(now)
                    ? 'Overdue · ${Fmt.time(nextTask.dueDate!)}'
                    : 'Next up at ${Fmt.time(nextTask.dueDate!)}')
              : 'Next: ${nextTask.title}')
        : remaining <= 0
        ? (totalCount == 0
              ? Fmt.fullDate(now)
              : 'All caught up for today')
        : habitsLeft == remaining
        ? (habitsLeft == 1
              ? '1 habit still open'
              : '$habitsLeft habits still open')
        : (remaining == 1 ? '1 thing still open' : '$remaining still open');

    // Timeline dots from today's timed doses, tasks & habits.
    final todayDate = Fmt.dateOnly(now);
    final events = <({DateTime time, Color color, bool done})>[
      for (final d in doses)
        (
          time: d.dose.scheduledTime,
          color: brand.medicineRoles.onInk,
          done: d.status == DoseStatus.taken,
        ),
      for (final t in tasks)
        if (t.hasDueTime && t.dueDate != null)
          (time: t.dueDate!, color: brand.taskRoles.onInk, done: t.isCompleted),
      for (final h in habits)
        if (h.reminderMinutes != null)
          (
            time: todayDate.add(Duration(minutes: h.reminderMinutes!)),
            color: brand.habitRoles.onInk,
            done: h.goalType == 0
                ? (habitLogs[h.id] ?? 0) >= h.targetAmount
                : (habitLogs[h.id] ?? 0) <= h.targetAmount,
          ),
    ];

    final spentToday = recentExpenses
        .where((e) => e.kind == 0 && Fmt.isSameDay(e.date, now))
        .fold<double>(0, (a, e) => a + e.amount);

    final subTiles = <Widget>[
      if (settings.isEnabled(AppModule.tasks))
        _HeroSubTile(
          dot: brand.taskRoles.onInk,
          label: 'Tasks',
          done: '$tasksDone',
          total: '/${tasks.length}',
          onTap: () => context.push('/tasks'),
        ),
      if (settings.isEnabled(AppModule.medicine))
        _HeroSubTile(
          dot: brand.medicineRoles.onInk,
          label: 'Meds',
          done: '$dosesDone',
          total: '/${doses.length}',
          onTap: () => context.push('/medicine'),
        ),
      if (settings.isEnabled(AppModule.habits))
        _HeroSubTile(
          dot: brand.habitRoles.onInk,
          label: 'Habits',
          done: '$habitsDone',
          total: '/${habits.length}',
          onTap: () => context.push('/habits'),
        ),
      if (settings.isEnabled(AppModule.focus))
        _HeroSubTile(
          dot: brand.focusRoles.onInk,
          label: 'Focus',
          done: '${(focusStats?.today ?? Duration.zero).inMinutes}',
          total: 'm',
          onTap: () => context.push('/focus'),
        ),
      if (settings.isEnabled(AppModule.expenses))
        _HeroSubTile(
          dot: brand.expenseRoles.onInk,
          label: 'Expenses',
          done: Fmt.compactMoney(spentToday, settings.currencySymbol),
          total: '',
          onTap: () => context.push('/expenses'),
        ),
      if (settings.isEnabled(AppModule.notes))
        _HeroSubTile(
          dot: brand.noteRoles.onInk,
          label: 'Notes',
          done: '$noteCount',
          total: '',
          onTap: () => context.push('/notes'),
        ),
      if (settings.isEnabled(AppModule.drop))
        _HeroSubTile(
          dot: brand.dropRoles.onInk,
          label: 'Drop',
          done: '$unreadDrops',
          total: '',
          onTap: () => context.push('/drop'),
        ),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
      decoration: BoxDecoration(
        color: brand.heroSurface,
        borderRadius: BorderRadius.circular(AppRadii.hero),
        boxShadow: AppShadows.hero(theme.brightness),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TODAY',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: brand.medicineRoles.onInk,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          '$doneCount',
                          style: theme.textTheme.displayLarge?.copyWith(
                            color: primaryText,
                            fontSize: 48,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -2,
                            height: 1.0,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'of $totalCount done',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: brand.onInkMuted,
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      nextLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: brand.onInkMuted, fontSize: 14),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              ProgressRing(
                value: progress,
                size: 92,
                thickness: 10,
                onInk: true,
                color: brand.medicineRoles.onInk,
                center: Text(
                  '${(progress * 100).round()}%',
                  style: TextStyle(
                    color: primaryText,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _DayTimeline(events: events, now: now),
          if (subTiles.isNotEmpty) ...[
            const SizedBox(height: 18),
            if (subTiles.length <= 4)
              Row(
                children: [
                  for (final (i, tile) in subTiles.indexed) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(child: tile),
                  ],
                ],
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final tileWidth = (constraints.maxWidth - 24) / 4;
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: [
                        for (final (i, tile) in subTiles.indexed) ...[
                          if (i > 0) const SizedBox(width: 8),
                          SizedBox(width: tileWidth, child: tile),
                        ],
                      ],
                    ),
                  );
                },
              ),
          ],
        ],
      ),
    );
  }
}

class _HeroSubTile extends StatelessWidget {
  final Color dot;
  final String label;
  final String done;
  final String total;
  final VoidCallback? onTap;

  const _HeroSubTile({
    required this.dot,
    required this.label,
    required this.done,
    required this.total,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryText = isDark ? brand.ink : brand.onInk;
    return BrandTappable(
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(AppRadii.field),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: brand.onInkMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    done,
                    style: TextStyle(
                      color: primaryText,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    total,
                    style: TextStyle(
                      color: brand.onInkMuted,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
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

class _DayTimeline extends StatelessWidget {
  final List<({DateTime time, Color color, bool done})> events;
  final DateTime now;

  const _DayTimeline({required this.events, required this.now});

  double _fraction(DateTime dt) {
    const startHour = 5.0;
    const endHour = 23.0;
    final hours = dt.hour + dt.minute / 60.0;
    return ((hours - startHour) / (endHour - startHour)).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryText = isDark ? brand.ink : brand.onInk;
    final nowFrac = _fraction(now);
    return Column(
      children: [
        SizedBox(
          height: 28,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              if (w <= 14) return const SizedBox.shrink();
              return Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 13,
                    child: Container(
                      height: 2,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    width: (nowFrac * w).clamp(0.0, w),
                    top: 13,
                    child: Container(
                      height: 2,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.42),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                  for (final e in events)
                    Positioned(
                      left: (_fraction(e.time) * (w - 10)).clamp(0.0, w - 10),
                      top: 9,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: e.done ? e.color : brand.heroSurface,
                          shape: BoxShape.circle,
                          border: Border.all(color: e.color, width: 2),
                        ),
                      ),
                    ),
                  Positioned(
                    left: (nowFrac * (w - 2)).clamp(0.0, w - 2),
                    top: 0,
                    height: 28,
                    child: Container(
                      width: 2,
                      decoration: BoxDecoration(
                        color: brand.medicineRoles.onInk,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                  Positioned(
                    left: (nowFrac * (w - 14)).clamp(0.0, w - 14),
                    top: 7,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: brand.medicineRoles.onInk,
                        shape: BoxShape.circle,
                        border: Border.all(color: brand.heroSurface, width: 3),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '5 AM',
              style: TextStyle(
                color: brand.onInkMuted,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
            Text(
              'Now · ${Fmt.time(now)}',
              style: TextStyle(
                color: primaryText,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
            Text(
              '11 PM',
              style: TextStyle(
                color: brand.onInkMuted,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TodayAddBar extends StatelessWidget {
  const _TodayAddBar();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.brand;
    return Container(
      height: 60,
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
      decoration: ShapeDecoration(
        color: brand.surface,
        shape: const StadiumBorder(),
        shadows: AppShadows.composer(theme.brightness),
      ),
      child: Row(
        children: [
          AppIcon(
            AppIcons.sparkle,
            size: 20,
            color: brand.medicineRoles.graphicOnTint,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: BrandTappable(
              onPressed: () {
                context.push('/assistant');
              },
              semanticsLabel: 'Add anything',
              child: Text(
                'Add anything...',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: context.muted,
                  fontSize: 15,
                ),
              ),
            ),
          ),
          CircleIconButton(
            icon: AppIcons.camera,
            tooltip: 'Scan a document',
            size: 38,
            onPressed: () async {
              final fromCamera = await showDocumentSourceSheet(context);
              if (fromCamera != null && context.mounted) {
                context.push('/assistant', extra: fromCamera);
              }
            },
          ),
          const SizedBox(width: 6),
          CircleIconButton(
            icon: AppIcons.mic,
            tooltip: 'Speak a command',
            size: 44,
            filled: true,
            color: brand.ink,
            onPressed: () => context.push('/assistant'),
          ),
        ],
      ),
    );
  }
}

class _UpNextSection extends ConsumerWidget {
  const _UpNextSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final brand = context.brand;
    final theme = Theme.of(context);

    final doses = settings.isEnabled(AppModule.medicine)
        ? (ref.watch(todayDoseViewsProvider).valueOrNull ?? const <DoseView>[])
        : const <DoseView>[];
    final now = DateTime.now();
    final pendingDoses = doses
        .where((d) => d.status == DoseStatus.pending)
        .take(1)
        .toList();

    final tasks = settings.isEnabled(AppModule.tasks)
        ? (ref.watch(todayTasksProvider).valueOrNull ?? const <Task>[])
        : const <Task>[];
    final openTasks = tasks.where((t) => !t.isCompleted).take(2).toList();

    final habits = settings.isEnabled(AppModule.habits)
        ? (ref.watch(habitsListProvider).valueOrNull ?? const <Habit>[])
        : const <Habit>[];
    final habitLogs = settings.isEnabled(AppModule.habits)
        ? (ref.watch(todayHabitLogsProvider).valueOrNull ??
              const <int, double>{})
        : const <int, double>{};
    final openHabits = habits
        .where((h) {
          final amount = habitLogs[h.id] ?? 0;
          return h.goalType == 0
              ? amount < h.targetAmount
              : amount > h.targetAmount;
        })
        .take(pendingDoses.length + openTasks.length < 3 ? 1 : 0)
        .toList();

    if (pendingDoses.isEmpty && openTasks.isEmpty && openHabits.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Up next',
          actionLabel: 'Full day',
          onAction: () => context.push('/reminders'),
        ),
        for (final v in pendingDoses) ...[
          // Coral outline and "Due now" only when the dose is actually due.
          // A later pending dose stays a plain row.
          Builder(
            builder: (context) {
              final dueNow = !v.dose.scheduledTime.isAfter(
                now.add(const Duration(minutes: 15)),
              );
              final expiry = AfterOpeningStatus.ofMedicine(v.medicine);
              final showExpiry = expiry.needsAttention(now: now);
              final expiryRoles = expiry.isExpired(now: now)
                  ? brand.dangerRoles
                  : brand.warningRoles;
              return Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                decoration: BoxDecoration(
                  color: brand.surface,
                  borderRadius: BorderRadius.circular(AppRadii.tile),
                  border: dueNow
                      ? Border.all(color: brand.medicine, width: 2)
                      : null,
                  boxShadow: AppShadows.card(theme.brightness),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: brand.medicineRoles.tintFill,
                        borderRadius: BorderRadius.circular(AppRadii.field),
                      ),
                      child: AppIcon(
                        AppIcons.medicineForm(v.medicine.form),
                        size: 24,
                        color: brand.medicineRoles.graphicOnTint,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            dueNow
                                ? 'DUE NOW · ${Fmt.time(v.dose.scheduledTime)}'
                                : Fmt.time(v.dose.scheduledTime),
                            style: TextStyle(
                              color: dueNow
                                  ? brand.medicineRoles.textOnTint
                                  : context.subtle,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: dueNow ? 0.6 : 0,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            v.medicine.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 17,
                              letterSpacing: -0.2,
                            ),
                          ),
                          Text(
                            '${v.dosageLabel}${v.mealLabel.isEmpty ? '' : ' · ${v.mealLabel}'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.subtle,
                              fontSize: 13,
                            ),
                          ),
                          if (showExpiry) ...[
                            const SizedBox(height: 5),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: ShapeDecoration(
                                color: expiryRoles.tintFill,
                                shape: const StadiumBorder(),
                              ),
                              child: Text(
                                expiry.shortBadgeLabel(now: now) ?? '',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: expiryRoles.textOnTint,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    BrandTappable(
                      onPressed: () {
                        AppHaptics.success();
                        ref
                            .read(medicineRepositoryProvider)
                            .setDoseStatus(v.dose.id, DoseStatus.taken);
                      },
                      child: Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        alignment: Alignment.center,
                        decoration: ShapeDecoration(
                          color: brand.ink,
                          shape: const StadiumBorder(),
                        ),
                        child: Text(
                          'Take',
                          style: TextStyle(
                            color: brand.onInk,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: cardGap),
        ],
        for (final t in openTasks) ...[
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            decoration: BoxDecoration(
              color: brand.surface,
              borderRadius: BorderRadius.circular(AppRadii.tile),
              boxShadow: AppShadows.card(theme.brightness),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: brand.taskRoles.tintFill,
                    borderRadius: BorderRadius.circular(AppRadii.field),
                  ),
                  child: AppIcon(
                    AppIcons.tasks,
                    size: 24,
                    color: brand.taskRoles.graphicOnTint,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (t.dueDate != null)
                        Text(
                          Fmt.due(t.dueDate!, withTime: t.hasDueTime),
                          style: TextStyle(
                            color: context.subtle,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      Text(
                        t.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 17,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                BrandCheckbox(
                  value: t.isCompleted,
                  semanticsLabel: 'Complete ${t.title}',
                  onChanged: (done) {
                    ref.read(taskRepositoryProvider).setCompleted(t.id, done);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: cardGap),
        ],
        for (final h in openHabits) ...[
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            decoration: BoxDecoration(
              color: brand.surface,
              borderRadius: BorderRadius.circular(AppRadii.tile),
              boxShadow: AppShadows.card(theme.brightness),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: brand.habitRoles.tintFill,
                    borderRadius: BorderRadius.circular(AppRadii.field),
                  ),
                  child: AppIcon(
                    AppIcons.habit(h.icon),
                    size: 24,
                    color: brand.habitRoles.graphicOnTint,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        h.reminderMinutes != null
                            ? '${Fmt.minutesOfDay(h.reminderMinutes!)} · Daily habit'
                            : 'Daily habit',
                        style: TextStyle(
                          color: context.subtle,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        h.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 17,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                BrandCheckbox(
                  value: false,
                  semanticsLabel: 'Log ${h.name}',
                  onChanged: (_) {
                    AppHaptics.success();
                    ref.read(habitRepositoryProvider).addToDay(h.id, 1);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: cardGap),
        ],
      ],
    );
  }
}

class _ActivityChart extends ConsumerWidget {
  const _ActivityChart();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final brand = context.brand;
    final theme = Theme.of(context);
    final today = Fmt.dateOnly(DateTime.now());
    final days = [
      for (var i = 6; i >= 0; i--) today.subtract(Duration(days: i)),
    ];

    final taskStats = settings.isEnabled(AppModule.tasks)
        ? ref.watch(taskStatsProvider(14)).valueOrNull
        : null;
    final doseStats = settings.isEnabled(AppModule.medicine)
        ? ref.watch(takenDosesByDayProvider(14)).valueOrNull
        : null;
    final focusStats = settings.isEnabled(AppModule.focus)
        ? ref.watch(focusStatsProvider).valueOrNull
        : null;
    final habits = settings.isEnabled(AppModule.habits)
        ? (ref.watch(habitsListProvider).valueOrNull ?? const <Habit>[])
        : const <Habit>[];
    final habitStats = {
      for (final h in habits)
        h.id:
            ref.watch(habitStatsProvider(h.id)).valueOrNull ?? HabitStats.empty,
    };

    int thingsOn(DateTime day) {
      var count = (taskStats?.perDay[day] ?? 0) + (doseStats?[day] ?? 0);
      if ((focusStats?.byDay[day] ?? Duration.zero) > Duration.zero) {
        count += 1;
      }
      for (final habit in habits) {
        final amount = habitStats[habit.id]?.byDay[day];
        if (amount == null) continue;
        final met = habit.goalType == 0
            ? amount >= habit.targetAmount
            : amount <= habit.targetAmount;
        if (met) count += 1;
      }
      return count;
    }

    final counts = [for (final d in days) thingsOn(d)];
    final lastWeek = [
      for (var i = 13; i >= 7; i--) today.subtract(Duration(days: i)),
    ].fold<int>(0, (sum, day) => sum + thingsOn(day));
    final totalDone = counts.fold<int>(0, (a, b) => a + b);
    final maxCount = counts.fold<int>(1, (a, b) => a > b ? a : b);
    // Section 8: show the week-over-week change only when last week has a
    // baseline. A zero baseline cannot become a percentage.
    final int? versusLastWeek = lastWeek == 0
        ? null
        : (((totalDone - lastWeek) / lastWeek) * 100).round();

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        boxShadow: AppShadows.card(theme.brightness),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'THIS WEEK',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: context.subtle,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '$totalDone ',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.6,
                        ),
                      ),
                      Text(
                        totalDone == 1 ? 'thing done' : 'things done',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: context.subtle,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (versusLastWeek != null)
                Container(
                  height: 28,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: versusLastWeek >= 0
                        ? brand.habitRoles.tintFill
                        : brand.dangerRoles.tintFill,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    versusLastWeek > 0
                        ? '+$versusLastWeek% vs last week'
                        : '$versusLastWeek% vs last week',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: versusLastWeek >= 0
                          ? brand.habitRoles.textOnTint
                          : brand.dangerRoles.textOnTint,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 88,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < days.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: FractionallySizedBox(
                              widthFactor: 1,
                              heightFactor: counts[i] == 0
                                  ? 0.14
                                  : (0.2 + 0.8 * (counts[i] / maxCount)).clamp(
                                      0.14,
                                      1.0,
                                    ),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: i == days.length - 1
                                      ? brand.medicine
                                      : brand.well,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          Fmt.weekday(days[i]).substring(0, 1),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: i == days.length - 1
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: i == days.length - 1
                                ? brand.ink
                                : context.subtle,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MedicineWidget extends ConsumerWidget {
  const _MedicineWidget();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doses = ref.watch(todayDoseViewsProvider).valueOrNull ?? const [];
    final upcoming = doses
        .where((d) => d.status == DoseStatus.pending)
        .take(3)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Medicine',
          actionLabel: 'Open',
          onAction: () => context.push('/medicine'),
        ),
        if (upcoming.isEmpty)
          _quiet(context, 'All doses handled for today.')
        else
          ...upcoming.map((v) => DoseTile(view: v)),
      ],
    );
  }
}

class _TasksWidget extends ConsumerWidget {
  const _TasksWidget();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(todayTasksProvider).valueOrNull ?? const [];
    final open = tasks.where((t) => !t.isCompleted).take(4).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Tasks due today',
          actionLabel: 'Open',
          onAction: () => context.push('/tasks'),
        ),
        if (open.isEmpty)
          _quiet(context, 'Nothing due — you are all caught up.')
        else
          ...open.map((t) => TaskTile(task: t, dense: true)),
      ],
    );
  }
}

class _HabitsWidget extends ConsumerWidget {
  const _HabitsWidget();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habits = ref.watch(habitsListProvider).valueOrNull ?? const [];
    final today = ref.watch(todayHabitLogsProvider).valueOrNull ?? const {};
    final repo = ref.read(habitRepositoryProvider);
    final brand = context.brand;
    final theme = Theme.of(context);

    final doneCount = habits.where((h) {
      final amount = today[h.id] ?? 0;
      return h.goalType == 0
          ? amount >= h.targetAmount
          : amount <= h.targetAmount;
    }).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Habits',
          actionLabel: habits.isEmpty
              ? 'Open'
              : '$doneCount of ${habits.length} done',
          onAction: () => context.push('/habits'),
        ),
        if (habits.isEmpty)
          _quiet(context, 'No habits yet.')
        else
          SizedBox(
            height: 96,
            child: GutterBleed(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.gutter,
                ),
                itemCount: habits.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final h = habits[i];
                  final amount = today[h.id] ?? 0;
                  final color = Color(h.color);
                  final roles = brand.roleFor(color);
                  final done = h.goalType == 0
                      ? amount >= h.targetAmount
                      : amount <= h.targetAmount;
                  final partial = !done && h.targetAmount > 1 && amount > 0;

                  return BrandTappable(
                    onPressed: () => repo.addToDay(h.id, 1),
                    onLongPress: () => context.push('/habits'),
                    semanticsLabel: 'Log ${h.name}',
                    child: Container(
                      width: 72,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: brand.surface,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: AppShadows.card(theme.brightness),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (done)
                            Container(
                              width: 40,
                              height: 40,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: brand.habit,
                                shape: BoxShape.circle,
                              ),
                              child: const AppIcon(
                                AppIcons.check,
                                color: Colors.white,
                                size: 18,
                              ),
                            )
                          else if (partial)
                            ProgressRing(
                              value: (amount / h.targetAmount).clamp(0.0, 1.0),
                              size: 40,
                              thickness: 3,
                              color: roles.graphicOnTint,
                              center: Text(
                                '${amount.toInt()}/${h.targetAmount.toInt()}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: roles.textOnTint,
                                ),
                              ),
                            )
                          else
                            Container(
                              width: 40,
                              height: 40,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: brand.outlineIdle,
                                  width: 2.5,
                                ),
                              ),
                              child: AppIcon(
                                AppIcons.habit(h.icon),
                                color: roles.graphicOnTint,
                                size: 18,
                              ),
                            ),
                          const SizedBox(height: 8),
                          Text(
                            h.name,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                              color: done ? context.subtle : brand.ink,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

class _ExpensesWidget extends ConsumerWidget {
  const _ExpensesWidget();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(settingsProvider).currencySymbol;
    final recent = ref.watch(recentExpensesProvider).valueOrNull ?? const [];
    final now = DateTime.now();
    final todays = recent
        .where((e) => e.kind == 0 && Fmt.isSameDay(e.date, now))
        .toList();
    final spentToday = todays.fold<double>(0, (a, e) => a + e.amount);
    final brand = context.brand;
    final reportMonth = ref.watch(reportMonthProvider);
    final budgets =
        reportMonth.year == now.year && reportMonth.month == now.month
        ? (ref.watch(budgetProgressProvider).valueOrNull ?? const [])
        : const <BudgetProgress>[];
    final monthlyBudget = budgets.isEmpty
        ? 0.0
        : (budgets
                  .where((row) => row.budget.categoryId == null)
                  .firstOrNull
                  ?.budget
                  .amount ??
              budgets.fold<double>(0, (sum, row) => sum + row.budget.amount));
    final dailyBudget = monthlyBudget <= 0
        ? null
        : monthlyBudget / DateUtils.getDaysInMonth(now.year, now.month);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          "Today's spending",
          actionLabel: 'Open',
          onAction: () => context.push('/expenses'),
        ),
        TintCard(
          accent: brand.expense,
          onTap: () => context.push('/expenses'),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Spent today',
                      style: TextStyle(
                        color: context.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: Fmt.money(spentToday, currency)),
                          if (dailyBudget != null)
                            TextSpan(
                              text: ' / ${Fmt.money(dailyBudget, currency)}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0,
                                color: context.subtle,
                              ),
                            ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.8,
                      ),
                    ),
                    if (dailyBudget != null) ...[
                      const SizedBox(height: 10),
                      BrandProgressBar(
                        value: spentToday / dailyBudget,
                        color: brand.expense,
                        semanticsLabel: 'Spent today',
                      ),
                    ],
                  ],
                ),
              ),
              Text(
                '${todays.length} ${todays.length == 1 ? 'entry' : 'entries'}',
                style: TextStyle(
                  color: brand.expenseRoles.textOnTint,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FocusWidget extends ConsumerWidget {
  const _FocusWidget();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(focusStatsProvider).valueOrNull ?? FocusStats.empty;
    final goal = ref.watch(focusGoalProvider);
    final brand = context.brand;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Focus',
          actionLabel: 'Start',
          onAction: () => context.push('/focus'),
        ),
        TintCard(
          accent: brand.focus,
          onTap: () => context.push('/focus'),
          child: Row(
            children: [
              ProgressRing(
                value: goal == 0 ? 0 : stats.today.inMinutes / goal,
                size: 78,
                thickness: 9,
                dashedGuide: false,
                color: brand.focus,
                center: FittedBox(
                  child: Text(
                    Fmt.percent(goal == 0 ? 0 : stats.today.inMinutes / goal),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      Fmt.duration(stats.today),
                      style: Theme.of(
                        context,
                      ).textTheme.titleLarge?.copyWith(fontSize: 24),
                    ),
                    Text(
                      'of ${Fmt.durationFromMinutes(goal)} · '
                      '${stats.sessionsToday} sessions',
                      style: TextStyle(color: context.muted, fontSize: 13),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NotesWidget extends ConsumerWidget {
  const _NotesWidget();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(recentNotesProvider).valueOrNull ?? const [];
    final noteCount = ref.watch(activeNoteCountProvider).valueOrNull ?? 0;
    final brand = context.brand;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Notes',
          actionLabel: noteCount == 0 ? 'Open' : 'All $noteCount',
          onAction: () => context.push('/notes'),
        ),
        if (notes.isEmpty)
          _quiet(context, 'No notes yet.')
        else
          Row(
            children: [
              for (final (i, n) in notes.take(2).indexed) ...[
                if (i > 0) const SizedBox(width: AppSpacing.grid),
                Expanded(
                  child: TintCard(
                    accent: brand.note,
                    onTap: () => context.push('/note_editor', extra: n.id),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: brand.surface,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: AppIcon(
                            AppIcons.notes,
                            color: brand.noteRoles.graphicOnTint,
                            size: 15,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          n.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          NoteRepository.previewOf(n.content, max: 60),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: context.muted, fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          Fmt.relativeDay(n.updatedAt),
                          style: TextStyle(
                            color: context.muted,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
      ],
    );
  }
}

Widget _quiet(BuildContext context, String message) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 4),
  child: Text(message, style: TextStyle(color: context.muted, fontSize: 14)),
);

class _DropWidget extends ConsumerWidget {
  const _DropWidget();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drops = ref.watch(recentDropsProvider).valueOrNull ?? const [];
    final unread = ref.watch(unreadDropsCountProvider).valueOrNull ?? 0;
    final brand = context.brand;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Drop',
          actionLabel: unread == 0 ? 'Open' : '$unread unread',
          onAction: () => context.push('/drop'),
        ),
        if (drops.isEmpty)
          _quiet(
            context,
            'No drops in inbox yet. Save links, notes, or photos.',
          )
        else
          TintCard(
            fill: brand.surface,
            padding: const EdgeInsets.all(12),
            onTap: () => context.push('/drop'),
            child: Row(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: brand.dropRoles.tintFill,
                    borderRadius: BorderRadius.circular(AppRadii.field),
                  ),
                  child: AppIcon(
                    drops.first.isArticle
                        ? AppIcons.link
                        : drops.first.isVideo
                        ? AppIcons.play
                        : drops.first.isImage
                        ? AppIcons.camera
                        : AppIcons.document,
                    color: brand.dropRoles.graphicOnTint,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (drops.first.drop.sourceDomain != null)
                        Text(
                          '${drops.first.isArticle ? 'ARTICLE · ' : ''}${drops.first.drop.sourceDomain!.toUpperCase()}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: brand.dropRoles.textOnTint,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                          ),
                        ),
                      const SizedBox(height: 2),
                      Text(
                        drops.first.title ?? drops.first.content,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Saved ${Fmt.relativeDay(drops.first.drop.createdAt)}',
                        style: TextStyle(color: context.subtle, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

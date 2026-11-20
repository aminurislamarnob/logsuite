import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ai/ai_drafts.dart';
import '../../core/ai/speech_service.dart';
import '../../core/database/app_database.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/common.dart';
import 'providers/tasks_provider.dart';
import 'repository/task_repository.dart';
import 'utils/nlp_parser.dart';
import 'widgets/task_editor_sheet.dart';
import 'widgets/task_tile.dart';

/// Filters the list views to a single project when set from the drawer.
final taskProjectFilterProvider = StateProvider<int?>((ref) => null);

enum _TaskViewMode { list, board, calendar, matrix }

enum _TaskListTab { today, upcoming, inbox }

bool _isTaskOverdue(Task task, DateTime now) {
  final due = task.dueDate;
  if (due == null || task.isCompleted) return false;
  return task.hasDueTime
      ? due.isBefore(now)
      : Fmt.dateOnly(due).isBefore(Fmt.dateOnly(now));
}

class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  final _quickAdd = TextEditingController();
  bool _listening = false;
  _TaskViewMode _viewMode = _TaskViewMode.list;
  _TaskListTab _listTab = _TaskListTab.today;

  @override
  void dispose() {
    _quickAdd.dispose();
    if (_listening) ref.read(speechServiceProvider).stop();
    super.dispose();
  }

  DateTime? _defaultDueForView() {
    if (_viewMode == _TaskViewMode.calendar) {
      return ref.read(_calendarSelectedProvider);
    }
    if (_viewMode == _TaskViewMode.list && _listTab == _TaskListTab.today) {
      return Fmt.dateOnly(DateTime.now());
    }
    return null;
  }

  Future<void> _submitQuickAdd() async {
    final raw = _quickAdd.text.trim();
    if (raw.isEmpty) return;

    final parsed = NlpParser.parse(raw);
    final repo = ref.read(taskRepositoryProvider);

    final defaultDue = parsed.dueDate ?? _defaultDueForView();

    final id = await repo.createTask(
      title: parsed.title,
      dueDate: defaultDue,
      hasDueTime: parsed.hasTime,
      priority: parsed.priority,
      projectId: ref.read(taskProjectFilterProvider),
      recurrenceRule: parsed.recurrenceRule,
      estimateMinutes: parsed.estimateMinutes,
    );
    if (parsed.tags.isNotEmpty) await repo.setTaskTags(id, parsed.tags);

    AppHaptics.success();
    _quickAdd.clear();
    if (mounted) FocusScope.of(context).unfocus();
  }

  Future<void> _dictate() async {
    final speech = ref.read(speechServiceProvider);
    if (_listening) {
      await speech.stop();
      setState(() => _listening = false);
      return;
    }
    final started = await speech.listen(
      onResult: (words, isFinal) {
        _quickAdd.text = words;
        if (isFinal && mounted) setState(() => _listening = false);
      },
    );
    if (!started) {
      if (mounted) {
        brandToast(context, 'Speech recognition unavailable on this device.');
      }
      return;
    }
    setState(() => _listening = true);
  }

  void _openProjectsDrawer() {
    brandSideSheet(context: context, builder: (_) => const _ProjectDrawer());
  }

  Future<void> _pickViewMode() async {
    final picked = await brandSheet<_TaskViewMode>(
      context: context,
      builder: (sheetContext) => SheetScaffold(
        title: 'View',
        child: TileColumn(
          children: [
            BrandTile(
              leading: const AppIcon(AppIcons.checklist),
              title: const Text('List'),
              selected: _viewMode == _TaskViewMode.list,
              onTap: () => Navigator.pop(sheetContext, _TaskViewMode.list),
            ),
            BrandTile(
              leading: const AppIcon(AppIcons.modules),
              title: const Text('Board'),
              selected: _viewMode == _TaskViewMode.board,
              onTap: () => Navigator.pop(sheetContext, _TaskViewMode.board),
            ),
            BrandTile(
              leading: const AppIcon(AppIcons.calendar),
              title: const Text('Calendar'),
              selected: _viewMode == _TaskViewMode.calendar,
              onTap: () => Navigator.pop(sheetContext, _TaskViewMode.calendar),
            ),
            BrandTile(
              leading: const AppIcon(AppIcons.otherCategory),
              title: const Text('Matrix'),
              selected: _viewMode == _TaskViewMode.matrix,
              onTap: () => Navigator.pop(sheetContext, _TaskViewMode.matrix),
            ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) {
      setState(() => _viewMode = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final projectId = ref.watch(taskProjectFilterProvider);
    final projects =
        ref.watch(projectsProvider).valueOrNull ?? const <Project>[];
    final projectName = projectId == null
        ? 'Tasks'
        : projects.where((p) => p.id == projectId).firstOrNull?.name ?? 'Tasks';
    final inset = MediaQuery.paddingOf(context).bottom;

    return BrandScaffold(
      header: BrandTopBar(
        title: projectName,
        leadingIcon: AppIcons.back,
        leadingActions: [
          CircleIconButton(
            icon: AppIcons.folder,
            tooltip: 'Projects',
            size: 40,
            onPressed: _openProjectsDrawer,
          ),
        ],
        actions: [
          _ViewSwitcherButton(mode: _viewMode, onTap: _pickViewMode),
          if (_viewMode == _TaskViewMode.list ||
              _viewMode == _TaskViewMode.board)
            CircleIconButton(
              icon: AppIcons.search,
              tooltip: 'Search',
              size: 44,
              onPressed: () => context.push('/search'),
            ),
          if (projectId != null)
            CircleIconButton(
              icon: AppIcons.filterOff,
              tooltip: 'Clear project filter',
              size: 40,
              onPressed: () =>
                  ref.read(taskProjectFilterProvider.notifier).state = null,
            ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: switch (_viewMode) {
              _TaskViewMode.list => Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.gutter,
                      4,
                      AppSpacing.gutter,
                      12,
                    ),
                    child: _TaskFilterBar(
                      selected: _listTab,
                      onSelectTab: (tab) => setState(() => _listTab = tab),
                      onOpenProjects: _openProjectsDrawer,
                    ),
                  ),
                  Expanded(
                    child: switch (_listTab) {
                      _TaskListTab.today => _TodayTaskListView(
                        onOpenUpcoming: () =>
                            setState(() => _listTab = _TaskListTab.upcoming),
                      ),
                      _TaskListTab.upcoming => _TaskListView(
                        provider: upcomingTasksProvider,
                        emptyTitle: 'Nothing in the next 7 days',
                        groupByDay: true,
                      ),
                      _TaskListTab.inbox => _TaskListView(
                        provider: inboxTasksProvider,
                        emptyTitle: 'Inbox zero',
                        emptyMessage:
                            'Quick captures without a date land here.',
                      ),
                    },
                  ),
                ],
              ),
              _TaskViewMode.board => _KanbanView(
                onOpenProjects: _openProjectsDrawer,
              ),
              _TaskViewMode.calendar => const _CalendarView(),
              _TaskViewMode.matrix => const _MatrixView(),
            },
          ),
          Positioned(
            left: AppSpacing.gutter,
            right: AppSpacing.gutter,
            bottom: 20 + inset,
            child: _buildFloatingComposer(context),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingComposer(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final selectedDay = ref.watch(_calendarSelectedProvider);

    final hint = switch (_viewMode) {
      _TaskViewMode.list => 'Add a task… “rent fri 9am !p1”',
      _TaskViewMode.board => 'Add to To do…',
      _TaskViewMode.calendar => 'Add a task for ${Fmt.dayMonth(selectedDay)}…',
      _TaskViewMode.matrix => 'Add a task… drag it to a box',
    };

    return Container(
      height: 62,
      padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
      decoration: ShapeDecoration(
        color: brand.surface,
        shape: const StadiumBorder(),
        shadows: AppShadows.composer(theme.brightness),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _quickAdd,
              onSubmitted: (_) => _submitQuickAdd(),
              textInputAction: TextInputAction.done,
              style: TextStyle(fontSize: 15, color: brand.ink),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(fontSize: 15, color: context.muted),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (_viewMode == _TaskViewMode.list) ...[
            BrandTappable(
              onPressed: () {
                final text = _quickAdd.text.trim();
                final defaultDue = _defaultDueForView();
                TaskEditorSheet.show(
                  context,
                  projectId: ref.read(taskProjectFilterProvider),
                  draft: text.isEmpty && defaultDue == null
                      ? null
                      : TaskDraft(title: text, dueDate: defaultDue),
                );
              },
              semanticsLabel: 'Set date',
              child: SizedBox(
                width: 40,
                height: 40,
                child: AppIcon(
                  AppIcons.calendar,
                  size: 20,
                  color: brand.subtle,
                ),
              ),
            ),
            BrandTappable(
              onPressed: _dictate,
              semanticsLabel: 'Dictate',
              child: SizedBox(
                width: 36,
                height: 40,
                child: AppIcon(
                  AppIcons.mic,
                  size: 19,
                  color: _listening ? brand.danger : brand.subtle,
                ),
              ),
            ),
          ],
          const SizedBox(width: 4),
          BrandTappable(
            key: const ValueKey('fab-new-task'),
            semanticsLabel: 'New task',
            onPressed: () {
              if (_quickAdd.text.trim().isNotEmpty) {
                _submitQuickAdd();
              } else {
                final defaultDue = _defaultDueForView();
                TaskEditorSheet.show(
                  context,
                  projectId: ref.read(taskProjectFilterProvider),
                  draft: defaultDue == null
                      ? null
                      : TaskDraft(title: '', dueDate: defaultDue),
                );
              }
            },
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: brand.ink,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: AppIcon(AppIcons.arrowUp, size: 20, color: brand.onInk),
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewSwitcherButton extends StatelessWidget {
  final _TaskViewMode mode;
  final VoidCallback onTap;

  const _ViewSwitcherButton({required this.mode, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final isList = mode == _TaskViewMode.list;
    final bg = isList ? brand.surface : brand.ink;
    final fg = isList ? brand.ink : brand.onInk;
    final chevronColor = isList ? brand.subtle : brand.onInkMuted;

    final (icon, label) = switch (mode) {
      _TaskViewMode.list => (AppIcons.checklist, 'List'),
      _TaskViewMode.board => (AppIcons.modules, 'Board'),
      _TaskViewMode.calendar => (AppIcons.calendar, 'Calendar'),
      _TaskViewMode.matrix => (AppIcons.otherCategory, 'Matrix'),
    };

    return BrandTappable(
      onPressed: onTap,
      semanticsLabel: 'Change view',
      child: Container(
        height: 44,
        padding: const EdgeInsets.only(left: 14, right: 12),
        decoration: ShapeDecoration(
          color: bg,
          shape: const StadiumBorder(),
          shadows: isList
              ? AppShadows.circleButton(theme.brightness)
              : const [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(icon, size: 18, color: fg),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
            const SizedBox(width: 4),
            AppIcon(AppIcons.chevronDown, size: 14, color: chevronColor),
          ],
        ),
      ),
    );
  }
}

class _TaskFilterBar extends ConsumerWidget {
  final _TaskListTab selected;
  final ValueChanged<_TaskListTab> onSelectTab;
  final VoidCallback onOpenProjects;

  const _TaskFilterBar({
    required this.selected,
    required this.onSelectTab,
    required this.onOpenProjects,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final projectId = ref.watch(taskProjectFilterProvider);
    final todayTasks = _applyFilter(
      ref.watch(todayTasksProvider).valueOrNull ?? const <Task>[],
      projectId,
    );
    final openTodayCount = todayTasks.where((t) => !t.isCompleted).length;

    Widget buildTab({
      required String label,
      required bool isSelected,
      required VoidCallback onTap,
      int? badge,
      int flex = 10,
    }) {
      return Expanded(
        flex: flex,
        child: BrandTappable(
          onPressed: () {
            AppHaptics.selection();
            onTap();
          },
          semanticsLabel: label,
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color: isSelected ? brand.ink : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w600,
                      color: isSelected ? brand.onInk : context.muted,
                    ),
                  ),
                ),
                if (badge != null && badge > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    height: 20,
                    constraints: const BoxConstraints(minWidth: 20),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? brand.taskRoles.graphicOnTint
                          : brand.taskRoles.tintFill,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$badge',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: isSelected
                            ? Colors.white
                            : brand.taskRoles.textOnTint,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: brand.well,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          buildTab(
            label: 'Today',
            isSelected: selected == _TaskListTab.today,
            onTap: () => onSelectTab(_TaskListTab.today),
            badge: openTodayCount,
            flex: 12,
          ),
          buildTab(
            label: 'Upcoming',
            isSelected: selected == _TaskListTab.upcoming,
            onTap: () => onSelectTab(_TaskListTab.upcoming),
            flex: 12,
          ),
          buildTab(
            label: 'Inbox',
            isSelected: selected == _TaskListTab.inbox,
            onTap: () => onSelectTab(_TaskListTab.inbox),
            flex: 10,
          ),
          buildTab(
            label: 'Projects',
            isSelected: projectId != null,
            onTap: onOpenProjects,
            flex: 10,
          ),
        ],
      ),
    );
  }
}

/// Applies the active project filter to any task list.
List<Task> _applyFilter(List<Task> tasks, int? projectId) => projectId == null
    ? tasks
    : tasks.where((t) => t.projectId == projectId).toList();

class _TodayTaskListView extends ConsumerStatefulWidget {
  final VoidCallback onOpenUpcoming;

  const _TodayTaskListView({required this.onOpenUpcoming});

  @override
  ConsumerState<_TodayTaskListView> createState() => _TodayTaskListViewState();
}

class _TodayTaskListViewState extends ConsumerState<_TodayTaskListView> {
  bool _doneExpanded = true;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(todayTasksProvider);
    final upcoming =
        ref.watch(upcomingTasksProvider).valueOrNull ?? const <Task>[];
    final projectId = ref.watch(taskProjectFilterProvider);
    final theme = Theme.of(context);
    final brand = context.brand;

    return async.when(
      data: (all) {
        final tasks = _applyFilter(all, projectId);
        if (tasks.isEmpty) {
          return const EmptyState(
            icon: AppIcons.checkCircle,
            title: 'Nothing due today',
            message: 'Enjoy the clear runway.',
          );
        }

        final now = DateTime.now();
        final doneTasks = tasks.where((t) => t.isCompleted).toList();
        final openTasks = tasks.where((t) => !t.isCompleted).toList();
        final overdueTasks = openTasks
            .where((t) => _isTaskOverdue(t, now))
            .toList();
        final todayOpenTasks = openTasks
            .where((t) => !_isTaskOverdue(t, now))
            .toList();

        final total = tasks.length;
        final doneCount = doneTasks.length;
        final leftCount = openTasks.length;
        final overdueCount = overdueTasks.length;
        final pct = total == 0 ? 0 : ((doneCount / total) * 100).round();

        final tomorrowDate = Fmt.dateOnly(now).add(const Duration(days: 1));
        final tomorrowCount = _applyFilter(upcoming, projectId)
            .where(
              (t) =>
                  t.dueDate != null && Fmt.isSameDay(t.dueDate!, tomorrowDate),
            )
            .length;

        return ListView(
          padding: pageInsets(context, top: 0, end: PageEnd.fab),
          children: [
            // Progress summary card (`04-tasks.html` lines 35-41)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: brand.surface,
                borderRadius: BorderRadius.circular(AppRadii.tile),
                boxShadow: AppShadows.card(theme.brightness),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          TextSpan(
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: brand.ink,
                            ),
                            children: [
                              TextSpan(
                                text: '$doneCount done · $leftCount left',
                              ),
                              if (overdueCount > 0) ...[
                                const TextSpan(text: ' · '),
                                TextSpan(
                                  text: '$overdueCount overdue',
                                  style: TextStyle(
                                    color: brand.dangerRoles.textOnTint,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 6,
                          child: Row(
                            children: [
                              if (doneCount > 0) ...[
                                Expanded(
                                  flex: doneCount,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: brand.taskRoles.graphicOnTint,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  ),
                                ),
                                if (overdueCount > 0 ||
                                    leftCount - overdueCount > 0)
                                  const SizedBox(width: 3),
                              ],
                              if (overdueCount > 0) ...[
                                Expanded(
                                  flex: overdueCount,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: brand.danger,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  ),
                                ),
                                if (leftCount - overdueCount > 0)
                                  const SizedBox(width: 3),
                              ],
                              if (leftCount - overdueCount > 0 || total == 0)
                                Expanded(
                                  flex: math.max(1, leftCount - overdueCount),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: brand.track,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    '$pct%',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: brand.ink,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // OVERDUE section (`04-tasks.html` lines 43-53)
            if (overdueTasks.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(left: 4, right: 4, bottom: 8),
                child: Text(
                  'OVERDUE',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: brand.dangerRoles.textOnTint,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              for (final t in overdueTasks) TaskTile(task: t),
              const SizedBox(height: 8),
            ],

            // TODAY section (`04-tasks.html` lines 55-80)
            if (todayOpenTasks.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(left: 4, right: 4, bottom: 8),
                child: Text(
                  'TODAY',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: brand.subtle,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              for (final t in todayOpenTasks) TaskTile(task: t),
              const SizedBox(height: 8),
            ],

            // DONE · N collapsible section (`04-tasks.html` lines 82-88)
            if (doneTasks.isNotEmpty) ...[
              BrandTappable(
                onPressed: () => setState(() => _doneExpanded = !_doneExpanded),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      AppIcon(
                        _doneExpanded
                            ? AppIcons.chevronDown
                            : AppIcons.chevronRight,
                        size: 14,
                        color: brand.subtle,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'DONE · ${doneTasks.length}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: brand.subtle,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_doneExpanded) ...[
                const SizedBox(height: 4),
                for (final t in doneTasks) _DoneTaskRow(task: t),
              ],
              const SizedBox(height: 8),
            ],

            // Tomorrow preview button (`04-tasks.html` line 90)
            if (tomorrowCount > 0)
              BrandTappable(
                onPressed: widget.onOpenUpcoming,
                child: Container(
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: brand.well,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      AppIcon(
                        AppIcons.calendar,
                        size: 18,
                        color: context.muted,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: brand.ink,
                            ),
                            children: [
                              const TextSpan(text: 'Tomorrow '),
                              TextSpan(
                                text:
                                    '· $tomorrowCount ${tomorrowCount == 1 ? 'task' : 'tasks'}',
                                style: TextStyle(
                                  color: context.muted,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      AppIcon(
                        AppIcons.chevronRight,
                        size: 16,
                        color: context.muted,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
      loading: () => const Center(child: BrandSpinner()),
      error: (e, _) =>
          EmptyState(icon: AppIcons.error, title: 'Error', message: '$e'),
    );
  }
}

class _DoneTaskRow extends ConsumerWidget {
  final Task task;

  const _DoneTaskRow({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final repo = ref.read(taskRepositoryProvider);
    return BrandTappable(
      onPressed: () => TaskEditorSheet.show(context, task: task),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Row(
          children: [
            BrandCheckbox(
              value: task.isCompleted,
              semanticsLabel: task.title,
              onChanged: (v) => repo.setCompleted(task.id, v),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                task.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  color: brand.subtle,
                  decoration: TextDecoration.lineThrough,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskListView extends ConsumerWidget {
  final StreamProvider<List<Task>> provider;
  final String emptyTitle;
  final String? emptyMessage;
  final bool groupByDay;

  const _TaskListView({
    required this.provider,
    required this.emptyTitle,
    this.emptyMessage,
    this.groupByDay = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(provider);
    final projectId = ref.watch(taskProjectFilterProvider);
    final brand = context.brand;

    return async.when(
      data: (all) {
        final tasks = _applyFilter(all, projectId);
        if (tasks.isEmpty) {
          return EmptyState(
            icon: AppIcons.checkCircle,
            title: emptyTitle,
            message: emptyMessage,
          );
        }
        if (!groupByDay) {
          return ListView.builder(
            padding: pageInsets(context, top: 4, end: PageEnd.fab),
            itemCount: tasks.length,
            itemBuilder: (_, i) => TaskTile(task: tasks[i]),
          );
        }

        final groups = <DateTime, List<Task>>{};
        for (final t in tasks) {
          if (t.dueDate == null) continue;
          groups.putIfAbsent(Fmt.dateOnly(t.dueDate!), () => []).add(t);
        }
        final days = groups.keys.toList()..sort();

        return ListView.builder(
          padding: pageInsets(context, top: 4, end: PageEnd.fab),
          itemCount: days.length,
          itemBuilder: (_, i) {
            final day = days[i];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(
                    left: 4,
                    right: 4,
                    top: 8,
                    bottom: 8,
                  ),
                  child: Text(
                    Fmt.relativeDay(day).toUpperCase(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: brand.subtle,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                ...groups[day]!.map((t) => TaskTile(task: t, showDue: false)),
              ],
            );
          },
        );
      },
      loading: () => const Center(child: BrandSpinner()),
      error: (e, _) =>
          EmptyState(icon: AppIcons.error, title: 'Error', message: '$e'),
    );
  }
}

// --- Calendar (`20-tasks-calendar.html`) ------------------------------------

final _calendarMonthProvider = StateProvider<DateTime>(
  (ref) => DateTime(DateTime.now().year, DateTime.now().month),
);

final _calendarSelectedProvider = StateProvider<DateTime>(
  (ref) => Fmt.dateOnly(DateTime.now()),
);

class _CalendarView extends ConsumerWidget {
  const _CalendarView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(_calendarMonthProvider);
    final selected = ref.watch(_calendarSelectedProvider);
    final grouped =
        ref.watch(monthTasksProvider(month)).valueOrNull ?? const {};
    final projectId = ref.watch(taskProjectFilterProvider);
    final theme = Theme.of(context);
    final brand = context.brand;
    final muted = theme.colorScheme.outline;
    final now = DateTime.now();

    final firstOfMonth = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    // Sunday-first layout (`S M T W T F S` in `20-tasks-calendar.html`).
    final leadingBlanks = firstOfMonth.weekday % 7;

    final selectedTasks = _applyFilter(
      grouped[selected] ?? const <Task>[],
      projectId,
    );
    final openCount = selectedTasks.where((t) => !t.isCompleted).length;
    final doneCount = selectedTasks.where((t) => t.isCompleted).length;

    return ListView(
      padding: pageInsets(context, top: 4, end: PageEnd.fab),
      children: [
        // White calendar card (`20-tasks-calendar.html` lines 30-45)
        Container(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
          decoration: BoxDecoration(
            color: brand.surface,
            borderRadius: BorderRadius.circular(26),
            boxShadow: AppShadows.card(theme.brightness),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        Fmt.monthYear(month),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                          color: brand.ink,
                        ),
                      ),
                    ),
                    BrandTappable(
                      onPressed: () {
                        final today = Fmt.dateOnly(DateTime.now());
                        ref.read(_calendarMonthProvider.notifier).state =
                            DateTime(today.year, today.month);
                        ref.read(_calendarSelectedProvider.notifier).state =
                            today;
                      },
                      child: Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: brand.hairline,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'Today',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: brand.ink,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    BrandTappable(
                      onPressed: () =>
                          ref.read(_calendarMonthProvider.notifier).state =
                              DateTime(month.year, month.month - 1),
                      semanticsLabel: 'Previous month',
                      child: SizedBox(
                        width: 40,
                        height: 40,
                        child: AppIcon(
                          AppIcons.chevronLeft,
                          size: 18,
                          color: brand.ink,
                        ),
                      ),
                    ),
                    BrandTappable(
                      onPressed: () =>
                          ref.read(_calendarMonthProvider.notifier).state =
                              DateTime(month.year, month.month + 1),
                      semanticsLabel: 'Next month',
                      child: SizedBox(
                        width: 40,
                        height: 40,
                        child: AppIcon(
                          AppIcons.chevronRight,
                          size: 18,
                          color: brand.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: const ['S', 'M', 'T', 'W', 'T', 'F', 'S']
                    .map(
                      (d) => Expanded(
                        child: Center(
                          child: Text(
                            d,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: muted,
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 4),
              GridView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisExtent: 44,
                  crossAxisSpacing: 2,
                  mainAxisSpacing: 2,
                ),
                itemCount: leadingBlanks + daysInMonth,
                itemBuilder: (_, i) {
                  if (i < leadingBlanks) return const SizedBox.shrink();
                  final day = DateTime(
                    month.year,
                    month.month,
                    i - leadingBlanks + 1,
                  );
                  final dayTasks = _applyFilter(
                    grouped[day] ?? const <Task>[],
                    projectId,
                  );
                  final count = dayTasks.length;
                  final hasOverdue = dayTasks.any(
                    (t) => _isTaskOverdue(t, now),
                  );
                  final isSelected = Fmt.isSameDay(day, selected);
                  final isToday = Fmt.isSameDay(day, now);
                  final dots = math.min(count, 3);

                  return GestureDetector(
                    onTap: () {
                      AppHaptics.selection();
                      ref.read(_calendarSelectedProvider.notifier).state = day;
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected
                            ? brand.ink
                            : isToday
                            ? brand.taskRoles.tintFill
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${day.day}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isSelected || isToday
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: isSelected
                                  ? brand.onInk
                                  : isToday
                                  ? brand.taskRoles.textOnTint
                                  : brand.ink,
                            ),
                          ),
                          const SizedBox(height: 3),
                          SizedBox(
                            height: 5,
                            child: dots == 0
                                ? null
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      for (var d = 0; d < dots; d++) ...[
                                        if (d > 0) const SizedBox(width: 2),
                                        Container(
                                          width: 5,
                                          height: 5,
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? brand.onInk
                                                : hasOverdue
                                                ? brand.danger
                                                : brand.taskRoles.graphicOnTint,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Selected day heading (`20-tasks-calendar.html` lines 47-50)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${Fmt.weekday(selected)} ${selected.day} ${Fmt.dayMonth(selected).split(' ').first}',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                  color: brand.ink,
                ),
              ),
              Text(
                '$openCount open · $doneCount done',
                style: TextStyle(fontSize: 13, color: muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        if (selectedTasks.isEmpty)
          EmptyState(
            icon: AppIcons.calendarDone,
            title: 'Nothing on ${Fmt.relativeDay(selected)}',
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            decoration: BoxDecoration(
              color: brand.surface,
              borderRadius: BorderRadius.circular(22),
              boxShadow: AppShadows.card(theme.brightness),
            ),
            child: Column(
              children: [
                for (final (i, t) in selectedTasks.indexed)
                  TaskTile(
                    task: t,
                    showDue: false,
                    inGroup: true,
                    showDivider: i < selectedTasks.length - 1,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

// --- Kanban / Board (`19-tasks-board.html`) ---------------------------------

class _KanbanView extends ConsumerWidget {
  final VoidCallback onOpenProjects;

  const _KanbanView({required this.onOpenProjects});

  static List<(int, String, Color)> _columnsOf(BuildContext context) => [
    (0, 'To do', context.brand.taskRoles.graphicOnTint),
    (1, 'In progress', context.brand.warning),
    (2, 'Done', context.brand.habit),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(allTasksProvider);
    final projectId = ref.watch(taskProjectFilterProvider);
    final projects =
        ref.watch(projectsProvider).valueOrNull ?? const <Project>[];
    final activeProject = projectId == null
        ? null
        : projects.where((p) => p.id == projectId).firstOrNull;
    final theme = Theme.of(context);
    final brand = context.brand;

    return async.when(
      data: (all) {
        final tasks = _applyFilter(all, projectId);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sub-header row (`19-tasks-board.html` lines 28-32)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.gutter,
                4,
                AppSpacing.gutter,
                14,
              ),
              child: Row(
                children: [
                  BrandTappable(
                    onPressed: onOpenProjects,
                    child: Container(
                      height: 40,
                      padding: const EdgeInsets.only(left: 14, right: 12),
                      decoration: BoxDecoration(
                        color: brand.surface,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: AppShadows.circleButton(theme.brightness),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            activeProject?.name ?? 'All projects',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: brand.ink,
                            ),
                          ),
                          const SizedBox(width: 6),
                          AppIcon(
                            AppIcons.chevronDown,
                            size: 14,
                            color: context.muted,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Container(
                        width: 20,
                        height: 6,
                        decoration: BoxDecoration(
                          color: brand.ink,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: brand.outlineIdle,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: brand.outlineIdle,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: pageInsets(context, top: 0, end: PageEnd.fab),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _columnsOf(context).map((col) {
                    final (status, label, color) = col;
                    final items = tasks
                        .where(
                          (t) => status == 2
                              ? t.isCompleted
                              : !t.isCompleted && t.boardStatus == status,
                        )
                        .toList();

                    return Container(
                      width: 272,
                      margin: const EdgeInsets.only(right: 12),
                      child: DragTarget<Task>(
                        onAcceptWithDetails: (details) async {
                          AppHaptics.medium();
                          final repo = ref.read(taskRepositoryProvider);
                          final task = details.data;
                          if (status == 2) {
                            await repo.setCompleted(task.id, true);
                          } else {
                            if (task.isCompleted) {
                              await repo.setCompleted(task.id, false);
                            }
                            await repo.updateTask(task.id, boardStatus: status);
                          }
                        },
                        builder: (context, candidate, _) {
                          return Container(
                            decoration: BoxDecoration(
                              color: candidate.isNotEmpty
                                  ? color.withValues(alpha: 0.14)
                                  : brand.well,
                              borderRadius: BorderRadius.circular(26),
                            ),
                            padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color: color,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          label,
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                            color: brand.ink,
                                          ),
                                        ),
                                      ),
                                      if (items.isNotEmpty)
                                        Container(
                                          height: 24,
                                          constraints: const BoxConstraints(
                                            minWidth: 24,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                          ),
                                          decoration: BoxDecoration(
                                            color: brand.surface,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          alignment: Alignment.center,
                                          child: Text(
                                            '${items.length}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800,
                                              color: brand.ink,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 10),
                                ...items.map(
                                  (t) => Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: LongPressDraggable<Task>(
                                      data: t,
                                      onDragStarted: AppHaptics.medium,
                                      feedback: Material(
                                        color: Colors.transparent,
                                        child: SizedBox(
                                          width: 252,
                                          child: _KanbanCard(
                                            task: t,
                                            projects: projects,
                                            dragging: true,
                                          ),
                                        ),
                                      ),
                                      childWhenDragging: Opacity(
                                        opacity: 0.3,
                                        child: _KanbanCard(
                                          task: t,
                                          projects: projects,
                                        ),
                                      ),
                                      child: _KanbanCard(
                                        task: t,
                                        projects: projects,
                                      ),
                                    ),
                                  ),
                                ),
                                if (status < 2)
                                  BrandTappable(
                                    onPressed: () => TaskEditorSheet.show(
                                      context,
                                      projectId: projectId,
                                    ),
                                    child: Container(
                                      height: 44,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: brand.outlineIdle,
                                          width: 1.5,
                                        ),
                                      ),
                                      alignment: Alignment.center,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          AppIcon(
                                            AppIcons.add,
                                            size: 16,
                                            color: context.muted,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Add task',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: context.muted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: BrandSpinner()),
      error: (e, _) =>
          EmptyState(icon: AppIcons.error, title: 'Error', message: '$e'),
    );
  }
}

class _KanbanCard extends ConsumerWidget {
  final Task task;
  final List<Project> projects;
  final bool dragging;

  const _KanbanCard({
    required this.task,
    required this.projects,
    this.dragging = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final muted = Theme.of(context).colorScheme.outline;
    final subtasks =
        ref.watch(subtasksProvider(task.id)).valueOrNull ?? const <Task>[];
    final project = task.projectId == null
        ? null
        : projects.where((p) => p.id == task.projectId).firstOrNull;
    final overdue = _isTaskOverdue(task, DateTime.now());

    return TintCard(
      fill: brand.surface,
      radius: 18,
      padding: const EdgeInsets.all(14),
      onTap: () => TaskEditorSheet.show(context, task: task),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  task.title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                    color: brand.ink,
                    decoration: task.isCompleted
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (task.priority <= 3) ...[
                const SizedBox(width: 8),
                Builder(
                  builder: (context) {
                    final tone = priorityColor(brand, muted, task.priority);
                    final roles = brand.roleFor(tone);
                    return Container(
                      height: 22,
                      padding: const EdgeInsets.symmetric(horizontal: 7),
                      decoration: BoxDecoration(
                        color: roles.tintFill,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'P${task.priority}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: roles.textOnTint,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
          if (subtasks.isNotEmpty) ...[
            const SizedBox(height: 10),
            Builder(
              builder: (context) {
                final done = subtasks.where((s) => s.isCompleted).length;
                final total = subtasks.length;
                final ratio = total == 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
                return Row(
                  children: [
                    Container(
                      width: 72,
                      height: 5,
                      decoration: BoxDecoration(
                        color: brand.track,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: ratio,
                        child: Container(
                          height: 5,
                          decoration: BoxDecoration(
                            color: brand.taskRoles.graphicOnTint,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '$done/$total${project != null ? ' · ${project.name}' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                    ),
                  ],
                );
              },
            ),
          ] else if (task.dueDate != null || project != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (task.dueDate != null)
                  Container(
                    height: 24,
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                    decoration: BoxDecoration(
                      color: overdue
                          ? brand.dangerRoles.tintFill
                          : brand.hairline,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      overdue
                          ? 'Overdue · ${Fmt.relativeDay(task.dueDate!).toLowerCase()}'
                          : Fmt.due(task.dueDate!, withTime: task.hasDueTime),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: overdue
                            ? brand.dangerRoles.textOnTint
                            : brand.ink,
                      ),
                    ),
                  ),
                if (task.dueDate != null && project != null)
                  const SizedBox(width: 8),
                if (project != null)
                  Flexible(
                    child: Text(
                      project.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// --- Eisenhower matrix (`21-tasks-matrix.html`) -----------------------------

class _MatrixView extends ConsumerWidget {
  const _MatrixView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(openTasksProvider);
    final projectId = ref.watch(taskProjectFilterProvider);
    final projects =
        ref.watch(projectsProvider).valueOrNull ?? const <Project>[];
    final brand = context.brand;
    final muted = Theme.of(context).colorScheme.outline;

    return async.when(
      data: (all) {
        final tasks = _applyFilter(all, projectId);
        final now = DateTime.now();
        final soon = now.add(const Duration(days: 2));

        bool urgent(Task t) => t.dueDate != null && t.dueDate!.isBefore(soon);
        bool important(Task t) => t.priority <= 2;

        final quadrants = [
          (
            title: 'Do first',
            subtitle: 'Important',
            bg: brand.dangerRoles.tintFill,
            titleColor: brand.dangerRoles.textOnTint,
            badgeColor: brand.dangerRoles.textOnTint,
            items: tasks.where((t) => urgent(t) && important(t)).toList(),
          ),
          (
            title: 'Schedule',
            subtitle: 'Important',
            bg: brand.taskRoles.tintFill,
            titleColor: brand.taskRoles.textOnTint,
            badgeColor: brand.taskRoles.textOnTint,
            items: tasks.where((t) => !urgent(t) && important(t)).toList(),
          ),
          (
            title: 'Delegate',
            subtitle: 'Not important',
            bg: brand.warningRoles.tintFill,
            titleColor: brand.warningRoles.textOnTint,
            badgeColor: brand.warningRoles.textOnTint,
            items: tasks.where((t) => urgent(t) && !important(t)).toList(),
          ),
          (
            title: 'Later',
            subtitle: 'Not important',
            bg: brand.well,
            titleColor: brand.ink,
            badgeColor: brand.ink,
            items: tasks.where((t) => !urgent(t) && !important(t)).toList(),
          ),
        ];

        return ListView(
          padding: pageInsets(context, top: 4, end: PageEnd.fab),
          children: [
            Row(
              children: [
                Expanded(
                  child: Center(
                    child: Text(
                      'URGENT',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: muted,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Center(
                    child: Text(
                      'NOT URGENT',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: muted,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _MatrixQuadrantCard(
                    quadrant: quadrants[0],
                    projects: projects,
                    minHeight: 260,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MatrixQuadrantCard(
                    quadrant: quadrants[1],
                    projects: projects,
                    minHeight: 260,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _MatrixQuadrantCard(
                    quadrant: quadrants[2],
                    projects: projects,
                    minHeight: 200,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MatrixQuadrantCard(
                    quadrant: quadrants[3],
                    projects: projects,
                    minHeight: 200,
                  ),
                ),
              ],
            ),
          ],
        );
      },
      loading: () => const Center(child: BrandSpinner()),
      error: (e, _) =>
          EmptyState(icon: AppIcons.error, title: 'Error', message: '$e'),
    );
  }
}

class _MatrixQuadrantCard extends ConsumerWidget {
  final ({
    String title,
    String subtitle,
    Color bg,
    Color titleColor,
    Color badgeColor,
    List<Task> items,
  })
  quadrant;
  final List<Project> projects;
  final double minHeight;

  const _MatrixQuadrantCard({
    required this.quadrant,
    required this.projects,
    required this.minHeight,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final muted = Theme.of(context).colorScheme.outline;
    final repo = ref.read(taskRepositoryProvider);
    final now = DateTime.now();

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
        decoration: BoxDecoration(
          color: quadrant.bg,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          quadrant.title,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                            color: quadrant.titleColor,
                          ),
                        ),
                        Text(
                          quadrant.subtitle,
                          style: TextStyle(fontSize: 11, color: muted),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    height: 24,
                    constraints: const BoxConstraints(minWidth: 24),
                    padding: const EdgeInsets.symmetric(horizontal: 7),
                    decoration: BoxDecoration(
                      color: brand.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${quadrant.items.length}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: quadrant.badgeColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            if (quadrant.items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'Empty',
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                ),
              )
            else
              for (final (i, t) in quadrant.items.indexed) ...[
                if (i > 0) const SizedBox(height: 8),
                Builder(
                  builder: (context) {
                    final overdue = _isTaskOverdue(t, now);
                    final project = t.projectId == null
                        ? null
                        : projects
                              .where((p) => p.id == t.projectId)
                              .firstOrNull;
                    final ringColor = overdue
                        ? brand.danger
                        : (t.priority <= 3
                              ? priorityColor(brand, muted, t.priority)
                              : null);

                    final String metaText;
                    if (overdue) {
                      metaText = 'Overdue';
                    } else if (t.dueDate != null) {
                      final dueStr = Fmt.due(
                        t.dueDate!,
                        withTime: t.hasDueTime,
                      );
                      metaText = project != null
                          ? '$dueStr · ${project.name}'
                          : dueStr;
                    } else {
                      metaText = project?.name ?? 'No date';
                    }

                    return BrandTappable(
                      onPressed: () => TaskEditorSheet.show(context, task: t),
                      semanticsLabel: t.title,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: brand.surface,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            BrandCheckbox(
                              value: t.isCompleted,
                              color: ringColor,
                              semanticsLabel: 'Complete ${t.title}',
                              onChanged: (v) => repo.setCompleted(t.id, v),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    t.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      height: 1.25,
                                      color: brand.ink,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    metaText,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: overdue
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: overdue
                                          ? brand.dangerRoles.textOnTint
                                          : muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
          ],
        ),
      ),
    );
  }
}

// --- Project drawer ---------------------------------------------------------

class _ProjectDrawer extends ConsumerWidget {
  const _ProjectDrawer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(projectsProvider);
    final selected = ref.watch(taskProjectFilterProvider);
    final counts = ref.watch(openTasksProvider).valueOrNull ?? const [];

    final brand = context.brand;
    final theme = Theme.of(context);

    return Drawer(
      backgroundColor: brand.canvas,
      surfaceTintColor: Colors.transparent,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Projects',
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                    ),
                  ),
                ),
                CircleIconButton(
                  icon: AppIcons.close,
                  tooltip: 'Close',
                  size: 40,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BrandTile(
                  leading: const AppIcon(AppIcons.inbox, size: 20),
                  title: const Text('All tasks'),
                  selected: selected == null,
                  onTap: () {
                    ref.read(taskProjectFilterProvider.notifier).state = null;
                    Navigator.pop(context);
                  },
                ),
                const SizedBox(height: 12),
                projects.maybeWhen(
                  data: (list) => TileColumn(
                    mainAxisSize: MainAxisSize.min,
                    children: list.map((p) {
                      final open = counts
                          .where((t) => t.projectId == p.id)
                          .length;
                      return BrandTile(
                        leading: AppIcon(
                          AppIcons.project(p.icon),
                          size: 20,
                          color: Color(p.color),
                        ),
                        title: Text(p.name),
                        trailing: open == 0
                            ? null
                            : Text(
                                '$open',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: context.muted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                        selected: selected == p.id,
                        onTap: () {
                          ref.read(taskProjectFilterProvider.notifier).state =
                              p.id;
                          Navigator.pop(context);
                        },
                        onLongPress: () async {
                          Navigator.pop(context);
                          await ref
                              .read(taskRepositoryProvider)
                              .deleteProject(p.id);
                        },
                      );
                    }).toList(),
                  ),
                  orElse: () => const SizedBox.shrink(),
                ),
                const SizedBox(height: 12),
                BrandTile(
                  leading: const AppIcon(AppIcons.add, size: 20),
                  title: const Text('New project'),
                  onTap: () => _createProject(context, ref),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createProject(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    var color = ColorPickerRow.palette.first;
    var icon = 'folder';

    final created = await brandDialog<bool>(
      context,
      title: 'New project',
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BrandField(
              controller: controller,
              autofocus: true,
              hint: 'Project name',
            ),
            const SizedBox(height: 16),
            ColorPickerRow(
              selected: color,
              onChanged: (c) => setState(() => color = c),
            ),
            const SizedBox(height: 12),
            IconPickerRow(
              options: AppIcons.projectIcons,
              selected: icon,
              color: Color(color),
              onChanged: (i) => setState(() => icon = i),
            ),
            const SizedBox(height: 20),
            BrandButton(
              label: 'Create',
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

    if (created == true && controller.text.trim().isNotEmpty) {
      await ref
          .read(taskRepositoryProvider)
          .createProject(controller.text.trim(), color, icon);
    }
    if (context.mounted) Navigator.of(context).maybePop();
  }
}

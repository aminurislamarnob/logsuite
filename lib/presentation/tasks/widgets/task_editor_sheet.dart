import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/ai_drafts.dart';
import '../../../core/database/app_database.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/widgets/brand.dart';
import '../../../core/widgets/common.dart';
import '../providers/tasks_provider.dart';
import '../repository/task_repository.dart';
import '../utils/recurrence.dart';

/// Full create/edit form for a task, presented as a bottom sheet.
///
/// Pops with the saved task's id, so a caller that prefilled the form (the
/// assistant's preview card) can tell a save from a dismissal.
class TaskEditorSheet extends ConsumerStatefulWidget {
  final Task? task;
  final int? projectId;

  /// Prefill for a new task; ignored when editing an existing one.
  final TaskDraft? draft;

  const TaskEditorSheet({super.key, this.task, this.projectId, this.draft});

  static Future<int?> show(
    BuildContext context, {
    Task? task,
    int? projectId,
    TaskDraft? draft,
  }) {
    return brandSheet<int>(
      context: context,
      builder: (_) =>
          TaskEditorSheet(task: task, projectId: projectId, draft: draft),
    );
  }

  @override
  ConsumerState<TaskEditorSheet> createState() => _TaskEditorSheetState();
}

class _TaskEditorSheetState extends ConsumerState<TaskEditorSheet> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _tags;

  DateTime? _dueDate;
  bool _hasTime = false;
  DateTime? _reminder;
  int _priority = 4;
  int? _projectId;
  String? _recurrence;
  int? _estimate;
  final _newSubtask = TextEditingController();
  final List<String> _pendingSubtasks = [];

  bool get _isEditing => widget.task != null;

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    final d = t == null ? widget.draft : null;
    _title = TextEditingController(text: t?.title ?? d?.title ?? '');
    _description = TextEditingController(
      text: t?.description ?? d?.description ?? '',
    );
    _tags = TextEditingController(text: d?.tags.join(', ') ?? '');
    _dueDate = t?.dueDate ?? d?.dueDate;
    _hasTime = t?.hasDueTime ?? d?.hasDueTime ?? false;
    _reminder = t?.reminderTime ?? d?.reminder;
    _priority = t?.priority ?? d?.priority ?? 4;
    _projectId = t?.projectId ?? d?.projectId ?? widget.projectId;
    _recurrence = t?.recurrenceRule ?? d?.recurrenceRule;
    _estimate = t?.estimateMinutes;
    if (t != null) _loadTags(t.id);
  }

  Future<void> _loadTags(int taskId) async {
    final tags = await ref.read(taskRepositoryProvider).tagsForTask(taskId);
    if (mounted) {
      setState(() {
        _tags.text = tags.map((e) => e.name).join(', ');
      });
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _tags.dispose();
    _newSubtask.dispose();
    super.dispose();
  }

  List<String> get _parsedTags => _tags.text
      .split(',')
      .map((e) => e.trim().replaceAll('#', ''))
      .where((e) => e.isNotEmpty)
      .toList();

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) return;

    final repo = ref.read(taskRepositoryProvider);
    final notifier = ref.read(notificationServiceProvider);
    final tagList = _parsedTags;

    int id;
    if (_isEditing) {
      id = widget.task!.id;
      await repo.updateTask(
        id,
        title: title,
        description: _description.text.trim(),
        dueDate: _dueDate,
        clearDueDate: _dueDate == null,
        hasDueTime: _hasTime,
        reminderTime: _reminder,
        clearReminder: _reminder == null,
        priority: _priority,
        projectId: _projectId,
        clearProject: _projectId == null,
        recurrenceRule: _recurrence,
        clearRecurrence: _recurrence == null,
        estimateMinutes: _estimate,
      );
    } else {
      id = await repo.createTask(
        title: title,
        description: _description.text.trim(),
        dueDate: _dueDate,
        hasDueTime: _hasTime,
        reminderTime: _reminder,
        priority: _priority,
        projectId: _projectId,
        recurrenceRule: _recurrence,
        estimateMinutes: _estimate,
      );
      for (final sub in _pendingSubtasks) {
        await repo.createTask(title: sub, parentTaskId: id);
      }
    }

    await repo.setTaskTags(id, tagList);

    if (_reminder != null) {
      await notifier.scheduleTaskReminder(
        taskId: id,
        title: title,
        when: _reminder!,
      );
    } else {
      await notifier.cancelTaskReminder(id);
    }

    if (mounted) Navigator.pop(context, id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final muted = theme.colorScheme.outline;
    final projects =
        ref.watch(projectsProvider).valueOrNull ?? const <Project>[];
    final selectedProject = _projectId == null
        ? null
        : projects.where((p) => p.id == _projectId).firstOrNull;
    final tags = _parsedTags;

    return SheetScaffold(
      title: _isEditing ? 'Edit task' : 'New task',
      showClose: false,
      actions: [
        if (_isEditing)
          CircleIconButton(
            icon: AppIcons.delete,
            tooltip: 'Delete task',
            color: brand.danger,
            size: 44,
            onPressed: () async {
              await ref
                  .read(taskRepositoryProvider)
                  .deleteTask(widget.task!.id);
              await ref
                  .read(notificationServiceProvider)
                  .cancelTaskReminder(widget.task!.id);
              if (context.mounted) Navigator.pop(context);
            },
          ),
        CircleIconButton(
          icon: AppIcons.close,
          tooltip: 'Close',
          size: 44,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
      bottomAction: BrandButton(label: 'Save', onPressed: _save),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title + description card (`18-task-editor.html`)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: brand.surface,
              borderRadius: BorderRadius.circular(22),
              boxShadow: AppShadows.card(theme.brightness),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _title,
                  autofocus: !_isEditing,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _save(),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                    color: brand.ink,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Task title',
                    hintStyle: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                      color: muted,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _description,
                  maxLines: 3,
                  minLines: 1,
                  textCapitalization: TextCapitalization.sentences,
                  style: TextStyle(fontSize: 14, color: muted),
                  decoration: InputDecoration(
                    hintText: 'Add notes or details…',
                    hintStyle: TextStyle(fontSize: 14, color: brand.subtle),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Due, Reminder, Repeat card (`18-task-editor.html`)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: brand.surface,
              borderRadius: BorderRadius.circular(22),
              boxShadow: AppShadows.card(theme.brightness),
            ),
            child: Column(
              children: [
                _scheduleRow(
                  context: context,
                  icon: AppIcons.calendar,
                  label: 'Due',
                  value: _dueDate == null
                      ? 'None'
                      : Fmt.due(_dueDate!, withTime: _hasTime),
                  hasValue: _dueDate != null,
                  showDivider: true,
                  onTap: _pickDueDate,
                  onClear: _dueDate == null
                      ? null
                      : () => setState(() {
                          _dueDate = null;
                          _hasTime = false;
                        }),
                ),
                _scheduleRow(
                  context: context,
                  icon: AppIcons.notifications,
                  label: 'Reminder',
                  value: _reminder == null
                      ? 'None'
                      : (_dueDate != null &&
                                Fmt.isSameDay(_reminder!, _dueDate!)
                            ? Fmt.time(_reminder!)
                            : Fmt.due(_reminder!, withTime: true)),
                  hasValue: _reminder != null,
                  showDivider: true,
                  onTap: _pickReminder,
                  onClear: _reminder == null
                      ? null
                      : () => setState(() => _reminder = null),
                ),
                _scheduleRow(
                  context: context,
                  icon: AppIcons.repeat,
                  label: 'Repeat',
                  value: Recurrence.label(_recurrence),
                  hasValue: _recurrence != null,
                  showDivider: false,
                  onTap: _pickRecurrence,
                  onClear: _recurrence == null
                      ? null
                      : () => setState(() => _recurrence = null),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Priority pills (`P1`..`P4`) (`18-task-editor.html`)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'PRIORITY',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: muted,
                letterSpacing: 0.8,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final p in const [1, 2, 3, 4]) ...[
                if (p > 1) const SizedBox(width: 8),
                Expanded(child: _buildPriorityPill(context, p)),
              ],
            ],
          ),
          const SizedBox(height: 12),

          // Project, tags, estimate pills row (`18-task-editor.html`)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _metaPill(
                  context: context,
                  onTap: () => _pickProject(projects),
                  leading: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: selectedProject != null
                          ? Color(selectedProject.color)
                          : brand.habit,
                      shape: BoxShape.circle,
                    ),
                  ),
                  label: selectedProject?.name ?? 'Project',
                ),
                const SizedBox(width: 8),
                for (final tag in tags) ...[
                  _metaPill(
                    context: context,
                    onTap: _editTagsDialog,
                    label: '#$tag',
                  ),
                  const SizedBox(width: 8),
                ],
                _metaPill(
                  context: context,
                  onTap: _pickEstimate,
                  leading: AppIcon(AppIcons.clock, size: 16, color: muted),
                  label: _estimate == null
                      ? 'Estimate'
                      : Fmt.durationFromMinutes(_estimate!),
                ),
                const SizedBox(width: 8),
                BrandTappable(
                  onPressed: _editTagsDialog,
                  semanticsLabel: 'Add a tag',
                  child: Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: brand.outlineIdle, width: 1.5),
                    ),
                    child: AppIcon(AppIcons.add, size: 16, color: muted),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Subtasks card (`18-task-editor.html`)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: brand.surface,
              borderRadius: BorderRadius.circular(22),
              boxShadow: AppShadows.card(theme.brightness),
            ),
            child: Column(
              children: [
                if (_isEditing)
                  _SubtaskList(parentId: widget.task!.id)
                else
                  for (final (idx, title) in _pendingSubtasks.indexed)
                    Container(
                      height: 44,
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: brand.hairline),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: brand.outlineIdle,
                                width: 2,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              title,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: brand.ink,
                              ),
                            ),
                          ),
                          BrandTappable(
                            onPressed: () =>
                                setState(() => _pendingSubtasks.removeAt(idx)),
                            semanticsLabel: 'Remove subtask',
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: AppIcon(
                                AppIcons.close,
                                size: 16,
                                color: muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                SizedBox(
                  height: 44,
                  child: Row(
                    children: [
                      BrandTappable(
                        onPressed: _addSubtask,
                        semanticsLabel: 'Add subtask',
                        child: AppIcon(AppIcons.add, size: 22, color: muted),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _newSubtask,
                          textCapitalization: TextCapitalization.sentences,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _addSubtask(),
                          style: TextStyle(fontSize: 14, color: brand.ink),
                          decoration: InputDecoration(
                            hintText: 'Add a subtask',
                            hintStyle: TextStyle(fontSize: 14, color: muted),
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
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriorityPill(BuildContext context, int p) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final muted = theme.colorScheme.outline;
    final selected = _priority == p;

    final (dotColor, textColor) = switch (p) {
      1 => (
        selected ? brand.dangerRoles.onInk : brand.danger,
        selected ? brand.onInk : brand.dangerRoles.textOnTint,
      ),
      2 => (
        selected ? brand.noteRoles.onInk : brand.warning,
        selected ? brand.onInk : brand.warningRoles.textOnTint,
      ),
      3 => (
        selected ? brand.taskRoles.onInk : brand.taskRoles.graphicOnTint,
        selected ? brand.onInk : brand.taskRoles.textOnTint,
      ),
      _ => (
        selected ? brand.onInkMuted : brand.subtle,
        selected ? brand.onInk : muted,
      ),
    };

    return BrandTappable(
      onPressed: () {
        AppHaptics.selection();
        setState(() => _priority = p);
      },
      semanticsLabel: 'P$p',
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: selected ? brand.ink : brand.surface,
          borderRadius: BorderRadius.circular(22),
          boxShadow: selected
              ? const []
              : AppShadows.circleButton(theme.brightness),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'P$p',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metaPill({
    required BuildContext context,
    required VoidCallback onTap,
    required String label,
    Widget? leading,
  }) {
    final theme = Theme.of(context);
    final brand = context.brand;
    return BrandTappable(
      onPressed: onTap,
      semanticsLabel: label,
      child: Container(
        height: 44,
        padding: EdgeInsets.only(left: leading == null ? 14 : 12, right: 14),
        decoration: BoxDecoration(
          color: brand.surface,
          borderRadius: BorderRadius.circular(22),
          boxShadow: AppShadows.circleButton(theme.brightness),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[leading, const SizedBox(width: 8)],
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: brand.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scheduleRow({
    required BuildContext context,
    required HugeIconData icon,
    required String label,
    required String value,
    required bool hasValue,
    required bool showDivider,
    required VoidCallback onTap,
    VoidCallback? onClear,
  }) {
    final brand = context.brand;
    final muted = Theme.of(context).colorScheme.outline;
    return BrandTappable(
      onPressed: onTap,
      onLongPress: onClear,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          border: showDivider
              ? Border(bottom: BorderSide(color: brand.hairline))
              : null,
        ),
        child: Row(
          children: [
            AppIcon(icon, size: 20, color: brand.taskRoles.graphicOnTint),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: brand.ink,
                ),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: hasValue ? FontWeight.w700 : FontWeight.w400,
                color: hasValue ? brand.ink : muted,
              ),
            ),
            const SizedBox(width: 8),
            if (onClear != null)
              BrandTappable(
                onPressed: onClear,
                semanticsLabel: 'Clear $label',
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: AppIcon(AppIcons.close, size: 15, color: brand.subtle),
                ),
              )
            else
              AppIcon(AppIcons.chevronRight, size: 16, color: brand.subtle),
          ],
        ),
      ),
    );
  }

  Future<void> _addSubtask() async {
    final text = _newSubtask.text.trim();
    if (text.isEmpty) return;
    if (widget.task != null) {
      await ref
          .read(taskRepositoryProvider)
          .createTask(title: text, parentTaskId: widget.task!.id);
    } else {
      setState(() => _pendingSubtasks.add(text));
    }
    _newSubtask.clear();
  }

  Future<void> _pickProject(List<Project> projects) async {
    final picked = await brandSheet<int?>(
      context: context,
      builder: (sheetContext) => SheetScaffold(
        title: 'Project',
        child: TileColumn(
          children: [
            BrandTile(
              leading: const AppIcon(AppIcons.inbox),
              title: const Text('None'),
              selected: _projectId == null,
              onTap: () => Navigator.pop(sheetContext, -1),
            ),
            ...projects.map(
              (p) => BrandTile(
                leading: AppIcon(
                  AppIcons.project(p.icon),
                  color: Color(p.color),
                ),
                title: Text(p.name),
                selected: _projectId == p.id,
                onTap: () => Navigator.pop(sheetContext, p.id),
              ),
            ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    setState(() => _projectId = picked == -1 ? null : picked);
  }

  Future<void> _editTagsDialog() async {
    final controller = TextEditingController(text: _tags.text);
    final saved = await brandDialog<String>(
      context,
      title: 'Tags',
      builder: (dialogContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BrandField(
            controller: controller,
            autofocus: true,
            hint: 'doctor, health, urgent',
            prefix: const AppIcon(AppIcons.tag),
            onSubmit: (v) => Navigator.pop(dialogContext, v),
          ),
          const SizedBox(height: 20),
          BrandButton(
            label: 'Done',
            onPressed: () => Navigator.pop(dialogContext, controller.text),
          ),
        ],
      ),
    );
    if (saved != null && mounted) {
      setState(() => _tags.text = saved);
    }
  }

  Future<void> _pickDueDate() async {
    final date = await brandDatePicker(
      context,
      initial: _dueDate,
      first: DateTime(2000),
      last: DateTime(2100),
      title: 'Due date',
    );
    if (date == null || !mounted) return;

    final wantsTime = await brandConfirm(
      context,
      title: 'Add a time?',
      cancelLabel: 'All day',
      confirmLabel: 'Pick time',
    );
    if (!mounted) return;

    if (wantsTime) {
      final minutes = await brandTimePicker(
        context,
        initialMinutes: _minutesOf(_dueDate ?? DateTime.now()),
        title: 'Due time',
      );
      if (minutes != null) {
        setState(() {
          _dueDate = DateTime(
            date.year,
            date.month,
            date.day,
            minutes ~/ 60,
            minutes % 60,
          );
          _hasTime = true;
        });
        return;
      }
    }
    setState(() {
      _dueDate = DateTime(date.year, date.month, date.day);
      _hasTime = false;
    });
  }

  static int _minutesOf(DateTime d) => d.hour * 60 + d.minute;

  Future<void> _pickReminder() async {
    final date = await brandDatePicker(
      context,
      initial: _reminder ?? _dueDate,
      first: DateTime.now().subtract(const Duration(days: 1)),
      last: DateTime(2100),
      title: 'Reminder date',
    );
    if (date == null || !mounted) return;
    final minutes = await brandTimePicker(
      context,
      initialMinutes: _minutesOf(
        _reminder ?? DateTime.now().add(const Duration(hours: 1)),
      ),
      title: 'Reminder time',
    );
    if (minutes == null) return;
    setState(() {
      _reminder = DateTime(
        date.year,
        date.month,
        date.day,
        minutes ~/ 60,
        minutes % 60,
      );
    });
  }

  Future<void> _pickRecurrence() async {
    final picked = await brandSheet<String?>(
      context: context,
      builder: (_) => SheetScaffold(
        title: 'Repeat',
        child: TileColumn(
          children: [
            BrandTile(
              title: const Text('Does not repeat'),
              onTap: () => Navigator.pop(context, ''),
            ),
            ...Recurrence.presets.entries.map(
              (e) => BrandTile(
                title: Text(e.value),
                selected: _recurrence == e.key,
                onTap: () => Navigator.pop(context, e.key),
              ),
            ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    setState(() => _recurrence = picked.isEmpty ? null : picked);
  }

  Future<void> _pickEstimate() async {
    final picked = await brandSheet<int>(
      context: context,
      builder: (_) => SheetScaffold(
        title: 'Time estimate',
        child: TileColumn(
          children: [
            BrandTile(
              title: const Text('None'),
              selected: _estimate == null,
              onTap: () => Navigator.pop(context, 0),
            ),
            ...[15, 25, 30, 45, 60, 90, 120].map(
              (m) => BrandTile(
                leading: const AppIcon(AppIcons.focus),
                title: Text(Fmt.durationFromMinutes(m)),
                selected: _estimate == m,
                onTap: () => Navigator.pop(context, m),
              ),
            ),
          ],
        ),
      ),
    );
    if (picked != null) {
      setState(() => _estimate = picked == 0 ? null : picked);
    }
  }
}

class _SubtaskList extends ConsumerWidget {
  final int parentId;
  const _SubtaskList({required this.parentId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subtasks = ref.watch(subtasksProvider(parentId));
    final brand = context.brand;
    final muted = Theme.of(context).colorScheme.outline;

    return subtasks.maybeWhen(
      data: (list) => Column(
        children: list
            .map(
              (s) => Container(
                height: 44,
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: brand.hairline)),
                ),
                child: Row(
                  children: [
                    BrandCheckbox(
                      value: s.isCompleted,
                      semanticsLabel: s.title,
                      onChanged: (v) => ref
                          .read(taskRepositoryProvider)
                          .setCompleted(s.id, v),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        s.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: s.isCompleted
                              ? FontWeight.w400
                              : FontWeight.w600,
                          color: s.isCompleted ? muted : brand.ink,
                          decoration: s.isCompleted
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                    BrandTappable(
                      onPressed: () =>
                          ref.read(taskRepositoryProvider).deleteTask(s.id),
                      semanticsLabel: 'Delete ${s.title}',
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: AppIcon(AppIcons.close, size: 16, color: muted),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
      orElse: () => const SizedBox.shrink(),
    );
  }
}

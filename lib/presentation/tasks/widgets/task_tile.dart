import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';

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
import 'task_editor_sheet.dart';

/// A swipe action laid out the way [SlidableAction] lays one out.
///
/// [SlidableAction] takes an [IconData], which a Hugeicons glyph is not, so the
/// icon-over-label column is rebuilt here on [CustomSlidableAction].
Widget _slideAction({
  required SlidableActionCallback onPressed,
  required Color background,
  required HugeIconData icon,
  required String label,
}) {
  // White in both themes. Swipe actions are white-on-colour everywhere else
  // on the platform, and that convention was chosen over the ratio — on the
  // dark-mode danger red it is about 2.8:1.
  const foreground = Colors.white;
  return CustomSlidableAction(
    onPressed: (ctx) {
      if (label == 'Delete') {
        AppHaptics.heavy();
      } else {
        AppHaptics.medium();
      }
      onPressed(ctx);
    },
    backgroundColor: background,
    foregroundColor: foreground,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIcon(icon, color: foreground),
        const SizedBox(height: 4),
        Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: foreground),
        ),
      ],
    ),
  );
}

/// The chip colour for a task priority. Takes the resolved palette rather than
/// a context so it stays callable from anywhere a [BrandColors] is already in
/// hand.
Color priorityColor(BrandColors brand, Color muted, int priority) =>
    switch (priority) {
      1 => brand.danger,
      2 => brand.warning,
      3 => brand.task,
      _ => muted,
    };

class TaskTile extends ConsumerWidget {
  final Task task;
  final bool showDue;
  final bool dense;

  /// When true, renders as a flush row inside a grouped surface (e.g. Calendar
  /// day card) rather than an independent shadowed card.
  final bool inGroup;

  /// Whether to draw a bottom hairline divider when [inGroup] is true.
  final bool showDivider;

  const TaskTile({
    super.key,
    required this.task,
    this.showDue = true,
    this.dense = false,
    this.inGroup = false,
    this.showDivider = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(taskRepositoryProvider);
    final theme = Theme.of(context);
    final brand = context.brand;
    final muted = theme.colorScheme.outline;
    final subtasks =
        ref.watch(subtasksProvider(task.id)).valueOrNull ?? const <Task>[];
    final projects =
        ref.watch(projectsProvider).valueOrNull ?? const <Project>[];
    final project = task.projectId == null
        ? null
        : projects.where((p) => p.id == task.projectId).firstOrNull;

    // A task due at 5pm is late at 5:01. One due 'today' with no time is
    // late tomorrow — comparing its midnight against now made every all-day
    // task light up red from the first minute of its own due date.
    final now = DateTime.now();
    final due = task.dueDate;
    final overdue =
        due != null &&
        !task.isCompleted &&
        (task.hasDueTime
            ? due.isBefore(now)
            : Fmt.dateOnly(due).isBefore(Fmt.dateOnly(now)));

    final ringColor = task.isCompleted
        ? null
        : (overdue
              ? brand.danger
              : (task.priority <= 3
                    ? priorityColor(brand, muted, task.priority)
                    : null));

    final subtitle = _buildSubtitle(
      context: context,
      brand: brand,
      muted: muted,
      overdue: overdue,
      subtasks: subtasks,
      projectName: project?.name,
    );

    final trailing = _buildTrailing(
      context: context,
      brand: brand,
      muted: muted,
      project: project,
    );

    final rowContent = Row(
      children: [
        BrandCheckbox(
          value: task.isCompleted,
          color: ringColor,
          semanticsLabel: 'Complete ${task.title}',
          onChanged: (v) async {
            final spawned = await repo.setCompleted(task.id, v);
            if (spawned != null && context.mounted) {
              brandToast(context, 'Next occurrence scheduled');
            }
          },
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                task.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: (dense || inGroup) ? 15 : 16,
                  fontWeight: FontWeight.w600,
                  decoration: task.isCompleted
                      ? TextDecoration.lineThrough
                      : null,
                  color: task.isCompleted ? brand.subtle : brand.ink,
                ),
              ),
              if (subtitle != null) ...[const SizedBox(height: 4), subtitle],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 10), trailing],
      ],
    );

    final Widget surface;
    if (inGroup) {
      surface = BrandTappable(
        onPressed: () => TaskEditorSheet.show(context, task: task),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            border: showDivider
                ? Border(bottom: BorderSide(color: brand.hairline))
                : null,
          ),
          child: rowContent,
        ),
      );
    } else {
      surface = Padding(
        padding: EdgeInsets.only(bottom: dense ? 6 : 8),
        child: TintCard(
          fill: brand.surface,
          radius: AppRadii.tile,
          padding: EdgeInsets.symmetric(
            horizontal: 14,
            vertical: dense ? 10 : 12,
          ),
          onTap: () => TaskEditorSheet.show(context, task: task),
          child: rowContent,
        ),
      );
    }

    return Slidable(
      key: ValueKey(task.id),
      startActionPane: ActionPane(
        motion: const ScrollMotion(),
        extentRatio: 0.28,
        children: [
          _slideAction(
            onPressed: (_) => context.push('/focus', extra: task.id),
            background: brand.focus,
            icon: AppIcons.play,
            label: 'Focus',
          ),
        ],
      ),
      endActionPane: ActionPane(
        motion: const ScrollMotion(),
        extentRatio: 0.5,
        children: [
          _slideAction(
            onPressed: (_) => TaskEditorSheet.show(context, task: task),
            background: theme.colorScheme.primary,
            icon: AppIcons.edit,
            label: 'Edit',
          ),
          _slideAction(
            onPressed: (_) async {
              await repo.deleteTask(task.id);
              await ref
                  .read(notificationServiceProvider)
                  .cancelTaskReminder(task.id);
            },
            background: brand.danger,
            icon: AppIcons.delete,
            label: 'Delete',
          ),
        ],
      ),
      child: surface,
    );
  }

  Widget? _buildTrailing({
    required BuildContext context,
    required BrandColors brand,
    required Color muted,
    required Project? project,
  }) {
    if (task.priority <= 3) {
      final tone = priorityColor(brand, muted, task.priority);
      final roles = brand.roleFor(tone);
      return Semantics(
        label: 'Priority ${task.priority}',
        child: Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: roles.tintFill,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'P${task.priority}',
            style: TextStyle(
              color: roles.textOnTint,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      );
    }

    if (!inGroup && project != null && project.name.trim().isNotEmpty) {
      final projectRoles = brand.roleFor(Color(project.color));
      return Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: projectRoles.tintFill,
          shape: BoxShape.circle,
        ),
        child: Text(
          project.name.trim()[0].toUpperCase(),
          style: TextStyle(
            color: projectRoles.graphicOnTint,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }

    return null;
  }

  Widget? _buildSubtitle({
    required BuildContext context,
    required BrandColors brand,
    required Color muted,
    required bool overdue,
    required List<Task> subtasks,
    required String? projectName,
  }) {
    final hasProject = projectName != null && projectName.isNotEmpty;

    // Subtask progress bar row (`Finish design review` in `04-tasks.html`).
    if (subtasks.isNotEmpty && !inGroup) {
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
              '$done/$total${hasProject ? ' · $projectName' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ),
        ],
      );
    }

    final spans = <InlineSpan>[];
    var showBell = false;

    if (inGroup && subtasks.isNotEmpty) {
      final done = subtasks.where((s) => s.isCompleted).length;
      spans.add(
        TextSpan(
          text: '$done of ${subtasks.length} subtasks',
          style: TextStyle(fontSize: 12, color: muted),
        ),
      );
    } else if (showDue && task.dueDate != null) {
      final due = task.dueDate!;
      final isToday = Fmt.isSameDay(due, DateTime.now());
      final label = isToday
          ? (task.hasDueTime ? Fmt.time(due) : 'Anytime')
          : Fmt.due(due, withTime: task.hasDueTime);

      if (overdue) {
        spans.add(
          TextSpan(
            text: Fmt.due(due, withTime: task.hasDueTime),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: brand.dangerRoles.textOnTint,
            ),
          ),
        );
      } else {
        showBell = task.hasDueTime || task.reminderTime != null;
        spans.add(
          TextSpan(
            text: label,
            style: TextStyle(fontSize: 12, color: muted),
          ),
        );
      }
    } else if (!showDue && task.dueDate != null) {
      final due = task.dueDate!;
      final label = task.hasDueTime ? Fmt.time(due) : 'Anytime';
      spans.add(
        TextSpan(
          text: label,
          style: TextStyle(fontSize: 12, color: muted),
        ),
      );
    } else if (hasProject) {
      spans.add(
        TextSpan(
          text: 'Anytime',
          style: TextStyle(fontSize: 12, color: muted),
        ),
      );
    }

    if (hasProject) {
      spans.add(
        TextSpan(
          text: spans.isEmpty ? projectName : ' · $projectName',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: muted,
          ),
        ),
      );
    }

    if (task.recurrenceRule != null) {
      final rec = Recurrence.label(task.recurrenceRule);
      spans.add(
        TextSpan(
          text: spans.isEmpty ? rec : ' · $rec',
          style: TextStyle(fontSize: 12, color: muted),
        ),
      );
    }

    if (task.loggedMinutes > 0) {
      final logged = Fmt.durationFromMinutes(task.loggedMinutes);
      spans.add(
        TextSpan(
          text: spans.isEmpty ? logged : ' · $logged',
          style: TextStyle(
            fontSize: 12,
            color: brand.focusRoles.textOnTint,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    if (spans.isEmpty) return null;

    final textWidget = Text.rich(
      TextSpan(children: spans),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    if (!showBell) return textWidget;

    return Row(
      children: [
        AppIcon(AppIcons.notifications, size: 12, color: muted),
        const SizedBox(width: 5),
        Expanded(child: textWidget),
      ],
    );
  }
}

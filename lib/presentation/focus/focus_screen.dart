import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/app_database.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/app_forui_theme.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/common.dart';
import '../tasks/providers/tasks_provider.dart';
import '../tasks/repository/task_repository.dart';
import 'providers/focus_provider.dart';

class FocusScreen extends ConsumerStatefulWidget {
  /// Optional task to attach the session to, passed by the task tile's
  /// "Focus" swipe action.
  final int? taskId;
  const FocusScreen({super.key, this.taskId});

  @override
  ConsumerState<FocusScreen> createState() => _FocusScreenState();
}

class _FocusScreenState extends ConsumerState<FocusScreen> {
  int _completedRating = 5;

  @override
  void initState() {
    super.initState();
    if (widget.taskId != null) {
      // Link after the first frame so the provider is ready.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(focusTimerProvider.notifier).linkTask(widget.taskId);
      });
    }
  }

  void _openStatsSheet(
    BuildContext context,
    ThemeData darkTheme,
    FThemeData darkForui,
  ) {
    brandSheet(
      context: context,
      builder: (_) => Theme(
        data: darkTheme,
        child: FTheme(
          data: darkForui,
          child: _FocusStatsSheet(onEditGoal: _editGoal),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(focusTimerProvider);
    final notifier = ref.read(focusTimerProvider.notifier);
    final stats = ref.watch(focusStatsProvider).valueOrNull ?? FocusStats.empty;
    final goal = ref.watch(focusGoalProvider);
    final tasks = ref.watch(openTasksProvider).valueOrNull ?? const [];
    final linkedTask = tasks.where((t) => t.id == state.taskId).firstOrNull;
    final sessions = ref.watch(recentSessionsProvider).valueOrNull ?? const [];

    ref.listen(focusTimerProvider, (prev, next) {
      if (prev?.phase != TimerPhase.finished &&
          next.phase == TimerPhase.finished) {
        AppHaptics.success();
        setState(() => _completedRating = 5);
      }
    });

    final settings = ref.watch(settingsProvider);
    final darkTheme = AppTheme.dark(
      palette: settings.palette,
      compact: settings.compactDensity,
      locale: settings.locale,
    );
    final darkForui = brandForuiTheme(
      brightness: Brightness.dark,
      palette: settings.palette,
      compact: settings.compactDensity,
      locale: settings.locale,
    );

    return Theme(
      data: darkTheme,
      child: FTheme(
        data: darkForui,
        child: Builder(
          builder: (context) {
            final brand = context.brand;
            final accent = state.isBreak
                ? brand.successRoles.onInk
                : brand.focusRoles.onInk;

            return ColoredBox(
              color: brand.inkDeep,
              child: BrandScaffold(
                header: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.gutter,
                      8,
                      AppSpacing.gutter,
                      8,
                    ),
                    child: Row(
                      children: [
                        CircleIconButton(
                          icon: AppIcons.back,
                          tooltip: 'Back',
                          onInk: true,
                          onPressed: () async {
                            final popped = await Navigator.maybePop(context);
                            if (!popped && context.mounted) {
                              context.go('/dashboard');
                            }
                          },
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Focus',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.displaySmall
                                ?.copyWith(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.8,
                                ),
                          ),
                        ),
                        BrandTooltip(
                          message: 'Stats',
                          child: BrandTappable(
                            onPressed: () =>
                                _openStatsSheet(context, darkTheme, darkForui),
                            semanticsLabel: 'Focus stats',
                            child: Container(
                              height: 44,
                              padding: const EdgeInsets.fromLTRB(12, 0, 16, 0),
                              decoration: ShapeDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                shape: const StadiumBorder(),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  AppIcon(
                                    AppIcons.barChart,
                                    size: 18,
                                    color: Colors.white,
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    'Stats',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                child: ColoredBox(
                  color: brand.inkDeep,
                  child: state.phase == TimerPhase.finished
                      ? _buildSessionComplete(
                          context,
                          state: state,
                          notifier: notifier,
                          stats: stats,
                          goal: goal,
                          linkedTask: linkedTask,
                          lastSession: sessions.firstOrNull,
                        )
                      : _buildActiveTimer(
                          context,
                          state: state,
                          notifier: notifier,
                          stats: stats,
                          goal: goal,
                          linkedTask: linkedTask,
                          accent: accent,
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildActiveTimer(
    BuildContext context, {
    required FocusState state,
    required FocusTimerNotifier notifier,
    required FocusStats stats,
    required int goal,
    required Task? linkedTask,
    required Color accent,
  }) {
    final brand = context.brand;
    final sessionNum = (state.completedIntervals % 4) + 1;
    final eyebrow = state.isBreak
        ? 'BREAK'
        : state.mode.countsUp
        ? 'FLOW SESSION'
        : 'SESSION $sessionNum OF 4';

    final endTime = DateTime.now().add(
      Duration(seconds: state.remainingSeconds),
    );
    final supporting = state.mode.countsUp
        ? 'Counting up · tap finish when done'
        : state.running
        ? 'of ${state.targetSeconds ~/ 60} min · ends ${Fmt.time(endTime)}'
        : 'of ${state.targetSeconds ~/ 60} min · ${state.mode.label}';

    final goalFraction = goal <= 0
        ? 0.0
        : (stats.today.inMinutes / goal).clamp(0.0, 1.0);

    return ListView(
      padding: pageInsets(context, top: 8),
      children: [
        Center(child: _buildModeSelector(context, state, notifier)),
        const SizedBox(height: 18),

        // Large 260 ring (09-focus.html)
        Center(
          child: ProgressRing(
            value: state.mode.countsUp
                ? (state.elapsedSeconds % 1500) / 1500
                : state.progress,
            size: 260,
            thickness: 12,
            onInk: true,
            color: accent,
            center: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  eyebrow,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: accent,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                FittedBox(
                  child: Text(
                    state.display,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 64,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -3,
                      height: 1.0,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  supporting,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: brand.onInkMuted),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),

        // Linked task dark pill (09-focus.html)
        Center(
          child: BrandTappable(
            onPressed: _pickTask,
            child: Container(
              height: 44,
              padding: const EdgeInsets.fromLTRB(12, 0, 16, 0),
              decoration: ShapeDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                shape: const StadiumBorder(),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: brand.taskRoles.onInk,
                        width: 2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Text(
                      linkedTask?.title ?? 'Not linked to a task',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (linkedTask != null)
                    GestureDetector(
                      onTap: () => notifier.linkTask(null),
                      child: AppIcon(
                        AppIcons.close,
                        size: 14,
                        color: brand.onInkMuted,
                      ),
                    )
                  else
                    AppIcon(
                      AppIcons.chevronDown,
                      size: 14,
                      color: brand.onInkMuted,
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Ambient sound section (09-focus.html)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'AMBIENT SOUND',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: brand.onInkMuted,
              letterSpacing: 0.8,
            ),
          ),
        ),
        const SizedBox(height: 10),
        const _AmbientRow(),
        const SizedBox(height: 24),

        // Transport controls (56 reset, 84 white play/pause, 56 complete)
        _buildControls(context, state, notifier),
        const SizedBox(height: 22),

        // Bottom daily goal dark card (09-focus.html)
        BrandTappable(
          onPressed: _editGoal,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${Fmt.duration(stats.today)} of ${Fmt.durationFromMinutes(goal)} goal today',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: SizedBox(
                          height: 5,
                          child: LinearProgressIndicator(
                            value: goalFraction,
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.12,
                            ),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              brand.focusRoles.onInk,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppIcon(
                      AppIcons.streak,
                      size: 16,
                      color: brand.warningRoles.onInk,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${stats.streakDays} ${stats.streakDays == 1 ? 'day' : 'days'}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSessionComplete(
    BuildContext context, {
    required FocusState state,
    required FocusTimerNotifier notifier,
    required FocusStats stats,
    required int goal,
    required Task? linkedTask,
    required FocusSession? lastSession,
  }) {
    final brand = context.brand;
    final focusOnInk = brand.focusRoles.onInk;
    final focusedSeconds = lastSession?.actualSeconds ?? state.targetSeconds;
    final goalFraction = goal <= 0
        ? 0.0
        : (stats.today.inMinutes / goal).clamp(0.0, 1.0);

    final qualityLabel = switch (_completedRating) {
      5 => 'Deep focus',
      4 => 'Strong focus',
      3 => 'Steady focus',
      2 => 'Distracted',
      _ => 'Tough session',
    };

    return ListView(
      padding: pageInsets(context, top: 8),
      children: [
        const SizedBox(height: 6),
        Center(
          child: Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: focusOnInk.withValues(alpha: 0.10),
              border: Border.all(color: focusOnInk, width: 14),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: focusOnInk,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: AppIcon(
                    AppIcons.check,
                    size: 22,
                    color: brand.inkDeep,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  Fmt.timerClock(focusedSeconds),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 64,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -3,
                    height: 1.0,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'focused',
                  style: TextStyle(fontSize: 14, color: brand.onInkMuted),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Column(
          children: [
            Text(
              'SESSION COMPLETE',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: focusOnInk,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Session ${math.max(1, state.completedIntervals)} of 4 done',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),

        // Linked task row (31-focus-complete.html)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: brand.taskRoles.onInk, width: 2.5),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      linkedTask?.title ?? 'Not linked to a task',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      linkedTask != null
                          ? '${Fmt.duration(Duration(seconds: focusedSeconds))} logged · ${Fmt.durationFromMinutes(linkedTask.loggedMinutes)} total'
                          : 'Link a task to track time spent',
                      style: TextStyle(fontSize: 12, color: brand.onInkMuted),
                    ),
                  ],
                ),
              ),
              if (linkedTask != null)
                BrandTappable(
                  onPressed: () async {
                    await ref
                        .read(taskRepositoryProvider)
                        .setCompleted(linkedTask.id, true);
                    notifier.linkTask(null);
                  },
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: ShapeDecoration(
                      color: Colors.white.withValues(alpha: 0.10),
                      shape: const StadiumBorder(),
                    ),
                    child: const Text(
                      'Mark done',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // Focus quality rating 1..5 (31-focus-complete.html)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'FOCUS QUALITY',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: brand.onInkMuted,
                  letterSpacing: 0.8,
                ),
              ),
              Text(
                qualityLabel,
                style: TextStyle(fontSize: 13, color: brand.onInkMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: List.generate(5, (i) {
            final rating = i + 1;
            final selected = _completedRating == rating;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(left: i == 0 ? 0 : 8),
                child: BrandTappable(
                  onPressed: () {
                    AppHaptics.selection();
                    setState(() => _completedRating = rating);
                    if (lastSession != null) {
                      notifier.annotateLast(lastSession.id, rating: rating);
                    }
                  },
                  semanticsLabel: 'Focus quality $rating',
                  child: Container(
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected
                          ? focusOnInk
                          : Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      '$rating',
                      style: TextStyle(
                        color: selected ? brand.inkDeep : Colors.white,
                        fontSize: 18,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 22),

        // Goal progress bar + Break / Again / Finish buttons
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: SizedBox(
                    height: 5,
                    child: LinearProgressIndicator(
                      value: goalFraction,
                      backgroundColor: Colors.white.withValues(alpha: 0.12),
                      valueColor: AlwaysStoppedAnimation<Color>(focusOnInk),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Text(
                '${Fmt.duration(stats.today)} of ${Fmt.durationFromMinutes(goal)} goal',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: brand.onInkMuted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        BrandTappable(
          onPressed: () {
            if (lastSession != null) {
              notifier.annotateLast(lastSession.id, rating: _completedRating);
            }
            notifier.reset();
            notifier.start();
          },
          child: Container(
            height: 58,
            decoration: const ShapeDecoration(
              color: Colors.white,
              shape: StadiumBorder(),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AppIcon(AppIcons.habits, size: 20, color: brand.inkDeep),
                const SizedBox(width: 8),
                Text(
                  'Break · ${state.mode.breakMinutes > 0 ? state.mode.breakMinutes : 5} min',
                  style: TextStyle(
                    color: brand.inkDeep,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: BrandTappable(
                onPressed: () {
                  if (lastSession != null) {
                    notifier.annotateLast(
                      lastSession.id,
                      rating: _completedRating,
                    );
                  }
                  notifier.reset();
                  notifier.start();
                },
                child: Container(
                  height: 52,
                  decoration: ShapeDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    shape: const StadiumBorder(),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AppIcon(AppIcons.replay, size: 18, color: Colors.white),
                      SizedBox(width: 8),
                      Text(
                        'Again',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: BrandTappable(
                onPressed: () {
                  if (lastSession != null) {
                    notifier.annotateLast(
                      lastSession.id,
                      rating: _completedRating,
                    );
                  }
                  notifier.reset();
                },
                child: Container(
                  height: 52,
                  alignment: Alignment.center,
                  decoration: ShapeDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    shape: const StadiumBorder(),
                  ),
                  child: const Text(
                    'Finish',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildModeSelector(
    BuildContext context,
    FocusState state,
    FocusTimerNotifier notifier,
  ) {
    final brand = context.brand;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Container(
            height: 40,
            padding: const EdgeInsets.all(4),
            decoration: ShapeDecoration(
              color: Colors.white.withValues(alpha: 0.07),
              shape: const StadiumBorder(),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final m in FocusMode.values)
                  BrandTappable(
                    onPressed: () => notifier.setMode(m),
                    semanticsLabel: m.label,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: ShapeDecoration(
                        color: state.mode == m
                            ? Colors.white
                            : Colors.transparent,
                        shape: const StadiumBorder(),
                      ),
                      child: Text(
                        m.label,
                        style: TextStyle(
                          color: state.mode == m
                              ? brand.inkDeep
                              : brand.onInkMuted,
                          fontSize: 13,
                          fontWeight: state.mode == m
                              ? FontWeight.w700
                              : FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (state.mode == FocusMode.custom && state.phase == TimerPhase.idle)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                Text(
                  '${state.customMinutes} min',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Expanded(
                  child: BrandSlider(
                    value: state.customMinutes.toDouble(),
                    min: 5,
                    max: 120,
                    divisions: 23,
                    onChanged: (v) => notifier.setCustomMinutes(v.round()),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Transport controls from 09-focus.html:
  /// 56 reset circle, 84 white play/pause circle, 56 complete circle.
  Widget _buildControls(
    BuildContext context,
    FocusState state,
    FocusTimerNotifier notifier,
  ) {
    final brand = context.brand;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        BrandTooltip(
          message: 'Reset',
          child: BrandTappable(
            onPressed: notifier.reset,
            semanticsLabel: 'Reset',
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const AppIcon(
                AppIcons.replay,
                size: 22,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(width: 20),
        BrandTooltip(
          message: state.running ? 'Pause' : 'Start',
          child: BrandTappable(
            onPressed: state.running ? notifier.pause : notifier.start,
            semanticsLabel: state.running ? 'Pause' : 'Start',
            child: Container(
              width: 84,
              height: 84,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: AppIcon(
                state.running ? AppIcons.reduceMotion : AppIcons.play,
                size: 30,
                color: brand.inkDeep,
              ),
            ),
          ),
        ),
        const SizedBox(width: 20),
        BrandTooltip(
          message: 'Finish session',
          child: BrandTappable(
            onPressed: notifier.stop,
            semanticsLabel: 'Finish session',
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const AppIcon(
                AppIcons.check,
                size: 22,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickTask() async {
    final tasks = ref.read(openTasksProvider).valueOrNull ?? const [];
    if (tasks.isEmpty) {
      brandToast(context, 'No open tasks to link.');
      return;
    }
    final picked = await brandSheet<int>(
      context: context,
      builder: (_) => SheetScaffold(
        title: 'Link a task',
        child: TileColumn(
          children: tasks
              .map(
                (t) => BrandTile(
                  leading: const AppIcon(AppIcons.checkCircle),
                  title: Text(t.title),
                  subtitle: t.estimateMinutes == null
                      ? null
                      : Text(
                          'Estimate ${Fmt.durationFromMinutes(t.estimateMinutes!)}',
                        ),
                  onTap: () => Navigator.pop(context, t.id),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (picked != null) {
      ref.read(focusTimerProvider.notifier).linkTask(picked);
    }
  }

  Future<void> _editGoal() async {
    final controller = TextEditingController(
      text: '${ref.read(focusGoalProvider)}',
    );
    final result = await brandDialog<String>(
      context,
      title: 'Daily focus goal',
      builder: (dialogContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BrandField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            suffix: const Text('minutes'),
          ),
          const SizedBox(height: 20),
          BrandButton(
            label: 'Save',
            onPressed: () => Navigator.pop(dialogContext, controller.text),
          ),
        ],
      ),
    );
    final minutes = int.tryParse(result?.trim() ?? '');
    if (minutes != null && minutes > 0) {
      ref.read(focusGoalProvider.notifier).state = minutes;
    }
  }
}

class _AmbientRow extends ConsumerWidget {
  const _AmbientRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final active = ref.watch(ambientPlayerProvider);
    final notifier = ref.read(ambientPlayerProvider.notifier);

    const items = <(String, String, HugeIconData)>[
      ('rain', 'Rain', AppIcons.water),
      ('forest', 'Forest', AppIcons.forest),
      ('ocean', 'Ocean', AppIcons.ocean),
      ('cafe', 'Café', AppIcons.habits),
      ('white', 'White', AppIcons.whiteNoise),
      ('brown', 'Brown', AppIcons.brownNoise),
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: items.map((entry) {
        final (key, label, icon) = entry;
        final selected = active == key;
        return Expanded(
          child: BrandTappable(
            onPressed: () async {
              AppHaptics.selection();
              final ok = await notifier.toggle(key);
              if (!ok && context.mounted) {
                brandToast(context, 'Could not play the $label sound.');
              }
            },
            semanticsLabel: label,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: selected
                        ? brand.focusRoles.onInk
                        : Colors.white.withValues(alpha: 0.07),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: AppIcon(
                    icon,
                    size: 20,
                    color: selected ? brand.inkDeep : Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: selected ? Colors.white : brand.onInkMuted,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _FocusStatsSheet extends ConsumerWidget {
  final VoidCallback onEditGoal;

  const _FocusStatsSheet({required this.onEditGoal});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final focusOnInk = brand.focusRoles.onInk;
    final stats = ref.watch(focusStatsProvider).valueOrNull ?? FocusStats.empty;
    final sessions = ref.watch(recentSessionsProvider).valueOrNull ?? const [];
    final goal = ref.watch(focusGoalProvider);

    final ratedSessions = sessions.where((s) => s.rating != null).toList();
    final avgQuality = ratedSessions.isEmpty
        ? null
        : ratedSessions.map((s) => s.rating!).reduce((a, b) => a + b) /
              ratedSessions.length;

    final now = DateTime.now();
    final today = Fmt.dateOnly(now);
    final last7Days = List.generate(
      7,
      (i) => today.subtract(Duration(days: 6 - i)),
    );

    return SheetScaffold(
      title: 'Focus stats',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top 3 stat cards (30-focus-stats.html)
          Row(
            children: [
              Expanded(
                child: _DarkStatCard(
                  label: 'TODAY',
                  value: Fmt.duration(stats.today),
                  tinted: true,
                  accent: focusOnInk,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _DarkStatCard(
                  label: 'THIS WEEK',
                  value: Fmt.duration(stats.week),
                  accent: focusOnInk,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _DarkStatCard(
                  label: 'ALL TIME',
                  value: Fmt.duration(stats.total),
                  accent: focusOnInk,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Last 7 days bar chart card (30-focus-stats.html)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'LAST 7 DAYS',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: brand.onInkMuted,
                        letterSpacing: 0.8,
                      ),
                    ),
                    BrandTappable(
                      onPressed: () {
                        Navigator.of(context).maybePop();
                        onEditGoal();
                      },
                      child: Container(
                        height: 32,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        alignment: Alignment.center,
                        decoration: ShapeDecoration(
                          color: Colors.white.withValues(alpha: 0.10),
                          shape: const StadiumBorder(),
                        ),
                        child: Text(
                          'Goal ${Fmt.durationFromMinutes(goal)} · Change',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 104,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final (i, day) in last7Days.indexed) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(
                          child: _DayBar(
                            day: day,
                            minutes:
                                (stats.byDay[day] ?? Duration.zero).inMinutes,
                            goalMinutes: math.max(goal, 30),
                            isToday: Fmt.isSameDay(day, today),
                            accent: focusOnInk,
                            mutedColor: brand.onInkMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 3-column secondary metrics (Streak, Best hour, Focus quality)
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Day streak',
                        style: TextStyle(fontSize: 11, color: brand.onInkMuted),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          AppIcon(
                            AppIcons.streak,
                            size: 14,
                            color: brand.warningRoles.onInk,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '${stats.streakDays} ${stats.streakDays == 1 ? 'day' : 'days'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Best hour',
                        style: TextStyle(fontSize: 11, color: brand.onInkMuted),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        stats.bestHour == null
                            ? '—'
                            : Fmt.minutesOfDay(stats.bestHour! * 60),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Focus quality',
                        style: TextStyle(fontSize: 11, color: brand.onInkMuted),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        avgQuality == null
                            ? '—'
                            : '${avgQuality.toStringAsFixed(1)} / 5',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Recent sessions',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  '${stats.sessionsWeek} this week',
                  style: TextStyle(fontSize: 13, color: brand.onInkMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (sessions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
              child: Text(
                'No sessions yet.',
                style: TextStyle(color: brand.onInkMuted),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                children: [
                  for (final (i, s) in sessions.take(10).indexed)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        border: i < math.min(sessions.length, 10) - 1
                            ? Border(
                                bottom: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.08),
                                ),
                              )
                            : null,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 48,
                            child: Text(
                              Fmt.duration(Duration(seconds: s.actualSeconds)),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.note?.isNotEmpty == true
                                      ? s.note!
                                      : 'Focus session',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${Fmt.relativeDay(s.startTime)} ${Fmt.time(s.startTime)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: brand.onInkMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (s.rating != null)
                            Container(
                              height: 26,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                              ),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: s.rating! >= 5
                                    ? focusOnInk.withValues(alpha: 0.16)
                                    : Colors.white.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: Text(
                                '${s.rating} / 5',
                                style: TextStyle(
                                  color: s.rating! >= 5
                                      ? focusOnInk
                                      : Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
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
}

class _DarkStatCard extends StatelessWidget {
  final String label;
  final String value;
  final bool tinted;
  final Color accent;

  const _DarkStatCard({
    required this.label,
    required this.value,
    required this.accent,
    this.tinted = false,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tinted
            ? accent.withValues(alpha: 0.14)
            : Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: tinted ? accent : brand.onInkMuted,
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DayBar extends StatelessWidget {
  final DateTime day;
  final int minutes;
  final int goalMinutes;
  final bool isToday;
  final Color accent;
  final Color mutedColor;

  const _DayBar({
    required this.day,
    required this.minutes,
    required this.goalMinutes,
    required this.isToday,
    required this.accent,
    required this.mutedColor,
  });

  static const _letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final fraction = (minutes / goalMinutes).clamp(0.04, 1.0);
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              heightFactor: fraction,
              widthFactor: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: isToday
                      ? accent
                      : Colors.white.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _letters[day.weekday - 1],
          style: TextStyle(
            fontSize: 11,
            fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
            color: isToday ? Colors.white : mutedColor,
          ),
        ),
      ],
    );
  }
}

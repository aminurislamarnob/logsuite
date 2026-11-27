import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/haptics.dart';
import '../utils/habit_detail_stats.dart';
import 'habit_detail_motion.dart';

class HabitTodayCard extends StatefulWidget {
  final Habit habit;
  final double todayAmount;
  final int currentStreak;
  final int bestStreak;
  final StreakMilestone milestone;
  final bool isEditing;
  final VoidCallback onStartEdit;
  final VoidCallback onCancelEdit;
  final Future<void> Function(double amount) onSaveAmount;
  final Future<void> Function(double delta) onAddDelta;

  const HabitTodayCard({
    super.key,
    required this.habit,
    required this.todayAmount,
    required this.currentStreak,
    required this.bestStreak,
    required this.milestone,
    required this.isEditing,
    required this.onStartEdit,
    required this.onCancelEdit,
    required this.onSaveAmount,
    required this.onAddDelta,
  });

  @override
  State<HabitTodayCard> createState() => _HabitTodayCardState();
}

class _HabitTodayCardState extends State<HabitTodayCard> {
  final _controller = TextEditingController();
  double _draft = 0;
  double? _lastAddedDelta;
  int _undoTick = 0;
  int _celebrationTick = 0;
  bool _wasDone = false;

  @override
  void initState() {
    super.initState();
    _draft = widget.todayAmount;
    _controller.text = trimHabitAmount(widget.todayAmount);
    _wasDone = _isDoneFor(widget.todayAmount);
  }

  @override
  void didUpdateWidget(covariant HabitTodayCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isEditing && !oldWidget.isEditing) {
      _draft = widget.todayAmount;
      _controller.text = trimHabitAmount(widget.todayAmount);
      _lastAddedDelta = null;
    }
    final nowDone = _isDoneFor(widget.todayAmount);
    if (!_wasDone && nowDone && widget.habit.goalType == 0) {
      _celebrationTick++;
      AppHaptics.tap();
    }
    _wasDone = nowDone;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _isDoneFor(double amount) {
    if (widget.habit.goalType == 1) {
      return amount <= widget.habit.targetAmount;
    }
    final target = widget.habit.targetAmount <= 0
        ? 1.0
        : widget.habit.targetAmount;
    return amount >= target;
  }

  bool get _isCountUnit {
    final u = widget.habit.unit?.trim().toLowerCase();
    if (u == null || u.isEmpty) return true;
    const countUnits = {
      'pages',
      'page',
      'glasses',
      'glass',
      'cups',
      'cup',
      'cigarettes',
      'cigarette',
      'reps',
      'rep',
      'steps',
      'step',
      'times',
      'time',
      'sessions',
      'session',
    };
    return countUnits.contains(u);
  }

  void _setDraft(double value) {
    final clamped = math.max(0.0, value);
    setState(() {
      _draft = clamped;
      _controller.text = trimHabitAmount(clamped);
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    });
  }

  Future<void> _handleQuickAdd(double delta) async {
    AppHaptics.tap();
    setState(() {
      _lastAddedDelta = delta;
      _undoTick++;
    });
    await widget.onAddDelta(delta);
  }

  Future<void> _handleMarkDone() async {
    AppHaptics.tap();
    final target = widget.habit.targetAmount <= 0
        ? 1.0
        : widget.habit.targetAmount;
    final added = math.max(0.0, target - widget.todayAmount);
    setState(() {
      _lastAddedDelta = added > 0 ? added : null;
      if (added > 0) _undoTick++;
    });
    await widget.onSaveAmount(math.max(target, widget.todayAmount));
  }

  Future<void> _handleUndoAdd() async {
    final delta = _lastAddedDelta;
    if (delta == null || delta <= 0) return;
    AppHaptics.tap();
    setState(() {
      _lastAddedDelta = null;
    });
    await widget.onAddDelta(-delta);
  }

  Future<void> _handleSaveDraft() async {
    AppHaptics.tap();
    setState(() {
      _lastAddedDelta = null;
    });
    await widget.onSaveAmount(_draft);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final roles = brand.roleFor(Color(widget.habit.color));
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final kind = habitKindOf(widget.habit);
    final target = widget.habit.targetAmount <= 0 && kind != HabitKind.reduce
        ? 1.0
        : widget.habit.targetAmount;
    final unit = widget.habit.unit?.trim();
    final unitSuffix = (unit == null || unit.isEmpty) ? '' : ' $unit';

    final activeAmount = widget.isEditing ? _draft : widget.todayAmount;
    final isDone = _isDoneFor(activeAmount);
    final isReduceOver = kind == HabitKind.reduce && activeAmount > target;

    final String eyebrow = widget.isEditing
        ? 'EDIT TODAY'
        : (isDone && kind != HabitKind.reduce ? 'TODAY · DONE' : 'TODAY');

    final String headline;
    final String subline;
    if (kind == HabitKind.yesNo) {
      if (isDone) {
        headline = '${widget.currentStreak}-day streak';
        subline =
            widget.currentStreak > 0 &&
                widget.currentStreak >= widget.bestStreak
            ? 'Your longest run yet.'
            : 'See you tomorrow.';
      } else {
        headline = 'Not done yet';
        subline = widget.currentStreak == 0
            ? 'Finish to start a new streak.'
            : 'Finish to reach a ${widget.currentStreak + 1}-day streak.';
      }
    } else if (kind == HabitKind.reduce) {
      if (isReduceOver) {
        headline =
            'Over by ${trimHabitAmount(activeAmount - target)}$unitSuffix';
      } else {
        headline =
            '${trimHabitAmount(target - activeAmount)} of ${trimHabitAmount(target)} left today';
      }
      if (widget.isEditing) {
        subline = 'Was ${trimHabitAmount(widget.todayAmount)}$unitSuffix.';
      } else if (isReduceOver) {
        subline =
            'Over today\'s limit of ${trimHabitAmount(target)}$unitSuffix.';
      } else {
        subline =
            'Stay at or under ${trimHabitAmount(target)}$unitSuffix to keep your streak.';
      }
    } else {
      // Amount habit
      if (widget.isEditing) {
        if (activeAmount >= target) {
          headline = 'Goal met';
        } else {
          headline =
              '${trimHabitAmount(target - activeAmount)}$unitSuffix to go';
        }
        subline = 'Was ${trimHabitAmount(widget.todayAmount)}$unitSuffix.';
      } else if (isDone) {
        headline = '${widget.currentStreak}-day streak';
        subline =
            widget.currentStreak > 0 &&
                widget.currentStreak >= widget.bestStreak
            ? 'Your longest run yet.'
            : 'See you tomorrow.';
      } else {
        headline = '${trimHabitAmount(target - activeAmount)}$unitSuffix to go';
        subline = widget.currentStreak == 0
            ? 'Finish to start a new streak.'
            : 'Finish to reach a ${widget.currentStreak + 1}-day streak.';
      }
    }

    final quickAdds = quickAddAmounts(target);
    final ringProgress = target <= 0
        ? (activeAmount > 0 ? 1.1 : 0.0)
        : (activeAmount / target);

    final ringColor = isReduceOver ? brand.danger : roles.onInk;
    final burstColors = [
      roles.onInk,
      roles.accent,
      brand.warningRoles.onInk,
      Colors.white,
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: brand.heroSurface,
        borderRadius: BorderRadius.circular(AppRadii.hero),
        boxShadow: AppShadows.hero(theme.brightness),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top row: text + ring
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _SlideSwitcher(
                  reduceMotion: reduceMotion,
                  child: Column(
                    key: ValueKey('$eyebrow|$headline|$subline'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        eyebrow,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                          color: roles.onInk,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        headline,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                          height: 1.15,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subline,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: brand.onInkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (kind != HabitKind.yesNo) ...[
                const SizedBox(width: 14),
                GoalCelebrationWrapper(
                  celebrationTick: _celebrationTick,
                  burstColors: burstColors,
                  child: PressScale(
                    semanticsLabel: "Edit today's amount",
                    onTap: () {
                      AppHaptics.tap();
                      if (widget.isEditing) {
                        widget.onCancelEdit();
                      } else {
                        widget.onStartEdit();
                      }
                    },
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        _AnimatedTodayRing(
                          progress: ringProgress,
                          amount: activeAmount,
                          target: target,
                          color: ringColor,
                          mutedColor: brand.onInkMuted,
                          reduceMotion: reduceMotion,
                        ),
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: brand.heroSurface,
                                width: 3,
                              ),
                            ),
                            child: const Center(
                              child: AppIcon(
                                AppIcons.edit,
                                size: 13,
                                color: AppColors.ink,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),

          // Actions or inline editor
          AnimatedSize(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 300),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, anim) {
                if (reduceMotion) return child;
                return FadeTransition(
                  opacity: anim,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.98, end: 1.0).animate(anim),
                    alignment: Alignment.topCenter,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, -0.04),
                        end: Offset.zero,
                      ).animate(anim),
                      child: child,
                    ),
                  ),
                );
              },
              child: widget.isEditing && kind != HabitKind.yesNo
                  ? _buildEditor(context, brand, target, unit, kind)
                  : _buildActions(
                      context,
                      brand,
                      roles,
                      kind,
                      isDone,
                      quickAdds,
                      unitSuffix,
                      reduceMotion,
                    ),
            ),
          ),

          const SizedBox(height: 16),
          // Milestone badge row
          Container(
            padding: const EdgeInsets.only(top: 14),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
              ),
            ),
            child: Row(
              children: [
                AppIcon(
                  AppIcons.streak,
                  size: 20,
                  color: brand.warningRoles.onInk,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${widget.milestone.nextMilestone}-day badge',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${widget.milestone.daysToGo} '
                            '${widget.milestone.daysToGo == 1 ? 'day' : 'days'} to go',
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 13,
                              color: brand.onInkMuted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Container(
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        alignment: Alignment.centerLeft,
                        child: LayoutBuilder(
                          builder: (context, constraints) => AnimatedContainer(
                            duration: reduceMotion
                                ? Duration.zero
                                : const Duration(milliseconds: 700),
                            curve: Curves.easeOutCubic,
                            height: 5,
                            width:
                                constraints.maxWidth *
                                widget.milestone.progress,
                            decoration: BoxDecoration(
                              color: brand.warningRoles.onInk,
                              borderRadius: BorderRadius.circular(3),
                            ),
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

  Widget _buildActions(
    BuildContext context,
    BrandColors brand,
    ModuleColors roles,
    HabitKind kind,
    bool isDone,
    List<int> quickAdds,
    String unitSuffix,
    bool reduceMotion,
  ) {
    return Column(
      key: const ValueKey('actions'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (kind == HabitKind.yesNo)
          PressScale(
            onTap: () {
              AppHaptics.tap();
              widget.onSaveAmount(isDone ? 0 : 1);
            },
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                color: isDone
                    ? Colors.white.withValues(alpha: 0.10)
                    : Colors.white,
                borderRadius: BorderRadius.circular(26),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AppIcon(
                    isDone ? AppIcons.replay : AppIcons.check,
                    size: 18,
                    color: isDone ? Colors.white : AppColors.ink,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isDone ? 'Undo' : 'Mark done',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: isDone ? Colors.white : AppColors.ink,
                    ),
                  ),
                ],
              ),
            ),
          )
        else if (kind == HabitKind.reduce) ...[
          Row(
            children: [
              PressScale(
                enabled: widget.todayAmount > 0,
                semanticsLabel: 'Subtract 1$unitSuffix',
                onTap: () async {
                  AppHaptics.tap();
                  setState(() => _lastAddedDelta = null);
                  await widget.onAddDelta(-1);
                },
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(
                      alpha: widget.todayAmount > 0 ? 0.10 : 0.05,
                    ),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '-1',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: widget.todayAmount > 0
                          ? Colors.white
                          : brand.onInkMuted,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              PressScale(
                enabled: widget.todayAmount > 0,
                semanticsLabel: 'Reset today to 0',
                onTap: () async {
                  AppHaptics.tap();
                  setState(() => _lastAddedDelta = null);
                  await widget.onSaveAmount(0);
                },
                child: Container(
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(
                      alpha: widget.todayAmount > 0 ? 0.10 : 0.05,
                    ),
                    borderRadius: BorderRadius.circular(26),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'Reset',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: widget.todayAmount > 0
                          ? Colors.white
                          : brand.onInkMuted,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: PressScale(
                  semanticsLabel: 'Add 1$unitSuffix',
                  onTap: () => _handleQuickAdd(1),
                  child: Container(
                    height: 52,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(26),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '+1$unitSuffix',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildStatusRow(brand, roles, unitSuffix, reduceMotion),
        ] else ...[
          // Amount habit
          if (!isDone)
            Row(
              children: [
                for (final n in quickAdds) ...[
                  PressScale(
                    semanticsLabel: 'Add $n$unitSuffix',
                    onTap: () => _handleQuickAdd(n.toDouble()),
                    child: Container(
                      height: 52,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(26),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '+$n',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: PressScale(
                    onTap: _handleMarkDone,
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(26),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AppIcon(
                            AppIcons.check,
                            size: 18,
                            color: AppColors.ink,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Mark done',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                for (var i = 0; i < quickAdds.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: PressScale(
                      semanticsLabel: 'Add ${quickAdds[i]} more$unitSuffix',
                      onTap: () => _handleQuickAdd(quickAdds[i].toDouble()),
                      child: Container(
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(26),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '+${quickAdds[i]} more',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          const SizedBox(height: 12),
          _buildStatusRow(brand, roles, unitSuffix, reduceMotion),
        ],
      ],
    );
  }

  Widget _buildStatusRow(
    BrandColors brand,
    ModuleColors roles,
    String unitSuffix,
    bool reduceMotion,
  ) {
    final hasUndo = _lastAddedDelta != null && _lastAddedDelta! > 0;
    final statusText = hasUndo
        ? 'Added ${trimHabitAmount(_lastAddedDelta!)}$unitSuffix'
        : (widget.todayAmount <= 0
              ? 'Nothing logged yet'
              : '${trimHabitAmount(widget.todayAmount)}$unitSuffix logged today');

    return Row(
      children: [
        Expanded(
          child: _SlideSwitcher(
            reduceMotion: reduceMotion,
            child: Row(
              key: ValueKey('$_undoTick|$statusText'),
              children: [
                Flexible(
                  child: Text(
                    statusText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: brand.onInkMuted),
                  ),
                ),
                if (hasUndo) ...[
                  const SizedBox(width: 12),
                  PressScale(
                    onTap: _handleUndoAdd,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      child: Text(
                        'Undo',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: roles.onInk,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        PressScale(
          onTap: () {
            AppHaptics.tap();
            widget.onStartEdit();
          },
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(AppIcons.edit, size: 13, color: Colors.white),
                SizedBox(width: 6),
                Text(
                  'Edit',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEditor(
    BuildContext context,
    BrandColors brand,
    double target,
    String? unit,
    HabitKind kind,
  ) {
    final half = target / 2;
    final oneAndHalf = target * 1.5;

    return Column(
      key: const ValueKey('editor'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _StepperButton(
              label: '−',
              tooltip: 'One less',
              onTap: () {
                AppHaptics.selection();
                _setDraft(_draft - 1);
              },
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.numberWithOptions(
                          decimal: !_isCountUnit,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            _isCountUnit ? RegExp(r'[0-9]') : RegExp(r'[0-9.]'),
                          ),
                        ],
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onChanged: (v) {
                          final parsed = double.tryParse(v.trim());
                          if (parsed != null) {
                            setState(() => _draft = math.max(0.0, parsed));
                          } else if (v.trim().isEmpty) {
                            setState(() => _draft = 0);
                          }
                        },
                      ),
                    ),
                    if (unit != null && unit.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(
                        unit,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6B625C),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            _StepperButton(
              label: '+',
              tooltip: 'One more',
              onTap: () {
                AppHaptics.selection();
                _setDraft(_draft + 1);
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        Builder(
          builder: (context) {
            final chips = <Widget>[
              _EditorChip(label: 'Clear', onTap: () => _setDraft(0)),
              if (target > 1)
                _EditorChip(
                  label: trimHabitAmount(half),
                  onTap: () => _setDraft(half),
                ),
              if (target > 0)
                _EditorChip(
                  label:
                      '${trimHabitAmount(target)} · ${kind == HabitKind.reduce ? 'limit' : 'goal'}',
                  onTap: () => _setDraft(target),
                ),
              if (target > 0)
                _EditorChip(
                  label: trimHabitAmount(oneAndHalf),
                  onTap: () => _setDraft(oneAndHalf),
                ),
            ];
            return Column(
              children: [
                for (var i = 0; i < chips.length; i += 2) ...[
                  if (i > 0) const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: chips[i]),
                      if (i + 1 < chips.length) ...[
                        const SizedBox(width: 8),
                        Expanded(child: chips[i + 1]),
                      ],
                    ],
                  ),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: PressScale(
                onTap: () {
                  AppHaptics.tap();
                  widget.onCancelEdit();
                },
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: PressScale(
                onTap: _handleSaveDraft,
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'Save',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
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
}

class _StepperButton extends StatelessWidget {
  final String label;
  final String tooltip;
  final VoidCallback onTap;

  const _StepperButton({
    required this.label,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: PressScale(
        semanticsLabel: tooltip,
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _EditorChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _EditorChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: () {
        AppHaptics.selection();
        onTap();
      },
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(18),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _AnimatedTodayRing extends StatelessWidget {
  final double progress;
  final double amount;
  final double target;
  final Color color;
  final Color mutedColor;
  final bool reduceMotion;

  const _AnimatedTodayRing({
    required this.progress,
    required this.amount,
    required this.target,
    required this.color,
    required this.mutedColor,
    required this.reduceMotion,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 84,
      height: 84,
      child: TweenAnimationBuilder<double>(
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        tween: Tween<double>(end: progress.clamp(0.0, 1.0)),
        builder: (context, animatedProgress, child) => CustomPaint(
          painter: _HeroRingPainter(
            value: animatedProgress,
            color: color,
            trackColor: Colors.white.withValues(alpha: 0.10),
          ),
          child: child,
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TweenAnimationBuilder<double>(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 520),
                    curve: Curves.easeOutCubic,
                    tween: Tween<double>(end: amount),
                    builder: (context, val, _) => Text(
                      val.round().toString(),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.8,
                        height: 1.0,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Text(
                    'of ${trimHabitAmount(target)}',
                    style: TextStyle(fontSize: 11, color: mutedColor),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroRingPainter extends CustomPainter {
  final double value;
  final Color color;
  final Color trackColor;

  _HeroRingPainter({
    required this.value,
    required this.color,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const thickness = 9.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - thickness) / 2;
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..color = trackColor;
    canvas.drawCircle(center, radius, trackPaint);

    if (value <= 0) return;
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 2 * value.clamp(0.0, 1.0),
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(_HeroRingPainter oldDelegate) =>
      oldDelegate.value != value ||
      oldDelegate.color != color ||
      oldDelegate.trackColor != trackColor;
}

class _SlideSwitcher extends StatelessWidget {
  final Widget child;
  final bool reduceMotion;

  const _SlideSwitcher({required this.child, required this.reduceMotion});

  @override
  Widget build(BuildContext context) {
    if (reduceMotion) return child;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.centerLeft,
        children: [...previousChildren, ?currentChild],
      ),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.12),
            end: Offset.zero,
          ).animate(anim),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/haptics.dart';
import '../utils/habit_detail_stats.dart';
import 'habit_detail_motion.dart';

// ---------------------------------------------------------------------------
// 6.3 Range Tabs
// ---------------------------------------------------------------------------

class HabitRangeTabs extends StatelessWidget {
  final HabitRange selected;
  final bool show90Days;
  final ValueChanged<HabitRange> onChanged;

  const HabitRangeTabs({
    super.key,
    required this.selected,
    required this.show90Days,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final options = <(HabitRange, String)>[
      (HabitRange.days30, '30 days'),
      if (show90Days) (HabitRange.days90, '90 days'),
      (HabitRange.allTime, 'All time'),
    ];

    final idx = math.max(0, options.indexWhere((o) => o.$1 == selected));
    final count = options.length;
    final alignX = count <= 1 ? 0.0 : -1.0 + (2.0 * idx / (count - 1));

    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: brand.well,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            alignment: Alignment(alignX, 0),
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 380),
            curve: Curves.easeOutBack,
            child: FractionallySizedBox(
              widthFactor: 1 / count,
              heightFactor: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: brand.ink,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (final (range, label) in options)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (range != selected) {
                        AppHaptics.selection();
                        onChanged(range);
                      }
                    },
                    child: Center(
                      child: AnimatedDefaultTextStyle(
                        duration: reduceMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 220),
                        style: TextStyle(
                          fontFamily: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.fontFamily,
                          fontSize: 14,
                          fontWeight: range == selected
                              ? FontWeight.w700
                              : FontWeight.w600,
                          color: range == selected
                              ? brand.onInk
                              : context.muted,
                        ),
                        child: Text(label, maxLines: 1),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 6.4 Three Stat Tiles
// ---------------------------------------------------------------------------

class HabitStatTiles extends StatelessWidget {
  final Habit habit;
  final HabitDetailStats detail;
  final int currentStreak;
  final int bestStreak;
  final DateTime? bestStreakEnd;

  const HabitStatTiles({
    super.key,
    required this.habit,
    required this.detail,
    required this.currentStreak,
    required this.bestStreak,
    required this.bestStreakEnd,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final kind = habitKindOf(habit);

    // Tile 1: Completion
    final String compCaption;
    final Color compCaptionColor;
    if (detail.range == HabitRange.allTime) {
      compCaption = 'Since ${Fmt.dayMonth(habit.createdAt)}';
      compCaptionColor = context.muted;
    } else if (detail.prevPeriodStartsBeforeCreation ||
        detail.prevCompletionPercent == null) {
      compCaption = 'New habit';
      compCaptionColor = context.muted;
    } else {
      final diff = detail.completionPercent - detail.prevCompletionPercent!;
      if (diff > 0) {
        compCaption = 'Up from ${detail.prevCompletionPercent}%';
        compCaptionColor = brand.successRoles.textOnTint;
      } else if (diff < 0) {
        compCaption = 'Down from ${detail.prevCompletionPercent}%';
        compCaptionColor = brand.dangerRoles.textOnTint;
      } else {
        compCaption = 'Same as before';
        compCaptionColor = context.muted;
      }
    }

    // Tile 2: Best streak
    final String streakCaption;
    if (bestStreak == 0) {
      streakCaption = 'No streak yet';
    } else if (currentStreak > 0 && currentStreak >= bestStreak) {
      streakCaption = "That's now";
    } else if (bestStreakEnd != null) {
      streakCaption = 'Ended ${Fmt.dayMonth(bestStreakEnd!)}';
    } else {
      streakCaption = '';
    }

    // Tile 3: Type-specific
    final String thirdLabel;
    final String thirdValue;
    final String thirdCaption;
    if (kind == HabitKind.yesNo) {
      thirdLabel = 'Days done';
      thirdValue = '${detail.doneCount}/${detail.trackedCount}';
      thirdCaption = switch (detail.range) {
        HabitRange.days30 => 'in 30 days',
        HabitRange.days90 => 'in 90 days',
        HabitRange.allTime => 'all time',
      };
    } else if (kind == HabitKind.reduce) {
      thirdLabel = 'Daily average';
      thirdValue = detail.dailyAverage.toStringAsFixed(1);
      thirdCaption = 'limit ${trimHabitAmount(habit.targetAmount)}';
    } else {
      final unit = habit.unit?.trim();
      if (unit != null && unit.isNotEmpty) {
        final cap = '${unit[0].toUpperCase()}${unit.substring(1)}';
        thirdLabel = unit.toLowerCase().contains('page')
            ? '$cap read'
            : '$cap logged';
      } else {
        thirdLabel = 'Total logged';
      }
      thirdValue = trimHabitAmount(detail.totalAmount);
      thirdCaption =
          '${trimHabitAmount(detail.dailyAverage.roundToDouble())} a day';
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _StatCard(
            label: 'Completion',
            value: '${detail.completionPercent}',
            unit: '%',
            caption: compCaption,
            captionColor: compCaptionColor,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            label: 'Best streak',
            value: '$bestStreak',
            unit: bestStreak == 1 ? ' day' : ' days',
            caption: streakCaption,
            captionColor: context.muted,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            label: thirdLabel,
            value: thirdValue,
            caption: thirdCaption,
            captionColor: context.muted,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final String caption;
  final Color captionColor;

  const _StatCard({
    required this.label,
    required this.value,
    this.unit,
    required this.caption,
    required this.captionColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.brand;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(AppRadii.tile),
        boxShadow: AppShadows.card(theme.brightness),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.muted,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: value,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                      height: 1.1,
                      color: brand.ink,
                    ),
                  ),
                  if (unit != null)
                    TextSpan(
                      text: unit,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: context.muted,
                      ),
                    ),
                ],
              ),
              maxLines: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            caption,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: captionColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 6.5 Activity Calendar / Heatmap + Day Bar
// ---------------------------------------------------------------------------

class HabitActivityCard extends StatefulWidget {
  final Habit habit;
  final HabitDetailStats detail;
  final DateTime selectedDay;
  final Set<DateTime> editedPastDays;
  final DateTime? lastPoppedDay;
  final int popTick;
  final ValueChanged<DateTime> onSelectDay;
  final VoidCallback onEditToday;
  final Future<void> Function(DateTime day, double amount) onSavePastDay;

  const HabitActivityCard({
    super.key,
    required this.habit,
    required this.detail,
    required this.selectedDay,
    required this.editedPastDays,
    required this.lastPoppedDay,
    required this.popTick,
    required this.onSelectDay,
    required this.onEditToday,
    required this.onSavePastDay,
  });

  @override
  State<HabitActivityCard> createState() => _HabitActivityCardState();
}

class _HabitActivityCardState extends State<HabitActivityCard> {
  bool _editingPastDay = false;
  final _pastCtrl = TextEditingController();
  double _pastDraft = 0;

  @override
  void didUpdateWidget(covariant HabitActivityCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!Fmt.isSameDay(widget.selectedDay, oldWidget.selectedDay)) {
      _editingPastDay = false;
    }
  }

  @override
  void dispose() {
    _pastCtrl.dispose();
    super.dispose();
  }

  void _startPastEdit(double currentAmount) {
    setState(() {
      _editingPastDay = true;
      _pastDraft = currentAmount;
      _pastCtrl.text = trimHabitAmount(currentAmount);
    });
  }

  void _setPastDraft(double val) {
    final clamped = math.max(0.0, val);
    setState(() {
      _pastDraft = clamped;
      _pastCtrl.text = trimHabitAmount(clamped);
      _pastCtrl.selection = TextSelection.collapsed(
        offset: _pastCtrl.text.length,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final roles = brand.roleFor(Color(widget.habit.color));
    final kind = habitKindOf(widget.habit);
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final today = widget.detail.today;

    final title = switch (widget.detail.range) {
      HabitRange.days30 => 'Last 30 days',
      HabitRange.days90 => 'Last 90 days',
      HabitRange.allTime => 'Since you started',
    };

    final partlyColor = Color.alphaBlend(
      roles.accent.withValues(alpha: 0.35),
      brand.surface,
    );

    final selDate = Fmt.dateOnly(widget.selectedDay);
    final selInfo =
        widget.detail.dayInfos[selDate] ??
        HabitDayInfo(
          day: selDate,
          status: HabitDayStatus.notTracked,
          amount: 0,
        );
    final isSelToday = Fmt.isSameDay(selDate, today);
    final isSelDone = selInfo.status == HabitDayStatus.done;
    final unit = widget.habit.unit?.trim();
    final unitWord = (unit == null || unit.isEmpty) ? 'count' : unit;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        boxShadow: AppShadows.card(theme.brightness),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header + legend
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: brand.ink,
                  ),
                ),
              ),
              _LegendDot(color: brand.track, label: 'Missed'),
              if (kind == HabitKind.amount) ...[
                const SizedBox(width: 8),
                _LegendDot(color: partlyColor, label: 'Partly'),
              ],
              const SizedBox(width: 8),
              _LegendDot(color: roles.accent, label: 'Done'),
            ],
          ),
          const SizedBox(height: 12),

          // Grid
          if (widget.detail.range == HabitRange.days30)
            _build30DayCalendar(brand, roles, partlyColor, reduceMotion)
          else
            _buildWeekHeatmap(brand, roles, partlyColor, reduceMotion),

          const SizedBox(height: 12),

          // Selected Day Bar
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            decoration: BoxDecoration(
              color: brand.canvas,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Row 1: status dot + date + status
                Row(
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: switch (selInfo.status) {
                          HabitDayStatus.done => roles.accent,
                          HabitDayStatus.partly => partlyColor,
                          _ => brand.track,
                        },
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      isSelToday
                          ? 'Today'
                          : DateFormat('EEE d MMM').format(selDate),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: brand.ink,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _dayStatusText(selInfo, kind, unit, selDate),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: context.muted),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Row 2: actions or inline past editor
                AnimatedSize(
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  child: AnimatedSwitcher(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 300),
                    child: (_editingPastDay && !isSelToday)
                        ? _buildPastEditor(brand, unit)
                        : _buildDayBarActions(
                            brand,
                            kind,
                            isSelToday,
                            isSelDone,
                            selDate,
                            selInfo.amount,
                            unitWord,
                          ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),
          Text(
            kind == HabitKind.yesNo
                ? 'Tap any day to see it or mark it done'
                : 'Tap any day to see it, change its $unitWord or mark it done',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: context.muted),
          ),
        ],
      ),
    );
  }

  String _dayStatusText(
    HabitDayInfo info,
    HabitKind kind,
    String? unit,
    DateTime selDate,
  ) {
    final unitSuffix = (unit == null || unit.isEmpty) ? '' : ' $unit';
    final editedSuffix = widget.editedPastDays.contains(selDate)
        ? ' · edited'
        : '';
    final target = widget.habit.targetAmount <= 0
        ? 1.0
        : widget.habit.targetAmount;

    if (kind == HabitKind.yesNo) {
      return '${info.status == HabitDayStatus.done ? 'Done' : 'Not done'}$editedSuffix';
    }
    if (info.status == HabitDayStatus.done) {
      return 'Done · ${trimHabitAmount(info.amount)}$unitSuffix$editedSuffix';
    }
    if (info.amount > 0) {
      return '${trimHabitAmount(info.amount)} of ${trimHabitAmount(target)}$unitSuffix$editedSuffix';
    }
    return 'Not done$editedSuffix';
  }

  Widget _buildDayBarActions(
    BrandColors brand,
    HabitKind kind,
    bool isSelToday,
    bool isSelDone,
    DateTime selDate,
    double currentAmount,
    String unitWord,
  ) {
    final target = widget.habit.targetAmount <= 0 && kind != HabitKind.reduce
        ? 1.0
        : widget.habit.targetAmount;
    final editLabel = kind == HabitKind.yesNo ? 'Edit' : 'Edit $unitWord';

    return Row(
      key: const ValueKey('day_actions'),
      children: [
        if (kind != HabitKind.yesNo) ...[
          Expanded(
            child: PressScale(
              onTap: () {
                AppHaptics.tap();
                if (isSelToday) {
                  widget.onEditToday();
                } else {
                  _startPastEdit(currentAmount);
                }
              },
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: brand.surface,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AppIcon(AppIcons.edit, size: 15, color: brand.ink),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        editLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: brand.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: PressScale(
            onTap: () async {
              AppHaptics.tap();
              final double nextAmount;
              if (kind == HabitKind.reduce) {
                nextAmount = currentAmount > 0 ? 0.0 : 1.0;
              } else {
                nextAmount = isSelDone ? 0.0 : math.max(target, currentAmount);
              }
              await widget.onSavePastDay(selDate, nextAmount);
            },
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: brand.ink,
                borderRadius: BorderRadius.circular(22),
              ),
              alignment: Alignment.center,
              child: Text(
                kind == HabitKind.reduce
                    ? (currentAmount > 0 ? 'Reset' : '+1')
                    : (isSelDone ? 'Undo' : 'Mark done'),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: brand.onInk,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPastEditor(BrandColors brand, String? unit) {
    final target = widget.habit.targetAmount <= 0
        ? 1.0
        : widget.habit.targetAmount;
    final unitSuffix = (unit == null || unit.isEmpty) ? '' : ' $unit';

    return Column(
      key: const ValueKey('past_editor'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _PastStepper(
              label: '−',
              tooltip: 'One less',
              onTap: () {
                AppHaptics.selection();
                _setPastDraft(_pastDraft - 1);
              },
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: brand.surface,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: brand.ink, width: 1.5),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _pastCtrl,
                        textAlign: TextAlign.center,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: brand.ink,
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
                          setState(() => _pastDraft = parsed ?? 0);
                        },
                      ),
                    ),
                    Text(
                      'of ${trimHabitAmount(target)}$unitSuffix',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: context.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            _PastStepper(
              label: '+',
              tooltip: 'One more',
              onTap: () {
                AppHaptics.selection();
                _setPastDraft(_pastDraft + 1);
              },
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: PressScale(
                onTap: () {
                  AppHaptics.tap();
                  setState(() => _editingPastDay = false);
                },
                child: Container(
                  height: 42,
                  decoration: BoxDecoration(
                    color: brand.surface,
                    borderRadius: BorderRadius.circular(21),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: brand.ink,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: PressScale(
                onTap: () async {
                  AppHaptics.tap();
                  final day = Fmt.dateOnly(widget.selectedDay);
                  setState(() => _editingPastDay = false);
                  await widget.onSavePastDay(day, _pastDraft);
                },
                child: Container(
                  height: 42,
                  decoration: BoxDecoration(
                    color: brand.ink,
                    borderRadius: BorderRadius.circular(21),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'Save',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: brand.onInk,
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

  Widget _build30DayCalendar(
    BrandColors brand,
    ModuleColors roles,
    Color partlyColor,
    bool reduceMotion,
  ) {
    final startMonday = Fmt.startOfWeek(widget.detail.rangeStart);
    final endSunday = Fmt.startOfWeek(
      widget.detail.today,
    ).add(const Duration(days: 6));

    final days = <DateTime>[];
    var d = startMonday;
    while (!d.isAfter(endSunday)) {
      days.add(d);
      d = d.add(const Duration(days: 1));
    }

    const headers = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return Column(
      children: [
        Row(
          children: [
            for (final h in headers)
              Expanded(
                child: Text(
                  h,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: context.muted,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: days.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            mainAxisExtent: 40,
          ),
          itemBuilder: (context, index) {
            final day = days[index];
            final info =
                widget.detail.dayInfos[day] ??
                HabitDayInfo(
                  day: day,
                  status: day.isAfter(widget.detail.today)
                      ? HabitDayStatus.future
                      : HabitDayStatus.notTracked,
                  amount: 0,
                );
            final isToday = Fmt.isSameDay(day, widget.detail.today);
            final isSelected = Fmt.isSameDay(day, widget.selectedDay);
            final tappable = info.status != HabitDayStatus.future;

            final Color bg;
            final Color fg;
            Border? border;

            if (info.status == HabitDayStatus.done) {
              bg = roles.accent;
              fg = brand.onAccent(roles.accent);
            } else if (info.status == HabitDayStatus.partly) {
              bg = partlyColor;
              fg = roles.textOnTint;
            } else if (isToday && info.status == HabitDayStatus.missed) {
              bg = brand.surface;
              fg = roles.textOnTint;
              border = Border.all(color: roles.accent, width: 1.5);
            } else if (info.status == HabitDayStatus.missed) {
              bg = brand.track;
              fg = context.muted;
            } else {
              bg = Colors.transparent;
              fg = brand.subtle;
              border = Border.all(color: brand.hairline, width: 1.5);
            }

            final labelText = day.day == 1
                ? DateFormat('d MMM').format(day)
                : '${day.day}';
            final semLabel = _cellSemantics(day, info, isToday);
            final isPopped =
                widget.lastPoppedDay != null &&
                Fmt.isSameDay(widget.lastPoppedDay!, day);

            Widget innerCell = AnimatedContainer(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(isSelected ? 8.5 : 12),
                border: border,
              ),
              alignment: Alignment.center,
              child: Text(
                labelText,
                maxLines: 1,
                style: TextStyle(
                  fontSize: day.day == 1 ? 10 : 13,
                  fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                  color: fg,
                ),
              ),
            );

            Widget cell = isSelected
                ? Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: brand.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: brand.ink, width: 2),
                    ),
                    child: innerCell,
                  )
                : innerCell;

            if (isPopped && !reduceMotion) {
              cell = _CellPop(popTick: widget.popTick, child: cell);
            }

            return Semantics(
              button: tappable,
              enabled: tappable,
              label: semLabel,
              child: GestureDetector(
                onTap: tappable
                    ? () {
                        AppHaptics.selection();
                        widget.onSelectDay(day);
                      }
                    : null,
                child: cell,
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildWeekHeatmap(
    BrandColors brand,
    ModuleColors roles,
    Color partlyColor,
    bool reduceMotion,
  ) {
    final startMonday = Fmt.startOfWeek(widget.detail.effectiveStart);
    final endSunday = Fmt.startOfWeek(
      widget.detail.today,
    ).add(const Duration(days: 6));

    final weeks = <DateTime>[];
    var w = startMonday;
    while (!w.isAfter(endSunday)) {
      weeks.add(w);
      w = w.add(const Duration(days: 7));
    }

    const cellGap = 4.0;
    const cellSize = 16.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Mon / Wed / Fri / Sun labels
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var row = 0; row < 7; row++) ...[
              if (row > 0) const SizedBox(height: cellGap),
              SizedBox(
                height: cellSize,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    switch (row) {
                      0 => 'Mon',
                      2 => 'Wed',
                      4 => 'Fri',
                      6 => 'Sun',
                      _ => '',
                    },
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: context.muted,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    for (var wi = 0; wi < weeks.length; wi++) ...[
                      if (wi > 0) const SizedBox(width: cellGap),
                      Column(
                        children: [
                          for (var row = 0; row < 7; row++) ...[
                            if (row > 0) const SizedBox(height: cellGap),
                            _buildHeatmapCell(
                              weeks[wi].add(Duration(days: row)),
                              cellSize,
                              brand,
                              roles,
                              partlyColor,
                              reduceMotion,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    for (var wi = 0; wi < weeks.length; wi++) ...[
                      if (wi > 0) const SizedBox(width: cellGap),
                      SizedBox(
                        width: cellSize,
                        child: _monthLabelForWeek(weeks, wi) == null
                            ? const SizedBox.shrink()
                            : OverflowBox(
                                maxWidth: 40,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  _monthLabelForWeek(weeks, wi)!,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: context.muted,
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String? _monthLabelForWeek(List<DateTime> weeks, int index) {
    final w = weeks[index];
    if (index == 0) return DateFormat('MMM').format(w);
    final prev = weeks[index - 1];
    if (w.month != prev.month) {
      return DateFormat('MMM').format(w);
    }
    return null;
  }

  Widget _buildHeatmapCell(
    DateTime day,
    double size,
    BrandColors brand,
    ModuleColors roles,
    Color partlyColor,
    bool reduceMotion,
  ) {
    final info =
        widget.detail.dayInfos[day] ??
        HabitDayInfo(
          day: day,
          status: day.isAfter(widget.detail.today)
              ? HabitDayStatus.future
              : HabitDayStatus.notTracked,
          amount: 0,
        );
    final isToday = Fmt.isSameDay(day, widget.detail.today);
    final isSelected = Fmt.isSameDay(day, widget.selectedDay);
    final tappable = info.status != HabitDayStatus.future;

    final Color bg;
    Border? border;
    if (info.status == HabitDayStatus.done) {
      bg = roles.accent;
    } else if (info.status == HabitDayStatus.partly) {
      bg = partlyColor;
    } else if (isToday && info.status == HabitDayStatus.missed) {
      bg = brand.surface;
      border = Border.all(color: roles.accent, width: 1.5);
    } else if (info.status == HabitDayStatus.missed) {
      bg = brand.track;
    } else {
      bg = Colors.transparent;
      border = Border.all(color: brand.hairline, width: 1);
    }

    return Semantics(
      button: tappable,
      enabled: tappable,
      label: _cellSemantics(day, info, isToday),
      child: GestureDetector(
        onTap: tappable
            ? () {
                AppHaptics.selection();
                widget.onSelectDay(day);
              }
            : null,
        child: isSelected
            ? Container(
                width: size,
                height: size,
                padding: const EdgeInsets.all(1.5),
                decoration: BoxDecoration(
                  color: brand.surface,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: brand.ink, width: 1.5),
                ),
                child: AnimatedContainer(
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 350),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(2),
                    border: border,
                  ),
                ),
              )
            : AnimatedContainer(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 350),
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(4),
                  border: border,
                ),
              ),
      ),
    );
  }

  String _cellSemantics(DateTime day, HabitDayInfo info, bool isToday) {
    final dateStr = DateFormat('EEE d MMM').format(day);
    final todayPrefix = isToday ? 'today, ' : '';
    final unit = widget.habit.unit?.trim();
    final unitSuffix = (unit == null || unit.isEmpty) ? '' : ' $unit';
    return switch (info.status) {
      HabitDayStatus.done =>
        '$dateStr, ${todayPrefix}done, ${trimHabitAmount(info.amount)}$unitSuffix',
      HabitDayStatus.partly =>
        '$dateStr, $todayPrefix${trimHabitAmount(info.amount)} of ${trimHabitAmount(widget.habit.targetAmount)}$unitSuffix',
      HabitDayStatus.missed => '$dateStr, ${todayPrefix}missed',
      HabitDayStatus.notTracked => '$dateStr, not tracked',
      HabitDayStatus.future => '$dateStr, upcoming',
    };
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: context.muted,
          ),
        ),
      ],
    );
  }
}

class _PastStepper extends StatelessWidget {
  final String label;
  final String tooltip;
  final VoidCallback onTap;

  const _PastStepper({
    required this.label,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Tooltip(
      message: tooltip,
      child: PressScale(
        semanticsLabel: tooltip,
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: brand.surface,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: brand.ink,
            ),
          ),
        ),
      ),
    );
  }
}

class _CellPop extends StatefulWidget {
  final int popTick;
  final Widget child;

  const _CellPop({required this.popTick, required this.child});

  @override
  State<_CellPop> createState() => _CellPopState();
}

class _CellPopState extends State<_CellPop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 1.22,
        ).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 45,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.22,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 55,
      ),
    ]).animate(_ctrl);
    _ctrl.forward();
  }

  @override
  void didUpdateWidget(covariant _CellPop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.popTick != oldWidget.popTick) {
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ScaleTransition(scale: _scale, child: widget.child);
}

// ---------------------------------------------------------------------------
// 6.6 Insight Card
// ---------------------------------------------------------------------------

class HabitInsightCard extends StatefulWidget {
  final Habit habit;
  final HabitDetailStats detail;
  final VoidCallback onChangeReminder;

  const HabitInsightCard({
    super.key,
    required this.habit,
    required this.detail,
    required this.onChangeReminder,
  });

  @override
  State<HabitInsightCard> createState() => _HabitInsightCardState();
}

class _HabitInsightCardState extends State<HabitInsightCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _ctrl.value = 1.0;
    } else if (_ctrl.status == AnimationStatus.dismissed) {
      _ctrl.forward();
    }
  }

  @override
  void didUpdateWidget(covariant HabitInsightCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.detail.range != widget.detail.range &&
        !MediaQuery.of(context).disableAnimations) {
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  static const _pluralNames = {
    1: 'Mondays',
    2: 'Tuesdays',
    3: 'Wednesdays',
    4: 'Thursdays',
    5: 'Fridays',
    6: 'Saturdays',
    7: 'Sundays',
  };

  static const _letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final roles = brand.roleFor(Color(widget.habit.color));
    final hasWeak = widget.detail.hasWeakSpot;
    final weak = widget.detail.weakestWeekday;
    final best = widget.detail.bestWeekday;

    final reminderStr = widget.habit.reminderMinutes == null
        ? null
        : Fmt.minutesOfDay(widget.habit.reminderMinutes!);

    final String title;
    final String body;
    if (hasWeak && weak != null && best != null) {
      final weakName = _pluralNames[weak.weekday] ?? '';
      final bestName = _pluralNames[best.weekday] ?? '';
      title = '$weakName are your weak spot';
      final reminderNote = reminderStr == null
          ? ''
          : ' A $reminderStr reminder may come too late that day.';
      body =
          'Done on ${weak.done} of ${weak.tracked} $weakName, against ${(best.rate * 100).round()}% on $bestName.$reminderNote';
    } else {
      title = 'Steady all week';
      final reminderNote = reminderStr == null
          ? ''
          : ' Your $reminderStr reminder is working.';
      body = 'No day of the week falls behind in this range.$reminderNote';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: roles.tintFill,
        borderRadius: BorderRadius.circular(AppRadii.card),
        boxShadow: AppShadows.card(theme.brightness),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: brand.surface,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: AppIcon(
                    AppIcons.idea,
                    size: 20,
                    color: roles.graphicOnTint,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: brand.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: roles.textOnTint,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            constraints: const BoxConstraints(minHeight: 76),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            decoration: BoxDecoration(
              color: brand.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (context, _) => Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < 7; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(
                      child: _buildWeekdayBar(
                        i,
                        widget.detail.weekdayRates[i],
                        hasWeak && weak?.weekday == i + 1,
                        roles,
                        brand,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (hasWeak) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: PressScale(
                onTap: () {
                  AppHaptics.tap();
                  widget.onChangeReminder();
                },
                child: Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  decoration: BoxDecoration(
                    color: brand.ink,
                    borderRadius: BorderRadius.circular(21),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'Change reminder time',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: brand.onInk,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWeekdayBar(
    int index,
    WeekdayRate rate,
    bool isWeak,
    ModuleColors roles,
    BrandColors brand,
  ) {
    final start = (index * 55) / 850.0;
    final end = (start + 500 / 850.0).clamp(0.0, 1.0);
    final t = Curves.easeOutCubic.transform(
      ((_ctrl.value - start) / (end - start)).clamp(0.0, 1.0),
    );
    final barHeight = math.max(4.0, 40.0 * rate.rate * t);
    final color = isWeak ? brand.warning : roles.accent;

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          height: barHeight,
          decoration: BoxDecoration(
            color: rate.tracked == 0 ? brand.track : color,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _letters[index],
          style: TextStyle(
            fontSize: 11,
            fontWeight: isWeak ? FontWeight.w800 : FontWeight.w600,
            color: isWeak ? brand.warningRoles.textOnTint : context.muted,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 6.7 Getting Steadier? (Rolling Trend Chart)
// ---------------------------------------------------------------------------

class HabitTrendCard extends StatefulWidget {
  final Habit habit;
  final HabitDetailStats detail;

  const HabitTrendCard({super.key, required this.habit, required this.detail});

  @override
  State<HabitTrendCard> createState() => _HabitTrendCardState();
}

class _HabitTrendCardState extends State<HabitTrendCard>
    with TickerProviderStateMixin {
  late final AnimationController _drawCtrl;
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _drawCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _drawCtrl.value = 1.0;
      _pulseCtrl.stop();
    } else if (_drawCtrl.status == AnimationStatus.dismissed) {
      _drawCtrl.forward();
      _pulseCtrl.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant HabitTrendCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.detail.range != widget.detail.range &&
        !MediaQuery.of(context).disableAnimations) {
      _drawCtrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _drawCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final roles = brand.roleFor(Color(widget.habit.color));
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    final (verdictText, verdictColor) = switch (widget.detail.trendVerdict) {
      TrendVerdict.trendingUp => (
        'Yes, trending up',
        brand.successRoles.textOnTint,
      ),
      TrendVerdict.slipping => (
        'Slipping lately',
        brand.dangerRoles.textOnTint,
      ),
      TrendVerdict.steady => ('Holding steady', context.muted),
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        boxShadow: AppShadows.card(theme.brightness),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  'Getting steadier?',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: brand.ink,
                  ),
                ),
              ),
              if (widget.detail.showTrendChart)
                Text(
                  verdictText,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: verdictColor,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (!widget.detail.showTrendChart)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Your trend shows up after a week.',
                style: TextStyle(fontSize: 13, color: context.muted),
              ),
            )
          else ...[
            Row(
              children: [
                SizedBox(
                  width: 32,
                  height: 96,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final y in ['100%', '50%', '0%'])
                        Text(
                          y,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: context.muted,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: SizedBox(
                    height: 96,
                    child: AnimatedBuilder(
                      animation: Listenable.merge([_drawCtrl, _pulseCtrl]),
                      builder: (context, _) => CustomPaint(
                        painter: _TrendPainter(
                          points: widget.detail.rollingSeries,
                          lineColor: roles.accent,
                          gridColor: brand.hairline,
                          targetColor: brand.warning,
                          surfaceColor: brand.surface,
                          drawProgress: _drawCtrl.value,
                          pulseProgress: reduceMotion ? 0 : _pulseCtrl.value,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 38),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    Fmt.dayMonth(widget.detail.rollingSeries.first.day),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: context.muted,
                    ),
                  ),
                  Text(
                    Fmt.dayMonth(
                      widget
                          .detail
                          .rollingSeries[widget.detail.rollingSeries.length ~/
                              2]
                          .day,
                    ),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: context.muted,
                    ),
                  ),
                  Text(
                    'Today',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: context.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 2,
                  child: CustomPaint(
                    painter: _DashPainter(color: brand.warning),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '7-day average against your 80% target',
                  style: TextStyle(fontSize: 12, color: context.muted),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  final Color color;

  _DashPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2;
    canvas.drawLine(const Offset(0, 1), const Offset(6, 1), p);
    canvas.drawLine(const Offset(10, 1), const Offset(16, 1), p);
  }

  @override
  bool shouldRepaint(_DashPainter oldDelegate) => oldDelegate.color != color;
}

class _TrendPainter extends CustomPainter {
  final List<RollingPoint> points;
  final Color lineColor;
  final Color gridColor;
  final Color targetColor;
  final Color surfaceColor;
  final double drawProgress;
  final double pulseProgress;

  _TrendPainter({
    required this.points,
    required this.lineColor,
    required this.gridColor,
    required this.targetColor,
    required this.surfaceColor,
    required this.drawProgress,
    required this.pulseProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (final y in [1.0, size.height / 2, size.height - 1]) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Dashed 80% target line
    final targetY = size.height * 0.2;
    final targetPaint = Paint()
      ..color = targetColor
      ..strokeWidth = 1.5;
    for (double x = 0; x < size.width; x += 8) {
      canvas.drawLine(
        Offset(x, targetY),
        Offset(math.min(x + 4, size.width), targetY),
        targetPaint,
      );
    }

    final coords = <Offset>[];
    final count = points.length;
    for (var i = 0; i < count; i++) {
      final x = count == 1 ? size.width : (i / (count - 1)) * size.width;
      final y = (1.0 - points[i].rate.clamp(0.0, 1.0)) * (size.height - 2) + 1;
      coords.add(Offset(x, y));
    }

    final fullPath = Path()..moveTo(coords.first.dx, coords.first.dy);
    for (var i = 1; i < coords.length; i++) {
      fullPath.lineTo(coords[i].dx, coords[i].dy);
    }

    // Draw line left-to-right
    final easedDraw = Curves.easeOutCubic.transform(drawProgress);
    final metrics = fullPath.computeMetrics().toList();
    if (metrics.isNotEmpty) {
      final partial = metrics.first.extractPath(
        0,
        metrics.first.length * easedDraw,
      );
      final linePaint = Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(partial, linePaint);
    }

    // Area + end dot fade in after 200ms (0.2 of 1s)
    final fadeT = ((drawProgress - 0.2) / 0.5).clamp(0.0, 1.0);
    if (fadeT > 0) {
      final areaPath = Path.from(fullPath)
        ..lineTo(coords.last.dx, size.height)
        ..lineTo(coords.first.dx, size.height)
        ..close();
      canvas.drawPath(
        areaPath,
        Paint()..color = lineColor.withValues(alpha: 0.12 * fadeT),
      );

      final last = coords.last;
      if (drawProgress >= 0.99 && pulseProgress > 0) {
        final ringR = 5.0 + 9.0 * pulseProgress;
        final ringAlpha = (1.0 - pulseProgress) * 0.45;
        canvas.drawCircle(
          last,
          ringR,
          Paint()..color = lineColor.withValues(alpha: ringAlpha),
        );
      }

      canvas.drawCircle(
        last,
        5.5,
        Paint()..color = surfaceColor.withValues(alpha: fadeT),
      );
      canvas.drawCircle(
        last,
        3.5,
        Paint()..color = lineColor.withValues(alpha: fadeT),
      );
    }
  }

  @override
  bool shouldRepaint(_TrendPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.drawProgress != drawProgress ||
      oldDelegate.pulseProgress != pulseProgress ||
      oldDelegate.lineColor != lineColor;
}

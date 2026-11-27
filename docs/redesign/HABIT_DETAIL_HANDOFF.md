# Habit detail (screen 23) — implementation handoff

This document is self-contained. It tells you how to replace the app's
current habit detail with the new design. Do this one screen only; nothing
else in the app should change.

## 1. The job in one paragraph

Today, tapping a habit card on the Habits screen opens a bottom sheet,
`_HabitDetailSheet` in `lib/presentation/habits/habits_screen.dart`. Replace
it with a **full-page screen**, `HabitDetailScreen`, reached by its own route.
The new screen puts today's logging first, lets the user correct any logged
amount, and explains the habit's history with a range selector, three stats,
a tappable calendar, one insight and a trend chart. All data already exists.
**No database or schema change is needed or allowed.**

## 2. Reference files

| File | What it shows |
|---|---|
| `docs/redesign/screens/23-habit-detail.png` | The screen, default state (today part-logged, 30-day range). 2× render, 390 pt wide. |
| `docs/redesign/screens/23b-habit-detail-editing.png` | The three editing states: after a quick-add (with Undo), editing today, editing a past day. |
| `docs/redesign/screens/23c-habit-detail-done-90d.png` | Today done, 90-day range, a past done day selected. |
| `docs/redesign/html/23-habit-detail.html` | The default state as static HTML. Read exact sizes, colours, radii, spacing and weights from its inline styles. It is a drawing to measure, not code to port. Its icons are placeholders. |

The example habit is "Read 20 pages": daily, target 20, unit "pages",
reminder 9:30 PM, created 24 Jul. Every number in the pictures is sample
data. On the real screen every value comes from the database.

## 3. Rules

1. **Presentation layer only.** You may edit `lib/presentation/habits/**`,
   add a route in `lib/core/router/app_router.dart`, and add pure helper
   functions under `lib/presentation/habits/utils/`. Do not touch
   `lib/core/database/**`, do not regenerate `.g.dart` files, do not add
   packages.
2. **Writes go through the existing repository** (`HabitRepository`):
   `setDayAmount(habitId, day, amount)` to set a day's total (0 deletes the
   row), `addToDay(habitId, delta)` for quick-adds, `updateHabit`,
   `deleteHabit`. One `HabitLogs` row per habit per day, as today.
3. **No hardcoded colours or fonts.** Use `context.brand`, the habit's own
   colour (`Color(habit.color)` through `brand.roleFor(...)`, as the current
   sheet does), and the theme's text styles. The app has four palettes in
   light and dark, and a Bangla font fallback; all must keep working.
4. **Use the existing widget kit** in `lib/core/widgets/` (`BrandScaffold`,
   `CircleIconButton`, `BrandButton`, `BrandSegmented`, `BrandField`,
   `ProgressRing`, `brandConfirm`, `brandSheet`…) and `AppIcons`. Only build a
   new widget when nothing fits, and keep it in the habits folder.
5. **No mock data, no dead buttons.** If something can't be backed by data,
   leave it out and close the gap in the layout.
6. **Never skip, delete or weaken a test.**
7. `dart format .`, `flutter analyze` and `flutter test` must pass.

## 4. Navigation

- Add a route `/habits/:id` (nested under `/habits` in `app_router.dart`,
  wrapped in the same `ModuleLockGate(module: AppModule.habits, …)`). It
  builds `HabitDetailScreen(habitId: int.parse(id))`.
- In `_HabitCard`, `_openDetail` becomes `context.push('/habits/${habit.id}')`.
- If the habit no longer exists (deleted elsewhere), pop back to the list.
- When the work is done, `_HabitDetailSheet` and helpers that only it used
  are deleted. `_HabitCard.editDay` (the old amount dialog) is deleted once
  nothing calls it.
- The screen watches `habitProvider(id)` / `habitsListProvider` and
  `habitLogsProvider(id)` / `habitStatsProvider(id)`, so it updates live when
  logs change.

## 5. Habit types the screen must handle

Read the type from the `Habits` row:

| Type | How to detect | Today card shows |
|---|---|---|
| **Amount** (the design) | `goalType == 0` and (`unit != null` or `targetAmount > 1`) | amount vs target, quick-adds, Mark done |
| **Yes / no** | `goalType == 0`, `unit == null`, `targetAmount <= 1` | Mark done / Undo only; no ring numbers, no editor field |
| **Reduce** | `goalType == 1` | amount vs allowance: "2 of 3 left today" / "Over by 1"; a `+1` button and Edit; no Mark done |

Schedule (`frequencyType`): 0 daily; 1 fixed weekdays (`weekdayMask`, bit 0 =
Monday); 2 "X times per week". The helpers `_isHabitScheduledOn`,
`_isHabitDoneOn` and `_habitFrequencyLabel` at the top of `habits_screen.dart`
already encode this. Reuse them (move them to `utils/` if the new screen
lives in its own file).

A day is **done** when `_isHabitDoneOn` is true. A day is **partly done** when
an amount habit logged more than 0 but less than the target. Otherwise a
scheduled past day is **missed**. Days before `createdAt`, and days the
schedule skips, are **not tracked**. They are never counted or drawn as
missed.

## 6. The screen, top to bottom

### 6.1 Header
- Left: back (circle button, tooltip "Back to habits").
- Right: Edit (pencil, opens `HabitEditorSheet.show(context, habit: habit)`)
  and ⋯ (menu with **Archive habit** and **Delete habit**).
- Below: the habit's icon on a filled rounded square in the habit colour, the
  name (28/800), and the subtitle `"<frequency label> · reminder <time>"`
  (omit the reminder part when `reminderMinutes` is null).

### 6.2 Today card (dark hero)
The most important card: the user should be able to log without scrolling.

- **Eyebrow:** "Today", "Today · done", or "Edit today" while editing.
- **Headline:** "8 pages to go" / "Goal met" while editing / "21-day streak"
  when done. Use the habit's unit; fall back to no unit word.
- **Sub-line:** before done, "Finish to reach a 21-day streak." (current
  streak + 1), or "Finish to start a new streak." when the streak is 0. When
  done, "Your longest run yet." if the current streak equals the best,
  otherwise "See you tomorrow." While editing, "Was 12 pages."
- **Ring (right):** today's amount over the target, the number in the middle
  and "of 20" under it. The ring **is a button** ("Edit today's amount") with
  a small pencil badge.
- **Buttons when not done:** two quick-adds and **Mark done**.
  - Quick-add sizes come from the target: `max(1, round(target / 4))` and
    `max(1, round(target / 2))`. For target 20 that is +5 and +10. If both
    round to the same value, show one.
  - Mark done sets the day to the full target with `setDayAmount`.
- **Buttons when done:** "+5 more" and "+10 more".
- **Status line under the buttons:** after a quick-add or Mark done it reads
  "Added 5 pages" with an **Undo** text button that subtracts exactly that
  amount (`addToDay(id, -5)`). Otherwise it reads "12 pages logged today" or
  "Nothing logged yet". An **Edit** pill sits at its right end. The undo is in
  memory only: forget it after an edit, or when the screen closes.
- **Edit mode** (ring or Edit pill): the buttons and status line are replaced
  by an editor:
  - a − button, a numeric field (keyboard: numbers, decimals allowed when the
    unit is not a count) with the unit after it, and a + button (step 1,
    never below 0);
  - shortcut chips: Clear (0), half the target, the target ("20 · goal"),
    and 1.5× the target;
  - Cancel and Save.
  The ring and headline preview the draft live. Nothing is written until
  **Save** (`setDayAmount`, 0 deletes the row). Cancel discards.
- **Badge row** at the bottom of the card, above a hairline: trophy icon,
  "30-day badge", "9 days to go" and a thin progress bar. The badge is the
  next of the fixed milestones **7, 14, 30, 60, 100, 365** above the current
  streak. The bar runs from the previous milestone (or 0) to the next. Not
  configurable, no new table.

### 6.3 Range tabs
Segmented control: **30 days · 90 days · All time**. Every card below follows
it. Hide "90 days" while the habit is less than 31 days old. Default is
30 days. Remember the choice for the screen's lifetime only.

### 6.4 Three stat tiles
White tiles in a row of three: small label, big number, one caption line.

1. **Completion**
   - Value: done days ÷ tracked scheduled days in the range, as a whole %.
   - **Today counts only once it is done.** An unfinished today is left out
     of both numbers.
   - Caption compares with the previous range of the same length:
     "Up from 67%" (success colour), "Down from 67%" (danger colour), or
     "Same as before" (muted). If that previous range starts before the habit
     existed, show "New habit". For "All time", show "Since 24 Jul".
2. **Best streak**
   - Value: `bestStreak` days (all-time, does not follow the range).
   - Caption: "That's now" when the current streak equals the best, otherwise
     "Ended 3 Oct". `HabitStats` does not record the end date yet; add a
     `bestStreakEnd` field to `HabitStats.compute` and cover it with a test.
3. **Third tile depends on the type**
   - Amount habits: "<Unit> read/logged" (e.g. "Pages read"), the total amount
     in the range including today, and "25 a day" (total ÷ days in range).
   - Yes/no habits: "Days done", value "28/30".
   - Reduce habits: "Daily average", value "1.4", caption "limit 3".

### 6.5 Activity
White card titled by the range ("Last 30 days", "Last 90 days", "Since you
started") with a legend: Missed · Partly · Done.

- **30 days:** a calendar, 7 columns Monday–Sunday, rounded cells (~40 pt)
  showing the date number ("1 Nov" on the 1st). Rows run from the Monday on
  or before the range start to the Sunday after today.
- **90 days and All time:** week columns, rows Monday–Sunday, small cells,
  "Mon / Wed / Fri / Sun" labels on the left and month labels below.
- **Cell look:** done = habit colour, white number; partly = light tint of
  the habit colour; missed = neutral track colour; not tracked and future =
  outline only; today unfinished = white with a habit-colour outline. The
  selected day has a dark outer ring.
- Each cell is a button with a full label, e.g. "Sat 24 Oct, missed", or
  "Tue 17 Nov, today, 12 of 20 pages". Not-tracked and future cells are not
  tappable.
- **Day bar** under the grid (defaults to today):
  - Row 1, one line that never wraps (ellipsis if needed): status dot, then
    "Today" or "Sat 24 Oct" in bold, then the status: "12 of 20 pages",
    "Not done", "Done · 23 pages", with " · edited" when the user changed a
    past day here.
  - Row 2: two equal buttons, **Edit pages** (pencil + label; use the unit
    word, or "Edit" for yes/no habits) and **Mark done**, or **Undo** when
    the day is done. No icon-only buttons in this bar.
  - Mark done writes the target, Undo writes 0, both via `setDayAmount`.
  - Edit pages opens an inline editor in the bar (− / field / +, then Cancel
    and Save on their own row). For today it opens the editor in the Today
    card instead, so there is only one editor for today.
- Caption under the card: "Tap any day to see it, change its pages or mark
  it done."

### 6.6 Insight (tinted card)
One finding plus the evidence for it.

- Compute the done rate per weekday over the range's tracked days, with
  today excluded until it is done.
- If the weakest weekday is under 75% **and** at least 15 points behind the
  best: title "Saturdays are your weak spot", body "Done on 6 of 13
  Saturdays, against 92% on Wednesdays. A 9:30 PM reminder may come too late
  that day." (drop the reminder sentence when there is no reminder), and a
  dark button **Change reminder time** that opens `HabitEditorSheet` for
  this habit.
- Otherwise: title "Steady all week", a body that says no weekday falls
  behind, and no button.
- Under the text: seven small bars (M T W T F S S) of the weekday rates; the
  weak day's bar and letter use the warning colour.
- Hide this card for "X times per week" habits (no fixed days), and when the
  range has fewer than 14 tracked days.

### 6.7 Getting steadier? (trend)
- Line of the 7-day rolling completion rate for each tracked day in the
  range (each point is done ÷ tracked over that day and the 6 before it),
  with a light area fill, a dashed 80% target line, a dot on the last point,
  y labels 100% / 50% / 0%, and x labels start / middle / "Today".
- Verdict at top right, comparing the mean of the second half with the first
  half: more than +5 points "Yes, trending up", less than −5 "Slipping
  lately" (danger colour), else "Holding steady".
- Caption: "7-day average against your 80% target". 80% is a constant; do
  not add a setting.
- Draw it with `fl_chart` (already a dependency) or a `CustomPainter`.
- Hide the chart when the range has fewer than 7 tracked days. Show a one-line
  note instead: "Your trend shows up after a week."

### 6.8 Footer
- One full-width white button: **Archive habit**. It sets
  `isArchived = true` with `updateHabit`, cancels its reminder
  (`notificationServiceProvider.cancelHabitNudge(id)`), pops back to the
  list, and shows a snackbar "Archived · Undo". Undo un-archives and
  reschedules the reminder when `reminderMinutes` is set.
- Under it, centred muted text: "Started 24 Jul · Archived habits keep their
  history." and "Delete is in the ⋯ menu."
- **Delete habit** (⋯ menu only): `brandConfirm(destructive: true, title:
  "Delete this habit?", message: "Its history is deleted too. This can't be
  undone.")`, then `deleteHabit`, `cancelHabitNudge`, and pop.
- There is **no Pause**: the data has no paused state.

## 7. Calculations to put in `utils/` (pure, unit-tested)

Add a small pure helper, e.g. `habit_detail_stats.dart`, that takes the
`Habit`, its `byDay` map, `today` and a range, and returns everything the
screen shows: done / tracked counts, previous-period rate, per-day states,
weekday rates, rolling series, total and average, milestone. Keep
`HabitStats` as the source of streaks and add `bestStreakEnd` to it.
Do not put these calculations in widgets.

Tests to add in `test/`:
- Completion excludes an unfinished today and includes a finished one.
- Previous-period caption: up / down / same / "New habit".
- Days before `createdAt` and unscheduled weekdays are never "missed".
- Partly vs done vs missed for amount habits; reduce-habit success.
- Weekday insight threshold (under 75% and 15 points behind).
- Rolling series length and values on a small fixture.
- Milestone: streak 0 → 7, 21 → 30 (9 to go), 30 → 60.
- `bestStreakEnd` on a fixture with two runs.
- A widget test: open `/habits/:id`, tap Mark done, and the headline becomes
  the streak; tap Edit, set 15, Save, and `setDayAmount` stored 15.

## 7b. Motion

Motion explains what changed; it never delays input. Every animation must be
skipped when `MediaQuery.of(context).disableAnimations` is true (the app
already respects reduced motion in the shell).

| What | When | How (duration, curve) |
|---|---|---|
| Cards enter | First build of the screen | Fade + slide up 14 pt, 550 ms `Curves.easeOutCubic`, staggered 50 ms per card from the header down. Once only, not on rebuilds. |
| Ring fill | Today's amount or the editor draft changes | Tween the progress arc, 700 ms `easeOutCubic` (`TweenAnimationBuilder<double>`). |
| Ring number | Same | Count up/down from the old to the new value, 520 ms `easeOutCubic`, rounded to whole units. |
| Goal reached | Today goes from not done to done (Mark done, quick-add or Save) | Ring scales 1 → 1.12 → 1 over 600 ms with an overshoot curve, plus a burst of 12 small dots in the habit/brand colours flying out about 54–74 pt and fading, 800 ms. One light haptic (`HapticFeedback.lightImpact`, through the app's haptics helper). |
| Headline / sub-line | Mode changes (open, done, editing) | `AnimatedSwitcher`, fade + 6 pt slide, 350 ms. |
| "Added 5 pages" line | Each quick-add or save | Same fade + slide, replayed every time. |
| Editors | Open | Expand from the top: fade + 6 pt slide + scale 0.98 → 1, 300 ms (`AnimatedSize` + `AnimatedSwitcher`). |
| Button press | Any button | Scale to 0.95 while pressed, 140 ms. |
| Range tabs | Tab change | The dark selected pill slides to the new tab, 380 ms with a slight overshoot (`Curves.easeOutBack`); labels cross-fade colour. |
| Stats, grid, day bar | Range change / new day selected | Fade + 6 pt slide in, 350 ms. |
| Calendar cells | A day's state changes | Colour cross-fades 350 ms; the edited cell pops (scale 1 → 1.22 → 1, 450 ms, overshoot). |
| Badge bar | Streak changes | Width animates 700 ms `easeOutCubic`. |
| Insight bars | Screen open / range change | Grow from the bottom, 500 ms, staggered 55 ms per weekday. |
| Trend line | Screen open / range change | Line draws left to right over 1 s; area and end dot fade in after 200 ms. The end dot then emits a soft pulse ring every 1.8 s. |

## 8. Accessibility and quality checks

- Every icon-only button has a tooltip / semantics label: Back, Edit habit,
  More, the ring ("Edit today's amount"), − / + ("One less", "One more").
- Touch targets ≥ 44 pt. Text never truncates in English or Bangla at 390 pt
  wide. At 360 pt wide or 1.3× text scale, nothing overflows; the stat tiles
  may wrap their caption to two lines.
- Light and dark, all four palettes, compact density.
- Reduced motion: no animation is required; if you animate the ring, skip it
  when reduced motion is on.

## 9. Done means

- Tapping a habit card opens the new page; the old sheet is gone.
- Logging, quick-add undo, editing today, editing a past day, Mark done /
  Undo, range switching, Archive (with undo), Delete (with confirmation) and
  Edit habit all work against the real database, and the screen updates
  live.
- It matches `23-habit-detail.png` and `23b`/`23c` in layout and hierarchy,
  using theme tokens.
- `dart format .`, `flutter analyze` and `flutter test` pass, including the
  new tests.
- Report what you built, anything you left out and why, and anything that
  doesn't work yet.

## 10. Ready-to-paste prompt

> You are implementing one screen in an existing Flutter app (logSuite): the
> new Habit detail page. Read `docs/redesign/HABIT_DETAIL_HANDOFF.md` fully
> before writing code and follow it exactly; it overrides your own
> preferences and any older description of screen 23 elsewhere. The design is
> in `docs/redesign/screens/23-habit-detail.png`, `23b-habit-detail-editing.png`
> and `23c-habit-detail-done-90d.png`, with exact measurements in
> `docs/redesign/html/23-habit-detail.html`. Replace the current
> `_HabitDetailSheet` bottom sheet in
> `lib/presentation/habits/habits_screen.dart` with a full-page
> `HabitDetailScreen` on the route `/habits/:id`. Change only the
> presentation layer: no database or schema changes, no new packages, no
> hardcoded colours, no mock data. Put the calculations in a pure helper
> under `lib/presentation/habits/utils/` with unit tests. When finished, run
> `dart format .`, `flutter analyze` and `flutter test`, fix anything that
> fails, and report what you built, what you left out and why, and anything
> that doesn't work yet.

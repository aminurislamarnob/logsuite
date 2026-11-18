# logSuite redesign — implementation handoff

This document hands the approved redesign to whoever implements it in Flutter.
It is written to be read cold: you do not need the design tool or any earlier
conversation. Everything it refers to is in this folder or in `lib/`.

## 1. What you are doing

Re-skin and re-lay-out the existing app to match 45 designed screens. The app
already works end to end; **this is a presentation-layer change**. Data,
repositories, providers, routes and features stay as they are.

- **In scope:** `lib/core/theme/`, `lib/core/widgets/`, `lib/presentation/**`
  screen and sheet layouts, `lib/presentation/shell/app_shell.dart`.
- **Out of scope:** drift tables and anything under `lib/core/database/`,
  repositories, AI clients and parsers, backup/restore logic, notification
  scheduling. Do not regenerate `.g.dart` files; nothing here needs it.
- **No new features.** Where a design shows something the app cannot do yet,
  section 8 says what to do instead.
- **No mock data.** The numbers and names in the designs are examples. Every
  value on screen must come from the existing providers.

## 2. What is in this folder

| Path | What it is |
|---|---|
| `screens/NN-name.png` | A render of each screen at 390 pt wide, 2× pixels. Look at these first. |
| `html/NN-name.html` | The same screen as standalone HTML with inline styles. Open it in a browser or read the source for exact sizes, colours, radii, spacing and font weights. Treat it as the measurement spec. |
| `HANDOFF.md` | This file. |

The HTML is a drawing, not code to port. Read values from it; build with the
app's own widgets. Its icons are placeholder SVGs: use the existing `AppIcons`
(HugeIcons) set, never new icon assets.

## 3. Read these before changing anything

1. `README.md` — how to run, test and format.
2. `lib/core/theme/app_colors.dart`, `app_palette.dart`, `app_theme.dart`,
   `app_forui_theme.dart` — the token system. Comments explain why values are
   what they are.
3. `lib/core/widgets/brand.dart` and `common.dart` — the shared widget kit.
   Almost every design element already has a widget here.
4. `lib/presentation/shell/app_shell.dart` and
   `lib/presentation/dashboard/dashboard_screen.dart` — the shell and the home
   screen you will change first.
5. `test/palette_contrast_test.dart`, `test/brand_theme_test.dart`,
   `test/forui_theme_test.dart` — tests that pin the current design rules.

## 4. Rules that must hold

1. **Four palettes, two brightnesses.** The user can pick Coral, Magenta,
   Cobalt or Aubergine (`AppPalette`), each in light and dark. The designs show
   Coral light only. Never hardcode a hex in a screen: read `context.brand`,
   `Theme.of(context).colorScheme` or a token you add to `PaletteSpec` /
   `BrandColors`. The Settings design shows five invented colour swatches;
   keep the real four from `PalettePicker`.
2. **Dark mode keeps working.** Section 6 gives the dark mapping.
3. **Contrast is tested.** `palette_contrast_test.dart` requires 4.5:1 for
   text and 3:1 for module accents on their own wash, for every palette. Any
   new token must be added to that test and pass.
4. **Bangla.** The `bn` locale swaps to Hind Siliguri via `BrandTokens.fontFamily`.
   Do not set a font family in a widget. Leave room for longer strings; do not
   fix widths around English labels.
5. **Compact density** (`settings.compactDensity`) must still tighten rows.
6. **Reduced motion** is respected in the shell (`_TabFade`). Keep that for
   any animation you add.
7. **Semantics.** Keep existing tooltips and labels ("Speak a command", "Scan a
   document", "Search everything", "Reminders", nav labels). The integration
   test in `integration_test/app_test.dart` finds widgets by them.
8. **Touch targets** are at least 44×44 logical pixels.
9. `dart format .` clean and `flutter analyze` clean before every commit.
10. Do not skip, delete or weaken a test to get green. If a test encodes a rule
    the redesign deliberately changes (section 7), change the test in the same
    commit and say why in the commit message.

## 5. Design tokens

Values are for Coral light. Add them as tokens; derive the other palettes the
way `PaletteSpec.tints` already derives from `primary`.

### Neutrals

| Token (suggested name) | Value | Use |
|---|---|---|
| `canvas` (page background) | `#F4F1EE` | Every screen background. Replaces pure white. |
| `surface` | `#FFFFFF` | Cards, rows, inputs, circle buttons. |
| `ink` | `#1A1614` | Text, hero cards, nav bar, primary buttons, selected segments. |
| `inkDeep` | `#14100F` | Full-screen dark surfaces (Focus, lock screen). Same as `backgroundDark`. |
| `muted` | `#6B625C` | Secondary text on canvas or white. |
| `subtle` | `#8C847F` | Decorative only: chevrons, inactive icons, 20 px+ numerals. Fails 4.5:1, so never body text. |
| `onInkMuted` | `#B5ADA8` | Secondary text on ink. |
| `hairline` | `#F0ECE8` | Dividers inside a card. |
| `track` | `#EFEAE6` | Empty progress bars, empty heatmap cells. |
| `well` | `#E8E3DF` | Background of segmented controls. |
| `outlineIdle` | `#D4CEC8` | Unchecked checkbox and radio rings. |

### Module colours

Each module needs four roles. The brand accent stays the value already in
`AppColors`; the other three are new.

| Module | Accent (existing) | Graphic on tint | Text on tint | Tint fill | On ink |
|---|---|---|---|---|---|
| Medicine / brand | `#F15F43` | `#E24E32` | `#B23A1F` | `#FFE7E0` | `#FF7D63` |
| Tasks | `#5B7CE0` | `#4A67C4` | `#3B4F8F` | `#EAEFFD` | `#7E9CF6` |
| Habits | `#2D8657` | `#2D8657` | `#1F5E3D` | `#E6F4EC` | `#56CE8E` |
| Expenses | `#9A6DD7` | `#7E52BE` | `#6A41A8` | `#F4EEFB` | `#B58DEC` |
| Focus | `#349CA5` | `#2B8790` | `#1F6A72` | `#E6F4F5` | `#59C2CC` |
| Notes | `#C38131` | `#A86C22` | `#8A5A1F` | `#FCF4E6` | `#FFB95C` |
| Drop | `#0284C7` | `#0274B0` | `#02598A` | `#E3F1FA` | `#38BDF8` |

"On ink" equals the existing dark-mode accents, so reuse those. Derive the
tint with `AppColors.wash` at a higher density (about 0.12 instead of 0.07)
and the text role by darkening the accent, then verify with the contrast test
rather than trusting the table for the other three palettes.

Status: danger text `#B3261E` on `#FDECEA`; warning graphic `#D98A2B`, text
`#A35E12` on `#FBF1E3`; success `#2D8657`, text `#1F6B45` on `#E6F4EC`.

### Colour usage rules

- **Primary text buttons are ink with white labels**, not coral. White on
  coral is 3.25:1, below the 4.5:1 a button label needs.
- **Coral (the palette primary) is for graphics only:** progress rings, the
  "now" marker, the centre + button, the due-now outline, chart highlights,
  eyebrow labels on ink.
- Small coral text on a light surface uses the "text on tint" role.
- One ink hero card per screen at most. It marks the single most important
  summary.
- Tinted cards mean "summary of a module". Rows the user acts on are white.

### Shape, elevation, spacing, type

| Thing | Value |
|---|---|
| Hero card radius | 28 |
| Card radius | 22–24 (`AppRadii.card` is 24; keep) |
| Tile / row radius | 16–20 (`AppRadii.tile` is 20; keep) |
| Icon chip | 44–48 square, radius 16; small 36–40, radius 12–14 |
| Pills, buttons, inputs in bars | fully rounded |
| Bottom sheet top corners | 32 (`AppRadii.sheet` is 28; raise) |
| Card shadow | `0 1 2 rgba(26,22,20,.05)` + `0 6 20 rgba(26,22,20,.06)` |
| Circle button shadow | `0 1 2 rgba(26,22,20,.05)` + `0 4 14 rgba(26,22,20,.06)` |
| Hero shadow | `0 16 40 rgba(26,22,20,.22)` |
| Floating bar shadow | nav `0 14 36 rgba(26,22,20,.28)`; white composer `0 14 36 rgba(26,22,20,.14)` |
| Gutter | 20 (`AppSpacing.gutter`; keep) |
| Gap between sections | 14–18; between stacked cards 8–12 |
| Nav bar | height 68, inset 20 from the sides, 24 above the bottom inset |

| Text style | Size / weight / tracking |
|---|---|
| Tab-root title (Modules, Insights, Settings) | 30 / 800 / −0.9 |
| Pushed-screen title | 28 / 800 / −0.8 |
| Hero numeral | 44–48 / 800 / −2 |
| Amount entry | 64 / 800 / −3 |
| Section heading | 20 / 700 / −0.4 |
| Row title | 15–17 / 600–700 |
| Body | 13–15 / 400–500 |
| Caption | 12 / 400–600 |
| Eyebrow | 12 / 700 / +0.8, uppercase |

Fit these onto the existing `TextTheme` slots in `AppTheme._textTheme`; add
weight 800 where the table needs it.

## 6. Dark mode mapping

The designs are light. Apply this mapping rather than inventing a dark design.

| Light | Dark |
|---|---|
| `canvas #F4F1EE` | `backgroundDark #14100F` |
| `surface #FFFFFF` | `surfaceDark #1F1A19` |
| `ink` hero cards | a raised surface, one step lighter than `surfaceDark` (about `#2A2422`) with `textDark` text |
| ink buttons with white text | `textDark` fill with `backgroundDark` text |
| tint fills | `AppColors.wash(accent, brightness: dark)` |
| accent roles | the existing dark accents |
| shadows | none; separate surfaces by fill |

Focus, Focus stats, session complete, Assistant listening and the lock screen
are dark in both modes.

## 7. Known conflicts with the current code

Decide these deliberately; do not work around them silently.

1. **Shadows.** `forui_theme_test.dart` asserts "the brand is flat — no
   shadow". The redesign uses soft shadows on cards. Keep the forui tokens
   flat and add the shadow in the brand card widgets (`TintCard`, `BrandTile`
   groups, `CircleIconButton`), so that test stays true for forui components.
2. **Page background.** Palettes use `#FFFFFF` for both `background` and
   `surface`. The redesign needs them different. Change `background` per
   palette to a warm off-white (Coral: `#F4F1EE`; derive the others as the
   palette primary at about 4% over `#F6F4F2`). `brand_theme_test.dart` and
   `forui_theme_test.dart` read these values: update expectations there.
3. **Muted grey.** `mutedLight #6C6C6C` passes on white. Re-check it on the
   new canvas, or move to `#6B625C`.
4. **Nav bar.** `CurvedNavBar` draws a notched white bar. The redesign is a
   floating ink pill with the active tab showing icon plus label and the +
   button inline (see `01-today.png`). Rewrite `CurvedNavBar` in place and
   keep its API (`items`, `currentIndex`, `onSelected`, `centerAction`) so
   `app_shell.dart` barely changes. Keep tap = quick add, long press =
   assistant on the centre button (`brand_tappable_test.dart`).
5. **Home layout.** `DashboardScreen` builds `GreetingHeader`, `_NextUpBanner`,
   "My plans" and per-module widgets ordered by `settings.dashboardOrder`.
   The redesign pins the hero, the add bar and "Up next" at the top, then
   renders the per-module sections in `dashboardOrder`, skipping disabled
   modules. Keep that setting working.

## 8. Where the designs go beyond the app

Build only what the data supports.

| Design element | What to do |
|---|---|
| Day timeline in the Today hero (`01`) | Build from today's doses, tasks with a due time and habit reminders. Items without a time are not plotted. |
| "7 of 14 done" total | Sum of today's tasks, doses and habits from the existing providers. |
| "Again" row in Quick add (`02`) | Only if recent entries can be read from existing repositories. Otherwise omit the row. |
| Parsed chips inside Quick add (`02`) | The parse happens in the assistant flow today. Either navigate to `/assistant` with the text, or omit the chips. Do not add a second parser. |
| Daily budget line ("of 1,200", "per day") | Show only when a budget exists; derive from the monthly budget. |
| "On track" / pace marker (`08`, `33`) | Derive from budget and day of month, or omit. |
| "+12% vs last week" (`01`, `12`) | Compute from existing insight data or omit. |
| Focus quality rating (`31`) | The app already has "Focus quality"; match its real scale. |
| Low-stock alert toggle (`25`) | Keep whatever stock fields the medicine editor has now. |
| People "linked to" counts (`40`) | Show only counts that are cheap to query; otherwise show relation only. |
| Settings colour swatches (`16`) | Use the real four palettes. |
| Badge icons (`24`) | Names and levels come from `drop_gamification.dart`. |

When you omit something, the layout must still look finished: close the gap,
do not leave a placeholder.

## 9. Shared widgets: what to change

Change the kit first. Most screens then update with little per-screen work.

| Widget | Change |
|---|---|
| `BrandScaffold` | Paints `canvas`. |
| `CircleIconButton` | White fill, soft shadow, no border; 44 default. Add an "on ink" variant (`rgba(255,255,255,.08)` fill, white icon). |
| `BrandTopBar` | Back circle, 28/800 title left-aligned next to it, actions as circles. Optional one-line subtitle under the title. |
| `GreetingHeader` | Avatar 48 in ink, uppercase date eyebrow, 22/700 greeting, two action circles (search, reminders with a count badge). The assistant and scan actions move into the add bar. |
| `HeroBanner` | Becomes the ink hero: eyebrow, large numeral, supporting line, optional trailing ring, optional row of sub-tiles (`rgba(255,255,255,.07)`, radius 16). |
| `TintCard` | Takes a module accent and paints the module tint; adds the card shadow. |
| `BrandTile` / `TileGroup` | White rows inside one rounded card, hairline dividers, 36–40 icon chip, trailing value plus chevron. Keep the corner logic the tests pin. |
| `BrandSegmented`, `BrandTabs` | Well background, ink selected segment with white label, 44–48 high. |
| `BrandChip`, `Pill` | 38–44 high. Selected = ink fill, white text. Unselected = white with a faint shadow. |
| `BrandButton` | `primary` = ink fill, white label, 52–58 high, fully rounded. `outline` = white with shadow. `danger` = danger text on white. |
| `BrandFab` | Extended ink pill ("+ Add", "New note"), bottom right. |
| `BrandCheckbox` | 26–28 circle, 2.5 ring. Ring colour carries task priority; checked = success fill with white tick. |
| `BrandSwitchTile` | 52×32 track, ink when on. |
| `ProgressRing` | Round caps, 10 stroke at 92, track `rgba(255,255,255,.10)` on ink or `track` on light. |
| `ContributionHeatmap` | Rounded cells (radius 5–7), four intensities of the module accent, today outlined. |
| `SheetScaffold` | Canvas fill, 32 top radius, 40×5 handle, title 24–28/800 with a close circle, sticky full-width primary button. |
| `BrandField` | White, radius 20, 56 high, 2 px ink outline when focused. |
| `EmptyState` | Keep; restyle to the same type scale and an icon chip. |
| New: floating composer | White pill, 62 high, text field plus a 46 round send button. Used by Tasks, Drop and the Today add bar. |
| New: stat tile | Small label over a bold value, used in rows of two to four. |

## 10. Screen map

`NN` is the file prefix in `screens/` and `html/`.

| NN | Screen | Code |
|---|---|---|
| 01 | Today | `dashboard/dashboard_screen.dart`, `shell/app_shell.dart` |
| 02 | Quick add sheet | `showQuickAdd` in `shell/app_shell.dart` |
| 03 | Add expense | `expenses/widgets/expense_entry_sheet.dart` |
| 04, 19, 20, 21 | Tasks: list, board, calendar, matrix | `tasks/tasks_screen.dart`, `tasks/widgets/task_tile.dart` |
| 18 | Task editor | `tasks/widgets/task_editor_sheet.dart` |
| 05, 22, 23 | Habits, editor, detail | `habits/habits_screen.dart` |
| 06, 26, 27 | Medicine: today, calendar, medicines | `medicine/medicine_screen.dart` |
| 25 | Medicine editor | `medicine/widgets/medicine_editor_sheet.dart` |
| 07 | Modules | `modules/modules_screen.dart` |
| 08, 32–35 | Expenses: overview, reports, budgets, bills, loans | `expenses/expenses_screen.dart`, `expenses/widgets/*_tab.dart` |
| 36 | Accounts and transfer | `expenses/widgets/accounts_sheet.dart` |
| 37 | Categories | `expenses/categories_screen.dart` |
| 09, 30, 31 | Focus, stats, session complete | `focus/focus_screen.dart` |
| 10, 29 | Notes, folders drawer | `notes/notes_screen.dart` |
| 28 | Note editor | `notes/note_editor_screen.dart` |
| 11, 24 | Drop, mastery sheet | `drop/drop_screen.dart`, `drop/widgets/` |
| 12 | Insights | `insights/insights_screen.dart` |
| 13, 38 | Assistant: preview, listening | `ai/assistant_screen.dart`, `ai/widgets/action_preview_card.dart` |
| 39 | Scan result | `medicine/camera_scan_screen.dart` |
| 14 | Search | `search/search_screen.dart` |
| 15 | Reminders | `reminders/reminders_screen.dart` |
| 16, 41, 42, 43 | Settings, AI settings, lock screen, data | `settings/settings_screen.dart`, security service UI |
| 40 | People | `settings/people_screen.dart` |
| 44 | How to | `settings/how_to_screen.dart` (text stays in `how_to_content.dart`) |
| 17, 45 | Onboarding steps 1 and 2 | `onboarding/onboarding_screen.dart` |

All paths are under `lib/presentation/`.

**Not designed.** Apply the same system by analogy, and do not redesign their
behaviour: Medicine Timeline and Table tabs, loan and repay sheets, Drop
archive, image viewer and in-app browser, the profile and project drawers,
onboarding step 3, every empty and error state.

## 11. Order of work

One phase per pull request or commit series. The app must run and tests must
pass at the end of each phase.

1. **Tokens.** New neutrals and module roles in `app_colors.dart`,
   `PaletteSpec`, `BrandColors`; canvas background; shadow constants; type
   scale; forui mapping in `app_forui_theme.dart`. Extend the contrast test.
   *Done when:* tests pass for all four palettes in both brightnesses and the
   app shows the new canvas with no other visual breakage.
2. **Widget kit.** Section 9, top to bottom. *Done when:* every existing
   screen picks up the new buttons, chips, segments, tiles and sheets without
   per-screen edits, in light and dark.
3. **Shell and Today.** New nav bar, then screen 01 and sheet 02.
4. **Add flows.** 03, 18, 22, 25, 13, 38, 39.
5. **Module screens.** Tasks (04, 19–21), Habits (05, 23), Medicine (06, 26,
   27), Focus (09, 30, 31), Notes (10, 28, 29), Drop (11, 24).
6. **Expenses.** 08, 32–37.
7. **Tab roots and system.** 07, 12, 14, 15, 16, 40–45, 17.
8. **Sweep.** Undesigned screens, empty states, dark mode, Bangla, compact
   density, the three non-Coral palettes.

## 12. How to verify each phase

```bash
flutter pub get
```

```bash
dart format .
```

```bash
flutter analyze
```

```bash
flutter test
```

Then run the app and compare each changed screen against its PNG at a 390 pt
wide device (iPhone 14 / 15 size):

```bash
flutter run
```

Check, for every screen you touched:

- Light and dark.
- At least one non-Coral palette.
- Bangla locale: no clipped or overflowing text.
- Compact density on.
- A small phone (360 pt wide) and large text scale (1.3×): no overflow
  stripes.
- Empty data: the empty state shows, not a blank card.
- Screen reader labels still present on icon-only buttons.

Report honestly at the end of each phase: what matches the design, what was
deliberately left out under section 8, and anything that does not work yet.

## 13. Ready-to-paste brief for the implementing model

> You are implementing an approved visual redesign of an existing Flutter app
> (logSuite). Read `docs/redesign/HANDOFF.md` fully before writing code and
> follow it exactly; it overrides your own design preferences. Screens are
> specified by `docs/redesign/screens/NN-name.png` (what it looks like) and
> `docs/redesign/html/NN-name.html` (exact measurements and colours). Work one
> phase from section 11 at a time, starting with phase 1. Change only the
> presentation layer. Never hardcode colours in screens, never add mock data,
> never skip or weaken a test. After each phase run `dart format .`,
> `flutter analyze` and `flutter test`, fix what fails, then summarise what
> changed, what you left out and why, and stop for review before the next
> phase.

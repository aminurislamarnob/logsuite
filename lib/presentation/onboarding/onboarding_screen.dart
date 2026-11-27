import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/app_database.dart';
import '../../core/people/people_repository.dart';
import '../../core/services/notification_service.dart';
import '../../core/services/security_service.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/palette_picker.dart';
import '../habits/repository/habit_repository.dart';
import '../modules/modules_screen.dart';

/// First-run flow (`17-onboarding.png`, `45-onboarding2.png`, plus step 3):
/// 1) Welcome, name & language; 2) Pick modules & extras; 3) Theme & habits.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pages = PageController();
  int _index = 0;

  final Set<AppModule> _modules = AppModule.values.toSet();
  final Set<String> _habits = {};
  final _name = TextEditingController();
  bool _remindersRequested = false;

  static const _lastPage = 2;

  void _next() {
    if (_index < _lastPage) {
      _pages.nextPage(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    } else {
      _finish();
    }
  }

  void _back() {
    if (_index > 0) {
      _pages.previousPage(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _finish() async {
    final notifier = ref.read(settingsProvider.notifier);
    notifier.setEnabledModules(_modules);

    final name = _name.text.trim();
    if (name.isNotEmpty) {
      final people = ref.read(peopleRepositoryProvider);
      await people.updatePerson(await people.selfId(), name: name);
    }

    if (_modules.contains(AppModule.habits) && _habits.isNotEmpty) {
      final repo = ref.read(habitRepositoryProvider);
      for (final preset in HabitRepository.presets.where(
        (p) => _habits.contains(p.name),
      )) {
        await repo.createHabit(
          HabitsCompanion(
            name: drift.Value(preset.name),
            icon: drift.Value(preset.icon),
            color: drift.Value(preset.color),
            unit: drift.Value(preset.unit),
            goalType: drift.Value(preset.goalType),
            targetAmount: drift.Value(preset.target),
            caffeineMgPerUnit: drift.Value(preset.caffeine),
          ),
        );
      }
    }

    notifier.completeOnboarding();
    if (mounted) context.go('/dashboard');
  }

  @override
  void dispose() {
    _pages.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final overlayStyle =
        (_index == 0 || Theme.of(context).brightness == Brightness.dark)
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;
    return BrandScaffold(
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: overlayStyle,
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (i) {
                  AppHaptics.selection();
                  setState(() => _index = i);
                },
                children: [_step1(), _step2(), _step3()],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.gutter,
                  8,
                  AppSpacing.gutter,
                  16,
                ),
                child: Row(
                  children: [
                    if (_index > 0) ...[
                      CircleIconButton(
                        icon: AppIcons.back,
                        tooltip: 'Back',
                        onPressed: _back,
                      ),
                      const SizedBox(width: 14),
                    ],
                    for (var i = 0; i <= _lastPage; i++) ...[
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        width: i == _index ? 22 : 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: i == _index ? brand.ink : brand.outlineIdle,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      if (i < _lastPage) const SizedBox(width: 6),
                    ],
                    const SizedBox(width: 16),
                    Expanded(
                      child: BrandTappable(
                        onPressed: _next,
                        semanticsLabel: _index == _lastPage
                            ? 'Get started'
                            : 'Continue',
                        child: Container(
                          height: 58,
                          decoration: ShapeDecoration(
                            color: brand.ink,
                            shape: const StadiumBorder(),
                            shadows: AppShadows.hero(
                              Theme.of(context).brightness,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _index == _lastPage
                                    ? 'Get started'
                                    : 'Continue',
                                style: TextStyle(
                                  color: brand.onInk,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 8),
                              AppIcon(
                                AppIcons.chevronRight,
                                size: 18,
                                color: brand.onInk,
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
          ],
        ),
      ),
    );
  }

  Widget _wordmark({required bool onDark}) {
    final brand = context.brand;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: 'log',
            style: TextStyle(color: onDark ? Colors.white : brand.ink),
          ),
          TextSpan(
            text: 'Suite',
            style: TextStyle(
              color: onDark ? brand.medicineRoles.onInk : brand.medicine,
            ),
          ),
        ],
      ),
      style: const TextStyle(
        fontSize: 21,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.6,
      ),
    );
  }

  Widget _skipButton({required bool onDark}) {
    final brand = context.brand;
    final theme = Theme.of(context);
    return BrandTappable(
      onPressed: _finish,
      semanticsLabel: 'Skip',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: ShapeDecoration(
          color: onDark ? Colors.white.withValues(alpha: 0.12) : brand.surface,
          shape: const StadiumBorder(),
          shadows: onDark
              ? const []
              : AppShadows.circleButton(theme.brightness),
        ),
        child: Text(
          'Skip',
          style: TextStyle(
            color: onDark ? Colors.white : brand.ink,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  /// Step 1 (`17-onboarding.png` / `17-onboarding.html`): dark hero collage +
  /// name + language.
  Widget _step1() {
    final brand = context.brand;
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);
    final topInset = MediaQuery.paddingOf(context).top;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            height: 332 + topInset,
            decoration: BoxDecoration(
              color: brand.heroSurface,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(40),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Positioned(
                  left: 20,
                  right: 20,
                  top: topInset + 12,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _wordmark(onDark: true),
                      _skipButton(onDark: true),
                    ],
                  ),
                ),
                Positioned(
                  left: 28,
                  top: topInset + 74,
                  child: Transform.rotate(
                    angle: -4 * 3.14159265 / 180,
                    child: Container(
                      width: 204,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Color.alphaBlend(
                          Colors.white.withValues(alpha: 0.08),
                          brand.heroSurface,
                        ),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x59000000),
                            offset: Offset(0, 16),
                            blurRadius: 40,
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          ProgressRing(
                            value: 0.67,
                            size: 62,
                            thickness: 8,
                            onInk: true,
                            color: brand.medicineRoles.onInk,
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  const Text(
                                    '7',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 26,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -1,
                                      height: 1,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'of 14',
                                    style: TextStyle(
                                      color: brand.onInkMuted,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'done today',
                                style: TextStyle(
                                  color: brand.onInkMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 16,
                  top: topInset + 142,
                  child: Transform.rotate(
                    angle: 3 * 3.14159265 / 180,
                    child: Container(
                      width: 234,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x59000000),
                            offset: Offset(0, 16),
                            blurRadius: 40,
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: brand.medicineRoles.tintFill,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: AppIcon(
                              AppIcons.medicine,
                              size: 20,
                              color: brand.medicineRoles.graphicOnTint,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Napa 500 mg',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: brand.inkDeep,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  '2:00 PM · after food',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: context.muted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            width: 28,
                            height: 28,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: brand.habit,
                              shape: BoxShape.circle,
                            ),
                            child: const AppIcon(
                              AppIcons.check,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 38,
                  top: topInset + 224,
                  child: Transform.rotate(
                    angle: -2 * 3.14159265 / 180,
                    child: Row(
                      children: [
                        _previewPill(
                          dot: brand.expense,
                          label: '${settings.currencySymbol} 200 · Lunch',
                          bg: brand.expenseRoles.tintFill,
                          fg: brand.inkDeep,
                        ),
                        const SizedBox(width: 8),
                        _previewPill(
                          dot: brand.habit,
                          label: '12-day streak',
                          bg: brand.habitRoles.tintFill,
                          fg: brand.inkDeep,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 26, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your day,\nin one place.',
                  style: theme.textTheme.displayMedium?.copyWith(
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.4,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Tasks, medicine, habits, money, notes and focus. '
                  'Turn on only what you need.',
                  style: TextStyle(
                    color: context.muted,
                    fontSize: 15,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'YOUR NAME',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: context.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 56,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: brand.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: brand.ink, width: 2),
                  ),
                  child: TextField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => _next(),
                    style: TextStyle(color: brand.ink, fontSize: 16),
                    decoration: InputDecoration(
                      hintText: 'What should we call you?',
                      hintStyle: TextStyle(color: context.muted, fontSize: 16),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _langButton(
                        label: 'English',
                        selected: settings.locale == 'en',
                        onTap: () =>
                            ref.read(settingsProvider.notifier).setLocale('en'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _langButton(
                        label: 'বাংলা',
                        selected: settings.locale == 'bn',
                        onTap: () =>
                            ref.read(settingsProvider.notifier).setLocale('bn'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    AppIcon(AppIcons.privacy, size: 18, color: brand.success),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Everything stays on this device. Nothing is uploaded.',
                        style: TextStyle(
                          color: context.muted,
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewPill({
    required Color dot,
    required String label,
    required Color bg,
    required Color fg,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: ShapeDecoration(color: bg, shape: const StadiumBorder()),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _langButton({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final brand = context.brand;
    final theme = Theme.of(context);
    return BrandTappable(
      onPressed: onTap,
      semanticsLabel: label,
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: ShapeDecoration(
          color: selected ? brand.ink : brand.surface,
          shape: const StadiumBorder(),
          shadows: selected
              ? const []
              : AppShadows.circleButton(theme.brightness),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? brand.onInk : brand.ink,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
    );
  }

  /// Step 2 (`45-onboarding2.png`): 2-col module grid + two optional extras.
  Widget _step2() {
    final brand = context.brand;
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);
    final topInset = MediaQuery.paddingOf(context).top;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        topInset + 14,
        AppSpacing.gutter,
        16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _wordmark(onDark: false),
              const Spacer(),
              _skipButton(onDark: false),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Pick what you need',
            style: theme.textTheme.displayMedium?.copyWith(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.9,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${_modules.length} of ${AppModule.values.length} on. '
            'You can change this any time in Settings.',
            style: TextStyle(color: context.muted, fontSize: 14),
          ),
          const SizedBox(height: 18),
          GridView.count(
            padding: EdgeInsets.zero,
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2.35,
            children: [
              for (final m in AppModule.values)
                Builder(
                  builder: (context) {
                    final (icon, color) = ModulesScreen.metaFor(context, m);
                    final roles = brand.roleFor(color);
                    final on = _modules.contains(m);
                    return BrandTappable(
                      onPressed: () => setState(() {
                        on ? _modules.remove(m) : _modules.add(m);
                      }),
                      semanticsLabel: m.label,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: on ? roles.tintFill : brand.surface,
                          borderRadius: BorderRadius.circular(AppRadii.tile),
                          border: on
                              ? Border.all(color: roles.accent, width: 1.5)
                              : null,
                          boxShadow: on
                              ? const []
                              : AppShadows.card(theme.brightness),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: on ? brand.surface : brand.well,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: AppIcon(
                                icon,
                                size: 18,
                                color: on ? roles.graphicOnTint : context.muted,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                m.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: on ? brand.ink : context.muted,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            BrandCheckbox(
                              value: on,
                              color: on ? brand.ink : null,
                              semanticsLabel: m.label,
                              onChanged: (v) => setState(() {
                                v ? _modules.add(m) : _modules.remove(m);
                              }),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            'TWO OPTIONAL EXTRAS',
            style: theme.textTheme.labelSmall?.copyWith(
              color: context.muted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),
          TileGroup(
            children: [
              BrandSwitchTile(
                leading: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: brand.noteRoles.tintFill,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: AppIcon(
                    AppIcons.notificationsActive,
                    size: 18,
                    color: brand.noteRoles.graphicOnTint,
                  ),
                ),
                title: 'Allow reminders',
                subtitle: 'Dose times, tasks and bills',
                value: _remindersRequested,
                onChanged: (v) async {
                  if (v) {
                    final granted = await ref
                        .read(notificationServiceProvider)
                        .requestPermissions();
                    if (mounted) {
                      setState(() => _remindersRequested = granted);
                      if (!granted) {
                        brandToast(
                          context,
                          'You can enable these later in Settings.',
                        );
                      }
                    }
                  } else {
                    setState(() => _remindersRequested = false);
                  }
                },
              ),
              BrandSwitchTile(
                leading: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: brand.habitRoles.tintFill,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: AppIcon(
                    AppIcons.lock,
                    size: 18,
                    color: brand.habitRoles.graphicOnTint,
                  ),
                ),
                title: 'Lock the app',
                subtitle: 'Use biometrics or a PIN on launch',
                value: settings.appLockEnabled,
                onChanged: (v) async {
                  final security = ref.read(securityServiceProvider);
                  if (v && !await security.canUseBiometrics()) {
                    if (!mounted) return;
                    brandToast(
                      context,
                      'No biometrics found — set a PIN in Settings.',
                    );
                  }
                  ref.read(settingsProvider.notifier).setAppLock(v);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Step 3: Theme, palette, and optional starter habits.
  Widget _step3() {
    final settings = ref.watch(settingsProvider);
    final theme = Theme.of(context);
    final topInset = MediaQuery.paddingOf(context).top;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        topInset + 14,
        AppSpacing.gutter,
        16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _wordmark(onDark: false),
              const Spacer(),
              _skipButton(onDark: false),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Make it yours',
            style: theme.textTheme.displayMedium?.copyWith(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.9,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Pick a look and optional starter habits.',
            style: TextStyle(color: context.muted, fontSize: 14),
          ),
          const SizedBox(height: 20),
          BrandSegmented<ThemeMode>(
            options: const {
              ThemeMode.system: 'Auto',
              ThemeMode.light: 'Light',
              ThemeMode.dark: 'Dark',
            },
            selected: settings.themeMode,
            onSelected: (m) =>
                ref.read(settingsProvider.notifier).setThemeMode(m),
          ),
          const SizedBox(height: 20),
          Text(
            'COLOUR',
            style: theme.textTheme.labelSmall?.copyWith(
              color: context.muted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            settings.palette.blurb,
            style: TextStyle(color: context.muted, fontSize: 13),
          ),
          const SizedBox(height: 10),
          const PalettePicker(),
          if (_modules.contains(AppModule.habits)) ...[
            const SizedBox(height: 24),
            Text(
              'STARTER HABITS',
              style: theme.textTheme.labelSmall?.copyWith(
                color: context.muted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: HabitRepository.presets
                  .map(
                    (p) => Pill(
                      icon: AppIcons.habit(p.icon),
                      label: p.name,
                      color: Color(p.color),
                      selected: _habits.contains(p.name),
                      onTap: () => setState(() {
                        _habits.contains(p.name)
                            ? _habits.remove(p.name)
                            : _habits.add(p.name);
                      }),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/services/security_service.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/common.dart';
import '../medicine/providers/medicine_provider.dart';
import '../medicine/repository/medicine_repository.dart';
import '../settings/settings_screen.dart' show showSetPinSheet;
import '../shell/app_shell.dart' show runModuleQuickAction;
import '../tasks/providers/tasks_provider.dart';
import 'widgets/medicine_hero_card.dart';
import 'widgets/module_grid_tile.dart';

class ModulesScreen extends ConsumerStatefulWidget {
  const ModulesScreen({super.key});

  /// Icon and accent colour for each module, shared with onboarding.
  static (HugeIconData, Color) metaFor(BuildContext context, AppModule m) =>
      (_icons[m]!, accentFor(context.brand, m));

  static const _icons = <AppModule, HugeIconData>{
    AppModule.notes: AppIcons.notes,
    AppModule.medicine: AppIcons.medicine,
    AppModule.habits: AppIcons.habits,
    AppModule.tasks: AppIcons.tasks,
    AppModule.expenses: AppIcons.expenses,
    AppModule.focus: AppIcons.focus,
    AppModule.drop: AppIcons.inbox,
  };

  /// The accent the active palette gives [m].
  static Color accentFor(BrandColors brand, AppModule m) => switch (m) {
    AppModule.notes => brand.note,
    AppModule.medicine => brand.medicine,
    AppModule.habits => brand.habit,
    AppModule.tasks => brand.task,
    AppModule.expenses => brand.expense,
    AppModule.focus => brand.focus,
    AppModule.drop => brand.drop,
  };

  static const _editOrder = <AppModule>[
    AppModule.medicine,
    AppModule.tasks,
    AppModule.habits,
    AppModule.expenses,
    AppModule.focus,
    AppModule.notes,
    AppModule.drop,
  ];

  static const _gridOrder = <AppModule>[
    AppModule.tasks,
    AppModule.habits,
    AppModule.expenses,
    AppModule.focus,
    AppModule.notes,
    AppModule.drop,
  ];

  @override
  ConsumerState<ModulesScreen> createState() => _ModulesScreenState();
}

class _ModulesScreenState extends ConsumerState<ModulesScreen> {
  bool _editing = false;

  int _attentionCount(AppSettings settings) {
    final now = DateTime.now();
    var count = 0;

    if (settings.isEnabled(AppModule.medicine) &&
        !settings.lockedModules.contains(AppModule.medicine)) {
      final doses = ref.watch(todayDoseViewsProvider).valueOrNull ?? const [];
      count += doses
          .where((d) => d.status == DoseStatus.pending && !d.at.isAfter(now))
          .length;
    }

    if (settings.isEnabled(AppModule.tasks) &&
        !settings.lockedModules.contains(AppModule.tasks)) {
      final taskStats = ref.watch(taskStatsProvider(7)).valueOrNull;
      count += taskStats?.overdue ?? 0;
    }

    return count;
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final brand = context.brand;
    final theme = Theme.of(context);
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    final enabled = ModulesScreen._editOrder.where(settings.isEnabled).toList();
    final disabled = ModulesScreen._editOrder
        .where((m) => !settings.isEnabled(m))
        .toList();
    final lockedCount = enabled
        .where((m) => settings.lockedModules.contains(m))
        .length;

    final now = DateTime.now();
    final String subtitle;
    if (_editing) {
      subtitle = '${enabled.length} on · $lockedCount locked';
    } else {
      final n = _attentionCount(settings);
      final dateStr = DateFormat('EEE d MMM').format(now);
      final statusStr = n == 0
          ? 'all clear'
          : (n == 1 ? '1 thing needs you' : '$n things need you');
      subtitle = '$dateStr · $statusStr';
    }

    return BrandScaffold(
      header: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            12,
            AppSpacing.gutter,
            8,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Modules',
                      style: theme.textTheme.displayMedium?.copyWith(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.9,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(color: context.muted, fontSize: 14),
                    ),
                  ],
                ),
              ),
              BrandTappable(
                onPressed: () {
                  AppHaptics.selection();
                  setState(() => _editing = !_editing);
                },
                semanticsLabel: _editing
                    ? 'Done editing modules'
                    : 'Edit modules',
                child: AnimatedContainer(
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  alignment: Alignment.center,
                  decoration: ShapeDecoration(
                    color: _editing ? brand.ink : brand.surface,
                    shape: const StadiumBorder(),
                    shadows: _editing
                        ? const []
                        : AppShadows.circleButton(theme.brightness),
                  ),
                  child: Text(
                    _editing ? 'Done' : 'Edit',
                    style: TextStyle(
                      color: _editing ? brand.onInk : brand.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      child: AnimatedSwitcher(
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 350),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: _editing
            ? _buildEditMode(context, settings, brand, theme)
            : _buildNormalMode(
                context,
                settings,
                brand,
                theme,
                enabled,
                disabled,
              ),
      ),
    );
  }

  Widget _buildNormalMode(
    BuildContext context,
    AppSettings settings,
    BrandColors brand,
    ThemeData theme,
    List<AppModule> enabled,
    List<AppModule> disabled,
  ) {
    final hasMedicineHero = settings.isEnabled(AppModule.medicine);
    final gridModules = ModulesScreen._gridOrder
        .where(settings.isEnabled)
        .toList();

    return ListView(
      key: const ValueKey('modules_normal'),
      padding: pageInsets(context, top: 8, end: PageEnd.navBar),
      children: [
        // 2. Search row
        Row(
          children: [
            Expanded(
              child: Semantics(
                button: true,
                label: 'Search everything',
                child: GestureDetector(
                  onTap: () {
                    AppHaptics.tap();
                    context.push('/search');
                  },
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: brand.surface,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: AppShadows.card(theme.brightness),
                    ),
                    child: Row(
                      children: [
                        AppIcon(
                          AppIcons.search,
                          size: 18,
                          color: context.muted,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Search all modules',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              color: context.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Tooltip(
              message: 'Ask the assistant',
              child: Semantics(
                button: true,
                label: 'Ask the assistant',
                child: GestureDetector(
                  onTap: () {
                    AppHaptics.tap();
                    context.push('/assistant');
                  },
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: brand.surface,
                      shape: BoxShape.circle,
                      boxShadow: AppShadows.card(theme.brightness),
                    ),
                    child: Center(
                      child: AppIcon(AppIcons.mic, size: 20, color: brand.ink),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        if (enabled.isEmpty)
          const EmptyState(
            icon: AppIcons.modules,
            title: 'Everything is switched off',
            message: 'Turn a module back on below to start using it.',
          )
        else ...[
          // 3. Medicine hero
          if (hasMedicineHero) ...[
            MedicineHeroCard(
              isLocked: settings.lockedModules.contains(AppModule.medicine),
            ),
            const SizedBox(height: 16),
          ],

          // 4. 2-column module grid
          for (var i = 0; i < gridModules.length; i += 2) ...[
            if (i > 0) const SizedBox(height: AppSpacing.grid),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _buildGridTile(gridModules[i], i, settings)),
                  const SizedBox(width: AppSpacing.grid),
                  Expanded(
                    child: i + 1 < gridModules.length
                        ? _buildGridTile(gridModules[i + 1], i + 1, settings)
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ],
        ],

        // 6. Switched off chips
        if (disabled.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'SWITCHED OFF',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: context.muted,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final m in disabled)
                _SwitchedOffChip(
                  module: m,
                  onTap: () {
                    AppHaptics.tap();
                    ref.read(settingsProvider.notifier).toggleModule(m, true);
                    brandToast(context, '${m.label} switched on.');
                  },
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildGridTile(AppModule m, int index, AppSettings settings) {
    final (icon, accent) = ModulesScreen.metaFor(context, m);
    return ModuleGridTile(
      module: m,
      icon: icon,
      accent: accent,
      index: index,
      isLocked: settings.lockedModules.contains(m),
      onTap: () => context.push(m.route),
      onQuickAction: () => runModuleQuickAction(context, ref, m),
    );
  }

  Widget _buildEditMode(
    BuildContext context,
    AppSettings settings,
    BrandColors brand,
    ThemeData theme,
  ) {
    final notifier = ref.read(settingsProvider.notifier);
    final security = ref.read(securityServiceProvider);

    return ListView(
      key: const ValueKey('modules_edit'),
      padding: pageInsets(context, top: 8, end: PageEnd.navBar),
      children: [
        Container(
          decoration: BoxDecoration(
            color: brand.surface,
            borderRadius: BorderRadius.circular(AppRadii.card),
            boxShadow: AppShadows.card(theme.brightness),
          ),
          child: Column(
            children: [
              for (var i = 0; i < ModulesScreen._editOrder.length; i++) ...[
                if (i > 0)
                  Divider(height: 1, thickness: 1, color: brand.hairline),
                _EditModuleRow(
                  module: ModulesScreen._editOrder[i],
                  isEnabled: settings.isEnabled(ModulesScreen._editOrder[i]),
                  isLocked: settings.lockedModules.contains(
                    ModulesScreen._editOrder[i],
                  ),
                  onToggleEnabled: (v) {
                    AppHaptics.selection();
                    notifier.toggleModule(ModulesScreen._editOrder[i], v);
                  },
                  onToggleLock: () async {
                    final m = ModulesScreen._editOrder[i];
                    if (!settings.isEnabled(m)) return;
                    final next = !settings.lockedModules.contains(m);
                    if (next &&
                        !security.hasPin &&
                        !await security.canUseBiometrics()) {
                      if (!context.mounted) return;
                      final set = await showSetPinSheet(context, ref);
                      if (!set) return;
                    }
                    AppHaptics.tap();
                    notifier.toggleModuleLock(m, next);
                  },
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Switched-off modules leave Today and Quick add. Nothing is '
            'deleted. A lock asks for your fingerprint or app PIN each time '
            'the module opens.',
            style: TextStyle(fontSize: 13, height: 1.45, color: context.muted),
          ),
        ),
      ],
    );
  }
}

class _SwitchedOffChip extends StatelessWidget {
  final AppModule module;
  final VoidCallback onTap;

  const _SwitchedOffChip({required this.module, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Semantics(
      button: true,
      label: 'Turn on ${module.label}',
      child: GestureDetector(
        onTap: onTap,
        child: CustomPaint(
          painter: _DashedStadiumPainter(color: brand.outlineIdle),
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(AppIcons.add, size: 16, color: context.muted),
                const SizedBox(width: 6),
                Text(
                  module.label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: brand.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedStadiumPainter extends CustomPainter {
  final Color color;

  _DashedStadiumPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height / 2),
    );
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (final metric in path.computeMetrics()) {
      const dash = 5.0;
      const gap = 4.0;
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedStadiumPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _EditModuleRow extends StatelessWidget {
  final AppModule module;
  final bool isEnabled;
  final bool isLocked;
  final ValueChanged<bool> onToggleEnabled;
  final VoidCallback onToggleLock;

  const _EditModuleRow({
    required this.module,
    required this.isEnabled,
    required this.isLocked,
    required this.onToggleEnabled,
    required this.onToggleLock,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final (icon, accent) = ModulesScreen.metaFor(context, module);
    final roles = brand.roleFor(accent);
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isEnabled ? roles.tintFill : brand.canvas,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: AppIcon(
                icon,
                size: 20,
                color: isEnabled ? roles.graphicOnTint : context.muted,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  module.label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: isEnabled ? brand.ink : context.muted,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  module.blurb,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: context.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Semantics(
            button: true,
            enabled: isEnabled,
            toggled: isLocked,
            label: isLocked ? 'Unlock ${module.label}' : 'Lock ${module.label}',
            child: GestureDetector(
              onTap: isEnabled ? onToggleLock : null,
              child: Opacity(
                opacity: isEnabled ? 1.0 : 0.45,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isLocked ? brand.ink : brand.well,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: AppIcon(
                      isLocked ? AppIcons.lock : AppIcons.unlock,
                      size: 18,
                      color: isLocked ? brand.onInk : context.muted,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Semantics(
            toggled: isEnabled,
            label: 'Toggle ${module.label}',
            child: GestureDetector(
              onTap: () => onToggleEnabled(!isEnabled),
              child: AnimatedContainer(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 220),
                width: 52,
                height: 32,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: isEnabled ? brand.ink : brand.well,
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: isEnabled
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: isEnabled ? brand.onInk : brand.surface,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

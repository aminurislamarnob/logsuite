import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/ai_client.dart';
import '../../core/ai/ai_command_service.dart';
import '../../core/ai/ai_provider.dart';
import '../../core/ai/api_key_store.dart';
import '../../core/people/people_repository.dart';
import '../../core/people/person_avatar.dart';
import '../../core/services/export_service.dart';
import '../../core/services/notification_service.dart';
import '../../core/services/reminder_sync.dart';
import '../../core/services/restore_service.dart';
import '../../core/services/security_service.dart';
import '../../core/settings/app_settings.dart';
import '../../core/settings/voice_language.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/palette_picker.dart';
import '../reminders/reminders_screen.dart';
import 'how_to_screen.dart';
import 'people_screen.dart';

/// Main Settings screen (`16-settings.html`), linking to [PeopleScreen]
/// (`40-people.html`), [AiSettingsScreen] (`41-aisettings.html`),
/// [BackupSettingsScreen] (`43-backup.html`), and [HowToScreen]
/// (`44-how-to.html`).
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _showMoreAppearance = false;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final last4 = ref.watch(aiKeyStatusProvider).valueOrNull;
    final brand = context.brand;
    final theme = Theme.of(context);

    final quietLabel = settings.dndEnabled
        ? 'Quiet ${Fmt.minutesOfDay(settings.dndStartMinutes)} – ${Fmt.minutesOfDay(settings.dndEndMinutes)}'
        : 'All hours';

    return BrandScaffold(
      header: const BrandTopBar(title: 'Settings', leadingIcon: null),
      child: ListView(
        padding: pageInsets(context, top: 8, end: PageEnd.navBar),
        children: [
          const _ProfileCard(),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: brand.surface,
              borderRadius: BorderRadius.circular(AppRadii.card),
              boxShadow: AppShadows.card(theme.brightness),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'APPEARANCE',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: context.muted,
                  ),
                ),
                const SizedBox(height: 14),
                _ThemeModeSegment(
                  selected: settings.themeMode,
                  onSelected: notifier.setThemeMode,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Colour',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const PalettePicker(),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Compact density',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            'Fit more on each screen',
                            style: TextStyle(
                              fontSize: 12,
                              color: context.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch.adaptive(
                      value: settings.compactDensity,
                      onChanged: notifier.setCompactDensity,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                BrandTappable(
                  onPressed: () => setState(
                    () => _showMoreAppearance = !_showMoreAppearance,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Text(
                          _showMoreAppearance
                              ? 'Fewer display options'
                              : 'Text size, motion & haptics',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: context.muted,
                          ),
                        ),
                        const SizedBox(width: 4),
                        AppIcon(
                          _showMoreAppearance
                              ? AppIcons.chevronUp
                              : AppIcons.chevronDown,
                          size: 14,
                          color: context.muted,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_showMoreAppearance) ...[
                  Divider(color: brand.hairline, height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Text size',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '${(settings.textScale * 100).round()}%',
                              style: TextStyle(
                                fontSize: 12,
                                color: context.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 150,
                        child: BrandSlider(
                          value: settings.textScale,
                          min: 0.85,
                          max: 1.6,
                          divisions: 15,
                          onChanged: notifier.setTextScale,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Reduce motion',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Switch.adaptive(
                        value: settings.reduceMotion,
                        onChanged: notifier.setReduceMotion,
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Haptic feedback',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Switch.adaptive(
                        value: settings.hapticsEnabled,
                        onChanged: notifier.setHapticsEnabled,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            decoration: BoxDecoration(
              color: brand.surface,
              borderRadius: BorderRadius.circular(AppRadii.card),
              boxShadow: AppShadows.card(theme.brightness),
            ),
            child: Column(
              children: [
                _SettingsNavRow(
                  chipColor: brand.hairline,
                  iconColor: brand.ink,
                  icon: AppIcons.modules,
                  title: 'Modules',
                  value: '${settings.enabledModules.length} on',
                  onTap: () => _showModulesSheet(context),
                ),
                _SettingsNavRow(
                  chipColor: brand.medicineRoles.tintFill,
                  iconColor: brand.medicineRoles.graphicOnTint,
                  icon: AppIcons.sparkle,
                  title: 'AI assistant',
                  value:
                      '${settings.aiProvider.label} · ${last4 == null ? 'no key' : 'key saved'}',
                  onTap: () => Navigator.of(context, rootNavigator: true).push(
                    MaterialPageRoute(builder: (_) => const AiSettingsScreen()),
                  ),
                ),
                _SettingsNavRow(
                  chipColor: brand.warningRoles.tintFill,
                  iconColor: brand.warningRoles.graphicOnTint,
                  icon: AppIcons.notifications,
                  title: 'Reminders',
                  value: quietLabel,
                  onTap: () => _showRemindersSheet(context),
                ),
                _SettingsNavRow(
                  chipColor: brand.habitRoles.tintFill,
                  iconColor: brand.habitRoles.graphicOnTint,
                  icon: AppIcons.lock,
                  title: 'Security',
                  value: settings.appLockEnabled ? 'App lock on' : 'Off',
                  onTap: () => _showSecuritySheet(context),
                ),
                _SettingsNavRow(
                  chipColor: brand.taskRoles.tintFill,
                  iconColor: brand.taskRoles.graphicOnTint,
                  icon: AppIcons.language,
                  title: 'Language & region',
                  value:
                      '${settings.locale == 'bn' ? 'বাংলা' : 'English'} · ${settings.currencySymbol}',
                  onTap: () => _showLanguageRegionSheet(context),
                ),
                _SettingsNavRow(
                  chipColor: brand.dropRoles.tintFill,
                  iconColor: brand.dropRoles.graphicOnTint,
                  icon: AppIcons.backup,
                  title: 'Backup & restore',
                  value: 'JSON & CSV',
                  showDivider: false,
                  onTap: () => Navigator.of(context, rootNavigator: true).push(
                    MaterialPageRoute(
                      builder: (_) => const BackupSettingsScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            decoration: BoxDecoration(
              color: brand.surface,
              borderRadius: BorderRadius.circular(AppRadii.card),
              boxShadow: AppShadows.card(theme.brightness),
            ),
            child: Column(
              children: [
                _SettingsNavRow(
                  chipColor: brand.hairline,
                  iconColor: brand.ink,
                  icon: AppIcons.idea,
                  title: 'How to use logSuite',
                  onTap: () => Navigator.of(context, rootNavigator: true).push(
                    MaterialPageRoute(builder: (_) => const HowToScreen()),
                  ),
                ),
                _SettingsNavRow(
                  chipColor: brand.hairline,
                  iconColor: brand.ink,
                  icon: AppIcons.info,
                  title: 'About',
                  value: 'Everything stays on this device',
                  showChevron: false,
                  showDivider: false,
                  onTap: () => brandToast(
                    context,
                    'logSuite 1.0.0 · Everything stays on this device.',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showModulesSheet(BuildContext context) async {
    await brandSheet<void>(
      context: context,
      builder: (_) => Consumer(
        builder: (context, ref, _) {
          final settings = ref.watch(settingsProvider);
          final notifier = ref.read(settingsProvider.notifier);
          return SheetScaffold(
            title: 'Modules',
            child: TileGroup(
              children: AppModule.values
                  .map(
                    (m) => BrandSwitchTile(
                      title: m.label,
                      subtitle: m.blurb,
                      value: settings.isEnabled(m),
                      onChanged: (v) => notifier.toggleModule(m, v),
                    ),
                  )
                  .toList(),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showRemindersSheet(BuildContext context) async {
    await brandSheet<void>(
      context: context,
      builder: (_) => Consumer(
        builder: (context, ref, _) {
          final settings = ref.watch(settingsProvider);
          final notifier = ref.read(settingsProvider.notifier);
          return SheetScaffold(
            title: 'Reminders',
            child: TileGroup(
              children: [
                BrandTile(
                  leading: const AppIcon(AppIcons.notificationsActive),
                  title: const Text('Allow notifications'),
                  subtitle: const Text(
                    'Medicine reminders always override quiet hours',
                    style: TextStyle(fontSize: 11),
                  ),
                  trailing: const AppIcon(AppIcons.chevronRight),
                  onTap: () async {
                    final granted = await ref
                        .read(notificationServiceProvider)
                        .requestPermissions();
                    if (context.mounted) {
                      brandToast(
                        context,
                        granted
                            ? 'Notifications enabled.'
                            : 'Permission denied — enable it in system settings.',
                      );
                    }
                  },
                ),
                BrandSwitchTile(
                  leading: const AppIcon(AppIcons.sleep),
                  title: 'Quiet hours',
                  subtitle:
                      '${Fmt.minutesOfDay(settings.dndStartMinutes)} — '
                      '${Fmt.minutesOfDay(settings.dndEndMinutes)}',
                  value: settings.dndEnabled,
                  onChanged: (v) => notifier.setDnd(v),
                ),
                if (settings.dndEnabled)
                  Row(
                    children: [
                      Expanded(
                        child: BrandTile(
                          title: const Text(
                            'From',
                            style: TextStyle(fontSize: 12),
                          ),
                          subtitle: Text(
                            Fmt.minutesOfDay(settings.dndStartMinutes),
                          ),
                          onTap: () async {
                            final t = await brandTimePicker(
                              context,
                              initialMinutes: settings.dndStartMinutes,
                              title: 'Quiet hours',
                            );
                            if (t != null) {
                              notifier.setDnd(
                                true,
                                start: t,
                                end: settings.dndEndMinutes,
                              );
                            }
                          },
                        ),
                      ),
                      Expanded(
                        child: BrandTile(
                          title: const Text(
                            'To',
                            style: TextStyle(fontSize: 12),
                          ),
                          subtitle: Text(
                            Fmt.minutesOfDay(settings.dndEndMinutes),
                          ),
                          onTap: () async {
                            final t = await brandTimePicker(
                              context,
                              initialMinutes: settings.dndEndMinutes,
                              title: 'Quiet hours',
                            );
                            if (t != null) {
                              notifier.setDnd(
                                true,
                                start: settings.dndStartMinutes,
                                end: t,
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _showSecuritySheet(BuildContext context) async {
    await brandSheet<void>(
      context: context,
      builder: (_) => Consumer(
        builder: (context, ref, _) {
          final settings = ref.watch(settingsProvider);
          final notifier = ref.read(settingsProvider.notifier);
          final security = ref.read(securityServiceProvider);
          final hasPin = ref.watch(pinStatusProvider);
          return SheetScaffold(
            title: 'Security',
            child: TileGroup(
              children: [
                BrandSwitchTile(
                  leading: const AppIcon(AppIcons.lock),
                  title: 'Lock the app',
                  subtitle: 'Biometric or PIN on launch',
                  value: settings.appLockEnabled,
                  onChanged: (v) async {
                    if (v &&
                        !await security.canUseBiometrics() &&
                        !security.hasPin) {
                      if (context.mounted) {
                        final set = await _setPin(context, ref);
                        if (!set) return;
                      }
                    }
                    notifier.setAppLock(v);
                  },
                ),
                BrandTile(
                  leading: const AppIcon(AppIcons.pin),
                  title: Text(hasPin ? 'Change PIN' : 'Set a PIN'),
                  trailing: hasPin
                      ? CircleIconButton(
                          icon: AppIcons.delete,
                          tooltip: 'Remove PIN',
                          size: 36,
                          onPressed: () async {
                            await ref.read(pinStatusProvider.notifier).clear();
                            if (context.mounted) {
                              brandToast(context, 'PIN removed.');
                            }
                          },
                        )
                      : const AppIcon(AppIcons.chevronRight),
                  onTap: () => _setPin(context, ref),
                ),
                BrandTile(
                  leading: const AppIcon(AppIcons.focus),
                  title: const Text('Auto-lock after'),
                  subtitle: Text('${settings.autoLockMinutes} minutes'),
                  onTap: () => _pickAutoLock(context, notifier),
                ),
                BrandAccordion(
                  leading: AppIcons.modules,
                  title: 'Lock individual modules',
                  child: TileGroup(
                    children: AppModule.values
                        .map(
                          (m) => BrandSwitchTile(
                            title: m.label,
                            value: settings.lockedModules.contains(m),
                            onChanged: (v) async {
                              if (v &&
                                  !await security.canUseBiometrics() &&
                                  !security.hasPin) {
                                if (context.mounted) {
                                  final set = await _setPin(context, ref);
                                  if (!set) return;
                                }
                              }
                              notifier.toggleModuleLock(m, v);
                            },
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _showLanguageRegionSheet(BuildContext context) async {
    await brandSheet<void>(
      context: context,
      builder: (_) => Consumer(
        builder: (context, ref, _) {
          final settings = ref.watch(settingsProvider);
          final notifier = ref.read(settingsProvider.notifier);
          return SheetScaffold(
            title: 'Language & region',
            child: TileGroup(
              children: [
                BrandTile(
                  leading: const AppIcon(AppIcons.language),
                  title: const Text('Language'),
                  subtitle: Text(settings.locale == 'bn' ? 'বাংলা' : 'English'),
                  trailing: BrandSegmented<String>(
                    options: const {'en': 'EN', 'bn': 'বাং'},
                    selected: settings.locale,
                    onSelected: notifier.setLocale,
                  ),
                ),
                BrandTile(
                  leading: const AppIcon(AppIcons.cash),
                  title: const Text('Currency symbol'),
                  subtitle: Text(settings.currencySymbol),
                  onTap: () => _pickCurrency(context, notifier),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _pickCurrency(
    BuildContext context,
    SettingsNotifier notifier,
  ) async {
    const options = ['৳', '\$', '€', '₹', '£', '¥'];
    final picked = await brandSheet<String>(
      context: context,
      builder: (sheetContext) => SheetScaffold(
        title: 'Currency symbol',
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: options
              .map(
                (s) => Pill(
                  label: s,
                  color: Theme.of(context).colorScheme.primary,
                  onTap: () => Navigator.pop(sheetContext, s),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (picked != null) notifier.setCurrencySymbol(picked);
  }

  Future<void> _pickAutoLock(
    BuildContext context,
    SettingsNotifier notifier,
  ) async {
    final picked = await brandSheet<int>(
      context: context,
      builder: (sheetContext) => SheetScaffold(
        title: 'Auto-lock after',
        child: TileColumn(
          children: [0, 1, 5, 15, 30]
              .map(
                (m) => BrandTile(
                  title: Text(m == 0 ? 'Immediately' : '$m minutes'),
                  onTap: () => Navigator.pop(sheetContext, m),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (picked != null) notifier.setAutoLockMinutes(picked);
  }

  Future<bool> _setPin(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final confirm = TextEditingController();
    String? lengthError;
    String? matchError;

    final result = await brandDialog<bool>(
      context,
      title: 'Set a PIN',
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BrandField(
              controller: controller,
              label: 'New PIN',
              error: lengthError,
              autofocus: true,
              obscure: true,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            BrandField(
              controller: confirm,
              label: 'Confirm PIN',
              error: matchError,
              obscure: true,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 20),
            BrandButton(
              label: 'Save',
              onPressed: () {
                final short = controller.text.length < 4;
                final mismatch = !short && controller.text != confirm.text;
                if (short || mismatch) {
                  setState(() {
                    lengthError = short ? 'Use at least 4 digits' : null;
                    matchError = mismatch ? 'PINs do not match' : null;
                  });
                  return;
                }
                Navigator.pop(context, true);
              },
            ),
            const SizedBox(height: 8),
            BrandButton(
              label: 'Cancel',
              kind: BrandButtonKind.ghost,
              onPressed: () => Navigator.pop(context, false),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      await ref.read(pinStatusProvider.notifier).set(controller.text);
      if (context.mounted) {
        brandToast(context, 'PIN saved.');
      }
      return true;
    }
    return false;
  }
}

class _ThemeModeSegment extends StatelessWidget {
  final ThemeMode selected;
  final ValueChanged<ThemeMode> onSelected;

  const _ThemeModeSegment({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    const entries = <(ThemeMode, String)>[
      (ThemeMode.system, 'Auto'),
      (ThemeMode.light, 'Light'),
      (ThemeMode.dark, 'Dark'),
    ];
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: brand.hairline,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          for (final (mode, label) in entries)
            Expanded(
              child: BrandTappable(
                onPressed: () => onSelected(mode),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected == mode ? brand.ink : Colors.transparent,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected == mode
                          ? FontWeight.w700
                          : FontWeight.w600,
                      color: selected == mode ? brand.onInk : context.muted,
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

class _SettingsNavRow extends StatelessWidget {
  final Color chipColor;
  final Color iconColor;
  final HugeIconData icon;
  final String title;
  final String? value;
  final bool showChevron;
  final bool showDivider;
  final VoidCallback onTap;

  const _SettingsNavRow({
    required this.chipColor,
    required this.iconColor,
    required this.icon,
    required this.title,
    this.value,
    this.showChevron = true,
    this.showDivider = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return BrandTappable(
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: showDivider
              ? Border(bottom: BorderSide(color: brand.hairline))
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: chipColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: AppIcon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (value != null) ...[
              const SizedBox(width: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 185),
                child: Text(
                  value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(fontSize: 13, color: context.muted),
                ),
              ),
            ],
            if (showChevron) ...[
              const SizedBox(width: 6),
              AppIcon(AppIcons.chevronRight, size: 16, color: context.subtle),
            ],
          ],
        ),
      ),
    );
  }
}

/// The user's own row (`16-settings.html` lines 23-27).
class _ProfileCard extends ConsumerWidget {
  const _ProfileCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final self = ref.watch(selfProvider);
    final people = ref.watch(peopleProvider).valueOrNull ?? const [];
    final brand = context.brand;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryText = isDark ? brand.ink : brand.onInk;
    final named = self != null && self.name.trim().isNotEmpty;
    final initials = Fmt.initials(self?.name ?? '');

    return Container(
      decoration: BoxDecoration(
        color: brand.heroSurface,
        borderRadius: BorderRadius.circular(26),
        boxShadow: AppShadows.hero(theme.brightness),
      ),
      child: BrandTappable(
        onPressed: () => Navigator.of(
          context,
          rootNavigator: true,
        ).push(MaterialPageRoute(builder: (_) => const PeopleScreen())),
        semanticsLabel: 'Your profile',
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              if (self?.photoPath != null)
                PersonAvatar(
                  photoPath: self!.photoPath,
                  color: personColor(context, self.color),
                  size: 56,
                )
              else
                Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: brand.medicine,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    initials.isEmpty ? 'ME' : initials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 19,
                    ),
                  ),
                ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      named ? self.name : 'Your profile',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 19,
                        letterSpacing: -0.3,
                        color: primaryText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Household & contacts · ${people.length} ${people.length == 1 ? 'person' : 'people'}',
                      style: TextStyle(fontSize: 13, color: brand.onInkMuted),
                    ),
                  ],
                ),
              ),
              AppIcon(AppIcons.chevronRight, color: brand.onInkMuted, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dedicated AI assistant settings screen (`41-aisettings.html`).
class AiSettingsScreen extends ConsumerStatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  ConsumerState<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends ConsumerState<AiSettingsScreen> {
  final _keyController = TextEditingController();
  bool _obscureKey = true;

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final provider = settings.aiProvider;
    final last4 = ref.watch(aiKeyStatusProvider).valueOrNull;
    final brand = context.brand;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryOnInk = isDark ? brand.ink : brand.onInk;

    return BrandScaffold(
      header: const BrandTopBar(
        title: 'AI assistant',
        leadingIcon: AppIcons.back,
      ),
      child: ListView(
        padding: pageInsets(context, top: 8, end: PageEnd.none),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
            child: Text(
              'PROVIDER',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: context.muted,
              ),
            ),
          ),
          GridView.count(
            padding: EdgeInsets.zero,
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2.75,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final p in AiProvider.values)
                Builder(
                  builder: (context) {
                    final selected = p == provider;
                    final hasKeyForThis = selected && last4 != null;
                    return BrandTappable(
                      onPressed: () {
                        if (p != provider) notifier.setAiProvider(p);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: selected ? brand.ink : brand.surface,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: selected
                              ? AppShadows.hero(theme.brightness)
                              : AppShadows.card(theme.brightness),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 22,
                              height: 22,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: selected
                                    ? brand.onInk
                                    : Colors.transparent,
                                shape: BoxShape.circle,
                                border: selected
                                    ? null
                                    : Border.all(
                                        color: brand.outlineIdle,
                                        width: 2,
                                      ),
                              ),
                              child: selected
                                  ? AppIcon(
                                      AppIcons.check,
                                      size: 13,
                                      color: brand.ink,
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    p.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: selected ? brand.onInk : brand.ink,
                                    ),
                                  ),
                                  Text(
                                    hasKeyForThis
                                        ? 'Key saved'
                                        : selected
                                        ? 'No key'
                                        : p.defaultModel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: selected
                                          ? brand.onInkMuted
                                          : context.muted,
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
          ),
          const SizedBox(height: 12),
          Container(
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
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'API KEY',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: context.muted,
                      ),
                    ),
                    if (last4 != null)
                      Container(
                        height: 24,
                        padding: const EdgeInsets.symmetric(horizontal: 9),
                        decoration: BoxDecoration(
                          color: brand.habitRoles.tintFill,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AppIcon(
                              AppIcons.check,
                              size: 11,
                              color: brand.habitRoles.textOnTint,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'Key saved',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: brand.habitRoles.textOnTint,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  height: 52,
                  padding: const EdgeInsets.fromLTRB(14, 0, 6, 0),
                  decoration: BoxDecoration(
                    color: brand.canvas,
                    borderRadius: BorderRadius.circular(AppRadii.field),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _keyController,
                          obscureText: _obscureKey,
                          keyboardType: TextInputType.visiblePassword,
                          style: TextStyle(fontSize: 15, color: brand.ink),
                          decoration: InputDecoration(
                            hintText: last4 == null
                                ? provider.keyHint
                                : '••••••••••••••••$last4',
                            hintStyle: TextStyle(
                              fontSize: 15,
                              color: context.muted,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                            isDense: true,
                          ),
                          onSubmitted: (_) => _saveTypedKey(provider),
                        ),
                      ),
                      BrandTappable(
                        onPressed: () =>
                            setState(() => _obscureKey = !_obscureKey),
                        semanticsLabel: 'Show key',
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: Center(
                            child: AppIcon(
                              _obscureKey ? AppIcons.eye : AppIcons.eyeClosed,
                              size: 20,
                              color: context.muted,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: AppIcon(
                        AppIcons.lock,
                        size: 14,
                        color: context.muted,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Stored in this phone’s keychain. It never goes into a backup.',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.muted,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: BrandTappable(
                        onPressed: () async {
                          if (_keyController.text.trim().isNotEmpty) {
                            await _saveTypedKey(provider);
                          } else if (last4 != null) {
                            await _testConnection(context, ref);
                          } else {
                            await _setApiKeyDialog(context, ref, provider);
                          }
                        },
                        child: Container(
                          height: 44,
                          alignment: Alignment.center,
                          decoration: ShapeDecoration(
                            color: brand.ink,
                            shape: const StadiumBorder(),
                          ),
                          child: Text(
                            _keyController.text.trim().isNotEmpty
                                ? 'Save key'
                                : last4 != null
                                ? 'Test connection'
                                : 'Add API key',
                            style: TextStyle(
                              color: brand.onInk,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (last4 != null) ...[
                      const SizedBox(width: 8),
                      BrandTappable(
                        onPressed: () async {
                          final ok = await brandConfirm(
                            context,
                            title: 'Remove the ${provider.label} key?',
                            message:
                                'The assistant will use the offline parser '
                                'until a key is added again.',
                            confirmLabel: 'Remove',
                            destructive: true,
                          );
                          if (!ok) return;
                          await ref.read(aiKeyStatusProvider.notifier).clear();
                          if (context.mounted) {
                            brandToast(context, 'Key removed.');
                          }
                        },
                        child: Container(
                          height: 44,
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          alignment: Alignment.center,
                          decoration: ShapeDecoration(
                            color: brand.danger.withValues(alpha: 0.12),
                            shape: const StadiumBorder(),
                          ),
                          child: Text(
                            'Remove key',
                            style: TextStyle(
                              color: brand.danger,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
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
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            decoration: BoxDecoration(
              color: brand.surface,
              borderRadius: BorderRadius.circular(AppRadii.card),
              boxShadow: AppShadows.card(theme.brightness),
            ),
            child: Column(
              children: [
                BrandTappable(
                  onPressed: () => _editModel(context, notifier, settings),
                  child: Container(
                    height: 60,
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: brand.hairline)),
                    ),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Model',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          settings.aiModel.isEmpty
                              ? 'Default'
                              : settings.aiModel,
                          style: TextStyle(fontSize: 13, color: context.muted),
                        ),
                        const SizedBox(width: 6),
                        AppIcon(
                          AppIcons.chevronRight,
                          size: 16,
                          color: context.subtle,
                        ),
                      ],
                    ),
                  ),
                ),
                BrandTappable(
                  onPressed: () =>
                      _pickVoiceLanguage(context, notifier, settings),
                  child: Container(
                    height: 60,
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: brand.hairline)),
                    ),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Voice language',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          settings.voiceLanguage.label,
                          style: TextStyle(fontSize: 13, color: context.muted),
                        ),
                        const SizedBox(width: 6),
                        AppIcon(
                          AppIcons.chevronRight,
                          size: 16,
                          color: context.subtle,
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Auto-save without preview',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Only when every entry resolved cleanly',
                              style: TextStyle(
                                fontSize: 12,
                                color: context.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch.adaptive(
                        value: settings.aiAutoSave,
                        onChanged: notifier.setAiAutoSave,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: brand.heroSurface,
              borderRadius: BorderRadius.circular(AppRadii.card),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AppIcon(
                      AppIcons.privacy,
                      size: 16,
                      color: brand.medicineRoles.onInk,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'WHAT LEAVES THIS PHONE',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: brand.medicineRoles.onInk,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _InkBulletRow(
                  text: 'The text of what you said or scanned',
                  color: primaryOnInk,
                ),
                const SizedBox(height: 8),
                _InkBulletRow(
                  text:
                      'The names of your categories, accounts, people, habits and projects',
                  color: primaryOnInk,
                ),
                const SizedBox(height: 12),
                Text(
                  'Nothing else is sent. Speech is turned into text on this phone.',
                  style: TextStyle(
                    fontSize: 13,
                    color: brand.onInkMuted,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: brand.well,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: AppIcon(AppIcons.info, size: 16, color: context.muted),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Without a key the assistant uses the offline parser. It works in English and Banglish; Bangla script needs a provider.',
                    style: TextStyle(
                      fontSize: 13,
                      color: context.muted,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveTypedKey(AiProvider provider) async {
    final key = _keyController.text.trim();
    if (key.isEmpty || key.contains(RegExp(r'\s'))) {
      brandToast(
        context,
        key.isEmpty ? 'Paste the key first.' : 'A key has no spaces.',
      );
      return;
    }
    await ref.read(aiKeyStatusProvider.notifier).save(key);
    _keyController.clear();
    if (mounted) {
      setState(() {});
      brandToast(context, '${provider.label} key saved.');
    }
  }

  Future<void> _pickVoiceLanguage(
    BuildContext context,
    SettingsNotifier notifier,
    AppSettings settings,
  ) async {
    final picked = await brandSheet<VoiceLanguage>(
      context: context,
      builder: (sheetContext) => SheetScaffold(
        title: 'Voice language',
        child: TileColumn(
          children: VoiceLanguage.values
              .map(
                (lang) => BrandTile(
                  title: Text(lang.label),
                  subtitle: Text(lang.description),
                  selected: lang == settings.voiceLanguage,
                  onTap: () => Navigator.pop(sheetContext, lang),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (picked != null) notifier.setVoiceLanguage(picked);
  }

  Future<void> _editModel(
    BuildContext context,
    SettingsNotifier notifier,
    AppSettings settings,
  ) async {
    final currentModel = settings.aiModel.isEmpty
        ? settings.aiProvider.defaultModel
        : settings.aiModel;
    final defaultModel = settings.aiProvider.defaultModel;
    final availableModels = settings.aiProvider.availableModels;

    final picked = await brandSheet<String>(
      context: context,
      builder: (sheetContext) => SheetScaffold(
        title: 'Model',
        child: TileColumn(
          children: availableModels
              .map(
                (model) => BrandTile(
                  title: Text(model),
                  subtitle: model == defaultModel
                      ? const Text('Default')
                      : null,
                  selected: model == currentModel,
                  onTap: () => Navigator.pop(
                    sheetContext,
                    model == defaultModel ? '' : model,
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );

    if (picked != null) notifier.setAiModel(picked);
  }

  Future<void> _setApiKeyDialog(
    BuildContext context,
    WidgetRef ref,
    AiProvider provider,
  ) async {
    final controller = TextEditingController();
    String? error;

    final result = await brandDialog<bool>(
      context,
      title: '${provider.label} API key',
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BrandField(
              controller: controller,
              hint: provider.keyHint,
              helper: 'From ${provider.consoleUrl}. Stored in the keychain.',
              error: error,
              autofocus: true,
              obscure: true,
              keyboardType: TextInputType.visiblePassword,
            ),
            const SizedBox(height: 20),
            BrandButton(
              label: 'Save',
              onPressed: () {
                final key = controller.text.trim();
                if (key.isEmpty || key.contains(RegExp(r'\s'))) {
                  setState(() {
                    error = key.isEmpty
                        ? 'Paste the key first'
                        : 'A key has no spaces';
                  });
                  return;
                }
                Navigator.pop(context, true);
              },
            ),
            const SizedBox(height: 8),
            BrandButton(
              label: 'Cancel',
              kind: BrandButtonKind.ghost,
              onPressed: () => Navigator.pop(context, false),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      await ref.read(aiKeyStatusProvider.notifier).save(controller.text);
      if (context.mounted) brandToast(context, 'Key saved.');
    }
  }

  Future<void> _testConnection(BuildContext context, WidgetRef ref) async {
    brandToast(context, 'Testing…', duration: const Duration(seconds: 2));
    try {
      final model = await ref.read(aiCommandServiceProvider).testConnection();
      if (context.mounted) brandToast(context, 'Connected · $model');
    } on AiException catch (e) {
      if (context.mounted) brandToast(context, 'Failed: ${e.message}');
    }
  }
}

class _InkBulletRow extends StatelessWidget {
  final String text;
  final Color color;

  const _InkBulletRow({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.only(top: 7),
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 14, color: color, height: 1.4),
          ),
        ),
      ],
    );
  }
}

/// Dedicated Backup & restore screen (`43-backup.html`, titled `Data`).
class BackupSettingsScreen extends ConsumerWidget {
  const BackupSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryOnInk = isDark ? brand.ink : brand.onInk;
    final remindersCount =
        ref.watch(remindersProvider).valueOrNull?.length ?? 0;

    return BrandScaffold(
      header: const BrandTopBar(title: 'Data', leadingIcon: AppIcons.back),
      child: ListView(
        padding: pageInsets(context, top: 8, end: PageEnd.none),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: brand.heroSurface,
              borderRadius: BorderRadius.circular(AppRadii.hero),
              boxShadow: AppShadows.hero(theme.brightness),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'LAST BACKUP',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.0,
                              color: brand.medicineRoles.onInk,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Full backup',
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1.0,
                              height: 1.05,
                              color: primaryOnInk,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Everything on this device · restorable',
                            style: TextStyle(
                              fontSize: 14,
                              color: brand.onInkMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: AppIcon(
                        AppIcons.privacy,
                        size: 24,
                        color: primaryOnInk,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tag in const [
                      'Every module',
                      'People & photos',
                      'One JSON file',
                    ])
                      Container(
                        height: 28,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              tag,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: primaryOnInk,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                BrandTappable(
                  onPressed: () =>
                      _export(context, ref, (e) => e.fullJsonBackup()),
                  child: Container(
                    height: 54,
                    decoration: BoxDecoration(
                      color: primaryOnInk,
                      borderRadius: BorderRadius.circular(27),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AppIcon(
                          AppIcons.share,
                          size: 18,
                          color: brand.heroSurface,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Share a full backup',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: brand.heroSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
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
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: brand.dropRoles.tintFill,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: AppIcon(
                        AppIcons.restoreBackup,
                        size: 22,
                        color: brand.dropRoles.graphicOnTint,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Restore from a backup',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Pick a logSuite backup file',
                            style: TextStyle(
                              fontSize: 13,
                              color: context.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: brand.warningRoles.tintFill,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: AppIcon(
                          AppIcons.warning,
                          size: 16,
                          color: brand.warningRoles.graphicOnTint,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Replaces everything on this device. The file is checked in full first, so a damaged one changes nothing.',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: brand.warningRoles.textOnTint,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                BrandTappable(
                  onPressed: () => _restoreBackup(context, ref),
                  child: Container(
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: brand.hairline,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Text(
                      'Choose a file',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: brand.ink,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
            child: Text(
              'EXPORT',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: context.muted,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            decoration: BoxDecoration(
              color: brand.surface,
              borderRadius: BorderRadius.circular(AppRadii.tile),
              boxShadow: AppShadows.card(theme.brightness),
            ),
            child: Column(
              children: [
                _SettingsNavRow(
                  chipColor: brand.expenseRoles.tintFill,
                  iconColor: brand.expenseRoles.graphicOnTint,
                  icon: AppIcons.expenses,
                  title: 'Transactions as CSV',
                  value: 'Expenses',
                  showChevron: false,
                  onTap: () => _export(context, ref, (e) => e.expensesCsv()),
                ),
                _SettingsNavRow(
                  chipColor: brand.taskRoles.tintFill,
                  iconColor: brand.taskRoles.graphicOnTint,
                  icon: AppIcons.checklist,
                  title: 'Tasks as CSV',
                  value: 'Tasks',
                  showChevron: false,
                  onTap: () => _export(context, ref, (e) => e.tasksCsv()),
                ),
                _SettingsNavRow(
                  chipColor: brand.medicineRoles.tintFill,
                  iconColor: brand.medicineRoles.graphicOnTint,
                  icon: AppIcons.medicine,
                  title: 'Medicine log as CSV',
                  value: 'Medicine',
                  showChevron: false,
                  onTap: () => _export(context, ref, (e) => e.medicineCsv()),
                ),
                _SettingsNavRow(
                  chipColor: brand.habitRoles.tintFill,
                  iconColor: brand.habitRoles.graphicOnTint,
                  icon: AppIcons.habits,
                  title: 'Habit log as CSV',
                  value: 'Habits',
                  showChevron: false,
                  showDivider: false,
                  onTap: () => _export(context, ref, (e) => e.habitsCsv()),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          BrandTappable(
            onPressed: () async {
              await ref.read(notificationServiceProvider).cancelAll();
              if (context.mounted) {
                brandToast(context, 'Reminders cleared.');
              }
            },
            child: Container(
              height: 60,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: brand.surface,
                borderRadius: BorderRadius.circular(AppRadii.tile),
                boxShadow: AppShadows.card(theme.brightness),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: brand.danger.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: AppIcon(
                      AppIcons.notificationsOff,
                      size: 18,
                      color: brand.danger,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Clear all scheduled reminders',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: brand.danger,
                          ),
                        ),
                        Text(
                          '$remindersCount scheduled · your data is kept',
                          style: TextStyle(fontSize: 12, color: context.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _export(
    BuildContext context,
    WidgetRef ref,
    Future Function(ExportService) build,
  ) async {
    final service = ref.read(exportServiceProvider);
    try {
      final file = await build(service);
      await service.shareFile(file);
    } on Exception catch (e) {
      if (context.mounted) {
        brandToast(context, 'Export failed: $e');
      }
    }
  }

  Future<void> _restoreBackup(BuildContext context, WidgetRef ref) async {
    final confirmed = await brandConfirm(
      context,
      title: 'Restore from a backup?',
      message:
          'Every note, task, habit, medicine, expense and person on this '
          'device is replaced by the backup you pick. This cannot be undone.',
      confirmLabel: 'Choose a file',
      destructive: true,
    );
    if (!confirmed) return;

    final FilePickerResult? picked;
    try {
      picked = await FilePicker.pickFiles(
        dialogTitle: 'Pick a logSuite backup',
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
    } on PlatformException {
      if (context.mounted) {
        brandToast(context, 'No file picker is available on this device.');
      }
      return;
    }

    final files = picked?.files ?? const [];
    final path = files.isEmpty ? null : files.first.path;
    if (path == null) return;

    if (!context.mounted) return;
    brandToast(context, 'Restoring…', duration: const Duration(seconds: 2));
    try {
      final summary = await ref
          .read(restoreServiceProvider)
          .restoreFromFile(File(path));
      await ref.read(notificationServiceProvider).cancelAll();
      await ref.read(reminderSyncProvider).syncAll();
      if (context.mounted) {
        brandToast(
          context,
          'Restored ${summary.total} ${summary.total == 1 ? 'entry' : 'entries'}.',
        );
      }
    } on RestoreException catch (e) {
      if (context.mounted) brandToast(context, e.message);
    }
  }
}

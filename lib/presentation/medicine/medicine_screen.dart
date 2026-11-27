import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/ai_drafts.dart';
import '../../core/database/app_database.dart';
import '../../core/people/person_avatar.dart';
import '../../core/services/export_service.dart';
import '../../core/services/notification_service.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/common.dart';
import 'camera_scan_screen.dart';
import 'providers/medicine_provider.dart';
import 'repository/medicine_repository.dart';
import 'utils/after_opening_expiry.dart';
import 'utils/dose_reminders.dart';
import 'utils/schedule_generator.dart';
import 'widgets/medicine_editor_sheet.dart';

class MedicineScreen extends ConsumerStatefulWidget {
  const MedicineScreen({super.key});

  @override
  ConsumerState<MedicineScreen> createState() => _MedicineScreenState();
}

class _MedicineScreenState extends ConsumerState<MedicineScreen> {
  Future<void> _scanPrescription() async {
    final result = await Navigator.of(context).push<ScanResult>(
      MaterialPageRoute(
        builder: (_) => const CameraScanScreen(mode: ScanMode.prescription),
      ),
    );
    if (result == null || !mounted) return;
    final start = Fmt.dateOnly(DateTime.now());
    final days = result.durationDays ?? 5;
    final times = ScheduleSpec.defaultTimesFor(result.timesPerDay ?? 1);
    final numeric = result.dosage == null
        ? null
        : RegExp(r'[\d.]+').firstMatch(result.dosage!)?.group(0);
    final unit = result.dosage == null
        ? null
        : RegExp(r'[a-zA-Z]+').firstMatch(result.dosage!)?.group(0);

    await MedicineEditorSheet.show(
      context,
      draft: MedicineDraft(
        name: result.medicineName ?? '',
        dosage: double.tryParse(numeric ?? '') ?? 1,
        dosageUnit: unit ?? 'tablet',
        doseMinutes: times,
        start: start,
        end: start.add(Duration(days: days - 1)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return BrandScaffold(
      header: BrandTopBar(
        title: 'Medicine',
        leadingIcon: AppIcons.back,
        leadingActions: [
          CircleIconButton(
            icon: AppIcons.person,
            tooltip: 'Profiles',
            size: 44,
            onPressed: () => brandSideSheet(
              context: context,
              builder: (_) => const _ProfileDrawer(),
            ),
          ),
        ],
        actions: [
          CircleIconButton(
            icon: AppIcons.camera,
            tooltip: 'Scan a prescription',
            size: 44,
            onPressed: _scanPrescription,
          ),
          CircleIconButton(
            key: const ValueKey('fab-add-medicine'),
            icon: AppIcons.add,
            tooltip: 'Add medicine',
            size: 44,
            filled: true,
            color: brand.ink,
            onPressed: () => MedicineEditorSheet.show(context),
          ),
        ],
      ),
      child: BrandTabs(
        tabs: {
          'Today': _TodayTab(
            onLogSymptom: () => _logSymptom(context),
            onShareSchedule: _exportSchedule,
          ),
          'Timeline': const _TimelineTab(),
          'Calendar': const _CalendarTab(),
          'Table': const _TableTab(),
          'Medicines': _MedicinesTab(
            onLogSymptom: () => _logSymptom(context),
            onShareSchedule: _exportSchedule,
          ),
        },
      ),
    );
  }

  Future<void> _exportSchedule() async {
    final export = ref.read(exportServiceProvider);
    final views = ref.read(monthDoseViewsProvider).valueOrNull ?? const [];
    if (views.isEmpty) {
      brandToast(context, 'No doses scheduled this month.');
      return;
    }
    final profiles = ref.read(profilesProvider).valueOrNull ?? const [];
    final activeId = ref.read(activeProfileProvider);
    final profileName = activeId == null
        ? 'All profiles'
        : profiles.where((p) => p.id == activeId).firstOrNull?.name ??
              'Profile';
    final adherence = ref.read(adherenceProvider).valueOrNull;

    final file = await export.medicineSchedulePdf(
      profileName: profileName,
      adherence: adherence?.monthly,
      doses: views
          .map(
            (v) => (
              medicine: v.medicine.name,
              dosage: v.dosageLabel,
              meal: v.mealLabel,
              at: v.at,
              status: v.status,
            ),
          )
          .toList(),
    );
    await export.shareFile(file, text: 'Medicine schedule');
  }

  Future<void> _logSymptom(BuildContext context) async {
    final controller = TextEditingController();
    var severity = 1;

    final saved = await brandSheet<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => SheetScaffold(
          title: 'Log symptom',
          bottomAction: BrandButton(
            label: 'Save symptom',
            onPressed: () => Navigator.pop(context, true),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BrandField(
                controller: controller,
                label: 'Symptom',
                hint: 'Headache, nausea…',
                autofocus: true,
              ),
              const SizedBox(height: 20),
              const Text(
                'Severity',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              BrandSlider(
                value: severity.toDouble(),
                min: 1,
                max: 5,
                divisions: 4,
                onChanged: (v) => setState(() => severity = v.round()),
              ),
            ],
          ),
        ),
      ),
    );

    if (saved == true && controller.text.trim().isNotEmpty) {
      await ref
          .read(medicineRepositoryProvider)
          .logSymptom(
            symptom: controller.text.trim(),
            severity: severity,
            profileId: ref.read(activeProfileProvider),
          );
    }
  }
}

// --- Course progress helpers ------------------------------------------------

({int currentDay, int totalDays, double progress}) _courseProgress(Medicine m) {
  final start = Fmt.dateOnly(m.startDate);
  final end = Fmt.dateOnly(m.endDate);
  final today = Fmt.dateOnly(DateTime.now());
  final totalDays = (end.difference(start).inDays + 1).clamp(1, 9999);
  final currentDay = (today.difference(start).inDays + 1).clamp(1, totalDays);
  final progress = (currentDay / totalDays).clamp(0.0, 1.0);
  return (currentDay: currentDay, totalDays: totalDays, progress: progress);
}

String _frequencySummary(Medicine m) {
  final spec = MedicineRepository.specOf(m);
  return switch (spec.frequency) {
    MedFrequency.timesPerDay => '${spec.doseMinutes.length}× daily',
    MedFrequency.everyXHours => 'Every ${spec.intervalHours}h',
    MedFrequency.specificWeekdays => 'Selected days',
    MedFrequency.alternateDays => 'Alternate days',
  };
}

// --- Today ------------------------------------------------------------------

class _TodayTab extends ConsumerWidget {
  final VoidCallback onLogSymptom;
  final VoidCallback onShareSchedule;

  const _TodayTab({required this.onLogSymptom, required this.onShareSchedule});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final dosesAsync = ref.watch(todayDoseViewsProvider);
    final meds = ref.watch(medicinesProvider).valueOrNull ?? const [];
    final lowStock = ref.watch(lowStockProvider);
    final forecast = ref
        .watch(runOutForecastProvider)
        .where((f) => f.date != null)
        .toList();
    final conflicts = ref.watch(conflictsProvider);

    return dosesAsync.when(
      loading: () => const Center(child: BrandSpinner()),
      error: (e, _) => Center(child: Text('$e')),
      data: (list) {
        final now = DateTime.now();
        final pendingDoses = list
            .where((v) => v.status == DoseStatus.pending)
            .toList();
        // Prefer the dose closest to now that is still pending.
        final dueDose = pendingDoses.firstOrNull;
        final takenCount = list
            .where((v) => v.status == DoseStatus.taken)
            .length;

        return ListView(
          padding: pageInsets(context, top: 12),
          children: [
            if (dueDose != null) ...[
              _DueNowHeroCard(view: dueDose, now: now),
              const SizedBox(height: 18),
            ],

            if (conflicts.isNotEmpty) ...[
              _AlertBanner(
                icon: AppIcons.warning,
                title:
                    '${conflicts.length} timing conflict'
                    '${conflicts.length == 1 ? '' : 's'} this month',
                body: conflicts
                    .take(2)
                    .map(
                      (c) =>
                          '${c.first} & ${c.second} at ${Fmt.time(c.at)} on ${Fmt.dayMonth(c.at)}',
                    )
                    .join('\n'),
              ),
              const SizedBox(height: 12),
            ],

            for (final f in forecast) ...[
              _AlertBanner(
                icon: AppIcons.inventory,
                title:
                    '${f.medicine.name} runs out ${Fmt.relativeDay(f.date!)}',
                body:
                    '${f.medicine.inventory} ${DoseView.formatUnit(f.medicine.inventory, f.medicine.dosageUnit)} left · plan a refill',
              ),
              const SizedBox(height: 12),
            ],

            for (final m in lowStock.where(
              (m) => !forecast.any((f) => f.medicine.id == m.id),
            )) ...[
              _AlertBanner(
                icon: AppIcons.inventory,
                title: '${m.name} is low in stock',
                body:
                    'Only ${m.inventory} ${DoseView.formatUnit(m.inventory, m.dosageUnit)} left.',
              ),
              const SizedBox(height: 12),
            ],

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Today',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                    ),
                  ),
                  if (list.isNotEmpty)
                    Text(
                      '$takenCount of ${list.length} taken',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: context.muted,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            if (list.isEmpty)
              EmptyState(
                icon: AppIcons.medicine,
                title: 'No doses today',
                message: 'Add a medicine to generate its schedule.',
                actionLabel: 'Add medicine',
                onAction: () => MedicineEditorSheet.show(context),
              )
            else
              Stack(
                children: [
                  Positioned(
                    left: 35,
                    top: 24,
                    bottom: 24,
                    child: Container(
                      width: 2,
                      color: brand.outlineIdle.withValues(alpha: 0.65),
                    ),
                  ),
                  Column(
                    children: [
                      for (final v in list)
                        _TodayTimelineRow(
                          view: v,
                          isDueNow: dueDose?.dose.id == v.dose.id,
                        ),
                    ],
                  ),
                ],
              ),

            if (meds.isNotEmpty) ...[
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Courses',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                      ),
                    ),
                    Text(
                      'All ${meds.length}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: context.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _CoursesGrid(medicines: meds),
            ],
          ],
        );
      },
    );
  }
}

class _DueNowHeroCard extends ConsumerWidget {
  final DoseView view;
  final DateTime now;

  const _DueNowHeroCard({required this.view, required this.now});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final roles = brand.medicineRoles;
    final repo = ref.read(medicineRepositoryProvider);
    final course = _courseProgress(view.medicine);
    final isDueOrPast = view.at.isBefore(now.add(const Duration(minutes: 45)));
    final expiry = AfterOpeningStatus.ofMedicine(view.medicine);
    final showExpiryWarning = expiry.needsAttention(now: now);
    final expiryRoles = expiry.isExpired(now: now)
        ? brand.dangerRoles
        : brand.warningRoles;

    final subtitleParts = <String>[
      view.dosageLabel,
      if (view.mealLabel.isNotEmpty) view.mealLabel.toLowerCase(),
      'day ${course.currentDay} of ${course.totalDays}',
    ];

    return Container(
      decoration: BoxDecoration(
        color: roles.tintFill,
        borderRadius: BorderRadius.circular(26),
        boxShadow: AppShadows.card(theme.brightness),
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: brand.medicine,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isDueOrPast ? 'DUE NOW' : 'NEXT DOSE',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                      color: roles.textOnTint,
                    ),
                  ),
                ],
              ),
              Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: brand.surface,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  Fmt.time(view.at),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: brand.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: brand.surface,
                  borderRadius: BorderRadius.circular(18),
                ),
                alignment: Alignment.center,
                child: AppIcon(
                  AppIcons.medicineForm(view.medicine.form),
                  size: 26,
                  color: roles.graphicOnTint,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      view.medicine.name,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                        height: 1.1,
                        color: brand.ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitleParts.join(' · '),
                      style: TextStyle(fontSize: 14, color: context.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (showExpiryWarning) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: brand.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: expiryRoles.graphicOnTint.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                children: [
                  AppIcon(
                    AppIcons.warning,
                    size: 16,
                    color: expiryRoles.graphicOnTint,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      expiry.detailLabel(now: now) ??
                          expiry.shortBadgeLabel(now: now) ??
                          '',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: expiryRoles.textOnTint,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: BrandTappable(
                  onPressed: () {
                    AppHaptics.success();
                    repo.setDoseStatus(view.dose.id, DoseStatus.taken);
                  },
                  semanticsLabel: 'Mark as taken',
                  child: Container(
                    height: 52,
                    decoration: ShapeDecoration(
                      color: brand.ink,
                      shape: const StadiumBorder(),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AppIcon(AppIcons.check, size: 18, color: brand.onInk),
                        const SizedBox(width: 8),
                        Text(
                          'Mark as taken',
                          style: TextStyle(
                            color: brand.onInk,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              BrandTappable(
                onPressed: () {
                  AppHaptics.selection();
                  brandToast(context, 'Snoozed ${view.medicine.name}');
                },
                semanticsLabel: 'Snooze',
                child: Container(
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  alignment: Alignment.center,
                  decoration: ShapeDecoration(
                    color: brand.surface,
                    shape: const StadiumBorder(),
                  ),
                  child: Text(
                    'Snooze',
                    style: TextStyle(
                      color: brand.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              BrandTooltip(
                message: 'Skip this dose',
                child: BrandTappable(
                  onPressed: () {
                    AppHaptics.selection();
                    repo.setDoseStatus(view.dose.id, DoseStatus.skipped);
                  },
                  semanticsLabel: 'Skip this dose',
                  child: Container(
                    width: 52,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: brand.surface,
                      shape: BoxShape.circle,
                    ),
                    child: AppIcon(AppIcons.close, size: 18, color: brand.ink),
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

class _TodayTimelineRow extends ConsumerWidget {
  final DoseView view;
  final bool isDueNow;

  const _TodayTimelineRow({required this.view, required this.isDueNow});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final repo = ref.read(medicineRepositoryProvider);
    final taken = view.status == DoseStatus.taken;
    final skipped = view.status == DoseStatus.skipped;
    final missed =
        !taken &&
        !skipped &&
        !isDueNow &&
        view.at.isBefore(DateTime.now().subtract(const Duration(hours: 1)));
    final expiry = AfterOpeningStatus.ofMedicine(view.medicine);
    final showExpiryPill = !taken && !skipped && expiry.needsAttention();
    final expiryRoles = expiry.isExpired()
        ? brand.dangerRoles
        : brand.warningRoles;

    final String statusText;
    if (taken) {
      final atLabel = view.dose.actionedAt != null
          ? 'Taken at ${Fmt.time(view.dose.actionedAt!)}'
          : 'Taken';
      statusText = [
        atLabel,
        if (view.mealLabel.isNotEmpty) view.mealLabel.toLowerCase(),
      ].join(' · ');
    } else if (skipped) {
      statusText = 'Skipped';
    } else if (isDueNow) {
      statusText = [
        'Due now',
        if (view.mealLabel.isNotEmpty) view.mealLabel.toLowerCase(),
      ].join(' · ');
    } else if (missed) {
      statusText = 'Missed · ${view.dosageLabel}';
    } else {
      statusText = [
        view.dosageLabel,
        if (view.mealLabel.isNotEmpty) view.mealLabel.toLowerCase(),
      ].join(' · ');
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 72,
            padding: const EdgeInsets.symmetric(vertical: 4),
            color: brand.canvas,
            alignment: Alignment.center,
            child: Text(
              Fmt.time(view.at),
              style: TextStyle(
                fontSize: 12,
                fontWeight: isDueNow ? FontWeight.w800 : FontWeight.w700,
                color: isDueNow
                    ? brand.medicineRoles.textOnTint
                    : context.muted,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: BrandTappable(
              onPressed: () {
                AppHaptics.selection();
                repo.setDoseStatus(
                  view.dose.id,
                  taken ? DoseStatus.pending : DoseStatus.taken,
                );
              },
              onLongPress: () =>
                  repo.setDoseStatus(view.dose.id, DoseStatus.skipped),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: brand.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: isDueNow
                      ? Border.all(color: brand.medicine, width: 2)
                      : null,
                  boxShadow: AppShadows.card(theme.brightness),
                ),
                child: Row(
                  children: [
                    _DoseStatusCircle(
                      taken: taken,
                      skipped: skipped,
                      isDueNow: isDueNow,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            view.medicine.name,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: isDueNow
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              color: (taken || skipped)
                                  ? context.muted
                                  : brand.ink,
                              decoration: skipped
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            statusText,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isDueNow
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: isDueNow
                                  ? brand.medicineRoles.textOnTint
                                  : missed
                                  ? brand.dangerRoles.textOnTint
                                  : context.muted,
                            ),
                          ),
                          if (showExpiryPill) ...[
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: ShapeDecoration(
                                color: expiryRoles.tintFill,
                                shape: const StadiumBorder(),
                              ),
                              child: Text(
                                expiry.shortBadgeLabel() ?? '',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: expiryRoles.textOnTint,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DoseStatusCircle extends StatelessWidget {
  final bool taken;
  final bool skipped;
  final bool isDueNow;
  final double size;

  const _DoseStatusCircle({
    required this.taken,
    required this.skipped,
    required this.isDueNow,
    this.size = 32,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    if (taken) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: brand.success, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: AppIcon(AppIcons.check, size: size * 0.5, color: Colors.white),
      );
    }
    if (skipped) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: brand.well, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: AppIcon(AppIcons.close, size: size * 0.45, color: context.muted),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isDueNow ? brand.medicine : brand.outlineIdle,
          width: 2.5,
        ),
      ),
    );
  }
}

class _CoursesGrid extends StatelessWidget {
  final List<Medicine> medicines;

  const _CoursesGrid({required this.medicines});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < medicines.length; i += 2) {
      final first = medicines[i];
      final second = i + 1 < medicines.length ? medicines[i + 1] : null;
      rows.add(
        Padding(
          padding: EdgeInsets.only(bottom: i + 2 < medicines.length ? 10 : 0),
          child: Row(
            children: [
              Expanded(child: _CourseCompactCard(medicine: first)),
              const SizedBox(width: 10),
              Expanded(
                child: second != null
                    ? _CourseCompactCard(medicine: second)
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}

class _CourseCompactCard extends StatelessWidget {
  final Medicine medicine;

  const _CourseCompactCard({required this.medicine});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final course = _courseProgress(medicine);
    final low = medicine.inventory <= medicine.lowStockThreshold;
    final expiry = AfterOpeningStatus.ofMedicine(medicine);
    final expiryAlert = expiry.needsAttention();
    final barColor = expiry.isExpired()
        ? brand.dangerRoles.graphicOnTint
        : (expiryAlert || low)
        ? brand.warningRoles.graphicOnTint
        : brand.medicine;
    final footerText = expiryAlert
        ? (expiry.shortBadgeLabel() ?? '')
        : low
        ? '${medicine.inventory} ${DoseView.formatUnit(medicine.inventory, medicine.dosageUnit)} left'
        : 'Day ${course.currentDay} of ${course.totalDays}';
    final footerColor = expiry.isExpired()
        ? brand.dangerRoles.textOnTint
        : (expiryAlert || low)
        ? brand.warningRoles.textOnTint
        : context.muted;

    return BrandTappable(
      onPressed: () => MedicineEditorSheet.show(context, medicine: medicine),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: brand.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: AppShadows.card(theme.brightness),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              medicine.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: brand.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${_frequencySummary(medicine)} · ${course.totalDays} days',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: context.muted),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 5,
                child: LinearProgressIndicator(
                  value: course.progress,
                  backgroundColor: brand.track,
                  valueColor: AlwaysStoppedAnimation<Color>(barColor),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              footerText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: (expiryAlert || low)
                    ? FontWeight.w700
                    : FontWeight.w600,
                color: footerColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertBanner extends StatelessWidget {
  final HugeIconData icon;
  final String title;
  final String body;

  const _AlertBanner({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final roles = context.brand.warningRoles;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: roles.tintFill,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIcon(icon, size: 18, color: roles.graphicOnTint),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: roles.textOnTint,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: TextStyle(fontSize: 12, color: roles.textOnTint),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One dose row with taken / skip / snooze actions.
class DoseTile extends ConsumerWidget {
  final DoseView view;
  final bool showDate;

  const DoseTile({super.key, required this.view, this.showDate = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(medicineRepositoryProvider);
    final muted = Theme.of(context).colorScheme.outline;
    final brand = context.brand;
    final taken = view.status == DoseStatus.taken;
    final skipped = view.status == DoseStatus.skipped;
    final missed =
        !taken &&
        !skipped &&
        view.at.isBefore(DateTime.now().subtract(const Duration(hours: 1)));
    final expiry = AfterOpeningStatus.ofMedicine(view.medicine);
    final showExpiry = !taken && !skipped && expiry.needsAttention();
    final expiryLabel = showExpiry ? expiry.shortBadgeLabel() : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TintCard(
        fill: brand.surface,
        padding: EdgeInsets.zero,
        child: BrandTile(
          onLongPress: () =>
              repo.setDoseStatus(view.dose.id, DoseStatus.skipped),
          leading: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: brand.medicineRoles.tintFill,
              borderRadius: BorderRadius.circular(14),
            ),
            child: AppIcon(
              AppIcons.medicineForm(view.medicine.form),
              color: brand.medicineRoles.graphicOnTint,
              size: 20,
            ),
          ),
          title: Text(
            view.medicine.name,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              decoration: skipped ? TextDecoration.lineThrough : null,
              color: skipped ? muted : null,
            ),
          ),
          subtitle: Text(
            [
              view.dosageLabel,
              if (view.mealLabel.isNotEmpty) view.mealLabel,
              if (showDate) Fmt.dayMonth(view.at),
              if (missed) 'Missed',
              ?expiryLabel,
            ].join(' · '),
            style: TextStyle(
              fontSize: 11,
              fontWeight: showExpiry ? FontWeight.w700 : null,
              color: (missed || (showExpiry && expiry.isExpired()))
                  ? brand.dangerRoles.textOnTint
                  : showExpiry
                  ? brand.warningRoles.textOnTint
                  : muted,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                Fmt.time(view.at),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 6),
              CircleIconButton(
                icon: taken ? AppIcons.checkCircle : AppIcons.circle,
                tooltip: taken ? 'Mark not taken' : 'Mark taken',
                color: taken ? brand.success : muted,
                size: 40,
                onPressed: () => repo.setDoseStatus(
                  view.dose.id,
                  taken ? DoseStatus.pending : DoseStatus.taken,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Calendar (26-medicine-calendar.html) -----------------------------------

final _selectedDayProvider = StateProvider<DateTime>(
  (ref) => Fmt.dateOnly(DateTime.now()),
);

class _CalendarTab extends ConsumerWidget {
  const _CalendarTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final month = ref.watch(scheduleMonthProvider);
    final byDay = ref.watch(monthDosesByDayProvider);
    final selected = ref.watch(_selectedDayProvider);
    final adherence = ref.watch(adherenceProvider).valueOrNull;
    final repo = ref.read(medicineRepositoryProvider);

    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leading = DateTime(month.year, month.month, 1).weekday - 1;
    final selectedDoses = byDay[selected] ?? const <DoseView>[];
    final selectedTaken = selectedDoses
        .where((d) => d.status == DoseStatus.taken)
        .length;

    return ListView(
      padding: pageInsets(context, top: 12),
      children: [
        Container(
          decoration: BoxDecoration(
            color: brand.surface,
            borderRadius: BorderRadius.circular(24),
            boxShadow: AppShadows.card(theme.brightness),
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          Fmt.monthYear(month),
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                            color: brand.ink,
                          ),
                        ),
                        if (adherence != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            '${Fmt.percent(adherence.monthly)} on time this month',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: brand.successRoles.textOnTint,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  BrandTappable(
                    onPressed: () =>
                        ref.read(scheduleMonthProvider.notifier).state =
                            DateTime(month.year, month.month - 1),
                    semanticsLabel: 'Previous month',
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: brand.canvas,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: AppIcon(
                        AppIcons.chevronLeft,
                        size: 16,
                        color: brand.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  BrandTappable(
                    onPressed: () =>
                        ref.read(scheduleMonthProvider.notifier).state =
                            DateTime(month.year, month.month + 1),
                    semanticsLabel: 'Next month',
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: brand.canvas,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: AppIcon(
                        AppIcons.chevronRight,
                        size: 16,
                        color: brand.ink,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: ['M', 'T', 'W', 'T', 'F', 'S', 'S']
                    .map(
                      (d) => Expanded(
                        child: Center(
                          child: Text(
                            d,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: context.muted,
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 8),
              GridView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisSpacing: 5,
                  childAspectRatio: 1.0,
                ),
                itemCount: leading + daysInMonth,
                itemBuilder: (_, i) {
                  if (i < leading) return const SizedBox.shrink();
                  final day = DateTime(
                    month.year,
                    month.month,
                    i - leading + 1,
                  );
                  final doses = byDay[day] ?? const <DoseView>[];
                  final isSel = Fmt.isSameDay(day, selected);
                  final isToday = Fmt.isSameDay(day, DateTime.now());

                  final taken = doses
                      .where((d) => d.status == DoseStatus.taken)
                      .length;
                  final allTaken = doses.isNotEmpty && taken == doses.length;
                  final partlyTaken = taken > 0 && taken < doses.length;
                  final anyMissed =
                      taken == 0 &&
                      doses.any(
                        (d) =>
                            d.status == DoseStatus.pending &&
                            d.at.isBefore(DateTime.now()),
                      );

                  Color bg = Colors.transparent;
                  Color fg = context.muted;
                  Border? border;
                  if (allTaken) {
                    bg = brand.success;
                    fg = Colors.white;
                  } else if (partlyTaken) {
                    bg = brand.surface;
                    fg = brand.ink;
                    border = Border.all(
                      color: brand.warningRoles.graphicOnTint,
                      width: 2.5,
                    );
                  } else if (anyMissed) {
                    bg = brand.dangerRoles.tintFill;
                    fg = brand.dangerRoles.textOnTint;
                  } else if (isToday || isSel) {
                    fg = brand.ink;
                  }

                  return Center(
                    child: GestureDetector(
                      onTap: () {
                        AppHaptics.selection();
                        ref.read(_selectedDayProvider.notifier).state = day;
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: bg,
                          shape: BoxShape.circle,
                          border:
                              border ??
                              (isSel || isToday
                                  ? Border.all(color: brand.ink, width: 2)
                                  : null),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Text(
                              '${day.day}',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight:
                                    (allTaken ||
                                        partlyTaken ||
                                        anyMissed ||
                                        isToday ||
                                        isSel)
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                                color: fg,
                              ),
                            ),
                            if (anyMissed)
                              Positioned(
                                bottom: 4,
                                child: Container(
                                  width: 5,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: brand.dangerRoles.textOnTint,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _LegendItem(
                    dot: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: brand.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                    label: 'All taken',
                  ),
                  const SizedBox(width: 14),
                  _LegendItem(
                    dot: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: brand.warningRoles.graphicOnTint,
                          width: 2,
                        ),
                      ),
                    ),
                    label: 'Partly',
                  ),
                  const SizedBox(width: 14),
                  _LegendItem(
                    dot: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: brand.dangerRoles.textOnTint,
                        shape: BoxShape.circle,
                      ),
                    ),
                    label: 'Missed',
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${Fmt.weekday(selected)} ${selected.day} · ${Fmt.relativeDay(selected)}',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                ),
              ),
              if (selectedDoses.isNotEmpty)
                Text(
                  '$selectedTaken of ${selectedDoses.length} taken',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.muted,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (selectedDoses.isEmpty)
          EmptyState(
            icon: AppIcons.calendarDone,
            title: 'No doses on ${Fmt.relativeDay(selected)}',
          )
        else
          Container(
            decoration: BoxDecoration(
              color: brand.surface,
              borderRadius: BorderRadius.circular(22),
              boxShadow: AppShadows.card(theme.brightness),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            child: Column(
              children: [
                for (final (i, v) in selectedDoses.indexed)
                  BrandTappable(
                    onPressed: () => repo.setDoseStatus(
                      v.dose.id,
                      v.status == DoseStatus.taken
                          ? DoseStatus.pending
                          : DoseStatus.taken,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      decoration: BoxDecoration(
                        border: i < selectedDoses.length - 1
                            ? Border(bottom: BorderSide(color: brand.hairline))
                            : null,
                      ),
                      child: Row(
                        children: [
                          _DoseStatusCircle(
                            taken: v.status == DoseStatus.taken,
                            skipped: v.status == DoseStatus.skipped,
                            isDueNow: false,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              v.medicine.name,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: v.status == DoseStatus.taken
                                    ? context.muted
                                    : brand.ink,
                              ),
                            ),
                          ),
                          Text(
                            Fmt.time(v.at),
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
              ],
            ),
          ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Widget dot;
  final String label;

  const _LegendItem({required this.dot, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dot,
        const SizedBox(width: 5),
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

class _MonthSwitcher extends ConsumerWidget {
  final DateTime month;
  const _MonthSwitcher({required this.month});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.gutter,
        vertical: 6,
      ),
      child: Row(
        children: [
          CircleIconButton(
            icon: AppIcons.chevronLeft,
            size: 40,
            onPressed: () => ref.read(scheduleMonthProvider.notifier).state =
                DateTime(month.year, month.month - 1),
          ),
          Expanded(
            child: Text(
              Fmt.monthYear(month),
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
          ),
          CircleIconButton(
            icon: AppIcons.chevronRight,
            size: 40,
            onPressed: () => ref.read(scheduleMonthProvider.notifier).state =
                DateTime(month.year, month.month + 1),
          ),
        ],
      ),
    );
  }
}

// --- Timeline ---------------------------------------------------------------

class _TimelineTab extends ConsumerWidget {
  const _TimelineTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(scheduleMonthProvider);
    final byDay = ref.watch(monthDosesByDayProvider);
    final days = byDay.keys.toList()..sort();

    return Column(
      children: [
        _MonthSwitcher(month: month),
        Expanded(
          child: days.isEmpty
              ? const EmptyState(
                  icon: AppIcons.timeline,
                  title: 'Nothing scheduled this month',
                )
              : ListView.builder(
                  padding: pageInsets(context, top: 0),
                  itemCount: days.length,
                  itemBuilder: (_, i) {
                    final day = days[i];
                    final doses = byDay[day]!;
                    final taken = doses
                        .where((d) => d.status == DoseStatus.taken)
                        .length;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              Text(
                                Fmt.relativeDay(day),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '$taken/${doses.length} taken',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ...doses.map((v) => DoseTile(view: v)),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// --- Table (rows = dates, columns = time slots) -----------------------------

class _TableTab extends ConsumerWidget {
  const _TableTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(scheduleMonthProvider);
    final byDay = ref.watch(monthDosesByDayProvider);
    final repo = ref.read(medicineRepositoryProvider);
    final muted = Theme.of(context).colorScheme.outline;

    final days = byDay.keys.toList()..sort();
    final slots = <int>{
      for (final list in byDay.values)
        for (final v in list) v.at.hour * 60 + v.at.minute,
    }.toList()..sort();

    if (days.isEmpty) {
      return Column(
        children: [
          _MonthSwitcher(month: month),
          const Expanded(
            child: EmptyState(
              icon: AppIcons.spreadsheet,
              title: 'Nothing scheduled this month',
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        _MonthSwitcher(month: month),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              padding: pageInsets(context, top: 0),
              child: DataTable(
                headingRowHeight: 40,
                dataRowMinHeight: 40,
                dataRowMaxHeight: 52,
                columnSpacing: 18,
                columns: [
                  const DataColumn(
                    label: Text(
                      'Date',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  ...slots.map(
                    (s) => DataColumn(
                      label: Text(
                        Fmt.minutesOfDay(s),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
                rows: days.map((day) {
                  final doses = byDay[day]!;
                  return DataRow(
                    cells: [
                      DataCell(
                        Text(
                          Fmt.dayMonth(day),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      ...slots.map((slot) {
                        final atSlot = doses
                            .where((v) => v.at.hour * 60 + v.at.minute == slot)
                            .toList();
                        if (atSlot.isEmpty) {
                          return DataCell(
                            Text(
                              '—',
                              style: TextStyle(color: muted, fontSize: 12),
                            ),
                          );
                        }
                        return DataCell(
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: atSlot.map((v) {
                              final taken = v.status == DoseStatus.taken;
                              final skipped = v.status == DoseStatus.skipped;
                              return BrandTappable(
                                onPressed: () => repo.setDoseStatus(
                                  v.dose.id,
                                  taken ? DoseStatus.pending : DoseStatus.taken,
                                ),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        (taken
                                                ? context.brand.success
                                                : skipped
                                                ? muted
                                                : context.brand.medicine)
                                            .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      AppIcon(
                                        taken
                                            ? AppIcons.check
                                            : skipped
                                            ? AppIcons.close
                                            : AppIcons.circle,
                                        size: 11,
                                        color: taken
                                            ? context.brand.success
                                            : skipped
                                            ? muted
                                            : context.brand.medicine,
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        v.medicine.name.length > 10
                                            ? '${v.medicine.name.substring(0, 9)}…'
                                            : v.medicine.name,
                                        style: const TextStyle(fontSize: 10),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        );
                      }),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// --- Per-medicine (27-medicine-list.html) -----------------------------------

class _MedicinesTab extends ConsumerWidget {
  final VoidCallback onLogSymptom;
  final VoidCallback onShareSchedule;

  const _MedicinesTab({
    required this.onLogSymptom,
    required this.onShareSchedule,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final meds = ref.watch(medicinesProvider);
    final profiles = ref.watch(profilesProvider).valueOrNull ?? const [];
    final activeProfileId = ref.watch(activeProfileProvider);
    final forecasts = ref.watch(runOutForecastProvider);
    final repo = ref.read(medicineRepositoryProvider);

    return meds.when(
      loading: () => const Center(child: BrandSpinner()),
      error: (e, _) => Center(child: Text('$e')),
      data: (list) => ListView(
        padding: pageInsets(context, top: 12),
        children: [
          // Profile selector strip (27-medicine-list.html)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Pill(
                  label: 'Everyone',
                  selected: activeProfileId == null,
                  color: brand.medicine,
                  onTap: () =>
                      ref.read(activeProfileProvider.notifier).state = null,
                ),
                const SizedBox(width: 8),
                for (final p in profiles) ...[
                  BrandTappable(
                    onPressed: () =>
                        ref.read(activeProfileProvider.notifier).state = p.id,
                    child: Container(
                      height: 44,
                      padding: const EdgeInsets.fromLTRB(6, 0, 14, 0),
                      decoration: ShapeDecoration(
                        color: activeProfileId == p.id
                            ? brand.ink
                            : brand.surface,
                        shape: const StadiumBorder(),
                        shadows: activeProfileId == p.id
                            ? const []
                            : AppShadows.circleButton(theme.brightness),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: activeProfileId == p.id
                                  ? Colors.white.withValues(alpha: 0.16)
                                  : personColor(context, p.color),
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              Fmt.initials(p.name).isEmpty
                                  ? '?'
                                  : Fmt.initials(p.name),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: activeProfileId == p.id
                                    ? brand.onInk
                                    : brand.onAccent(
                                        personColor(context, p.color),
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            p.name,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: activeProfileId == p.id
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              color: activeProfileId == p.id
                                  ? brand.onInk
                                  : brand.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                BrandTooltip(
                  message: 'Add profile',
                  child: BrandTappable(
                    onPressed: () =>
                        _ProfileDrawer.showAddProfileDialog(context, ref),
                    semanticsLabel: 'Add profile',
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: brand.outlineIdle,
                          width: 1.5,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: AppIcon(
                        AppIcons.add,
                        size: 16,
                        color: context.muted,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          if (list.isEmpty)
            EmptyState(
              icon: AppIcons.medicine,
              title: 'No medicines yet',
              message: 'Add one to generate its full course automatically.',
              actionLabel: 'Add medicine',
              onAction: () => MedicineEditorSheet.show(context),
            )
          else
            for (final m in list) ...[
              _MedicineCourseCard(
                medicine: m,
                profileName: profiles
                    .where((p) => p.id == m.profileId)
                    .firstOrNull
                    ?.name,
                runOutDate: forecasts
                    .where((f) => f.medicine.id == m.id)
                    .firstOrNull
                    ?.date,
                onEdit: () => MedicineEditorSheet.show(context, medicine: m),
                onRefill: () => _refill(context, ref, m),
                onMarkOpened: supportsAfterOpening(m.form)
                    ? () => _markNewBottleOpened(context, ref, m)
                    : null,
                onDelete: () async {
                  await ref
                      .read(notificationServiceProvider)
                      .cancelMedicineExpiryAlerts(m.id);
                  await repo.deleteMedicine(m.id);
                },
              ),
              const SizedBox(height: 12),
            ],

          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: BrandTappable(
                  onPressed: onLogSymptom,
                  child: Container(
                    height: 52,
                    decoration: BoxDecoration(
                      color: brand.surface,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: AppShadows.card(theme.brightness),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AppIcon(AppIcons.symptom, size: 18, color: brand.ink),
                        const SizedBox(width: 8),
                        Text(
                          'Log a symptom',
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
              const SizedBox(width: 10),
              Expanded(
                child: BrandTappable(
                  onPressed: onShareSchedule,
                  child: Container(
                    height: 52,
                    decoration: BoxDecoration(
                      color: brand.surface,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: AppShadows.card(theme.brightness),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AppIcon(AppIcons.share, size: 18, color: brand.ink),
                        const SizedBox(width: 8),
                        Text(
                          'Share schedule',
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
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _markNewBottleOpened(
    BuildContext context,
    WidgetRef ref,
    Medicine m,
  ) async {
    AppHaptics.success();
    final repo = ref.read(medicineRepositoryProvider);
    final updated = await repo.markBottleOpened(m.id);
    if (updated != null) {
      try {
        await syncMedicineExpiryAlerts(
          notifier: ref.read(notificationServiceProvider),
          medicine: updated,
        );
      } on Exception catch (e) {
        debugPrint('Could not reschedule expiry alerts: $e');
      }
      if (context.mounted) {
        final useBy = AfterOpeningStatus.ofMedicine(updated).useByDate;
        brandToast(
          context,
          useBy != null
              ? 'Marked ${m.name} opened today · use by ${Fmt.dayMonth(useBy)}'
              : 'Marked ${m.name} opened today',
        );
      }
    }
  }

  Future<void> _refill(BuildContext context, WidgetRef ref, Medicine m) async {
    final controller = TextEditingController(text: '30');
    final canOpenNewBottle = supportsAfterOpening(m.form);
    var openedNewBottle =
        canOpenNewBottle && AfterOpeningStatus.ofMedicine(m).needsAttention();
    final result = await brandDialog<({String text, bool openedNewBottle})>(
      context,
      title: 'Add stock — ${m.name}',
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BrandField(
              controller: controller,
              label: 'Units to add',
              autofocus: true,
              keyboardType: TextInputType.number,
              suffix: Text(m.dosageUnit),
            ),
            if (canOpenNewBottle) ...[
              const SizedBox(height: 12),
              BrandSwitchTile(
                title: 'Opened new bottle',
                subtitle: m.bestUseWithinDays != null
                    ? 'Resets ${m.bestUseWithinDays}d countdown to today'
                    : 'Sets opened date to today',
                value: openedNewBottle,
                onChanged: (v) => setDialogState(() => openedNewBottle = v),
              ),
            ],
            const SizedBox(height: 20),
            BrandButton(
              label: 'Add',
              onPressed: () => Navigator.pop(dialogContext, (
                text: controller.text,
                openedNewBottle: openedNewBottle,
              )),
            ),
            const SizedBox(height: 8),
            BrandButton(
              label: 'Cancel',
              kind: BrandButtonKind.ghost,
              onPressed: () => Navigator.pop(dialogContext),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    final repo = ref.read(medicineRepositoryProvider);
    final delta = int.tryParse(result.text.trim());
    if (delta != null && delta > 0) {
      await repo.adjustInventory(m.id, delta);
    }
    if (result.openedNewBottle && context.mounted) {
      await _markNewBottleOpened(context, ref, m);
    }
  }
}

class _MedicineCourseCard extends StatelessWidget {
  final Medicine medicine;
  final String? profileName;
  final DateTime? runOutDate;
  final VoidCallback onEdit;
  final VoidCallback onRefill;
  final VoidCallback? onMarkOpened;
  final VoidCallback onDelete;

  const _MedicineCourseCard({
    required this.medicine,
    required this.profileName,
    required this.runOutDate,
    required this.onEdit,
    required this.onRefill,
    required this.onMarkOpened,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final low =
        medicine.inventory <= medicine.lowStockThreshold || runOutDate != null;
    final expiry = AfterOpeningStatus.ofMedicine(medicine);
    final expiryState = expiry.state();
    final iconRoles = expiry.isExpired()
        ? brand.dangerRoles
        : (expiry.isWarning() || low)
        ? brand.warningRoles
        : brand.medicineRoles;
    final course = _courseProgress(medicine);
    final times = ScheduleSpec.parseTimes(medicine.doseTimes);
    final meal = MealRelationX.fromToken(medicine.mealRelation).label;
    final formLabel = medicine.form.isEmpty
        ? 'Tablet'
        : '${medicine.form[0].toUpperCase()}${medicine.form.substring(1)}';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppShadows.card(theme.brightness),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: iconRoles.tintFill,
                  borderRadius: BorderRadius.circular(18),
                ),
                alignment: Alignment.center,
                child: AppIcon(
                  AppIcons.medicineForm(medicine.form),
                  size: 26,
                  color: iconRoles.graphicOnTint,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      medicine.name,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                        color: brand.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        formLabel,
                        _frequencySummary(medicine),
                        if (meal.isNotEmpty) meal.toLowerCase(),
                      ].join(' · '),
                      style: TextStyle(fontSize: 13, color: context.muted),
                    ),
                  ],
                ),
              ),
              BrandTooltip(
                message: 'Edit ${medicine.name}',
                child: BrandTappable(
                  onPressed: onEdit,
                  semanticsLabel: 'Edit ${medicine.name}',
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: brand.canvas,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: AppIcon(AppIcons.edit, size: 18, color: brand.ink),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              BrandMenuButton<String>(
                items: {
                  'refill': 'Add stock',
                  if (onMarkOpened != null)
                    'opened': medicine.openedDate == null
                        ? 'Mark opened today'
                        : 'Opened new bottle',
                  'delete': 'Delete',
                },
                onSelected: (value) {
                  switch (value) {
                    case 'refill':
                      onRefill();
                    case 'opened':
                      onMarkOpened?.call();
                    case 'delete':
                      onDelete();
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final t in times.take(4))
                Container(
                  height: 30,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: brand.canvas,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        Fmt.minutesOfDay(t),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: brand.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              if (profileName != null && profileName!.trim().isNotEmpty)
                Container(
                  height: 30,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: brand.ink,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        profileName!,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: brand.onInk,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Day ${course.currentDay} of ${course.totalDays}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: brand.ink,
                ),
              ),
              Text(
                'Ends ${Fmt.dayMonth(medicine.endDate)}',
                style: TextStyle(fontSize: 13, color: context.muted),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 6,
              child: LinearProgressIndicator(
                value: course.progress,
                backgroundColor: brand.track,
                valueColor: AlwaysStoppedAnimation<Color>(
                  brand.medicineRoles.graphicOnTint,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (expiryState != AfterOpeningState.none) ...[
            _AfterOpeningCardBanner(status: expiry, onMarkOpened: onMarkOpened),
            const SizedBox(height: 10),
          ],
          if (low)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              decoration: BoxDecoration(
                color: brand.warningRoles.tintFill,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  AppIcon(
                    AppIcons.warning,
                    size: 18,
                    color: brand.warningRoles.graphicOnTint,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      runOutDate != null
                          ? '${medicine.inventory} left · runs out ${Fmt.relativeDay(runOutDate!)}'
                          : '${medicine.inventory} ${DoseView.formatUnit(medicine.inventory, medicine.dosageUnit)} left',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: brand.warningRoles.textOnTint,
                      ),
                    ),
                  ),
                  BrandTappable(
                    onPressed: onRefill,
                    child: Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: ShapeDecoration(
                        color: brand.ink,
                        shape: const StadiumBorder(),
                      ),
                      child: Text(
                        'Add stock',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: brand.onInk,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${medicine.inventory} ${DoseView.formatUnit(medicine.inventory, medicine.dosageUnit)} left · covers the course',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: brand.successRoles.textOnTint,
                    ),
                  ),
                ),
                BrandTappable(
                  onPressed: onRefill,
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: ShapeDecoration(
                      color: brand.canvas,
                      shape: const StadiumBorder(),
                    ),
                    child: Text(
                      'Add stock',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: brand.ink,
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

class _AfterOpeningCardBanner extends StatelessWidget {
  final AfterOpeningStatus status;
  final VoidCallback? onMarkOpened;

  const _AfterOpeningCardBanner({
    required this.status,
    required this.onMarkOpened,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final s = status.state();
    final isDanger = s == AfterOpeningState.expired;
    final isWarning =
        s == AfterOpeningState.expiresToday ||
        s == AfterOpeningState.expiringSoon;
    final isUnopened = s == AfterOpeningState.unopened;
    final roles = isDanger
        ? brand.dangerRoles
        : isWarning
        ? brand.warningRoles
        : null;

    final showAction =
        onMarkOpened != null && (isDanger || isWarning || isUnopened);
    final actionLabel = isUnopened ? 'Mark opened' : 'New bottle';

    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, showAction ? 8 : 12, 8),
      decoration: BoxDecoration(
        color: roles?.tintFill ?? brand.canvas,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          AppIcon(
            (isDanger || isWarning) ? AppIcons.warning : AppIcons.calendar,
            size: 18,
            color: roles?.graphicOnTint ?? context.muted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              status.detailLabel() ?? '',
              style: TextStyle(
                fontSize: 13,
                fontWeight: (isDanger || isWarning)
                    ? FontWeight.w700
                    : FontWeight.w600,
                color: roles?.textOnTint ?? brand.ink,
              ),
            ),
          ),
          if (showAction) ...[
            const SizedBox(width: 8),
            BrandTappable(
              onPressed: onMarkOpened,
              semanticsLabel: actionLabel,
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: ShapeDecoration(
                  color: brand.ink,
                  shape: const StadiumBorder(),
                ),
                child: Text(
                  actionLabel,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: brand.onInk,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// --- Profiles ---------------------------------------------------------------

class _ProfileDrawer extends ConsumerWidget {
  const _ProfileDrawer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(profilesProvider);
    final active = ref.watch(activeProfileProvider);
    final brand = context.brand;

    return Drawer(
      backgroundColor: brand.canvas,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Profiles',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                  ),
                ),
                CircleIconButton(
                  icon: AppIcons.close,
                  tooltip: 'Close',
                  size: 40,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            BrandTile(
              leading: const AppIcon(AppIcons.people, size: 20),
              title: const Text('Everyone'),
              selected: active == null,
              onTap: () {
                ref.read(activeProfileProvider.notifier).state = null;
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 12),
            profiles.maybeWhen(
              data: (list) => TileColumn(
                mainAxisSize: MainAxisSize.min,
                children: list
                    .map(
                      (p) => BrandTile(
                        leading: CircleAvatar(
                          radius: 14,
                          backgroundColor: personColor(context, p.color),
                          child: Text(
                            p.name.isEmpty ? '?' : p.name[0].toUpperCase(),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: brand.onAccent(
                                personColor(context, p.color),
                              ),
                            ),
                          ),
                        ),
                        title: Text(p.name),
                        subtitle: Text(
                          p.relation,
                          style: const TextStyle(fontSize: 11),
                        ),
                        selected: active == p.id,
                        onTap: () {
                          ref.read(activeProfileProvider.notifier).state = p.id;
                          Navigator.pop(context);
                        },
                        onLongPress: () async {
                          Navigator.pop(context);
                          await ref
                              .read(medicineRepositoryProvider)
                              .deleteProfile(p.id);
                        },
                      ),
                    )
                    .toList(),
              ),
              orElse: () => const SizedBox.shrink(),
            ),
            const SizedBox(height: 12),
            BrandTile(
              leading: const AppIcon(AppIcons.personAdd, size: 20),
              title: const Text('Add profile'),
              onTap: () async {
                await showAddProfileDialog(context, ref);
                if (context.mounted) Navigator.of(context).maybePop();
              },
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> showAddProfileDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final name = TextEditingController();
    final relation = TextEditingController(text: 'Family');
    var color = 0xFFFF6547;

    final saved = await brandDialog<bool>(
      context,
      title: 'New profile',
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BrandField(controller: name, label: 'Name', autofocus: true),
            const SizedBox(height: 12),
            BrandField(
              controller: relation,
              label: 'Relation',
              hint: 'Mum, son, partner',
            ),
            const SizedBox(height: 16),
            ColorPickerRow(
              selected: color,
              onChanged: (c) => setState(() => color = c),
            ),
            const SizedBox(height: 20),
            BrandButton(
              label: 'Create',
              onPressed: () => Navigator.pop(dialogContext, true),
            ),
            const SizedBox(height: 8),
            BrandButton(
              label: 'Cancel',
              kind: BrandButtonKind.ghost,
              onPressed: () => Navigator.pop(dialogContext, false),
            ),
          ],
        ),
      ),
    );

    if (saved == true && name.text.trim().isNotEmpty) {
      await ref
          .read(medicineRepositoryProvider)
          .createProfile(name.text.trim(), relation.text.trim(), color);
    }
  }
}

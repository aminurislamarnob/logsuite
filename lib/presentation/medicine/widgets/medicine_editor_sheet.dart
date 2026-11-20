import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/ai_drafts.dart';
import '../../../core/database/app_database.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/widgets/brand.dart';
import '../../../core/widgets/common.dart';
import '../camera_scan_screen.dart';
import '../providers/medicine_provider.dart';
import '../repository/medicine_repository.dart';
import '../utils/after_opening_expiry.dart';
import '../utils/dose_reminders.dart';
import '../utils/schedule_generator.dart';

/// Create/edit a medicine and preview the generated course before saving.
///
/// Pops with the saved medicine's id so a prefilled open (the assistant's
/// preview card) can tell a save from a dismissal.
class MedicineEditorSheet extends ConsumerStatefulWidget {
  final Medicine? medicine;

  /// Prefill for a new medicine; ignored when editing an existing one.
  final MedicineDraft? draft;

  const MedicineEditorSheet({super.key, this.medicine, this.draft});

  static Future<int?> show(
    BuildContext context, {
    Medicine? medicine,
    MedicineDraft? draft,
  }) {
    return brandSheet<int>(
      context: context,
      builder: (_) => MedicineEditorSheet(medicine: medicine, draft: draft),
    );
  }

  @override
  ConsumerState<MedicineEditorSheet> createState() =>
      _MedicineEditorSheetState();
}

class _MedicineEditorSheetState extends ConsumerState<MedicineEditorSheet> {
  late final TextEditingController _name;
  late final TextEditingController _dosage;
  late final TextEditingController _dosageUnit;
  late final TextEditingController _inventory;
  late final TextEditingController _doctor;
  late final TextEditingController _notes;
  late final TextEditingController _bestUseInput;

  String _form = 'tablet';
  MedFrequency _frequency = MedFrequency.timesPerDay;
  List<int> _times = [480]; // 08:00
  int _intervalHours = 8;
  int _weekdayMask = 127;
  MealRelation _meal = MealRelation.none;
  DateTime _start = Fmt.dateOnly(DateTime.now());
  DateTime _end = Fmt.dateOnly(DateTime.now()).add(const Duration(days: 6));
  Set<DateTime> _skip = {};
  int? _profileId;
  DateTime? _openedDate;
  bool _bestUseInMonths = false;
  int? _expiryAlertDaysBefore = defaultExpiryAlertDaysBefore;

  bool get _isEditing => widget.medicine != null;

  int? get _bestUseWithinDays {
    final raw = int.tryParse(_bestUseInput.text.trim());
    if (raw == null || raw <= 0) return null;
    return _bestUseInMonths ? raw * 30 : raw;
  }

  AfterOpeningStatus get _afterOpeningStatus => AfterOpeningStatus(
    form: _form,
    openedDate: _openedDate,
    bestUseWithinDays: _bestUseWithinDays,
    alertDaysBefore: _expiryAlertDaysBefore,
  );

  @override
  void initState() {
    super.initState();
    final m = widget.medicine;
    final d = m == null ? widget.draft : null;
    _name = TextEditingController(text: m?.name ?? d?.name ?? '');
    _dosage = TextEditingController(
      text: m != null
          ? _trim(m.dosage)
          : d != null
          ? _trim(d.dosage)
          : '1',
    );
    _dosageUnit = TextEditingController(
      text: m?.dosageUnit ?? d?.dosageUnit ?? 'tablet',
    );
    _inventory = TextEditingController(text: '${m?.inventory ?? 15}');
    _doctor = TextEditingController(text: m?.doctorName ?? '');
    _notes = TextEditingController(text: m?.notes ?? d?.notes ?? '');
    _bestUseInput = TextEditingController(
      text: m?.bestUseWithinDays != null ? '${m!.bestUseWithinDays}' : '',
    );

    if (d != null) {
      _form = d.form;
      _times = List.of(d.doseMinutes);
      _meal = d.meal;
      _start = d.start;
      _end = d.end;
      _profileId = d.profileId;
    }

    if (m != null) {
      _form = m.form;
      _frequency = MedFrequency
          .values[m.frequencyType.clamp(0, MedFrequency.values.length - 1)];
      _times = ScheduleSpec.parseTimes(m.doseTimes);
      _intervalHours = m.intervalHours;
      _weekdayMask = m.weekdayMask;
      _meal = MealRelationX.fromToken(m.mealRelation);
      _start = m.startDate;
      _end = m.endDate;
      _skip = ScheduleSpec.parseSkipDates(m.skipDates);
      _profileId = m.profileId;
      _openedDate = m.openedDate;
      if (m.openedDate != null || m.bestUseWithinDays != null) {
        _expiryAlertDaysBefore = m.expiryAlertDaysBefore;
      }
    }
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _dosage,
      _dosageUnit,
      _inventory,
      _doctor,
      _notes,
      _bestUseInput,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  ScheduleSpec get _spec => ScheduleSpec(
    start: _start,
    end: _end,
    frequency: _frequency,
    doseMinutes: _times,
    intervalHours: _intervalHours,
    weekdayMask: _weekdayMask,
    skipDates: _skip,
  );

  Future<void> _scanPrescription() async {
    final result = await Navigator.of(context).push<ScanResult>(
      MaterialPageRoute(
        builder: (_) => const CameraScanScreen(mode: ScanMode.prescription),
      ),
    );
    if (result == null || !mounted) return;

    setState(() {
      if (result.medicineName != null) _name.text = result.medicineName!;
      if (result.dosage != null) {
        final numeric = RegExp(r'[\d.]+').firstMatch(result.dosage!)?.group(0);
        final unit = RegExp(r'[a-zA-Z]+').firstMatch(result.dosage!)?.group(0);
        if (numeric != null) _dosage.text = numeric;
        if (unit != null) _dosageUnit.text = unit;
      }
      if (result.timesPerDay != null) {
        _frequency = MedFrequency.timesPerDay;
        _times = ScheduleSpec.defaultTimesFor(result.timesPerDay!);
      }
      if (result.durationDays != null) {
        _end = _start.add(Duration(days: result.durationDays! - 1));
      }
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      brandToast(context, 'Enter a medicine name.');
      return;
    }

    final repo = ref.read(medicineRepositoryProvider);
    final profiles = await repo.profiles();
    final profileId = _profileId ?? profiles.firstOrNull?.id;

    final tracksAfterOpening = supportsAfterOpening(_form);
    final openedDate = tracksAfterOpening ? _openedDate : null;
    final bestUseDays = tracksAfterOpening ? _bestUseWithinDays : null;
    final alertBefore =
        tracksAfterOpening && (openedDate != null || bestUseDays != null)
        ? _expiryAlertDaysBefore
        : null;

    final companion = MedicinesCompanion(
      name: drift.Value(name),
      form: drift.Value(_form),
      dosage: drift.Value(double.tryParse(_dosage.text.trim()) ?? 1),
      dosageUnit: drift.Value(
        _dosageUnit.text.trim().isEmpty ? 'tablet' : _dosageUnit.text.trim(),
      ),
      inventory: drift.Value(int.tryParse(_inventory.text.trim()) ?? 0),
      doctorName: drift.Value(
        _doctor.text.trim().isEmpty ? null : _doctor.text.trim(),
      ),
      notes: drift.Value(
        _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      ),
      profileId: drift.Value(profileId),
      frequencyType: drift.Value(_frequency.index),
      doseTimes: drift.Value(ScheduleSpec.encodeTimes(_times)),
      intervalHours: drift.Value(_intervalHours),
      weekdayMask: drift.Value(_weekdayMask),
      mealRelation: drift.Value(_meal.token),
      startDate: drift.Value(_start),
      endDate: drift.Value(_end),
      skipDates: drift.Value(ScheduleSpec.encodeSkipDates(_skip)),
      openedDate: drift.Value(openedDate),
      bestUseWithinDays: drift.Value(bestUseDays),
      expiryAlertDaysBefore: drift.Value(alertBefore),
    );

    int medicineId;
    if (_isEditing) {
      medicineId = widget.medicine!.id;
      await repo.updateMedicine(medicineId, companion);
      await repo.regenerateSchedule(medicineId, _spec);
    } else {
      medicineId = await repo.createMedicineWithSchedule(
        medicine: companion,
        spec: _spec,
      );
    }

    // The course is already saved at this point. Reminder scheduling depends on
    // OS permissions that can be denied or revoked, so a failure here must
    // never lose the user's medicine or trap them in the form.
    try {
      final notifier = ref.read(notificationServiceProvider);
      await scheduleDoseReminders(
        repo: repo,
        notifier: notifier,
        medicineId: medicineId,
        name: name,
        dosageLabel: '${_dosage.text.trim()} ${_dosageUnit.text.trim()}',
        mealHint: _meal.label,
      );
      final saved = await repo.getMedicine(medicineId);
      if (saved != null) {
        await syncMedicineExpiryAlerts(notifier: notifier, medicine: saved);
      }
    } on Exception catch (e) {
      debugPrint('Could not schedule dose reminders: $e');
      if (mounted) {
        brandToast(
          context,
          'Saved, but reminders could not be scheduled. '
          'Check notification permissions in Settings.',
        );
      }
    }

    if (mounted) Navigator.pop(context, medicineId);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final profiles = ref.watch(profilesProvider).valueOrNull ?? const [];
    final preview = ScheduleGenerator.generate(_spec);
    final inventory = int.tryParse(_inventory.text.trim()) ?? 0;
    final dosage = double.tryParse(_dosage.text.trim()) ?? 1;
    final runOut = ScheduleGenerator.runOutDate(_spec, inventory, dosage);
    final durationDays = (_end.difference(_start).inDays + 1).clamp(1, 9999);
    final selectedProfile = profiles
        .where((p) => p.id == (_profileId ?? profiles.firstOrNull?.id))
        .firstOrNull;

    return SheetScaffold(
      title: _isEditing ? 'Edit medicine' : 'Add medicine',
      actions: [
        BrandTappable(
          onPressed: _scanPrescription,
          semanticsLabel: 'Scan prescription',
          child: Container(
            height: 40,
            padding: const EdgeInsets.fromLTRB(12, 0, 14, 0),
            decoration: ShapeDecoration(
              color: brand.medicineRoles.tintFill,
              shape: const StadiumBorder(),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(
                  AppIcons.scan,
                  size: 16,
                  color: brand.medicineRoles.textOnTint,
                ),
                const SizedBox(width: 6),
                Text(
                  'Scan',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: brand.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
        CircleIconButton(
          icon: AppIcons.close,
          tooltip: 'Close',
          size: 40,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
      bottomAction: BrandTappable(
        onPressed: _save,
        semanticsLabel: 'Save medicine',
        child: Container(
          height: 58,
          padding: const EdgeInsets.fromLTRB(24, 0, 10, 0),
          decoration: ShapeDecoration(
            color: brand.ink,
            shape: const StadiumBorder(),
            shadows: AppShadows.hero(theme.brightness),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _isEditing ? 'Save changes' : 'Save medicine',
                style: TextStyle(
                  color: brand.onInk,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: ShapeDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  shape: const StadiumBorder(),
                ),
                child: Text(
                  '${preview.length} ${preview.length == 1 ? 'dose' : 'doses'}',
                  style: TextStyle(
                    color: brand.onInk,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _eyebrow(context, 'MEDICINE NAME'),
                    const SizedBox(height: 6),
                    BrandField(
                      controller: _name,
                      hint: 'Napa',
                      autofocus: !_isEditing,
                      textCapitalization: TextCapitalization.words,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _eyebrow(context, 'DOSE'),
                    const SizedBox(height: 6),
                    BrandField(
                      controller: _dosage,
                      hint: '1',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          _eyebrow(context, 'FORM'),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: AppIcons.medicineForms.keys.map((f) {
                final selected = _form == f;
                final label = '${f[0].toUpperCase()}${f.substring(1)}';
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: BrandTappable(
                    onPressed: () {
                      AppHaptics.selection();
                      setState(() {
                        _form = f;
                        _dosageUnit.text = DoseView.defaultUnitForForm(f);
                      });
                    },
                    semanticsLabel: label,
                    child: Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
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
                          fontSize: 13,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w600,
                          color: selected ? brand.onInk : brand.ink,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 14),

          // Dynamic after-opening shelf life card (syrup, drops, inhaler only)
          AnimatedSize(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: supportsAfterOpening(_form)
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _buildAfterOpeningCard(context),
                  )
                : const SizedBox.shrink(),
          ),

          // Schedule card (25-medicine-editor.html)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: brand.surface,
              borderRadius: BorderRadius.circular(22),
              boxShadow: AppShadows.card(theme.brightness),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_frequency == MedFrequency.timesPerDay) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Times a day',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: brand.ink,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Tap a time to change it',
                              style: TextStyle(
                                fontSize: 12,
                                color: context.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      BrandTappable(
                        onPressed: _times.length <= 1
                            ? null
                            : () {
                                AppHaptics.selection();
                                setState(() {
                                  _times = ScheduleSpec.defaultTimesFor(
                                    _times.length - 1,
                                  );
                                });
                              },
                        semanticsLabel: 'Fewer times a day',
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: brand.canvas,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '−',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: brand.ink,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 32,
                        child: Text(
                          '${_times.length}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            color: brand.ink,
                          ),
                        ),
                      ),
                      BrandTappable(
                        onPressed: () {
                          AppHaptics.selection();
                          if (_times.length < 4) {
                            setState(() {
                              _times = ScheduleSpec.defaultTimesFor(
                                _times.length + 1,
                              );
                            });
                          } else {
                            _addTime();
                          }
                        },
                        semanticsLabel: 'More times a day',
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: brand.ink,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: AppIcon(
                            AppIcons.add,
                            size: 18,
                            color: brand.onInk,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      for (final (i, m) in _times.indexed) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(
                          child: BrandTappable(
                            onPressed: () => _editTime(m),
                            child: Container(
                              height: 44,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: brand.medicineRoles.tintFill,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                Fmt.minutesOfDay(m),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: brand.ink,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ] else if (_frequency == MedFrequency.everyXHours) ...[
                  Row(
                    children: [
                      Text(
                        'Every $_intervalHours hours',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Expanded(
                        child: BrandSlider(
                          value: _intervalHours.toDouble(),
                          min: 1,
                          max: 24,
                          divisions: 23,
                          onChanged: (v) =>
                              setState(() => _intervalHours = v.round()),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  Row(
                    children: [
                      Text(
                        'Dose times',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: brand.ink,
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        icon: const AppIcon(AppIcons.add, size: 16),
                        label: const Text('Add time'),
                        onPressed: _addTime,
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _times
                        .map(
                          (m) => Pill(
                            icon: AppIcons.clock,
                            label: Fmt.minutesOfDay(m),
                            color: theme.colorScheme.primary,
                            onTap: () => _editTime(m),
                          ),
                        )
                        .toList(),
                  ),
                ],
                if (_frequency == MedFrequency.specificWeekdays) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: List.generate(7, (i) {
                      const labels = [
                        'Mon',
                        'Tue',
                        'Wed',
                        'Thu',
                        'Fri',
                        'Sat',
                        'Sun',
                      ];
                      final on = (_weekdayMask & (1 << i)) != 0;
                      return Pill(
                        label: labels[i],
                        selected: on,
                        color: theme.colorScheme.primary,
                        onTap: () {
                          final v = !on;
                          setState(() {
                            _weekdayMask = v
                                ? _weekdayMask | (1 << i)
                                : _weekdayMask & ~(1 << i);
                          });
                        },
                      );
                    }),
                  ),
                ],
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _freqChip(MedFrequency.timesPerDay, 'Times a day'),
                      const SizedBox(width: 6),
                      _freqChip(MedFrequency.everyXHours, 'Every X hours'),
                      const SizedBox(width: 6),
                      _freqChip(MedFrequency.specificWeekdays, 'Certain days'),
                      const SizedBox(width: 6),
                      _freqChip(MedFrequency.alternateDays, 'Alternate days'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // With food segmented bar (25-medicine-editor.html)
          _eyebrow(context, 'WITH FOOD'),
          const SizedBox(height: 8),
          Container(
            height: 44,
            padding: const EdgeInsets.all(4),
            decoration: ShapeDecoration(
              color: brand.well,
              shape: const StadiumBorder(),
            ),
            child: Row(
              children: [
                for (final m in [
                  MealRelation.before,
                  MealRelation.after,
                  MealRelation.with_,
                  MealRelation.none,
                ])
                  Expanded(
                    child: BrandTappable(
                      onPressed: () {
                        AppHaptics.selection();
                        setState(() => _meal = m);
                      },
                      child: Container(
                        alignment: Alignment.center,
                        decoration: ShapeDecoration(
                          color: _meal == m ? brand.ink : Colors.transparent,
                          shape: const StadiumBorder(),
                        ),
                        child: Text(
                          m == MealRelation.none ? 'Any time' : m.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: _meal == m
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: _meal == m ? brand.onInk : context.muted,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Duration & Profile 2-column cards (25-medicine-editor.html)
          Row(
            children: [
              Expanded(
                child: BrandTappable(
                  onPressed: _pickDurationOrDates,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: brand.surface,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: AppShadows.card(theme.brightness),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'DURATION',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: context.muted,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '$durationDays ${durationDays == 1 ? 'day' : 'days'}',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: brand.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Ends ${Fmt.dayMonth(_end)}',
                          style: TextStyle(fontSize: 12, color: context.muted),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: BrandTappable(
                  onPressed: profiles.isEmpty
                      ? null
                      : () {
                          AppHaptics.selection();
                          final currentIdx = profiles.indexWhere(
                            (p) => p.id == selectedProfile?.id,
                          );
                          final next =
                              profiles[(currentIdx + 1) % profiles.length];
                          setState(() => _profileId = next.id);
                        },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: brand.surface,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: AppShadows.card(theme.brightness),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PROFILE',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: context.muted,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          selectedProfile?.name ?? 'Me',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: brand.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Who takes it',
                          style: TextStyle(fontSize: 12, color: context.muted),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [3, 5, 7, 10, 14, 30]
                  .map(
                    (d) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Pill(
                        label: '$d days',
                        selected: durationDays == d,
                        color: theme.colorScheme.primary,
                        onTap: () => setState(
                          () => _end = _start.add(Duration(days: d - 1)),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 14),

          // In stock card (25-medicine-editor.html)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: brand.surface,
              borderRadius: BorderRadius.circular(18),
              boxShadow: AppShadows.card(theme.brightness),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'In stock · $inventory ${DoseView.formatUnit(inventory, _dosageUnit.text)}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: brand.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        runOut == null
                            ? 'Covers the course'
                            : 'Runs out ${Fmt.dayMonth(runOut)}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: runOut == null
                              ? brand.successRoles.textOnTint
                              : brand.warningRoles.textOnTint,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 92,
                  child: BrandField(
                    controller: _inventory,
                    hint: '15',
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Extra details accordion (unit, start date, skip dates, doctor, notes)
          Container(
            decoration: BoxDecoration(
              color: brand.surface,
              borderRadius: BorderRadius.circular(18),
              boxShadow: AppShadows.card(theme.brightness),
            ),
            child: BrandAccordion(
              title: 'More details (dates, doctor, notes)',
              leading: AppIcons.notes,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BrandField(
                    controller: _dosageUnit,
                    label: 'Unit',
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _dateField(
                          'Starts',
                          _start,
                          (d) => setState(() {
                            _start = d;
                            if (_end.isBefore(_start)) _end = _start;
                          }),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _dateField(
                          'Ends',
                          _end,
                          (d) => setState(() => _end = d),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  BrandTile(
                    leading: const AppIcon(AppIcons.travel),
                    title: const Text('Skip dates'),
                    subtitle: Text(
                      _skip.isEmpty
                          ? 'Travel or holiday — none set'
                          : '${_skip.length} date${_skip.length == 1 ? '' : 's'} skipped',
                    ),
                    trailing: const AppIcon(AppIcons.chevronRight),
                    onTap: _pickSkipDates,
                  ),
                  const SizedBox(height: 10),
                  BrandField(
                    controller: _doctor,
                    label: 'Doctor',
                    prefix: const AppIcon(AppIcons.person),
                  ),
                  const SizedBox(height: 10),
                  BrandField(
                    controller: _notes,
                    label: 'Notes',
                    maxLines: 2,
                    minLines: 1,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAfterOpeningCard(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final status = _afterOpeningStatus;
    final useBy = status.useByDate;
    final state = status.state();
    final periodDays = _bestUseWithinDays;
    final badgeText = useBy != null ? status.shortBadgeLabel() : null;

    final badgeRoles = switch (state) {
      AfterOpeningState.expired => brand.dangerRoles,
      AfterOpeningState.expiresToday ||
      AfterOpeningState.expiringSoon => brand.warningRoles,
      _ => brand.medicineRoles,
    };

    String? alertSummary;
    if (useBy != null) {
      if (_expiryAlertDaysBefore == null || _expiryAlertDaysBefore! <= 0) {
        alertSummary = 'Expiry notifications off · in-app warnings stay on';
      } else {
        final pre = status.preExpiryAlertAt;
        if (pre != null) {
          final adjusted = status.wasLeadClamped
              ? ' (adjusted for ${periodDays}d period)'
              : '';
          alertSummary =
              'Alerts ${Fmt.dayMonth(pre)} & ${Fmt.dayMonth(useBy)} at 9:00 AM$adjusted';
        } else {
          alertSummary = 'Alert on ${Fmt.dayMonth(useBy)} at 9:00 AM';
        }
      }
    } else if (_openedDate != null) {
      alertSummary = 'Set "Best use within" to calculate use-by date & alerts';
    } else if (periodDays != null) {
      alertSummary = 'Set opened date once opened to start the countdown';
    }

    final exceedsBottleLife = useBy != null && _end.isAfter(useBy);

    return Container(
      key: const ValueKey('after-opening-card'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: AppShadows.card(theme.brightness),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                Text(
                  'AFTER OPENING',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7,
                    color: context.muted,
                  ),
                ),
                if (badgeText != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: ShapeDecoration(
                      color: badgeRoles.tintFill,
                      shape: const StadiumBorder(),
                    ),
                    child: Text(
                      badgeText,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: badgeRoles.textOnTint,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Opened date selector + 1-tap Today / Clear action
          Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
            decoration: BoxDecoration(
              color: brand.canvas,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Expanded(
                  child: BrandTappable(
                    onPressed: _pickOpenedDate,
                    semanticsLabel: 'Opened date',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          AppIcon(
                            AppIcons.calendar,
                            size: 18,
                            color: _openedDate != null
                                ? brand.medicineRoles.graphicOnTint
                                : context.muted,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Opened date',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: context.muted,
                                  ),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  _openedDate == null
                                      ? 'Not opened yet'
                                      : Fmt.dayMonthYear(_openedDate!),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: _openedDate == null
                                        ? context.muted
                                        : brand.ink,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (_openedDate == null)
                  BrandTappable(
                    onPressed: () {
                      AppHaptics.selection();
                      setState(
                        () => _openedDate = Fmt.dateOnly(DateTime.now()),
                      );
                    },
                    semanticsLabel: 'Opened today',
                    child: Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: ShapeDecoration(
                        color: brand.ink,
                        shape: const StadiumBorder(),
                      ),
                      child: Text(
                        'Today',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: brand.onInk,
                        ),
                      ),
                    ),
                  )
                else
                  BrandTooltip(
                    message: 'Clear opened date',
                    child: BrandTappable(
                      onPressed: () {
                        AppHaptics.selection();
                        setState(() => _openedDate = null);
                      },
                      semanticsLabel: 'Clear opened date',
                      child: Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: brand.surface,
                          shape: BoxShape.circle,
                        ),
                        child: AppIcon(
                          AppIcons.close,
                          size: 16,
                          color: context.muted,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Best use within presets + custom input with Days / Months toggle
          Text(
            'Best use within',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: brand.ink,
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final days in afterOpeningPresets) ...[
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: BrandTappable(
                      onPressed: () {
                        AppHaptics.selection();
                        setState(() {
                          if (!_bestUseInMonths && periodDays == days) {
                            _bestUseInput.clear();
                          } else {
                            _bestUseInMonths = false;
                            _bestUseInput.text = '$days';
                          }
                        });
                      },
                      semanticsLabel: '$days days',
                      child: Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        alignment: Alignment.center,
                        decoration: ShapeDecoration(
                          color: periodDays == days ? brand.ink : brand.canvas,
                          shape: const StadiumBorder(),
                        ),
                        child: Text(
                          '${days}d',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: periodDays == days ? brand.onInk : brand.ink,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: brand.canvas,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: TextField(
                    controller: _bestUseInput,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: brand.ink,
                    ),
                    decoration: InputDecoration(
                      hintText: _bestUseInMonths ? 'e.g. 1' : 'e.g. 28',
                      hintStyle: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: context.muted,
                      ),
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              BrandSegmented<bool>(
                options: const {false: 'Days', true: 'Months'},
                selected: _bestUseInMonths,
                onSelected: (months) {
                  setState(() {
                    if (months == _bestUseInMonths) return;
                    final current = int.tryParse(_bestUseInput.text.trim());
                    _bestUseInMonths = months;
                    if (current != null && current > 0) {
                      _bestUseInput.text = months
                          ? '${(current / 30).round().clamp(1, 120)}'
                          : '${current * 30}';
                    }
                  });
                },
              ),
            ],
          ),

          if (_openedDate != null || periodDays != null) ...[
            const SizedBox(height: 12),
            Text(
              'Alert before expiry',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: brand.ink,
              ),
            ),
            const SizedBox(height: 8),
            BrandSegmented<int>(
              expand: true,
              options: const {1: '1d', 3: '3d', 7: '7d', 0: 'Off'},
              selected: _expiryAlertDaysBefore ?? 0,
              onSelected: (days) => setState(
                () => _expiryAlertDaysBefore = days == 0 ? null : days,
              ),
            ),
            if (alertSummary != null) ...[
              const SizedBox(height: 8),
              Text(
                alertSummary,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: context.muted,
                ),
              ),
            ],
          ],

          if (exceedsBottleLife) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: brand.warningRoles.tintFill,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  AppIcon(
                    AppIcons.warning,
                    size: 16,
                    color: brand.warningRoles.graphicOnTint,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Bottle expires ${Fmt.dayMonth(useBy)} — before course ends ${Fmt.dayMonth(_end)}',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: brand.warningRoles.textOnTint,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickOpenedDate() async {
    final today = Fmt.dateOnly(DateTime.now());
    final picked = await brandDatePicker(
      context,
      initial: _openedDate ?? today,
      first: today.subtract(const Duration(days: 1095)),
      last: today.add(const Duration(days: 365)),
      title: 'Bottle opened date',
    );
    if (picked != null) {
      setState(() => _openedDate = Fmt.dateOnly(picked));
    }
  }

  Widget _eyebrow(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: context.muted,
        ),
      ),
    );
  }

  Future<void> _pickDurationOrDates() async {
    final picked = await brandDatePicker(
      context,
      initial: _end,
      first: _start,
      last: _start.add(const Duration(days: 3650)),
      title: 'Course end date',
    );
    if (picked != null) {
      setState(() => _end = Fmt.dateOnly(picked));
    }
  }

  Widget _freqChip(MedFrequency f, String label) => Pill(
    label: label,
    selected: _frequency == f,
    color: Theme.of(context).colorScheme.primary,
    onTap: () => setState(() => _frequency = f),
  );

  Widget _dateField(
    String label,
    DateTime value,
    ValueChanged<DateTime> onSet,
  ) {
    return BrandTile(
      leading: const AppIcon(AppIcons.calendar),
      title: Text(label),
      subtitle: Text(Fmt.dayMonthYear(value)),
      trailing: const AppIcon(AppIcons.chevronRight),
      onTap: () async {
        final picked = await brandDatePicker(
          context,
          initial: value,
          first: DateTime.now().subtract(const Duration(days: 365)),
          last: DateTime.now().add(const Duration(days: 3650)),
          title: label,
        );
        if (picked != null) onSet(picked);
      },
    );
  }

  Future<void> _addTime() async {
    final minutes = await brandTimePicker(
      context,
      initialMinutes: 8 * 60,
      title: 'Add a dose time',
    );
    if (minutes == null) return;
    if (_times.contains(minutes)) return;
    setState(() => _times = [..._times, minutes]..sort());
  }

  Future<void> _editTime(int existing) async {
    final minutes = await brandTimePicker(
      context,
      initialMinutes: existing,
      title: 'Dose time',
    );
    if (minutes == null) return;
    setState(() {
      _times = [..._times.where((t) => t != existing), minutes]..sort();
    });
  }

  Future<void> _pickSkipDates() async {
    final range = await brandDateRangePicker(
      context,
      first: _start,
      last: _end,
      title: 'Days to skip',
    );
    if (range == null) return;
    setState(() {
      var day = Fmt.dateOnly(range.$1);
      final last = Fmt.dateOnly(range.$2);
      while (!day.isAfter(last)) {
        _skip.add(day);
        day = day.add(const Duration(days: 1));
      }
    });
  }
}

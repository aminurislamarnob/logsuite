import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:logsuite/core/database/app_database.dart';
import 'package:logsuite/core/people/avatar_storage.dart';
import 'package:logsuite/core/providers/database_provider.dart';
import 'package:logsuite/core/services/notification_service.dart';
import 'package:logsuite/core/services/reminder_target.dart';
import 'package:logsuite/core/settings/app_settings.dart';
import 'package:logsuite/core/theme/app_forui_theme.dart';
import 'package:logsuite/core/theme/app_theme.dart';
import 'package:logsuite/core/utils/formatters.dart';
import 'package:logsuite/presentation/medicine/repository/medicine_repository.dart';
import 'package:logsuite/presentation/medicine/utils/after_opening_expiry.dart';
import 'package:logsuite/presentation/medicine/utils/dose_reminders.dart';
import 'package:logsuite/presentation/medicine/utils/schedule_generator.dart';
import 'package:logsuite/presentation/medicine/widgets/medicine_editor_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeNotifications extends NotificationService {
  _FakeNotifications(super.ref);

  final scheduledWarnings =
      <({int id, DateTime useBy, int daysBefore, DateTime when})>[];
  final scheduledExpiryDays = <({int id, DateTime when})>[];
  final cancelledIds = <int>[];

  @override
  Future<void> scheduleDose({
    required int doseId,
    required String medicineName,
    required String dosageLabel,
    required String mealHint,
    required DateTime when,
  }) async {}

  @override
  Future<void> scheduleMedicineExpiryWarning({
    required int medicineId,
    required String medicineName,
    required DateTime useByDate,
    required int daysBefore,
    required DateTime when,
  }) async {
    scheduledWarnings.add((
      id: medicineId,
      useBy: useByDate,
      daysBefore: daysBefore,
      when: when,
    ));
  }

  @override
  Future<void> scheduleMedicineExpiryDay({
    required int medicineId,
    required String medicineName,
    required DateTime when,
  }) async {
    scheduledExpiryDays.add((id: medicineId, when: when));
  }

  @override
  Future<void> cancelMedicineExpiryAlerts(int medicineId) async {
    cancelledIds.add(medicineId);
  }
}

void main() {
  group('AfterOpeningStatus pure calculations', () {
    test('supports only syrup, drops, and inhaler', () {
      expect(supportsAfterOpening('syrup'), isTrue);
      expect(supportsAfterOpening('drops'), isTrue);
      expect(supportsAfterOpening('inhaler'), isTrue);
      expect(supportsAfterOpening('SYRUP'), isTrue);
      expect(supportsAfterOpening('tablet'), isFalse);
      expect(supportsAfterOpening('capsule'), isFalse);
      expect(supportsAfterOpening('injection'), isFalse);
    });

    test('computes useByDate, remaining days, and state transitions', () {
      final opened = DateTime(2026, 11, 1);
      final status = AfterOpeningStatus(
        form: 'syrup',
        openedDate: opened,
        bestUseWithinDays: 14,
        alertDaysBefore: 3,
      );

      expect(status.useByDate, DateTime(2026, 11, 15));
      expect(status.effectiveLeadDays, 3);
      expect(status.wasLeadClamped, isFalse);
      expect(status.preExpiryAlertAt, DateTime(2026, 11, 12, 9));
      expect(status.expiryDayAlertAt, DateTime(2026, 11, 15, 9));

      // Well before warning window
      expect(status.state(now: DateTime(2026, 11, 5)), AfterOpeningState.ok);
      expect(status.needsAttention(now: DateTime(2026, 11, 5)), isFalse);

      // Inside 3-day warning window
      expect(
        status.state(now: DateTime(2026, 11, 12)),
        AfterOpeningState.expiringSoon,
      );
      expect(
        status.shortBadgeLabel(now: DateTime(2026, 11, 12)),
        'Expires in 3d',
      );
      expect(
        status.shortBadgeLabel(now: DateTime(2026, 11, 14)),
        'Expires tomorrow',
      );

      // On expiry day
      expect(
        status.state(now: DateTime(2026, 11, 15)),
        AfterOpeningState.expiresToday,
      );
      expect(
        status.shortBadgeLabel(now: DateTime(2026, 11, 15)),
        'Expires today',
      );

      // Past expiry day
      expect(
        status.state(now: DateTime(2026, 11, 17)),
        AfterOpeningState.expired,
      );
      expect(
        status.detailLabel(now: DateTime(2026, 11, 17)),
        'Expired 2d ago · discard bottle',
      );
    });

    test('auto-clamps lead time when period is shorter than requested lead', () {
      final opened = DateTime(2026, 11, 10);
      final threeDay = AfterOpeningStatus(
        form: 'drops',
        openedDate: opened,
        bestUseWithinDays: 3,
        alertDaysBefore: 7,
      );
      expect(threeDay.useByDate, DateTime(2026, 11, 13));
      expect(threeDay.effectiveLeadDays, 2);
      expect(threeDay.wasLeadClamped, isTrue);
      expect(threeDay.preExpiryAlertAt, DateTime(2026, 11, 11, 9));
      expect(threeDay.expiryDayAlertAt, DateTime(2026, 11, 13, 9));

      // 1-day period: no pre-expiry alert, expiry-day morning reminder still fires.
      final oneDay = AfterOpeningStatus(
        form: 'drops',
        openedDate: opened,
        bestUseWithinDays: 1,
        alertDaysBefore: 3,
      );
      expect(oneDay.effectiveLeadDays, isNull);
      expect(oneDay.preExpiryAlertAt, isNull);
      expect(oneDay.expiryDayAlertAt, DateTime(2026, 11, 11, 9));
    });

    test('unopened bottle and notifications-off states behave cleanly', () {
      const unopened = AfterOpeningStatus(
        form: 'inhaler',
        openedDate: null,
        bestUseWithinDays: 30,
        alertDaysBefore: 3,
      );
      expect(unopened.state(), AfterOpeningState.unopened);
      expect(unopened.useByDate, isNull);
      expect(unopened.alertsEnabled, isFalse);

      final alertsOff = AfterOpeningStatus(
        form: 'syrup',
        openedDate: DateTime(2026, 11, 1),
        bestUseWithinDays: 10,
        alertDaysBefore: null,
      );
      expect(alertsOff.alertsEnabled, isFalse);
      expect(alertsOff.preExpiryAlertAt, isNull);
      expect(alertsOff.expiryDayAlertAt, isNull);
      // In-app warning still shows within 3 days even if push alerts are off.
      expect(
        alertsOff.state(now: DateTime(2026, 11, 9)),
        AfterOpeningState.expiringSoon,
      );
    });

    test('ReminderTarget routes medicine_expiry payloads to /medicine', () {
      final target = ReminderTarget.parse('medicine_expiry:42');
      expect(target, isNotNull);
      expect(target!.route, '/medicine');
    });
  });

  group('syncMedicineExpiryAlerts & database persistence', () {
    late AppDatabase db;
    late Directory avatarRoot;
    late ProviderContainer container;
    late _FakeNotifications notifications;
    late MedicineRepository repo;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      db = AppDatabase.forTesting(NativeDatabase.memory());
      avatarRoot = Directory.systemTemp.createTempSync('logsuite-expiry');
      container = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          databaseProvider.overrideWithValue(db),
          avatarStorageProvider.overrideWithValue(AvatarStorage(avatarRoot)),
          notificationServiceProvider.overrideWith((ref) {
            return notifications = _FakeNotifications(ref);
          }),
        ],
      );
      container.read(notificationServiceProvider);
      repo = container.read(medicineRepositoryProvider);
    });

    tearDown(() async {
      container.dispose();
      await db.close();
      if (avatarRoot.existsSync()) avatarRoot.deleteSync(recursive: true);
    });

    test(
      'schedules both alerts and cancels cleanly when disabled or changed',
      () async {
        final now = DateTime(2026, 11, 20, 8, 0);
        final opened = DateTime(2026, 11, 20);
        final id = await repo.createMedicineWithSchedule(
          medicine: MedicinesCompanion(
            name: const Value('Napa Syrup'),
            form: const Value('syrup'),
            startDate: Value(opened),
            endDate: Value(opened.add(const Duration(days: 6))),
            openedDate: Value(opened),
            bestUseWithinDays: const Value(14),
            expiryAlertDaysBefore: const Value(3),
          ),
          spec: ScheduleSpec(
            start: opened,
            end: opened.add(const Duration(days: 6)),
          ),
        );

        final med = (await repo.getMedicine(id))!;
        await syncMedicineExpiryAlerts(
          notifier: notifications,
          medicine: med,
          now: now,
        );

        expect(notifications.cancelledIds, [id]);
        expect(notifications.scheduledWarnings, hasLength(1));
        expect(
          notifications.scheduledWarnings.single.when,
          DateTime(2026, 12, 1, 9),
        );
        expect(notifications.scheduledWarnings.single.daysBefore, 3);
        expect(notifications.scheduledExpiryDays, hasLength(1));
        expect(
          notifications.scheduledExpiryDays.single.when,
          DateTime(2026, 12, 4, 9),
        );

        // Turning alert off cancels previous alerts and schedules nothing new.
        notifications.scheduledWarnings.clear();
        notifications.scheduledExpiryDays.clear();
        await repo.updateMedicine(
          id,
          const MedicinesCompanion(expiryAlertDaysBefore: Value(null)),
        );
        final updated = (await repo.getMedicine(id))!;
        await syncMedicineExpiryAlerts(
          notifier: notifications,
          medicine: updated,
          now: now,
        );
        expect(notifications.scheduledWarnings, isEmpty);
        expect(notifications.scheduledExpiryDays, isEmpty);
      },
    );

    test(
      'markBottleOpened resets openedDate while keeping period & alert settings',
      () async {
        final oldOpen = DateTime(2026, 10, 1);
        final id = await repo.createMedicineWithSchedule(
          medicine: MedicinesCompanion(
            name: const Value('Eye Drops'),
            form: const Value('drops'),
            startDate: Value(oldOpen),
            endDate: Value(oldOpen.add(const Duration(days: 6))),
            openedDate: Value(oldOpen),
            bestUseWithinDays: const Value(28),
            expiryAlertDaysBefore: const Value(7),
          ),
          spec: ScheduleSpec(
            start: oldOpen,
            end: oldOpen.add(const Duration(days: 6)),
          ),
        );

        final freshDate = DateTime(2026, 11, 20);
        final updated = await repo.markBottleOpened(id, openedDate: freshDate);
        expect(updated, isNotNull);
        expect(updated!.openedDate, freshDate);
        expect(updated.bestUseWithinDays, 28);
        expect(updated.expiryAlertDaysBefore, 7);
      },
    );

    test(
      'v3 backup Medicine JSON without new columns deserializes cleanly',
      () {
        final v3Json = <String, dynamic>{
          'id': 1,
          'profileId': null,
          'name': 'Napa',
          'form': 'syrup',
          'dosage': 5.0,
          'dosageUnit': 'ml',
          'inventory': 10,
          'lowStockThreshold': 3,
          'doctorName': null,
          'prescriptionPath': null,
          'notes': null,
          'frequencyType': 0,
          'doseTimes': '480',
          'intervalHours': 8,
          'weekdayMask': 127,
          'mealRelation': 'after',
          'startDate': DateTime(2026, 11, 1).millisecondsSinceEpoch,
          'endDate': DateTime(2026, 11, 7).millisecondsSinceEpoch,
          'skipDates': '',
          'isActive': true,
          'createdAt': DateTime(2026, 11, 1).millisecondsSinceEpoch,
        };

        final med = Medicine.fromJson(v3Json);
        expect(med.openedDate, isNull);
        expect(med.bestUseWithinDays, isNull);
        expect(med.expiryAlertDaysBefore, isNull);
      },
    );
  });

  group('MedicineEditorSheet dynamic after-opening UI', () {
    late AppDatabase db;
    late Directory avatarRoot;
    late SharedPreferences prefs;
    late _FakeNotifications notifications;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      db = AppDatabase.forTesting(NativeDatabase.memory());
      avatarRoot = Directory.systemTemp.createTempSync('logsuite-editor-ui');
    });

    tearDown(() async {
      await db.close();
      if (avatarRoot.existsSync()) avatarRoot.deleteSync(recursive: true);
    });

    Widget wrapEditor({Medicine? medicine}) {
      final container = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          databaseProvider.overrideWithValue(db),
          avatarStorageProvider.overrideWithValue(AvatarStorage(avatarRoot)),
          notificationServiceProvider.overrideWith((ref) {
            return notifications = _FakeNotifications(ref);
          }),
        ],
      );
      addTearDown(container.dispose);
      return UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => FTheme(
            data: brandForuiTheme(brightness: Brightness.light),
            child: FToaster(child: child!),
          ),
          home: Scaffold(body: MedicineEditorSheet(medicine: medicine)),
        ),
      );
    }

    testWidgets(
      'shows dynamic fields only for syrup/drops/inhaler, warns on course overlap, and saves',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(wrapEditor());
        await tester.pumpAndSettle();

        // Default form is Tablet -> After opening card is hidden.
        expect(find.byKey(const ValueKey('after-opening-card')), findsNothing);

        // Switch to Syrup -> dynamic card appears.
        await tester.tap(find.text('Syrup'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('after-opening-card')),
          findsOneWidget,
        );
        expect(find.text('Not opened yet'), findsOneWidget);

        // Switch to Injection -> hidden again.
        await tester.ensureVisible(find.text('Injection'));
        await tester.tap(find.text('Injection'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('after-opening-card')), findsNothing);

        // Switch to Inhaler -> visible.
        await tester.ensureVisible(find.text('Inhaler'));
        await tester.tap(find.text('Inhaler'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('after-opening-card')),
          findsOneWidget,
        );

        // Switch to Drops -> visible again.
        await tester.ensureVisible(find.text('Drops'));
        await tester.tap(find.text('Drops'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('after-opening-card')),
          findsOneWidget,
        );

        // Enter medicine name, tap Today, tap 14d preset.
        await tester.enterText(find.byType(EditableText).first, 'Tear Drops');
        await tester.tap(find.text('Today'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('14d'));
        await tester.pumpAndSettle();

        final today = Fmt.dateOnly(DateTime.now());
        final expectedUseBy = today.add(const Duration(days: 14));
        expect(
          find.text('Use by ${Fmt.dayMonth(expectedUseBy)}'),
          findsOneWidget,
        );

        // Extend course to 30 days (> 14d bottle life) -> overlap warning appears.
        final thirtyDays = find.text('30 days');
        await tester.ensureVisible(thirtyDays);
        await tester.tap(thirtyDays);
        await tester.pumpAndSettle();
        expect(find.textContaining('before course ends'), findsOneWidget);

        // Save medicine and verify DB columns + scheduled alerts.
        await tester.tap(find.text('Save medicine'));
        await tester.pumpAndSettle();

        final meds = await db.select(db.medicines).get();
        expect(meds, hasLength(1));
        final saved = meds.single;
        expect(saved.name, 'Tear Drops');
        expect(saved.form, 'drops');
        expect(saved.openedDate, today);
        expect(saved.bestUseWithinDays, 14);
        expect(saved.expiryAlertDaysBefore, 3);
        expect(notifications.scheduledWarnings, hasLength(1));
        expect(notifications.scheduledExpiryDays, hasLength(1));
      },
    );

    testWidgets(
      'switching an existing syrup to tablet clears after-opening fields and cancels alerts',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.reset);

        final today = Fmt.dateOnly(DateTime.now());
        final id = await db
            .into(db.medicines)
            .insert(
              MedicinesCompanion(
                name: const Value('Cough Syrup'),
                form: const Value('syrup'),
                startDate: Value(today),
                endDate: Value(today.add(const Duration(days: 6))),
                openedDate: Value(today),
                bestUseWithinDays: const Value(30),
                expiryAlertDaysBefore: const Value(3),
              ),
            );
        final existing = await (db.select(
          db.medicines,
        )..where((t) => t.id.equals(id))).getSingle();

        await tester.pumpWidget(wrapEditor(medicine: existing));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('after-opening-card')),
          findsOneWidget,
        );

        await tester.ensureVisible(find.text('Tablet'));
        await tester.tap(find.text('Tablet'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('after-opening-card')), findsNothing);

        await tester.tap(find.text('Save changes'));
        await tester.pumpAndSettle();

        final updated = await (db.select(
          db.medicines,
        )..where((t) => t.id.equals(id))).getSingle();
        expect(updated.form, 'tablet');
        expect(updated.openedDate, isNull);
        expect(updated.bestUseWithinDays, isNull);
        expect(updated.expiryAlertDaysBefore, isNull);
        expect(notifications.cancelledIds, contains(id));
        expect(notifications.scheduledWarnings, isEmpty);
        expect(notifications.scheduledExpiryDays, isEmpty);
      },
    );
  });
}

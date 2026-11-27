import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logsuite/core/database/app_database.dart';
import 'package:logsuite/core/people/avatar_storage.dart';
import 'package:logsuite/core/people/people_repository.dart';
import 'package:logsuite/core/providers/database_provider.dart';
import 'package:logsuite/core/services/notification_service.dart';
import 'package:logsuite/core/services/reminder_sync.dart';
import 'package:logsuite/core/settings/app_settings.dart';
import 'package:logsuite/presentation/expenses/repository/expense_repository.dart';
import 'package:logsuite/presentation/drop/repository/drop_repository.dart';
import 'package:logsuite/presentation/habits/repository/habit_repository.dart';
import 'package:logsuite/presentation/medicine/repository/medicine_repository.dart';
import 'package:logsuite/presentation/medicine/utils/schedule_generator.dart';
import 'package:logsuite/presentation/notes/repository/note_repository.dart';
import 'package:logsuite/presentation/tasks/repository/task_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records ids per kind instead of touching the platform plugin.
class _RecordingNotifications extends NotificationService {
  _RecordingNotifications(super.ref);

  final tasks = <int>[];
  final notes = <int>[];
  final habits = <int>[];
  final doses = <int>[];
  final bills = <int>[];
  final loans = <int>[];
  final drops = <int>[];
  final expiryWarnings = <int>[];
  final expiryDays = <int>[];
  final cancelledExpiry = <int>[];
  final dosageLabels = <String>{};

  @override
  Future<void> scheduleTaskReminder({
    required int taskId,
    required String title,
    required DateTime when,
  }) async => tasks.add(taskId);

  @override
  Future<void> scheduleNoteReminder({
    required int noteId,
    required String title,
    required DateTime when,
  }) async => notes.add(noteId);

  @override
  Future<void> scheduleHabitNudge({
    required int habitId,
    required String habitName,
    required int minutesFromMidnight,
  }) async => habits.add(habitId);

  @override
  Future<void> scheduleDose({
    required int doseId,
    required String medicineName,
    required String dosageLabel,
    required String mealHint,
    required DateTime when,
  }) async {
    doses.add(doseId);
    dosageLabels.add(dosageLabel);
  }

  @override
  Future<void> scheduleBillReminder({
    required int billId,
    required String name,
    required double amount,
    required String currency,
    required DateTime when,
  }) async => bills.add(billId);

  @override
  Future<void> cancelBillReminder(int billId) async {}

  @override
  Future<void> scheduleLoanReminder({
    required int loanId,
    required String personName,
    required bool lent,
    required double outstanding,
    required String currency,
    required DateTime when,
  }) async => loans.add(loanId);

  @override
  Future<void> cancelLoanReminder(int loanId) async {}

  @override
  Future<void> scheduleDropReminder({
    required int id,
    required String title,
    required DateTime when,
  }) async => drops.add(id);

  @override
  Future<void> cancelDropReminder(int id) async {}

  @override
  Future<void> scheduleMedicineExpiryWarning({
    required int medicineId,
    required String medicineName,
    required DateTime useByDate,
    required int daysBefore,
    required DateTime when,
  }) async => expiryWarnings.add(medicineId);

  @override
  Future<void> scheduleMedicineExpiryDay({
    required int medicineId,
    required String medicineName,
    required DateTime when,
  }) async => expiryDays.add(medicineId);

  @override
  Future<void> cancelMedicineExpiryAlerts(int medicineId) async =>
      cancelledExpiry.add(medicineId);
}

void main() {
  late AppDatabase db;
  late Directory avatarRoot;
  late ProviderContainer container;
  late _RecordingNotifications notifications;

  final tomorrow = DateTime.now().add(const Duration(days: 1));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    avatarRoot = Directory.systemTemp.createTempSync('logsuite-sync');
    container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        databaseProvider.overrideWithValue(db),
        avatarStorageProvider.overrideWithValue(AvatarStorage(avatarRoot)),
        notificationServiceProvider.overrideWith((ref) {
          return notifications = _RecordingNotifications(ref);
        }),
      ],
    );
    container.read(notificationServiceProvider);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    if (avatarRoot.existsSync()) avatarRoot.deleteSync(recursive: true);
  });

  Future<int> task({DateTime? reminder, bool done = false}) async {
    final repo = container.read(taskRepositoryProvider);
    final id = await repo.createTask(title: 'Call', reminderTime: reminder);
    if (done) await repo.setCompleted(id, true);
    return id;
  }

  Future<int> medicine() async {
    final repo = container.read(medicineRepositoryProvider);
    final start = DateTime(tomorrow.year, tomorrow.month, tomorrow.day);
    return repo.createMedicineWithSchedule(
      medicine: MedicinesCompanion(
        name: const Value('Napa'),
        dosage: const Value(1.5),
        dosageUnit: const Value('tablet'),
        startDate: Value(start),
        endDate: Value(start),
      ),
      spec: ScheduleSpec(start: start, end: start, doseMinutes: const [480]),
    );
  }

  test('every module with something due gets re-armed', () async {
    final due = await task(reminder: tomorrow);
    await task();
    await task(reminder: tomorrow, done: true);

    final notes = container.read(noteRepositoryProvider);
    final noted = await notes.createNote(
      title: 'Idea',
      contentJson: NoteRepository.emptyDelta,
    );
    await notes.updateNote(noted, reminderAt: tomorrow);
    await notes.createNote(
      title: 'Quiet',
      contentJson: NoteRepository.emptyDelta,
    );

    final habit = await container
        .read(habitRepositoryProvider)
        .createHabit(
          const HabitsCompanion(
            name: Value('Water'),
            reminderMinutes: Value(540),
          ),
        );

    final med = await medicine();

    final expenses = container.read(expenseRepositoryProvider);
    final cash = (await expenses.accounts()).first.id;
    final bill = await expenses.createRecurring(
      RecurringExpensesCompanion.insert(
        name: 'Rent',
        amount: 100,
        nextDueDate: tomorrow,
        accountId: Value(cash),
      ),
    );
    final rahim = await container
        .read(peopleRepositoryProvider)
        .createPerson(name: 'Rahim', type: PersonType.contact);
    final loan = await expenses.createLoan(
      personId: rahim,
      direction: LoanDirection.lent,
      principal: 50,
      accountId: cash,
      dueDate: tomorrow,
    );

    final dropRepo = container.read(dropRepositoryProvider);
    final dropId = await dropRepo.createDrop(
      content: 'Important article',
      reminderAt: tomorrow,
    );

    await container.read(reminderSyncProvider).syncAll();

    expect(notifications.tasks, [due]);
    expect(notifications.notes, [noted]);
    expect(notifications.habits, [habit]);
    expect(notifications.drops, [dropId]);
    expect(notifications.doses, hasLength(1));
    expect(notifications.dosageLabels, {'1.5 tablet'});
    expect(notifications.bills, [bill.id]);
    expect(notifications.loans, [loan]);
    expect(med, isPositive);
  });

  test('a switched-off module stays quiet', () async {
    await task(reminder: tomorrow);
    await medicine();
    container
        .read(settingsProvider.notifier)
        .toggleModule(AppModule.tasks, false);

    await container.read(reminderSyncProvider).syncAll();

    expect(notifications.tasks, isEmpty);
    expect(notifications.doses, hasLength(1));
  });

  test(
    'syncMedicine re-arms syrup expiry alerts even after dose course ended',
    () async {
      final repo = container.read(medicineRepositoryProvider);
      final today = DateTime.now();
      final pastStart = DateTime(today.year, today.month, today.day - 6);
      final pastEnd = DateTime(today.year, today.month, today.day - 2);
      final opened = DateTime(today.year, today.month, today.day - 1);

      final syrupId = await repo.createMedicineWithSchedule(
        medicine: MedicinesCompanion(
          name: const Value('Cough Syrup'),
          form: const Value('syrup'),
          dosage: const Value(5),
          dosageUnit: const Value('ml'),
          startDate: Value(pastStart),
          endDate: Value(pastEnd),
          openedDate: Value(opened),
          bestUseWithinDays: const Value(30),
          expiryAlertDaysBefore: const Value(3),
        ),
        spec: ScheduleSpec(
          start: pastStart,
          end: pastEnd,
          doseMinutes: const [480],
        ),
      );

      final inactiveId = await repo.createMedicineWithSchedule(
        medicine: MedicinesCompanion(
          name: const Value('Old Drops'),
          form: const Value('drops'),
          startDate: Value(pastStart),
          endDate: Value(pastEnd),
          openedDate: Value(opened),
          bestUseWithinDays: const Value(28),
          expiryAlertDaysBefore: const Value(3),
          isActive: const Value(false),
        ),
        spec: ScheduleSpec(
          start: pastStart,
          end: pastEnd,
          doseMinutes: const [480],
        ),
      );

      await container.read(reminderSyncProvider).syncAll();

      expect(notifications.expiryWarnings, [syrupId]);
      expect(notifications.expiryDays, [syrupId]);
      expect(notifications.cancelledExpiry, containsAll([syrupId, inactiveId]));
    },
  );
}

import '../../../core/database/app_database.dart';
import '../../../core/services/notification_service.dart';
import '../repository/medicine_repository.dart';
import 'after_opening_expiry.dart';

/// Schedules notifications for a medicine's upcoming doses.
///
/// Only the near-term window is registered: both platforms cap how many
/// pending local notifications an app may hold, and a long course can easily
/// generate hundreds. Shared by the editor sheet and the assistant so a
/// spoken "add Napa" reminds exactly like a typed one.
Future<void> scheduleDoseReminders({
  required MedicineRepository repo,
  required NotificationService notifier,
  required int medicineId,
  required String name,
  required String dosageLabel,
  required String mealHint,
  DateTime? now,
}) async {
  final reference = now ?? DateTime.now();
  final horizon = reference.add(const Duration(days: 14));
  final doses = await repo.dosesFor(medicineId);

  final upcoming = doses
      .where(
        (d) =>
            d.scheduledTime.isAfter(reference) &&
            d.scheduledTime.isBefore(horizon),
      )
      .take(50);

  for (final dose in upcoming) {
    await notifier.scheduleDose(
      doseId: dose.id,
      medicineName: name,
      dosageLabel: dosageLabel,
      mealHint: mealHint,
      when: dose.scheduledTime,
    );
  }
}

/// Cancels any previous after-opening alerts for [medicine] and schedules
/// fresh ones when the medicine is active, uses a supported form (syrup,
/// drops, inhaler), and has both an opened date and a best-use period.
Future<void> syncMedicineExpiryAlerts({
  required NotificationService notifier,
  required Medicine medicine,
  DateTime? now,
}) async {
  await notifier.cancelMedicineExpiryAlerts(medicine.id);
  if (!medicine.isActive) return;

  final status = AfterOpeningStatus.ofMedicine(medicine);
  if (!status.alertsEnabled) return;

  final reference = now ?? DateTime.now();
  final useBy = status.useByDate!;
  final preAt = status.preExpiryAlertAt;
  final lead = status.effectiveLeadDays;
  if (preAt != null && lead != null && preAt.isAfter(reference)) {
    await notifier.scheduleMedicineExpiryWarning(
      medicineId: medicine.id,
      medicineName: medicine.name,
      useByDate: useBy,
      daysBefore: lead,
      when: preAt,
    );
  }

  final expiryAt = status.expiryDayAlertAt;
  if (expiryAt != null && expiryAt.isAfter(reference)) {
    await notifier.scheduleMedicineExpiryDay(
      medicineId: medicine.id,
      medicineName: medicine.name,
      when: expiryAt,
    );
  }
}

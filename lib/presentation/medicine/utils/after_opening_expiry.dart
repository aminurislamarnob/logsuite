import 'package:flutter/foundation.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/formatters.dart';

/// Forms that carry an after-opening shelf life (PAO / "best use within").
const afterOpeningForms = <String>{'syrup', 'drops', 'inhaler'};

/// Quick duration presets (in days) offered in the medicine editor.
const afterOpeningPresets = <int>[7, 14, 28, 30, 60, 90];

/// Lead-time choices (in days before expiry) offered in the medicine editor.
const expiryAlertLeadOptions = <int>[1, 3, 7];

/// Default lead time when the user sets an after-opening period.
const defaultExpiryAlertDaysBefore = 3;

/// Morning hour (local time) at which bottle expiry notifications fire.
const expiryAlertHour = 9;

bool supportsAfterOpening(String form) =>
    afterOpeningForms.contains(form.trim().toLowerCase());

enum AfterOpeningState {
  /// Not applicable to this form, or neither opened date nor period is set.
  none,

  /// Period is configured, but the bottle has not been opened yet.
  unopened,

  /// Opened and well within the best-use window.
  ok,

  /// Approaching the use-by date (within the alert window, or <= 3 days).
  expiringSoon,

  /// Last day of the best-use window.
  expiresToday,

  /// Past the use-by date.
  expired,
}

/// Pure calculation of a bottle's after-opening expiry state and alert times.
@immutable
class AfterOpeningStatus {
  final String form;
  final DateTime? openedDate;
  final int? bestUseWithinDays;

  /// Days before [useByDate] to send the advance alert. `null` or `<= 0` means
  /// notifications are turned off.
  final int? alertDaysBefore;

  const AfterOpeningStatus({
    required this.form,
    required this.openedDate,
    required this.bestUseWithinDays,
    required this.alertDaysBefore,
  });

  factory AfterOpeningStatus.ofMedicine(Medicine m) => AfterOpeningStatus(
    form: m.form,
    openedDate: m.openedDate,
    bestUseWithinDays: m.bestUseWithinDays,
    alertDaysBefore: m.expiryAlertDaysBefore,
  );

  bool get isSupported => supportsAfterOpening(form);

  bool get hasValidPeriod =>
      bestUseWithinDays != null && bestUseWithinDays! > 0;

  /// Inclusive final day the opened bottle should be used.
  DateTime? get useByDate {
    if (!isSupported || openedDate == null || !hasValidPeriod) return null;
    return Fmt.dateOnly(openedDate!).add(Duration(days: bestUseWithinDays!));
  }

  /// Calendar days remaining until [useByDate]: positive = days left,
  /// `0` = expires today, negative = expired that many days ago.
  int? daysRemaining({DateTime? now}) {
    final target = useByDate;
    if (target == null) return null;
    final today = Fmt.dateOnly(now ?? DateTime.now());
    return target.difference(today).inDays;
  }

  bool get alertsEnabled =>
      useByDate != null && alertDaysBefore != null && alertDaysBefore! > 0;

  /// Actual lead days used for the advance alert, clamped so a short shelf
  /// life (e.g. 3 days with a 7-day lead) never schedules on/before opening.
  int? get effectiveLeadDays {
    if (!alertsEnabled) return null;
    final period = bestUseWithinDays!;
    if (period <= 1) return null;
    final requested = alertDaysBefore!;
    return requested < period ? requested : period - 1;
  }

  bool get wasLeadClamped {
    final eff = effectiveLeadDays;
    return alertsEnabled && eff != null && eff != alertDaysBefore;
  }

  /// Advance notification timestamp (9:00 AM local time), or `null` if off or
  /// the period is only 1 day (expiry-day reminder still fires).
  DateTime? get preExpiryAlertAt {
    final target = useByDate;
    final lead = effectiveLeadDays;
    if (target == null || lead == null) return null;
    final day = target.subtract(Duration(days: lead));
    return DateTime(day.year, day.month, day.day, expiryAlertHour);
  }

  /// Expiry-day morning notification timestamp (9:00 AM local time).
  DateTime? get expiryDayAlertAt {
    if (!alertsEnabled) return null;
    final target = useByDate!;
    return DateTime(target.year, target.month, target.day, expiryAlertHour);
  }

  AfterOpeningState state({DateTime? now}) {
    if (!isSupported) return AfterOpeningState.none;
    if (openedDate == null) {
      return hasValidPeriod
          ? AfterOpeningState.unopened
          : AfterOpeningState.none;
    }
    if (!hasValidPeriod) return AfterOpeningState.none;
    final rem = daysRemaining(now: now)!;
    if (rem < 0) return AfterOpeningState.expired;
    if (rem == 0) return AfterOpeningState.expiresToday;
    final warnWindow = effectiveLeadDays ?? defaultExpiryAlertDaysBefore;
    if (rem <= warnWindow) return AfterOpeningState.expiringSoon;
    return AfterOpeningState.ok;
  }

  bool isExpired({DateTime? now}) =>
      state(now: now) == AfterOpeningState.expired;

  bool isWarning({DateTime? now}) {
    final s = state(now: now);
    return s == AfterOpeningState.expiringSoon ||
        s == AfterOpeningState.expiresToday;
  }

  bool needsAttention({DateTime? now}) =>
      isExpired(now: now) || isWarning(now: now);

  /// Compact badge text for dose rows, compact course tiles, and Up Next cards.
  String? shortBadgeLabel({DateTime? now}) {
    final s = state(now: now);
    final rem = daysRemaining(now: now);
    return switch (s) {
      AfterOpeningState.expired => 'Expired bottle',
      AfterOpeningState.expiresToday => 'Expires today',
      AfterOpeningState.expiringSoon =>
        rem == 1 ? 'Expires tomorrow' : 'Expires in ${rem}d',
      AfterOpeningState.ok =>
        useByDate != null ? 'Use by ${Fmt.dayMonth(useByDate!)}' : null,
      AfterOpeningState.unopened => 'Unopened · ${bestUseWithinDays}d limit',
      AfterOpeningState.none => null,
    };
  }

  /// Richer status copy for the full Medicine card in the Medicines tab.
  String? detailLabel({DateTime? now}) {
    final s = state(now: now);
    final rem = daysRemaining(now: now);
    return switch (s) {
      AfterOpeningState.expired => () {
        final ago = -(rem ?? 0);
        final agoText = ago == 1 ? 'yesterday' : '${ago}d ago';
        return 'Expired $agoText · discard bottle';
      }(),
      AfterOpeningState.expiresToday => 'Expires today · discard after today',
      AfterOpeningState.expiringSoon =>
        rem == 1
            ? 'Expires tomorrow · use by ${Fmt.dayMonth(useByDate!)}'
            : 'Expires in ${rem}d · use by ${Fmt.dayMonth(useByDate!)}',
      AfterOpeningState.ok =>
        'Opened ${Fmt.dayMonth(openedDate!)} · use by ${Fmt.dayMonth(useByDate!)}',
      AfterOpeningState.unopened =>
        'Not opened yet · best within ${formatPeriodDays(bestUseWithinDays!)}',
      AfterOpeningState.none => null,
    };
  }

  /// Formats a day count into concise human copy (e.g. `28 days`, `1 month`).
  static String formatPeriodDays(int days) {
    if (days >= 30 && days % 30 == 0) {
      final months = days ~/ 30;
      return months == 1 ? '30 days' : '$months months ($days days)';
    }
    return days == 1 ? '1 day' : '$days days';
  }
}

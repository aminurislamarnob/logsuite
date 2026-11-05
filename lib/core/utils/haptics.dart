import 'package:flutter/services.dart';

/// Centralized haptic feedback helper for LogSuite.
///
/// Respects the global [enabled] flag synced with [AppSettings.hapticsEnabled].
abstract final class AppHaptics {
  /// Global toggle synced by [SettingsNotifier].
  static bool enabled = true;

  /// Light impact for standard button taps, tile presses, and icon actions.
  static Future<void> tap() async {
    if (!enabled) return;
    await HapticFeedback.lightImpact();
  }

  /// Crisp selection tick for switches, tabs, pills, day strip cells, and pickers.
  static Future<void> selection() async {
    if (!enabled) return;
    await HapticFeedback.selectionClick();
  }

  /// Medium impact for primary FABs, long-press actions, and drag/reorder start.
  static Future<void> medium() async {
    if (!enabled) return;
    await HapticFeedback.mediumImpact();
  }

  /// Heavy impact for destructive actions (delete, dismiss) and major state changes.
  static Future<void> heavy() async {
    if (!enabled) return;
    await HapticFeedback.heavyImpact();
  }

  /// Tactile confirmation for completing a task, habit, medicine dose, or timer.
  static Future<void> success() async {
    if (!enabled) return;
    await HapticFeedback.mediumImpact();
  }

  /// Alert pulse for threshold warnings or budget/limit overruns.
  static Future<void> warning() async {
    if (!enabled) return;
    await HapticFeedback.heavyImpact();
  }

  /// Distinct vibration for validation errors or failed PIN attempts.
  static Future<void> error() async {
    if (!enabled) return;
    await HapticFeedback.vibrate();
  }
}

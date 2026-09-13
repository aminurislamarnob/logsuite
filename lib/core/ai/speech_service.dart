import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../settings/app_settings.dart';
import '../settings/voice_language.dart';

final speechServiceProvider = Provider<SpeechService>((ref) {
  final service = SpeechService(ref);
  ref.onDispose(service.dispose);
  return service;
});

/// Which recogniser a session will run, and whether it is the one the user
/// asked for. [localeId] null means the device default.
class SpeechLocale {
  final String? localeId;

  /// True when the language from Settings has no recogniser on this device
  /// and the session fell back to the device language instead.
  final bool fellBack;

  const SpeechLocale({required this.localeId, this.fellBack = false});
}

/// The one speech recogniser, shared by the assistant and every dictation
/// button.
///
/// Three screens used to each construct their own `SpeechToText` and repeat
/// the same initialise-then-listen dance, and none of them set a locale, so
/// dictation always ran in the device language even with the app in Bangla.
/// Wrapping the plugin once means the locale follows the "Voice language"
/// setting everywhere and the platform quirks (a `false` from initialize, a
/// listen that ends on its own after a pause) are handled in one place.
class SpeechService {
  SpeechService(this._ref);

  final Ref _ref;
  final _stt = stt.SpeechToText();
  final _listening = StreamController<bool>.broadcast();
  bool _ready = false;
  List<stt.LocaleName>? _locales;

  /// True between a successful [listen] and the recogniser going quiet,
  /// whether the user stopped it or it timed out on its own.
  Stream<bool> get listening => _listening.stream;

  bool get isListening => _stt.isListening;

  /// Idempotent. False means no recogniser on this device or permission
  /// denied; the caller decides how to say so.
  Future<bool> initialize() async {
    if (_ready) return true;
    try {
      _ready = await _stt.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            _listening.add(false);
          }
        },
        onError: (e) {
          debugPrint('Speech error: ${e.errorMsg}');
          _listening.add(false);
        },
      );
    } on Exception catch (e) {
      debugPrint('Speech init failed: $e');
      _ready = false;
    }
    return _ready;
  }

  /// The recogniser that matches the "Voice language" setting.
  ///
  /// Auto is the device default. English and Bangla look for an installed
  /// recogniser in that language, preferring the regional variant the app's
  /// users are most likely to want (en_US, bn_BD); when none is installed
  /// the result says so, and the session runs in the device language.
  Future<SpeechLocale> resolveLocale() async {
    final wanted = _ref.read(settingsProvider).voiceLanguage.languageCode;
    if (wanted == null) return const SpeechLocale(localeId: null);
    final locales = await _availableLocales();
    final matches = locales.where(
      (l) => l.localeId.toLowerCase().replaceAll('-', '_').startsWith(wanted),
    );
    if (matches.isEmpty) {
      return const SpeechLocale(localeId: null, fellBack: true);
    }
    final preferredRegion = wanted == 'bn' ? 'bd' : 'us';
    final regional = matches
        .where((l) => l.localeId.toLowerCase().contains(preferredRegion))
        .firstOrNull;
    return SpeechLocale(localeId: (regional ?? matches.first).localeId);
  }

  /// Kept for the dictation buttons that only need an id.
  Future<String?> preferredLocaleId() async => (await resolveLocale()).localeId;

  Future<List<stt.LocaleName>> _availableLocales() async {
    final cached = _locales;
    if (cached != null) return cached;
    if (!await initialize()) return const [];
    try {
      return _locales = await _stt.locales();
    } on Exception catch (e) {
      debugPrint('Could not list speech locales: $e');
      return const [];
    }
  }

  /// Starts listening. [onResult] is called with every partial transcript
  /// and once more with `isFinal` true. [onSoundLevel] receives the raw
  /// platform level in decibels several times a second. Returns false when
  /// the recogniser is unavailable.
  ///
  /// [locale] skips the settings lookup; a caller that already ran
  /// [resolveLocale] passes it through so the locale list is not consulted
  /// again on every restart.
  Future<bool> listen({
    required void Function(String words, bool isFinal) onResult,
    void Function(double level)? onSoundLevel,
    Duration listenFor = const Duration(seconds: 60),
    Duration pauseFor = const Duration(seconds: 4),
    SpeechLocale? locale,
  }) async {
    if (!await initialize()) return false;
    final localeId = (locale ?? await resolveLocale()).localeId;
    try {
      await _stt.listen(
        onResult: (r) {
          onResult(r.recognizedWords, r.finalResult);
          if (r.finalResult) _listening.add(false);
        },
        onSoundLevelChange: onSoundLevel,
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: stt.ListenMode.dictation,
          listenFor: listenFor,
          pauseFor: pauseFor,
          localeId: localeId,
        ),
      );
      _listening.add(true);
      return true;
    } on Exception catch (e) {
      debugPrint('Speech listen failed: $e');
      _listening.add(false);
      return false;
    }
  }

  /// Ends the session and lets the recogniser send its final result.
  Future<void> stop() async {
    try {
      await _stt.stop();
    } on Exception catch (e) {
      debugPrint('Speech stop failed: $e');
    }
    _listening.add(false);
  }

  /// Ends the session without a final result.
  Future<void> cancel() async {
    try {
      await _stt.cancel();
    } on Exception catch (e) {
      debugPrint('Speech cancel failed: $e');
    }
    _listening.add(false);
  }

  void dispose() {
    _stt.stop();
    _listening.close();
  }
}

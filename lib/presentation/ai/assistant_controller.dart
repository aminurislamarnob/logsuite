import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/ai_action.dart';
import '../../core/ai/ai_client.dart';
import '../../core/ai/ai_command_executor.dart';
import '../../core/ai/ai_command_service.dart';
import '../../core/ai/ai_drafts.dart';
import '../../core/ai/speech_service.dart';
import '../../core/services/document_scanner.dart';
import '../../core/services/ocr_service.dart';
import '../../core/settings/app_settings.dart';
import '../../core/settings/voice_language.dart';

/// The assistant screen's states, in the order a command moves through them.
sealed class AssistantState {
  const AssistantState();
}

class AssistantIdle extends AssistantState {
  const AssistantIdle();
}

/// The microphone is open. [partial] is everything heard so far across
/// every recogniser session of this recording, [level] the current input
/// loudness from 0 to 1 for the animation, [elapsed] the recording clock.
class AssistantListening extends AssistantState {
  final String partial;
  final double level;
  final Duration elapsed;

  /// Shown under the mic when the language from Settings has no recogniser
  /// on this device and the session runs in the device language instead.
  final String? notice;

  const AssistantListening({
    this.partial = '',
    this.level = 0,
    this.elapsed = Duration.zero,
    this.notice,
  });

  AssistantListening copyWith({
    String? partial,
    double? level,
    Duration? elapsed,
  }) => AssistantListening(
    partial: partial ?? this.partial,
    level: level ?? this.level,
    elapsed: elapsed ?? this.elapsed,
    notice: notice,
  );
}

class AssistantTranscript extends AssistantState {
  final String text;

  const AssistantTranscript(this.text);
}

class AssistantThinking extends AssistantState {
  final String transcript;

  const AssistantThinking(this.transcript);
}

class AssistantPreview extends AssistantState {
  final String transcript;
  final AiCommandResult result;
  final List<ActionPreview> previews;

  /// Cards already written, by index, after a tap-to-edit save or a save
  /// that only partly succeeded.
  final Map<int, SavedItem> saved;

  /// Why the last save did not finish: a refused unlock, or the rows that
  /// could not be written. Shown above the cards; the rest can be retried.
  final String? error;

  const AssistantPreview({
    required this.transcript,
    required this.result,
    required this.previews,
    this.saved = const {},
    this.error,
  });

  /// Cards still to be written by "Save all".
  Iterable<int> get pending => [
    for (var i = 0; i < previews.length; i++)
      if (!saved.containsKey(i) && !previews[i].blocked) i,
  ];

  AssistantPreview copyWith({
    List<ActionPreview>? previews,
    Map<int, SavedItem>? saved,
    String? error,
    bool clearError = false,
  }) => AssistantPreview(
    transcript: transcript,
    result: result,
    previews: previews ?? this.previews,
    saved: saved ?? this.saved,
    error: clearError ? null : (error ?? this.error),
  );
}

class AssistantSaving extends AssistantState {
  final String transcript;

  const AssistantSaving(this.transcript);
}

class AssistantSaved extends AssistantState {
  final List<SavedItem> items;
  final String reply;
  final AiSource source;

  const AssistantSaved({
    required this.items,
    this.reply = '',
    required this.source,
  });
}

enum AssistantErrorKind {
  noSpeech,
  noKey,
  auth,
  network,
  rateLimit,
  refused,
  malformed,
  nothingParsed,
  unknown,
}

class AssistantFailure extends AssistantState {
  final AssistantErrorKind kind;
  final String message;
  final String transcript;
  final AiSource? source;

  const AssistantFailure({
    required this.kind,
    required this.message,
    this.transcript = '',
    this.source,
  });
}

final assistantControllerProvider =
    StateNotifierProvider.autoDispose<AssistantController, AssistantState>(
      (ref) => AssistantController(ref),
    );

/// Drives one command from the mic to the rows.
///
/// The screen only renders states and forwards taps; everything that decides
/// what happens next lives here so it can be exercised without widgets.
class AssistantController extends StateNotifier<AssistantState> {
  AssistantController(this._ref)
    : _speech = _ref.read(speechServiceProvider),
      super(const AssistantIdle()) {
    _listening = _speech.listening.listen(_onListening);
  }

  final Ref _ref;

  // Held from construction: dispose runs while the container may already be
  // tearing down, when reading a provider is no longer allowed.
  final SpeechService _speech;
  StreamSubscription<bool>? _listening;
  Timer? _finishTimer;
  Timer? _clock;
  String _transcript = '';

  /// Asked before writing into a locked module. Set by the screen, which can
  /// show the biometric prompt; when unset (tests) the write is allowed.
  Future<bool> Function(Set<AppModule> modules)? unlockGate;

  String get transcript => _transcript;

  @override
  void dispose() {
    _finishTimer?.cancel();
    _clock?.cancel();
    _listening?.cancel();
    if (_speech.isListening) _speech.cancel();
    super.dispose();
  }

  // --- Listening -----------------------------------------------------------

  /// A forgotten open mic stops itself here and sends what it heard.
  static const maxRecording = Duration(minutes: 2);

  /// How long the recogniser waits in silence before ending a session. The
  /// recording survives it: the next session starts at once.
  static const _sessionPause = Duration(seconds: 3);

  /// Both platforms report "not listening" a moment *before* they deliver
  /// the final result; this is how long to wait for it.
  static const _finalGrace = Duration(milliseconds: 600);

  /// Words from sessions that already delivered their final result.
  String _committed = '';

  /// The live session's latest partial.
  String _current = '';

  /// False once the user tapped stop or the cap ran out: no more sessions.
  bool _recording = false;
  DateTime? _startedAt;
  SpeechLocale? _locale;

  /// Opens the mic and keeps it open until [stopListening], [cancelListening]
  /// or [maxRecording]. On-device recognisers end a session after a pause,
  /// so this restarts one each time and stitches the transcripts, which is
  /// what lets the user stop to remember a price mid-command.
  Future<void> startListening() async {
    _transcript = '';
    _committed = '';
    _current = '';
    _recording = true;
    _startedAt = DateTime.now();
    _locale = await _speech.resolveLocale();
    if (!mounted) return;
    state = AssistantListening(
      notice: _locale!.fellBack
          ? 'No ${_ref.read(settingsProvider).voiceLanguage.label} recogniser '
                'on this device. Listening in the device language.'
          : null,
    );
    final started = await _startSession();
    if (!started) {
      _recording = false;
      if (mounted) {
        state = const AssistantFailure(
          kind: AssistantErrorKind.noSpeech,
          message: 'Speech recognition is unavailable on this device.',
        );
      }
      return;
    }
    _clock?.cancel();
    _clock = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
  }

  Future<bool> _startSession() {
    final remaining = maxRecording - _elapsed;
    return _speech.listen(
      locale: _locale,
      listenFor: remaining.isNegative ? Duration.zero : remaining,
      pauseFor: _sessionPause,
      onSoundLevel: _onSoundLevel,
      onResult: (words, isFinal) {
        if (!mounted || state is! AssistantListening) return;
        if (isFinal) {
          _commit(words);
        } else {
          _current = words;
          _publish();
        }
      },
    );
  }

  Duration get _elapsed => _startedAt == null
      ? Duration.zero
      : DateTime.now().difference(_startedAt!);

  void _commit(String words) {
    _current = '';
    final w = words.trim();
    if (w.isNotEmpty) _committed = _committed.isEmpty ? w : '$_committed $w';
    _publish();
  }

  String get _stitched => _current.trim().isEmpty
      ? _committed
      : '$_committed ${_current.trim()}'.trim();

  void _publish({double? level}) {
    final s = state;
    if (s is! AssistantListening) return;
    state = s.copyWith(partial: _stitched, level: level, elapsed: _elapsed);
  }

  void _tick() {
    if (!mounted || state is! AssistantListening) {
      _clock?.cancel();
      return;
    }
    if (_recording && _elapsed >= maxRecording) {
      stopListening();
      return;
    }
    _publish();
  }

  /// The plugin reports decibels: roughly -2..10 on Android and -50..0 on
  /// iOS. Both are squashed into 0..1 for the rings.
  void _onSoundLevel(double db) {
    if (!mounted || state is! AssistantListening) return;
    final level = db < 0
        ? ((db + 50) / 50).clamp(0.0, 1.0)
        : (db / 10).clamp(0.0, 1.0);
    _publish(level: level);
  }

  /// The user tapped stop. What has been heard goes to the model.
  Future<void> stopListening() async {
    if (!_recording) return;
    _recording = false;
    _clock?.cancel();
    await _speech.stop();
  }

  /// The user changed their mind. Nothing is sent.
  Future<void> cancelListening() async {
    _recording = false;
    _clock?.cancel();
    _finishTimer?.cancel();
    await _speech.cancel();
    if (!mounted) return;
    discard();
  }

  /// A session went quiet: the user paused, the platform's own cap hit, or
  /// [stopListening] ran. Wait briefly for the session's final words, then
  /// either start the next session or finish the recording.
  void _onListening(bool active) {
    if (active || !mounted || state is! AssistantListening) return;
    _finishTimer?.cancel();
    _finishTimer = Timer(_finalGrace, _onSessionEnded);
  }

  Future<void> _onSessionEnded() async {
    _finishTimer = null;
    if (!mounted || state is! AssistantListening) return;
    // The final result never came; keep the last partial rather than lose it.
    if (_current.trim().isNotEmpty) _commit(_current);
    if (_recording && _elapsed < maxRecording) {
      final started = await _startSession();
      if (started || !mounted || state is! AssistantListening) return;
      _recording = false;
    }
    _finishListening();
  }

  /// Runs once per recording, when no more sessions will start.
  void _finishListening() {
    _finishTimer?.cancel();
    _finishTimer = null;
    _clock?.cancel();
    if (!mounted || state is! AssistantListening) return;
    _transcript = _stitched;
    if (_transcript.trim().isEmpty) {
      state = const AssistantFailure(
        kind: AssistantErrorKind.noSpeech,
        message: 'Nothing was heard. Try again, or type it instead.',
      );
      return;
    }
    // No review step: the preview cards are where the user checks the result.
    submit();
  }

  // --- Scanning ------------------------------------------------------------

  /// Camera or gallery, an optional crop, on-device OCR, then the text goes
  /// to the model the same way spoken words do. The image never leaves the
  /// phone.
  Future<void> scanDocument({required bool fromCamera}) async {
    final image = await _ref
        .read(documentScannerProvider)
        .pick(fromCamera: fromCamera);
    if (image == null || !mounted) return;

    state = const AssistantThinking('Reading the document…');
    final text = await _ref.read(ocrServiceProvider).extractText(image);
    if (!mounted) return;

    if (text == null || text.trim().isEmpty) {
      state = const AssistantFailure(
        kind: AssistantErrorKind.nothingParsed,
        message:
            'No text could be read from that image. Try a sharper photo, '
            'or type it instead.',
      );
      return;
    }

    // The prefix is what the prompt keys on to treat this as OCR output.
    _transcript = '[Scanned Document]\n${text.trim()}';
    await submit();
  }

  // --- Typing --------------------------------------------------------------

  void typeInstead() {
    state = AssistantTranscript(_transcript);
  }

  void editTranscript(String text) {
    _transcript = text;
  }

  // --- Parsing -------------------------------------------------------------

  Future<void> submit({bool forceOffline = false}) async {
    final transcript = _transcript.trim();
    if (transcript.isEmpty) {
      state = AssistantTranscript(_transcript);
      return;
    }
    state = AssistantThinking(transcript);

    AiCommandRun run;
    try {
      run = await _ref
          .read(aiCommandServiceProvider)
          .run(transcript, forceOffline: forceOffline);
    } on AiException catch (e) {
      if (mounted) state = _failure(e, transcript);
      return;
    } on Exception catch (e) {
      debugPrint('Assistant failed: $e');
      if (mounted) {
        state = AssistantFailure(
          kind: AssistantErrorKind.unknown,
          message: 'Something went wrong. Try again.',
          transcript: transcript,
        );
      }
      return;
    }
    if (!mounted) return;

    final result = run.result;
    if (result.actions.isEmpty) {
      state = AssistantFailure(
        kind: AssistantErrorKind.nothingParsed,
        message: result.reply.isNotEmpty
            ? result.reply
            : 'Nothing to add was found in that. Try rephrasing.',
        transcript: transcript,
        source: result.source,
      );
      return;
    }

    final previews = await _ref
        .read(aiCommandExecutorProvider)
        .resolve(result.actions, run.context);
    if (!mounted) return;

    final preview = AssistantPreview(
      transcript: transcript,
      result: result,
      previews: previews,
    );
    state = preview;

    // Auto-save only skips a preview that had nothing to say.
    final settings = _ref.read(settingsProvider);
    if (settings.aiAutoSave &&
        !result.needsClarification &&
        previews.every((p) => p.clean)) {
      await saveAll();
    }
  }

  AssistantFailure _failure(AiException e, String transcript) {
    final kind = switch (e) {
      AiAuthException() => AssistantErrorKind.auth,
      AiRateLimitException() => AssistantErrorKind.rateLimit,
      AiRefusalException() => AssistantErrorKind.refused,
      AiNetworkException() => AssistantErrorKind.network,
      AiMalformedException() => AssistantErrorKind.malformed,
      _ => AssistantErrorKind.unknown,
    };
    return AssistantFailure(
      kind: kind,
      message: e.message,
      transcript: transcript,
    );
  }

  // --- Preview -------------------------------------------------------------

  void removePreview(int index) {
    final s = state;
    if (s is! AssistantPreview) return;
    final previews = List.of(s.previews)..removeAt(index);
    final saved = <int, SavedItem>{
      for (final e in s.saved.entries)
        if (e.key < index)
          e.key: e.value
        else if (e.key > index)
          e.key - 1: e.value,
    };
    if (previews.isEmpty) {
      state = AssistantTranscript(_transcript);
      return;
    }
    state = s.copyWith(previews: previews, saved: saved);
  }

  void markSaved(int index, SavedItem item) {
    final s = state;
    if (s is! AssistantPreview) return;
    state = s.copyWith(saved: {...s.saved, index: item}, clearError: true);
  }

  /// Writes every pending card. Returns false when a lock prompt was refused
  /// or a write failed; the preview stays, with the rows that did get written
  /// marked saved and the reason shown, so a retry only writes the rest.
  Future<bool> saveAll() async {
    final s = state;
    if (s is! AssistantPreview) return false;
    final pending = s.pending.toList();
    if (pending.isEmpty) {
      state = AssistantSaved(
        items: s.saved.values.toList(),
        reply: s.result.reply,
        source: s.result.source,
      );
      return true;
    }

    final locked = _ref.read(settingsProvider).lockedModules;
    final needsUnlock = {
      for (final i in pending)
        if (locked.contains(s.previews[i].draft.module))
          s.previews[i].draft.module,
    };
    if (needsUnlock.isNotEmpty && unlockGate != null) {
      final ok = await unlockGate!(needsUnlock);
      if (!mounted) return false;
      if (!ok) {
        state = s.copyWith(
          error:
              '${needsUnlock.map((m) => m.label).join(', ')} '
              '${needsUnlock.length == 1 ? 'is' : 'are'} locked. '
              'Unlock to save.',
        );
        return false;
      }
    }

    state = AssistantSaving(s.transcript);
    final executor = _ref.read(aiCommandExecutorProvider);
    final outcome = await executor.saveAll([
      for (final i in pending) s.previews[i].draft,
    ]);
    if (!mounted) return false;

    final saved = {...s.saved};
    for (var k = 0; k < pending.length; k++) {
      final item = outcome.results[k];
      if (item != null) saved[pending[k]] = item;
    }

    if (outcome.failures.isEmpty) {
      state = AssistantSaved(
        items: [for (final i in saved.keys.toList()..sort()) saved[i]!],
        reply: s.result.reply,
        source: s.result.source,
      );
      return true;
    }
    state = s.copyWith(saved: saved, error: outcome.failures.join('\n'));
    return false;
  }

  // --- Navigation between states ------------------------------------------

  void discard() {
    _transcript = '';
    state = const AssistantIdle();
  }

  void editAgain() {
    state = AssistantTranscript(_transcript);
  }

  void reset() => discard();
}

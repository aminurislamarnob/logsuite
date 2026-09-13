import 'dart:io';

import 'package:drift/native.dart';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logsuite/core/ai/ai_action.dart';
import 'package:logsuite/core/ai/ai_client.dart';
import 'package:logsuite/core/ai/ai_provider.dart';
import 'package:logsuite/core/ai/ai_providers.dart';
import 'package:logsuite/core/ai/speech_service.dart';
import 'package:logsuite/core/database/app_database.dart';
import 'package:logsuite/core/people/avatar_storage.dart';
import 'package:logsuite/core/providers/database_provider.dart';
import 'package:logsuite/core/services/document_scanner.dart';
import 'package:logsuite/core/services/notification_service.dart';
import 'package:logsuite/core/services/ocr_service.dart';
import 'package:logsuite/core/settings/app_settings.dart';
import 'package:logsuite/presentation/ai/assistant_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_fixtures.dart';

/// A provider that answers with whatever the test hands it.
class _FakeClient implements AiClient {
  _FakeClient(this.reply);

  final Object reply; // String body, or an exception to throw
  int calls = 0;

  @override
  AiProvider get provider => AiProvider.anthropic;

  @override
  String get model => 'fake-model';

  @override
  Future<AiRawResponse> complete({
    required String system,
    required String user,
    required Map<String, Object?> schema,
  }) async {
    calls++;
    if (reply is Exception) throw reply as Exception;
    return AiRawResponse(text: reply as String, model: model);
  }
}

/// A recogniser the test drives by hand: it hands out the callbacks of the
/// latest session so words can be fed in, and mirrors the real service's
/// "went quiet" signal after a final result, a stop or a cancel.
class _FakeSpeech extends SpeechService {
  _FakeSpeech(super.ref, {this.available = true, this.fellBack = false});

  final bool available;
  final bool fellBack;
  final _quiet = StreamController<bool>.broadcast();
  void Function(String words, bool isFinal)? onResult;
  void Function(double level)? onSoundLevel;
  int sessions = 0;
  int stops = 0;
  int cancels = 0;
  bool _live = false;

  @override
  Stream<bool> get listening => _quiet.stream;

  @override
  bool get isListening => _live;

  @override
  Future<SpeechLocale> resolveLocale() async =>
      SpeechLocale(localeId: fellBack ? null : 'bn_BD', fellBack: fellBack);

  @override
  Future<bool> listen({
    required void Function(String words, bool isFinal) onResult,
    void Function(double level)? onSoundLevel,
    Duration listenFor = const Duration(seconds: 60),
    Duration pauseFor = const Duration(seconds: 4),
    SpeechLocale? locale,
  }) async {
    if (!available) return false;
    sessions++;
    this.onResult = onResult;
    this.onSoundLevel = onSoundLevel;
    _live = true;
    _quiet.add(true);
    return true;
  }

  void partial(String words) => onResult?.call(words, false);

  /// The platform delivers the final words and then reports not listening.
  void finalWords(String words) {
    onResult?.call(words, true);
    _live = false;
    _quiet.add(false);
  }

  /// The session ended in silence without a final result.
  void wentQuiet() {
    _live = false;
    _quiet.add(false);
  }

  @override
  Future<void> stop() async {
    stops++;
    _live = false;
    _quiet.add(false);
  }

  @override
  Future<void> cancel() async {
    cancels++;
    _live = false;
    _quiet.add(false);
  }
}

class _FakeScanner extends DocumentScanner {
  _FakeScanner(this.file);

  final File? file;

  @override
  Future<File?> pick({required bool fromCamera}) async => file;
}

class _FakeOcr extends OcrService {
  const _FakeOcr(this.text);

  final String? text;

  @override
  Future<String?> extractText(File imageFile) async => text;
}

/// Never touches the platform plugin.
class _QuietNotifications extends NotificationService {
  _QuietNotifications(super.ref);

  @override
  Future<void> scheduleTaskReminder({
    required int taskId,
    required String title,
    required DateTime when,
  }) async {}

  @override
  Future<void> scheduleDose({
    required int doseId,
    required String medicineName,
    required String dosageLabel,
    required String mealHint,
    required DateTime when,
  }) async {}
}

void main() {
  late AppDatabase db;
  late Directory avatarRoot;

  Future<ProviderContainer> container({
    AiClient? client,
    Map<String, Object> prefs = const {},
    _FakeSpeech Function(Ref ref)? speech,
    File? scanned,
    String? ocrText,
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    final sharedPrefs = await SharedPreferences.getInstance();
    return ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(sharedPrefs),
        databaseProvider.overrideWithValue(db),
        avatarStorageProvider.overrideWithValue(AvatarStorage(avatarRoot)),
        notificationServiceProvider.overrideWith(_QuietNotifications.new),
        aiClientProvider.overrideWith((ref) async => client),
        if (speech != null) speechServiceProvider.overrideWith(speech),
        documentScannerProvider.overrideWithValue(_FakeScanner(scanned)),
        ocrServiceProvider.overrideWithValue(_FakeOcr(ocrText)),
      ],
    );
  }

  /// Past the grace the controller gives a session's final words.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 750));

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    avatarRoot = Directory.systemTemp.createTempSync('logsuite-assistant');
  });

  tearDown(() async {
    await db.close();
    if (avatarRoot.existsSync()) avatarRoot.deleteSync(recursive: true);
  });

  /// Keeps the autoDispose controller alive for the test's duration.
  AssistantController controllerOf(ProviderContainer c) {
    c.listen(assistantControllerProvider, (_, _) {});
    return c.read(assistantControllerProvider.notifier);
  }

  // Dated tomorrow so the reminder is never "already passed".
  final canonical = canonicalJsonFor(
    DateTime.now().add(const Duration(days: 1)),
  );

  test('a typed command previews one card per action', () async {
    final client = _FakeClient(canonical);
    final c = await container(client: client);
    final controller = controllerOf(c);

    controller.editTranscript('spent 200 taka on lunch with bKash …');
    await controller.submit();

    final state = c.read(assistantControllerProvider);
    expect(state, isA<AssistantPreview>());
    final preview = state as AssistantPreview;
    expect(preview.previews, hasLength(3));
    expect(preview.result.source, isA<RemoteSource>());
    expect(client.calls, 1);
    // The medicine card carries no length warning: the canned reply says 5 days.
    expect(preview.previews.every((p) => p.clean), isTrue);
  });

  test('auto-save writes straight through when every card is clean', () async {
    final c = await container(
      client: _FakeClient(canonical),
      prefs: {'ai_auto_save': true},
    );
    final controller = controllerOf(c);
    controller.editTranscript('the canonical sentence');
    await controller.submit();

    final state = c.read(assistantControllerProvider);
    expect(state, isA<AssistantSaved>());
    expect((state as AssistantSaved).items, hasLength(3));
    expect(await db.select(db.expenses).get(), hasLength(1));
    expect(await db.select(db.tasks).get(), hasLength(1));
    expect(await db.select(db.medicines).get(), hasLength(1));
  });

  test('auto-save still previews when a card has a warning', () async {
    const withUnknownAccount =
        '{"actions": [{"kind": "add_expense", "title": "Tea", "amount": 20, '
        '"account": "Paytm"}], "reply": "", "needs_clarification": false}';
    final c = await container(
      client: _FakeClient(withUnknownAccount),
      prefs: {'ai_auto_save': true},
    );
    final controller = controllerOf(c);
    controller.editTranscript('tea 20 taka paytm');
    await controller.submit();

    final state = c.read(assistantControllerProvider);
    expect(state, isA<AssistantPreview>());
    expect((state as AssistantPreview).previews.single.warnings, isNotEmpty);
    expect(await db.select(db.expenses).get(), isEmpty);
  });

  test('no client means the offline parser answers', () async {
    final c = await container(client: null);
    final controller = controllerOf(c);
    controller.editTranscript('spent 200 taka on lunch with bKash');
    await controller.submit();

    final state = c.read(assistantControllerProvider) as AssistantPreview;
    expect(state.result.source, isA<OfflineSource>());
    expect(state.previews.single.draft.title, 'Lunch');
  });

  test('an auth failure maps to the auth error kind', () async {
    final c = await container(
      client: _FakeClient(const AiAuthException('invalid x-api-key')),
    );
    final controller = controllerOf(c);
    controller.editTranscript('anything');
    await controller.submit();

    final state = c.read(assistantControllerProvider) as AssistantFailure;
    expect(state.kind, AssistantErrorKind.auth);
    expect(state.message, 'invalid x-api-key');
    expect(state.transcript, 'anything');
  });

  test('removing every card returns to the transcript', () async {
    final c = await container(client: _FakeClient(canonical));
    final controller = controllerOf(c);
    controller.editTranscript('x');
    await controller.submit();
    controller.removePreview(0);
    controller.removePreview(0);
    expect(c.read(assistantControllerProvider), isA<AssistantPreview>());
    controller.removePreview(0);
    expect(c.read(assistantControllerProvider), isA<AssistantTranscript>());
  });

  test('a locked module asks the gate and stops when refused', () async {
    final c = await container(
      client: _FakeClient(canonical),
      prefs: {
        'locked_modules': ['expenses'],
      },
    );
    final controller = controllerOf(c);
    final asked = <Set<AppModule>>[];
    controller.unlockGate = (modules) async {
      asked.add(modules);
      return false;
    };
    controller.editTranscript('x');
    await controller.submit();
    expect(await controller.saveAll(), isFalse);
    expect(asked.single, {AppModule.expenses});
    // The preview survives with the reason, so a second Save can retry
    // without another provider round trip.
    final state = c.read(assistantControllerProvider) as AssistantPreview;
    expect(state.error, contains('locked'));
    expect(state.previews, hasLength(3));
    expect(await db.select(db.tasks).get(), isEmpty);

    // Granting the unlock on the retry writes everything.
    controller.unlockGate = (_) async => true;
    expect(await controller.saveAll(), isTrue);
    expect(c.read(assistantControllerProvider), isA<AssistantSaved>());
    expect(await db.select(db.tasks).get(), hasLength(1));
    expect(await db.select(db.expenses).get(), hasLength(1));
  });
  group('recording', () {
    test('stitches sessions across a pause and sends on stop', () async {
      final client = _FakeClient(canonical);
      late _FakeSpeech speech;
      final c = await container(
        client: client,
        speech: (ref) => speech = _FakeSpeech(ref),
      );
      final controller = controllerOf(c);

      await controller.startListening();
      expect(c.read(assistantControllerProvider), isA<AssistantListening>());
      expect(speech.sessions, 1);

      speech.partial('fish 50');
      var s = c.read(assistantControllerProvider) as AssistantListening;
      expect(s.partial, 'fish 50');

      // The user pauses: the platform closes the session with its final
      // words, and the recording carries on in a new one.
      speech.finalWords('fish 50');
      await settle();
      expect(c.read(assistantControllerProvider), isA<AssistantListening>());
      expect(speech.sessions, 2);

      speech.partial('rice 30');
      s = c.read(assistantControllerProvider) as AssistantListening;
      expect(s.partial, 'fish 50 rice 30');

      speech.onSoundLevel?.call(5);
      s = c.read(assistantControllerProvider) as AssistantListening;
      expect(s.level, closeTo(0.5, 0.01));

      await controller.stopListening();
      speech.finalWords('rice 30');
      await settle();

      // No review step: stop went straight to the model.
      expect(speech.sessions, 2);
      expect(client.calls, 1);
      expect(controller.transcript, 'fish 50 rice 30');
      expect(c.read(assistantControllerProvider), isA<AssistantPreview>());
    });

    test('keeps the last partial when no final result arrives', () async {
      final client = _FakeClient(canonical);
      late _FakeSpeech speech;
      final c = await container(
        client: client,
        speech: (ref) => speech = _FakeSpeech(ref),
      );
      final controller = controllerOf(c);
      await controller.startListening();
      speech.partial('lunch 200');
      await controller.stopListening();
      speech.wentQuiet();
      await settle();
      expect(controller.transcript, 'lunch 200');
      expect(client.calls, 1);
    });

    test('cancel throws the words away', () async {
      final client = _FakeClient(canonical);
      late _FakeSpeech speech;
      final c = await container(
        client: client,
        speech: (ref) => speech = _FakeSpeech(ref),
      );
      final controller = controllerOf(c);
      await controller.startListening();
      speech.partial('fish 50');
      await controller.cancelListening();
      await settle();
      expect(c.read(assistantControllerProvider), isA<AssistantIdle>());
      expect(speech.cancels, 1);
      expect(speech.sessions, 1);
      expect(client.calls, 0);
    });

    test('silence all the way through is a noSpeech failure', () async {
      late _FakeSpeech speech;
      final c = await container(
        client: _FakeClient(canonical),
        speech: (ref) => speech = _FakeSpeech(ref),
      );
      final controller = controllerOf(c);
      await controller.startListening();
      await controller.stopListening();
      speech.wentQuiet();
      await settle();
      final s = c.read(assistantControllerProvider) as AssistantFailure;
      expect(s.kind, AssistantErrorKind.noSpeech);
    });

    test('no recogniser on the device fails at once', () async {
      final c = await container(
        client: _FakeClient(canonical),
        speech: (ref) => _FakeSpeech(ref, available: false),
      );
      final controller = controllerOf(c);
      await controller.startListening();
      final s = c.read(assistantControllerProvider) as AssistantFailure;
      expect(s.kind, AssistantErrorKind.noSpeech);
    });

    test('a missing Bangla recogniser is said under the mic', () async {
      final c = await container(
        client: _FakeClient(canonical),
        prefs: {'voice_language': 'bangla'},
        speech: (ref) => _FakeSpeech(ref, fellBack: true),
      );
      final controller = controllerOf(c);
      await controller.startListening();
      final s = c.read(assistantControllerProvider) as AssistantListening;
      expect(s.notice, contains('device language'));
    });
  });

  group('scanning', () {
    test(
      'OCR text goes straight to the model with the document prefix',
      () async {
        final client = _FakeClient(canonical);
        final c = await container(
          client: client,
          scanned: File('receipt.jpg'),
          ocrText: 'Lunch 200\nbKash',
        );
        final controller = controllerOf(c);
        await controller.scanDocument(fromCamera: true);
        expect(controller.transcript, '[Scanned Document]\nLunch 200\nbKash');
        expect(client.calls, 1);
        expect(c.read(assistantControllerProvider), isA<AssistantPreview>());
      },
    );

    test('a cancelled pick leaves the state alone', () async {
      final client = _FakeClient(canonical);
      final c = await container(client: client, scanned: null);
      final controller = controllerOf(c);
      await controller.scanDocument(fromCamera: false);
      expect(c.read(assistantControllerProvider), isA<AssistantIdle>());
      expect(client.calls, 0);
    });

    test('an unreadable image is a nothingParsed failure', () async {
      final client = _FakeClient(canonical);
      final c = await container(
        client: client,
        scanned: File('blurry.jpg'),
        ocrText: '',
      );
      final controller = controllerOf(c);
      await controller.scanDocument(fromCamera: true);
      final s = c.read(assistantControllerProvider) as AssistantFailure;
      expect(s.kind, AssistantErrorKind.nothingParsed);
      expect(client.calls, 0);
    });
  });
}

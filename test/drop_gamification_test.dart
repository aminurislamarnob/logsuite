import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:logsuite/core/database/app_database.dart';
import 'package:logsuite/core/providers/database_provider.dart';
import 'package:logsuite/core/settings/app_settings.dart';
import 'package:logsuite/core/theme/app_forui_theme.dart';
import 'package:logsuite/core/theme/app_theme.dart';
import 'package:logsuite/presentation/drop/drop_screen.dart';
import 'package:logsuite/presentation/drop/repository/drop_repository.dart';
import 'package:logsuite/presentation/drop/services/drop_gamification_service.dart';
import 'package:logsuite/presentation/drop/widgets/drop_gamification_bar.dart';
import 'package:logsuite/presentation/drop/widgets/drop_mastery_sheet.dart';
import 'package:logsuite/presentation/notes/repository/note_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DropGamificationService Unit Tests', () {
    late SharedPreferences prefs;
    late DropGamificationService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      service = DropGamificationService(prefs);
    });

    test('Initial stats are zeroed out at Level 1 Novice', () {
      final stats = service.getStats();
      expect(stats.xp, 0);
      expect(stats.level, 1);
      expect(stats.levelTitle, 'Novice Collector');
      expect(stats.currentStreak, 0);
      expect(stats.totalDropsCaptured, 0);
      expect(stats.unlockedBadgeIds.isEmpty, isTrue);
    });

    test('Capturing first drop awards XP, updates streak and unlocks first_drop badge', () async {
      final reward = await service.recordDropCaptured(hasTags: false);

      expect(reward.xpGained, 35); // 10 (drop) + 25 (first_drop badge)
      expect(reward.unlockedBadges.any((b) => b.id == 'first_drop'), isTrue);
      expect(reward.streakExtended, isTrue);
      expect(reward.streakCount, 1);

      final stats = service.getStats();
      expect(stats.xp, 35);
      expect(stats.totalDropsCaptured, 1);
      expect(stats.currentStreak, 1);
      expect(stats.unlockedBadgeIds.contains('first_drop'), isTrue);
    });

    test('Capturing drop with #tags awards bonus XP and unlocks tag_architect badge', () async {
      final reward = await service.recordDropCaptured(hasTags: true);

      // 15 (drop with tag) + 25 (first_drop) + 30 (tag_architect) = 70 XP
      expect(reward.xpGained, 70);
      expect(reward.unlockedBadges.map((b) => b.id).toSet(), containsAll({'first_drop', 'tag_architect'}));
      expect(reward.didLevelUp, isTrue); // > 50 XP reaches Level 2
      expect(reward.newLevel, 2);
      expect(reward.newLevelTitle, 'Active Gatherer');
    });

    test('Triaging items awards XP and unlocks triage_specialist badge after 5', () async {
      for (int i = 0; i < 4; i++) {
        await service.recordDropTriaged();
      }
      final r5 = await service.recordDropTriaged();
      expect(r5.unlockedBadges.any((b) => b.id == 'triage_specialist'), isTrue);

      final stats = service.getStats();
      expect(stats.totalDropsTriaged, 5);
      expect(stats.unlockedBadgeIds.contains('triage_specialist'), isTrue);
    });

    test('Reaching inbox zero grants +50 XP bonus and inbox_zero badge', () async {
      final reward = await service.recordDropTriaged(reachedInboxZero: true);
      // 10 base + 50 hero bonus + 50 inbox_zero badge = 110 XP
      expect(reward.xpGained, 110);
      expect(reward.unlockedBadges.any((b) => b.id == 'inbox_zero'), isTrue);

      final stats = service.getStats();
      expect(stats.inboxZeroCount, 1);
    });

    test('Favoriting and converting awards XP and badges', () async {
      final favReward = await service.recordDropFavorited();
      expect(favReward.xpGained, 5);

      final taskReward = await service.recordConvertedToTask();
      expect(taskReward.xpGained, 15 + 35); // 15 + 35 for action_taker badge
      expect(taskReward.unlockedBadges.any((b) => b.id == 'action_taker'), isTrue);

      final noteReward = await service.recordConvertedToNote();
      expect(noteReward.xpGained, 15 + 35); // 15 + 35 for scholar badge
      expect(noteReward.unlockedBadges.any((b) => b.id == 'scholar'), isTrue);
    });
  });

  group('Drop Gamification Widget Tests', () {
    late AppDatabase db;
    late DropRepository repo;
    late NoteRepository noteRepo;
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'drop_gamification_xp': 85,
        'drop_gamification_current_streak': 3,
        'drop_gamification_total_captured': 5,
        'drop_gamification_total_triaged': 2,
        'drop_gamification_unlocked_badges': ['first_drop', 'tag_architect'],
      });
      prefs = await SharedPreferences.getInstance();
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = DropRepository(db);
      noteRepo = NoteRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    Future<ProviderContainer> pumpScreen(WidgetTester tester) async {
      final container = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          databaseProvider.overrideWithValue(db),
          dropRepositoryProvider.overrideWithValue(repo),
          noteRepositoryProvider.overrideWithValue(noteRepo),
        ],
      );
      addTearDown(container.dispose);

      final router = GoRouter(
        initialLocation: '/drop',
        routes: [
          GoRoute(
            path: '/drop',
            builder: (_, _) => const DropScreen(),
          ),
          GoRoute(
            path: '/note_editor',
            builder: (_, state) => const Scaffold(body: Text('Note Editor')),
          ),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: router,
            builder: (context, child) => FTheme(
              data: brandForuiTheme(brightness: Brightness.light),
              child: FToaster(
                child: FTooltipGroup(
                  child: child!,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return container;
    }

    testWidgets('DropGamificationBar renders streak, level, and XP accurately', (tester) async {
      await pumpScreen(tester);
      await tester.pumpAndSettle();

      // Verify Gamification Bar is rendered
      expect(find.byType(DropGamificationBar), findsOneWidget);
      expect(find.text('3d'), findsOneWidget);
      expect(find.text('Lvl 2'), findsOneWidget);
      expect(find.textContaining('Active Gatherer'), findsWidgets);
      expect(find.textContaining('85 XP'), findsOneWidget);
    });

    testWidgets('Tapping DropGamificationBar opens DropMasterySheet bottom sheet', (tester) async {
      await pumpScreen(tester);
      await tester.pumpAndSettle();

      // Tap gamification bar
      await tester.tap(find.byType(DropGamificationBar));
      await tester.pumpAndSettle();

      // Verify DropMasterySheet is displayed
      expect(find.byType(DropMasterySheet), findsOneWidget);
      expect(find.text('Drop Mastery & Badges'), findsOneWidget);
      expect(find.textContaining('Level 2'), findsWidgets);
      expect(find.textContaining('Active Gatherer'), findsWidgets);
      expect(find.text('Streak'), findsOneWidget);
      expect(find.text('Captured'), findsOneWidget);
      expect(find.text('Inbox Zero'), findsWidgets);
      expect(find.text('2 of 9 unlocked'), findsOneWidget);

      // Verify badges section
      expect(find.text('First Capture'), findsOneWidget);
      expect(find.text('Tag Architect'), findsOneWidget);
      expect(find.text('Inbox Zero Hero'), findsOneWidget);
    });

    testWidgets('Submitting a drop with tags grants XP and updates bar', (tester) async {
      await pumpScreen(tester);
      await tester.pumpAndSettle();

      final inputFinder = find.byKey(const ValueKey('drop_message_input_field'));
      expect(inputFinder, findsOneWidget);

      await tester.enterText(inputFinder, 'Read this article #flutter #mobile');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      // Gamification bar should update XP (85 + 15 = 100 XP)
      expect(find.textContaining('100 XP'), findsOneWidget);
    });

    testWidgets('Inbox Zero hero view is shown when all drops are cleared', (tester) async {
      // With drops empty and totalDropsCaptured > 0 (preset in prefs as 5)
      await pumpScreen(tester);
      await tester.pumpAndSettle();

      expect(find.text('Inbox Zero!'), findsOneWidget);
      expect(find.textContaining('All items triaged! Your workspace is clear and calm.'), findsOneWidget);
      expect(find.textContaining('Inbox Zero Master • +50 XP Hero Bonus'), findsOneWidget);
    });
  });
}

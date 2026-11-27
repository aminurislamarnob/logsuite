import 'package:drift/drift.dart' as drift;
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
import 'package:logsuite/core/utils/formatters.dart';
import 'package:logsuite/presentation/habits/habit_detail_screen.dart';
import 'package:logsuite/presentation/habits/repository/habit_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets(
    'open /habits/:id, tap Mark done -> headline becomes streak, Edit -> 15 -> Save stores 15',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = HabitRepository(db);
      final habitId = await repo.createHabit(
        HabitsCompanion.insert(
          name: 'Read 20 pages',
          icon: const drift.Value('reading'),
          color: const drift.Value(0xFF2D8657),
          unit: const drift.Value('pages'),
          goalType: const drift.Value(0),
          targetAmount: const drift.Value(20),
        ),
      );

      final router = GoRouter(
        initialLocation: '/habits/$habitId',
        routes: [
          GoRoute(
            path: '/habits',
            builder: (_, _) => const Scaffold(body: Text('Habits List')),
          ),
          GoRoute(
            path: '/habits/:id',
            builder: (_, state) => HabitDetailScreen(
              habitId: int.parse(state.pathParameters['id']!),
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPrefsProvider.overrideWithValue(prefs),
            databaseProvider.overrideWithValue(db),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: router,
            builder: (context, child) => FTheme(
              data: brandForuiTheme(brightness: Brightness.light),
              child: FToaster(child: FTooltipGroup(child: child!)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify initial state
      expect(find.text('Read 20 pages'), findsOneWidget);
      expect(find.text('20 pages to go'), findsOneWidget);

      // Tap Mark done in Today card (first Mark done button)
      await tester.tap(find.text('Mark done').first);
      await tester.pumpAndSettle();

      // Headline becomes the streak
      expect(find.text('1-day streak'), findsOneWidget);

      // Tap Edit pill in Today card
      await tester.tap(find.text('Edit').first);
      await tester.pumpAndSettle();

      // Enter 15 in the editor TextField and tap Save
      final field = find.byType(TextField).first;
      await tester.enterText(field, '15');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Verify database stored 15 for today
      final todayLog = await repo.logForDay(
        habitId,
        Fmt.dateOnly(DateTime.now()),
      );
      expect(todayLog, isNotNull);
      expect(todayLog!.amount, 15);
      expect(find.text('5 pages to go'), findsOneWidget);

      // Flush Drift stream cleanup timers before test invariants check.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    },
  );
}

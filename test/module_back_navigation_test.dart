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
import 'package:logsuite/core/theme/app_icons.dart';
import 'package:logsuite/core/theme/app_theme.dart';
import 'package:logsuite/core/widgets/brand.dart';
import 'package:logsuite/presentation/medicine/medicine_screen.dart';
import 'package:logsuite/presentation/notes/notes_screen.dart';
import 'package:logsuite/presentation/tasks/tasks_screen.dart';
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

  Future<ProviderContainer> pumpTestScreen(
    WidgetTester tester, {
    required String initialLocation,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        databaseProvider.overrideWithValue(db),
      ],
    );
    addTearDown(container.dispose);

    final router = GoRouter(
      initialLocation: '/dashboard',
      routes: [
        GoRoute(
          path: '/dashboard',
          builder: (_, _) => const Scaffold(body: Text('Dashboard Screen')),
        ),
        GoRoute(
          path: '/notes',
          builder: (_, _) => const NotesScreen(),
        ),
        GoRoute(
          path: '/tasks',
          builder: (_, _) => const TasksScreen(),
        ),
        GoRoute(
          path: '/medicine',
          builder: (_, _) => const MedicineScreen(),
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
    await tester.pumpAndSettle();

    // Push into the target module screen
    router.push(initialLocation);
    await tester.pumpAndSettle();

    return container;
  }

  testWidgets('NotesScreen renders Back button and Folders button; tapping Back returns to previous screen', (tester) async {
    await pumpTestScreen(tester, initialLocation: '/notes');

    expect(find.byType(NotesScreen), findsOneWidget);

    // Verify both Back button and Folders button exist via their ValueKeys
    final backBtn = find.byKey(const ValueKey('button-back'));
    final folderBtn = find.byKey(const ValueKey('button-folders'));

    expect(backBtn, findsOneWidget);
    expect(folderBtn, findsOneWidget);

    // Tap back button
    await tester.tap(backBtn);
    await tester.pumpAndSettle();

    // Should return to Dashboard
    expect(find.text('Dashboard Screen'), findsOneWidget);
    expect(find.byType(NotesScreen), findsNothing);
  });

  testWidgets('TasksScreen renders Back button and Projects button; tapping Back returns to previous screen', (tester) async {
    await pumpTestScreen(tester, initialLocation: '/tasks');

    expect(find.byType(TasksScreen), findsOneWidget);

    // Verify both Back button and Projects folder button exist
    final backBtn = find.byKey(const ValueKey('button-back'));
    final projectBtn = find.byKey(const ValueKey('button-projects'));

    expect(backBtn, findsOneWidget);
    expect(projectBtn, findsOneWidget);

    // Tap back button
    await tester.tap(backBtn);
    await tester.pumpAndSettle();

    // Should return to Dashboard
    expect(find.text('Dashboard Screen'), findsOneWidget);
    expect(find.byType(TasksScreen), findsNothing);
  });

  testWidgets('MedicineScreen renders Back button and Profiles button; tapping Back returns to previous screen', (tester) async {
    await pumpTestScreen(tester, initialLocation: '/medicine');

    expect(find.byType(MedicineScreen), findsOneWidget);

    // Verify both Back button and Profiles button exist
    final backBtn = find.byKey(const ValueKey('button-back'));
    final profileBtn = find.byKey(const ValueKey('button-profiles'));

    expect(backBtn, findsOneWidget);
    expect(profileBtn, findsOneWidget);

    // Tap back button
    await tester.tap(backBtn);
    await tester.pumpAndSettle();

    // Should return to Dashboard
    expect(find.text('Dashboard Screen'), findsOneWidget);
    expect(find.byType(MedicineScreen), findsNothing);
  });
}

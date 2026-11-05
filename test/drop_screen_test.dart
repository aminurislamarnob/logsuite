import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:logsuite/core/database/app_database.dart';
import 'package:logsuite/core/providers/database_provider.dart';
import 'package:logsuite/core/settings/app_settings.dart';
import 'package:logsuite/core/theme/app_forui_theme.dart';
import 'package:logsuite/core/theme/app_theme.dart';
import 'package:logsuite/presentation/drop/drop_screen.dart';
import 'package:logsuite/presentation/drop/repository/drop_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppDatabase db;
  late DropRepository repo;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = DropRepository(db);
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
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: FTheme(
            data: brandForuiTheme(brightness: Brightness.light),
            child: const FToaster(
              child: FTooltipGroup(
                child: DropScreen(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return container;
  }

  testWidgets('renders DropScreen empty state and filter pills', (tester) async {
    await pumpScreen(tester);
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Drop'), findsOneWidget);
    expect(find.text('Your Drop is empty'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Articles'), findsOneWidget);
    expect(find.text('Videos'), findsOneWidget);
    expect(find.text('Clips'), findsOneWidget);
    expect(find.text('Images'), findsOneWidget);
    expect(find.text('Favorites'), findsOneWidget);
  });

  testWidgets('submits new drop from bottom input bar and updates feed', (tester) async {
    await pumpScreen(tester);
    await tester.pump(const Duration(milliseconds: 50));

    final inputFinder = find.byType(TextField);
    expect(inputFinder, findsOneWidget);

    await tester.enterText(inputFinder, 'Quick note to check later #idea');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();

    expect(find.text('Quick note to check later #idea'), findsOneWidget);
    // #idea appears in both the card tags and the top hashtag strip
    expect(find.text('#idea'), findsNWidgets(2));
    expect(find.text('Your Drop is empty'), findsNothing);
  });

  testWidgets('toggles between inbox and archive views', (tester) async {
    await repo.createDrop(
      content: 'Inbox item',
      triageStatus: 'inbox',
    );
    await repo.createDrop(
      content: 'Archived item',
      triageStatus: 'archived',
    );

    await pumpScreen(tester);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    // Default is Inbox
    expect(find.text('Inbox item'), findsOneWidget);
    expect(find.text('Archived item'), findsNothing);

    // Tap archive toggle in top bar
    final archiveToggle = find.byTooltip('View Archive');
    expect(archiveToggle, findsOneWidget);
    await tester.tap(archiveToggle);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();

    // Now in Archive view
    expect(find.text('Archived item'), findsOneWidget);
    expect(find.text('Inbox item'), findsNothing);
  });
}

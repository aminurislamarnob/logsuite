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

  testWidgets('filters by Favorites when pinned items exist', (tester) async {
    await repo.createDrop(content: 'Normal drop', isPinned: false);
    await repo.createDrop(content: 'Important pinned drop', isPinned: true);

    await pumpScreen(tester);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Normal drop'), findsOneWidget);
    expect(find.text('Important pinned drop'), findsOneWidget);

    // Tap Favorites filter pill
    await tester.tap(find.text('Favorites'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    expect(find.text('Important pinned drop'), findsOneWidget);
    expect(find.text('Normal drop'), findsNothing);
  });

  testWidgets('enters multi-select mode on long press and archives items', (tester) async {
    final id1 = await repo.createDrop(content: 'Item 1');
    final id2 = await repo.createDrop(content: 'Item 2');

    await pumpScreen(tester);
    await tester.pump(const Duration(milliseconds: 100));

    // Long press first item
    await tester.longPress(find.text('Item 1'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('1 selected'), findsOneWidget);

    // Tap second item to select it
    await tester.tap(find.text('Item 2'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('2 selected'), findsOneWidget);

    // Tap bulk archive button
    final bulkArchiveBtn = find.byTooltip('Bulk Archive');
    expect(bulkArchiveBtn, findsOneWidget);
    await tester.tap(bulkArchiveBtn);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();

    // In inbox view, both are gone
    expect(find.text('Your Drop is empty'), findsOneWidget);

    // Verify in repository that both are archived
    final archived = await repo.getDrops(triageStatus: 'archived');
    expect(archived.length, 2);
    expect(archived.map((d) => d.id), containsAll([id1, id2]));
  });
}

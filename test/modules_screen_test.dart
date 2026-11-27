import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:logsuite/core/database/app_database.dart';
import 'package:logsuite/core/providers/database_provider.dart';
import 'package:logsuite/core/people/avatar_storage.dart';
import 'package:logsuite/core/services/security_service.dart';
import 'package:logsuite/core/settings/app_settings.dart';
import 'package:logsuite/core/theme/app_forui_theme.dart';
import 'package:logsuite/core/theme/app_theme.dart';
import 'package:logsuite/presentation/medicine/repository/medicine_repository.dart';
import 'package:logsuite/presentation/modules/modules_screen.dart';
import 'package:logsuite/presentation/tasks/providers/tasks_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late SharedPreferences prefs;
  late Directory avatarRoot;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    avatarRoot = Directory.systemTemp.createTempSync('logsuite-modules-test');
  });

  tearDown(() async {
    await db.close();
    if (avatarRoot.existsSync()) {
      avatarRoot.deleteSync(recursive: true);
    }
  });

  Future<void> pumpFrame(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
  }

  Future<ProviderContainer> pumpModulesScreen(
    WidgetTester tester, {
    List<Override> extraOverrides = const [],
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        databaseProvider.overrideWithValue(db),
        avatarStorageProvider.overrideWithValue(AvatarStorage(avatarRoot)),
        ...extraOverrides,
      ],
    );
    addTearDown(container.dispose);

    final router = GoRouter(
      initialLocation: '/modules',
      routes: [
        GoRoute(path: '/modules', builder: (_, _) => const ModulesScreen()),
        GoRoute(
          path: '/search',
          builder: (_, _) => const Scaffold(body: Text('Search')),
        ),
        GoRoute(
          path: '/assistant',
          builder: (_, _) => const Scaffold(body: Text('Assistant')),
        ),
        for (final m in AppModule.values)
          GoRoute(
            path: m.route,
            builder: (_, _) => Scaffold(body: Text(m.label)),
          ),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MaterialApp.router(
            theme: ThemeData.light().copyWith(
              extensions: [AppTheme.tokens(brightness: Brightness.light).brand],
            ),
            routerConfig: router,
            builder: (context, child) => FTheme(
              data: brandForuiTheme(brightness: Brightness.light),
              child: FToaster(child: FTooltipGroup(child: child!)),
            ),
          ),
        ),
      ),
    );
    await pumpFrame(tester);
    return container;
  }

  Future<void> flushStreams(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }

  testWidgets(
    'subtitle counts due-now pending doses and overdue tasks, excluding locked modules',
    (tester) async {
      final now = DateTime.now();
      final medId = await db
          .into(db.medicines)
          .insert(
            MedicinesCompanion.insert(
              name: 'Napa 500 mg',
              dosage: const drift.Value(1),
              dosageUnit: const drift.Value('tablet'),
              startDate: now,
              endDate: now.add(const Duration(days: 7)),
            ),
          );
      await db
          .into(db.medicineDoses)
          .insert(
            MedicineDosesCompanion.insert(
              medicineId: medId,
              scheduledTime: now.subtract(const Duration(minutes: 15)),
            ),
          );
      await db
          .into(db.tasks)
          .insert(
            TasksCompanion.insert(
              title: 'Overdue task',
              dueDate: drift.Value(now.subtract(const Duration(days: 1))),
            ),
          );

      final container = await pumpModulesScreen(
        tester,
        extraOverrides: [
          taskStatsProvider(7).overrideWith(
            (ref) async =>
                const TaskStats(completed: 0, open: 1, overdue: 1, perDay: {}),
          ),
        ],
      );
      await pumpFrame(tester);
      expect(find.textContaining('2 things need you'), findsOneWidget);

      // Lock medicine -> only overdue task counts
      container
          .read(settingsProvider.notifier)
          .toggleModuleLock(AppModule.medicine, true);
      await pumpFrame(tester);
      expect(find.textContaining('1 thing needs you'), findsOneWidget);

      // Lock tasks -> 0 -> all clear
      container
          .read(settingsProvider.notifier)
          .toggleModuleLock(AppModule.tasks, true);
      await pumpFrame(tester);
      expect(find.textContaining('all clear'), findsOneWidget);

      await flushStreams(tester);
    },
  );

  testWidgets('locked tile shows Locked and hides module figures', (
    tester,
  ) async {
    await db
        .into(db.expenses)
        .insert(
          ExpensesCompanion.insert(
            amount: 550,
            categoryId: const drift.Value(1),
            accountId: 1,
            personId: 1,
            date: drift.Value(DateTime.now()),
            note: const drift.Value('Groceries'),
          ),
        );

    final container = await pumpModulesScreen(tester);
    container
        .read(settingsProvider.notifier)
        .toggleModuleLock(AppModule.expenses, true);
    await pumpFrame(tester);

    expect(find.text('Locked'), findsOneWidget);
    expect(find.text('Tap to unlock'), findsOneWidget);
    expect(find.textContaining('550'), findsNothing);

    await flushStreams(tester);
  });

  testWidgets('turning a module on from Switched off chips enables it', (
    tester,
  ) async {
    final container = await pumpModulesScreen(tester);
    container
        .read(settingsProvider.notifier)
        .toggleModule(AppModule.focus, false);
    await pumpFrame(tester);

    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await pumpFrame(tester);
    expect(find.text('SWITCHED OFF'), findsOneWidget);
    expect(find.byKey(const ValueKey('module-focus')), findsNothing);

    final focusChip = find.text('Focus').last;
    await tester.tap(focusChip);
    await pumpFrame(tester);

    expect(container.read(settingsProvider).isEnabled(AppModule.focus), isTrue);
    expect(find.byKey(const ValueKey('module-focus')), findsOneWidget);

    await flushStreams(tester);
  });

  testWidgets(
    'edit-mode switch and lock behaviour: lock disabled while module is off',
    (tester) async {
      final container = await pumpModulesScreen(tester);
      await container.read(pinStatusProvider.notifier).set('1234');

      // Enter edit mode
      await tester.tap(find.text('Edit'));
      await pumpFrame(tester);
      expect(find.text('7 on · 0 locked'), findsOneWidget);

      // Toggle Notes off
      await tester.tap(find.bySemanticsLabel('Toggle Notes'));
      await pumpFrame(tester);
      expect(
        container.read(settingsProvider).isEnabled(AppModule.notes),
        isFalse,
      );
      expect(find.text('6 on · 0 locked'), findsOneWidget);

      // Tapping lock on disabled Notes does nothing
      await tester.tap(find.bySemanticsLabel('Lock Notes'));
      await pumpFrame(tester);
      expect(
        container
            .read(settingsProvider)
            .lockedModules
            .contains(AppModule.notes),
        isFalse,
      );

      // Tapping lock on enabled Expenses locks it
      await tester.tap(find.bySemanticsLabel('Lock Expenses'));
      await pumpFrame(tester);
      expect(
        container
            .read(settingsProvider)
            .lockedModules
            .contains(AppModule.expenses),
        isTrue,
      );
      expect(find.text('6 on · 1 locked'), findsOneWidget);

      await flushStreams(tester);
    },
  );

  testWidgets('Take now calls setDoseStatus and Undo reverts it', (
    tester,
  ) async {
    final now = DateTime.now();
    final medId = await db
        .into(db.medicines)
        .insert(
          MedicinesCompanion.insert(
            name: 'Napa 500 mg',
            dosage: const drift.Value(1),
            dosageUnit: const drift.Value('tablet'),
            startDate: now,
            endDate: now.add(const Duration(days: 7)),
          ),
        );
    final doseId = await db
        .into(db.medicineDoses)
        .insert(
          MedicineDosesCompanion.insert(
            medicineId: medId,
            scheduledTime: now.subtract(const Duration(minutes: 10)),
          ),
        );

    await pumpModulesScreen(tester);

    expect(find.text('Take now'), findsOneWidget);
    await tester.tap(find.text('Take now'));
    await pumpFrame(tester);

    final takenDose = await (db.select(
      db.medicineDoses,
    )..where((t) => t.id.equals(doseId))).getSingle();
    expect(takenDose.status, DoseStatus.taken);

    // Tap Undo in the hero card
    await tester.tap(find.text('Undo').first);
    await pumpFrame(tester);

    final revertedDose = await (db.select(
      db.medicineDoses,
    )..where((t) => t.id.equals(doseId))).getSingle();
    expect(revertedDose.status, DoseStatus.pending);

    await flushStreams(tester);
  });
}

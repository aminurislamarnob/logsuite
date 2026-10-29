import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:logsuite/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> tapNav(WidgetTester tester, String label) async {
    await tester.tap(find.byKey(ValueKey('nav-${label.toLowerCase()}')));
    await tester.pumpAndSettle();
  }

  Future<void> openModule(WidgetTester tester, String module) async {
    final card = find.byKey(ValueKey('module-$module'));
    await tester.scrollUntilVisible(
      card,
      -500,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(card);
    await tester.pumpAndSettle();
  }

  Future<void> returnToModules(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      if (find.text('Modules').evaluate().isNotEmpty) {
        break;
      }
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    }
    await tapNav(tester, 'Modules');
    expect(find.text('Modules'), findsOneWidget);
  }

  testWidgets('onboarding and core module workflows', (tester) async {
    app.main();
    await tester.pumpAndSettle();

    if (find.text('Your day, in one place.').evaluate().isNotEmpty) {
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
    }

    expect(find.text('My plans'), findsOneWidget);

    await tapNav(tester, 'Modules');
    expect(find.text('Notes'), findsWidgets);
    expect(find.text('Medicine'), findsWidgets);
    expect(find.text('Habits'), findsWidgets);
    expect(find.text('Tasks'), findsWidgets);
    expect(find.text('Expenses'), findsWidgets);
    expect(find.text('Focus'), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('Tasks').first,
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await openModule(tester, 'tasks');
    await tester.pumpAndSettle();
    expect(find.text('Tasks'), findsWidgets);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Upcoming'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('fab-new-task')));
    await tester.pumpAndSettle();
    expect(find.text('New task'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Review release');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Review release'), findsOneWidget);
    tester.binding.focusManager.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    await returnToModules(tester);
    await openModule(tester, 'notes');
    expect(find.byKey(const ValueKey('fab-new-note')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('fab-new-note')));
    await tester.pumpAndSettle();
    expect(find.text('New note'), findsWidgets);
    await returnToModules(tester);

    await openModule(tester, 'habits');
    expect(find.text('Habits'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('button-add-habit')));
    await tester.pumpAndSettle();
    expect(find.text('New habit'), findsOneWidget);
    await returnToModules(tester);

    await openModule(tester, 'medicine');
    expect(find.text('Medicine'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('fab-add-medicine')));
    await tester.pumpAndSettle();
    expect(find.text('Add medicine'), findsOneWidget);
    await returnToModules(tester);

    await openModule(tester, 'expenses');
    expect(find.text('Expenses'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('fab-add-transaction')));
    await tester.pumpAndSettle();
    expect(find.text('Add expense'), findsOneWidget);
    await returnToModules(tester);

    await openModule(tester, 'focus');
    expect(find.text('Focus'), findsWidgets);
    expect(find.text('Pomodoro'), findsWidgets);
    await returnToModules(tester);

    await tapNav(tester, 'Insights');
    expect(find.text('Insights'), findsOneWidget);
    await tapNav(tester, 'Settings');
    expect(find.text('Settings'), findsOneWidget);
  });
}

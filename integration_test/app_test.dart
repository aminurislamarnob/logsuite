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
      if (find.byKey(const ValueKey('module-medicine')).evaluate().isNotEmpty) {
        break;
      }
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    }
    await tapNav(tester, 'Modules');
    expect(find.text('Modules'), findsWidgets);
  }

  testWidgets('onboarding and core module workflows', (tester) async {
    app.main();
    await tester.pumpAndSettle();

    if (find.text('Skip').evaluate().isNotEmpty) {
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
    }

    expect(find.text('TODAY'), findsOneWidget);

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
    expect(find.text('Add medicine'), findsWidgets);
    // Dynamic after-opening fields appear only for syrup, drops, and inhaler.
    final afterOpeningCard = find.byKey(const ValueKey('after-opening-card'));
    expect(afterOpeningCard, findsNothing);
    await tester.tap(find.text('Syrup'));
    await tester.pumpAndSettle();
    expect(afterOpeningCard, findsOneWidget);
    await tester.enterText(find.byType(EditableText).first, 'Napa Syrup');
    await tester.tap(
      find.descendant(of: afterOpeningCard, matching: find.text('Today')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: afterOpeningCard, matching: find.text('14d')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Use by '), findsOneWidget);
    await tester.tap(find.text('Save medicine'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Medicines'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Napa Syrup'), findsWidgets);
    expect(find.textContaining('use by'), findsWidgets);
    await returnToModules(tester);

    await openModule(tester, 'expenses');
    expect(find.text('Expenses'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('fab-add-transaction')));
    await tester.pumpAndSettle();
    expect(find.text('Add expense'), findsWidgets);
    await returnToModules(tester);

    await openModule(tester, 'focus');
    expect(find.text('Focus'), findsWidgets);
    expect(find.text('Pomodoro'), findsWidgets);
    await returnToModules(tester);

    await tapNav(tester, 'Insights');
    expect(find.text('Insights'), findsWidgets);
    await tapNav(tester, 'Settings');
    expect(find.text('Settings'), findsWidgets);
  });
}

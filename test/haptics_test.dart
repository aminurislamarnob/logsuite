import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:logsuite/core/settings/app_settings.dart';
import 'package:logsuite/core/theme/app_forui_theme.dart';
import 'package:logsuite/core/theme/app_icons.dart';
import 'package:logsuite/core/theme/app_theme.dart';
import 'package:logsuite/core/utils/haptics.dart';
import 'package:logsuite/core/widgets/brand.dart';
import 'package:logsuite/core/widgets/common.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<String> hapticCalls = [];

  setUp(() {
    hapticCalls.clear();
    AppHaptics.enabled = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        hapticCalls.add('${call.arguments ?? 'vibrate'}');
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('AppHaptics', () {
    test('fires expected platform haptic types when enabled', () async {
      await AppHaptics.tap();
      await AppHaptics.selection();
      await AppHaptics.medium();
      await AppHaptics.heavy();
      await AppHaptics.success();
      await AppHaptics.warning();
      await AppHaptics.error();

      expect(hapticCalls, [
        'HapticFeedbackType.lightImpact',
        'HapticFeedbackType.selectionClick',
        'HapticFeedbackType.mediumImpact',
        'HapticFeedbackType.heavyImpact',
        'HapticFeedbackType.mediumImpact',
        'HapticFeedbackType.heavyImpact',
        'vibrate',
      ]);
    });

    test('suppresses all haptic calls when disabled', () async {
      AppHaptics.enabled = false;

      await AppHaptics.tap();
      await AppHaptics.selection();
      await AppHaptics.medium();
      await AppHaptics.heavy();
      await AppHaptics.success();
      await AppHaptics.warning();
      await AppHaptics.error();

      expect(hapticCalls, isEmpty);
    });
  });

  group('SettingsNotifier.setHapticsEnabled', () {
    test('persists hapticsEnabled and syncs AppHaptics.enabled', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = SettingsNotifier(prefs);

      expect(notifier.state.hapticsEnabled, isTrue);
      expect(AppHaptics.enabled, isTrue);

      notifier.setHapticsEnabled(false);
      expect(notifier.state.hapticsEnabled, isFalse);
      expect(AppHaptics.enabled, isFalse);
      expect(prefs.getBool('haptics_enabled'), isFalse);

      hapticCalls.clear();
      notifier.setHapticsEnabled(true);
      expect(notifier.state.hapticsEnabled, isTrue);
      expect(AppHaptics.enabled, isTrue);
      expect(prefs.getBool('haptics_enabled'), isTrue);
      // Turning haptics back on gives an immediate selection click preview
      await Future<void>.delayed(Duration.zero);
      expect(hapticCalls, ['HapticFeedbackType.selectionClick']);
    });
  });

  group('Widget Haptics', () {
    Widget wrap(Widget child) {
      return MaterialApp(
        theme: AppTheme.light(),
        builder: (context, c) => FTheme(
          data: brandForuiTheme(brightness: Brightness.light),
          child: Scaffold(body: Center(child: child)),
        ),
        home: const SizedBox.shrink(),
      );
    }

    testWidgets('BrandButton triggers tap and danger triggers heavy', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              BrandButton(label: 'Save', onPressed: () {}),
              BrandButton(
                label: 'Delete',
                kind: BrandButtonKind.danger,
                onPressed: () {},
              ),
            ],
          ),
        ),
      );

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(hapticCalls, ['HapticFeedbackType.lightImpact']);

      hapticCalls.clear();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(hapticCalls, ['HapticFeedbackType.heavyImpact']);
    });

    testWidgets('BrandCheckbox triggers success on check and selection on uncheck', (
      tester,
    ) async {
      bool checked = false;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => wrap(
            BrandCheckbox(
              value: checked,
              onChanged: (v) => setState(() => checked = v),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(BrandCheckbox));
      await tester.pumpAndSettle();
      expect(checked, isTrue);
      expect(hapticCalls, ['HapticFeedbackType.mediumImpact']);

      hapticCalls.clear();
      await tester.tap(find.byType(BrandCheckbox));
      await tester.pumpAndSettle();
      expect(checked, isFalse);
      expect(hapticCalls, ['HapticFeedbackType.selectionClick']);
    });

    testWidgets('Pill and CircleIconButton trigger haptics on tap', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Pill(label: 'Filter', color: Colors.orange, onTap: () {}),
              CircleIconButton(
                icon: AppIcons.add,
                tooltip: 'Add item',
                onPressed: () {},
              ),
            ],
          ),
        ),
      );

      await tester.tap(find.text('Filter'));
      await tester.pumpAndSettle();
      expect(hapticCalls, ['HapticFeedbackType.selectionClick']);

      hapticCalls.clear();
      await tester.tap(find.byKey(const ValueKey('button-add-item')));
      await tester.pumpAndSettle();
      expect(hapticCalls, ['HapticFeedbackType.lightImpact']);
    });
  });
}

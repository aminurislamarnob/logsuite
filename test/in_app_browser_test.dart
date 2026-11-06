import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:logsuite/core/database/app_database.dart';
import 'package:logsuite/core/theme/app_forui_theme.dart';
import 'package:logsuite/core/theme/app_palette.dart';
import 'package:logsuite/core/theme/app_theme.dart';
import 'package:logsuite/core/widgets/in_app_browser.dart';
import 'package:logsuite/presentation/drop/models/drop_with_tags.dart';
import 'package:logsuite/presentation/drop/widgets/drop_card.dart';

Widget _wrapWithTheme(Widget child) {
  final material = AppTheme.light(
    palette: AppPalette.coral,
    compact: false,
  );
  final forui = brandForuiTheme(
    brightness: Brightness.light,
    palette: AppPalette.coral,
    compact: false,
    locale: 'en',
  );
  return MaterialApp(
    theme: material,
    builder: (context, inner) => FTheme(
      data: forui,
      child: FToaster(child: inner!),
    ),
    home: child,
  );
}

void main() {
  group('InAppBrowserScreen.normalizeUrl', () {
    test('extracts https URL from mixed text', () {
      expect(
        InAppBrowserScreen.normalizeUrl(
          'Read this article https://www.linkedin.com/pulse/flutter-news now',
        ),
        'https://www.linkedin.com/pulse/flutter-news',
      );
    });

    test('prepends https:// when scheme is omitted', () {
      expect(
        InAppBrowserScreen.normalizeUrl('example.com/article'),
        'https://example.com/article',
      );
    });

    test('extracts http URL with port and query params', () {
      expect(
        InAppBrowserScreen.normalizeUrl('http://localhost:8080/test?user=1&ref=app'),
        'http://localhost:8080/test?user=1&ref=app',
      );
    });

    test('returns null for empty string or whitespace', () {
      expect(InAppBrowserScreen.normalizeUrl('   '), isNull);
      expect(InAppBrowserScreen.normalizeUrl(''), isNull);
    });
  });

  group('InAppBrowserScreen widget', () {
    testWidgets(
      'renders Facebook/LinkedIn style header, domain, and external browser options',
      (tester) async {
        await tester.pumpWidget(
          _wrapWithTheme(
            const InAppBrowserScreen(
              initialUrl: 'https://www.flutter.dev/docs',
              initialTitle: 'Flutter Documentation',
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Shows initial title and stripped domain in header
        expect(find.text('Flutter Documentation'), findsWidgets);
        expect(find.text('flutter.dev'), findsOneWidget);

        // Has top and bottom external browser buttons and close button
        expect(
          find.byKey(const Key('in_app_browser_open_external_top')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('in_app_browser_open_external_bottom')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('in_app_browser_close')), findsOneWidget);

        // Has bottom navigation bar controls
        expect(find.byKey(const Key('in_app_browser_back')), findsOneWidget);
        expect(find.byKey(const Key('in_app_browser_forward')), findsOneWidget);
        expect(find.byKey(const Key('in_app_browser_reload')), findsOneWidget);
        expect(find.byKey(const Key('in_app_browser_share')), findsOneWidget);

        // Opening the '...' menu reveals 'Open in external browser' option
        await tester.tap(find.byKey(const Key('in_app_browser_more')));
        await tester.pumpAndSettle();

        expect(find.text('Open in external browser'), findsOneWidget);
        expect(find.text('Reload page'), findsOneWidget);
        expect(find.text('Copy link'), findsOneWidget);
        expect(find.text('Share link'), findsOneWidget);
      },
    );

    testWidgets('InAppBrowserScreen.open pushes in-app browser route', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapWithTheme(
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => InAppBrowserScreen.open(
                    context,
                    'https://github.com/flutter/flutter',
                    initialTitle: 'Flutter Repo',
                  ),
                  child: const Text('Open Link'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Link'));
      await tester.pumpAndSettle();

      expect(find.byType(InAppBrowserScreen), findsOneWidget);
      expect(find.text('Flutter Repo'), findsWidgets);
      expect(find.text('github.com'), findsOneWidget);

      // Closing returns to the previous screen
      await tester.tap(find.byKey(const Key('in_app_browser_close')));
      await tester.pumpAndSettle();

      expect(find.byType(InAppBrowserScreen), findsNothing);
    });

    testWidgets('DropCard primary tap opens InAppBrowserScreen for article drops', (
      tester,
    ) async {
      final dropItem = DropWithTags(
        drop: Drop(
          id: 42,
          content: 'https://news.ycombinator.com',
          title: 'Hacker News',
          description: 'Tech discussions',
          assetType: 'article',
          triageStatus: 'inbox',
          isPinned: false,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        tags: const ['tech', 'news'],
      );

      await tester.pumpWidget(
        ProviderScope(
          child: _wrapWithTheme(
            Scaffold(
              body: DropCard(item: dropItem),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap the drop card
      await tester.tap(find.text('Hacker News'));
      await tester.pumpAndSettle();

      // Verify InAppBrowserScreen opened with URL and title
      expect(find.byType(InAppBrowserScreen), findsOneWidget);
      expect(find.text('Hacker News'), findsWidgets);
      expect(find.text('news.ycombinator.com'), findsOneWidget);
    });
  });
}

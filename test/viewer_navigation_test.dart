import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veloxmd/screens/viewer_screen.dart';
import 'package:veloxmd/services/font_service.dart';
import 'package:veloxmd/services/keybindings_service.dart';
import 'package:veloxmd/widgets/markdown_viewer.dart';
import 'package:veloxmd/widgets/toc_panel.dart';

void main() {
  late Directory tempDir;
  late KeybindingsService keybindings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in ['window_manager', 'desktop_drop']) {
      messenger.setMockMethodCallHandler(
        MethodChannel(channel),
        (call) async => call.method == 'isAlwaysOnTop' ? false : null,
      );
    }
    keybindings = await KeybindingsService.load();
    tempDir = await Directory.systemTemp.createTemp('veloxmd_nav_');
    final filler = List.filled(400, 'filler').join(' ');
    await File(p.join(tempDir.path, 'a.md')).writeAsString(
      '# Doc A\n\n[to B](b.md#details) [missing](nope.md) [down](#end)\n\n'
      '$filler\n\n## End\n\nbottom\n',
    );
    await File(p.join(tempDir.path, 'b.md')).writeAsString(
      '# Doc B\n\n$filler\n\n## Details\n\nB details\n',
    );
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  /// Pumps frames while letting real file I/O complete.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      // Bounded pumps: a loading spinner would make pumpAndSettle time out.
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  void tapLink(WidgetTester tester, String text) {
    for (final w in tester.widgetList<SelectableText>(
      find.byType(SelectableText),
    )) {
      TapGestureRecognizer? recognizer;
      w.textSpan?.visitChildren((span) {
        if (span is TextSpan &&
            span.text == text &&
            span.recognizer is TapGestureRecognizer) {
          recognizer = span.recognizer! as TapGestureRecognizer;
          return false;
        }
        return true;
      });
      if (recognizer != null) {
        recognizer!.onTap!();
        return;
      }
    }
    fail('No link "$text" found');
  }

  /// Taps a link and lets the real file I/O it triggers complete.
  Future<void> followLink(WidgetTester tester, String text) async {
    await tester.runAsync(() async {
      tapLink(tester, text);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await settle(tester);
  }

  ScrollPosition docScroll(WidgetTester tester) => tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byType(MarkdownViewer),
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position;

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: ViewerScreen(
            initialFile: p.join(tempDir.path, 'a.md'),
            themeMode: ThemeMode.light,
            onThemeModeChanged: (_) {},
            keybindings: keybindings,
            fonts: const FontConfig(
              uiFontFamily: 'Inter',
              codeFontFamily: 'FiraCode',
            ),
          ),
        ),
      );
    });
    await settle(tester);
  }

  IconButton backButton(WidgetTester tester) => tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.arrow_back),
      );

  testWidgets('document link opens target at anchor; Back restores', (
    tester,
  ) async {
    await pumpScreen(tester);
    expect(find.widgetWithText(AppBar, 'a.md'), findsOneWidget);
    expect(backButton(tester).onPressed, isNull);

    await followLink(tester, 'to B');

    expect(find.widgetWithText(AppBar, 'b.md'), findsOneWidget);
    expect(docScroll(tester).pixels, greaterThan(0));
    expect(backButton(tester).onPressed, isNotNull);

    await tester.tap(find.widgetWithIcon(IconButton, Icons.arrow_back));
    await settle(tester);
    expect(find.widgetWithText(AppBar, 'a.md'), findsOneWidget);
    expect(docScroll(tester).pixels, 0);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await settle(tester);
    expect(find.widgetWithText(AppBar, 'b.md'), findsOneWidget);
  });

  testWidgets('anchor link scrolls within the document and is undoable', (
    tester,
  ) async {
    await pumpScreen(tester);

    await followLink(tester, 'down');
    expect(docScroll(tester).pixels, greaterThan(0));

    await tester.tap(find.widgetWithIcon(IconButton, Icons.arrow_back));
    await settle(tester);
    expect(find.widgetWithText(AppBar, 'a.md'), findsOneWidget);
    expect(docScroll(tester).pixels, 0);
  });

  testWidgets('table of contents jump is undoable with Back', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byTooltip('Toggle Table of Contents (Ctrl+T)'));
    await settle(tester);
    await tester.tap(find.descendant(
      of: find.byType(TocPanel),
      matching: find.text('End'),
    ));
    await settle(tester);
    expect(docScroll(tester).pixels, greaterThan(0));

    await tester.tap(find.widgetWithIcon(IconButton, Icons.arrow_back));
    await settle(tester);
    expect(docScroll(tester).pixels, 0);
  });

  testWidgets('unreachable link shows a notice and keeps the document', (
    tester,
  ) async {
    await pumpScreen(tester);

    await followLink(tester, 'missing');

    expect(find.text('Link target not found: nope.md'), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'a.md'), findsOneWidget);
    expect(backButton(tester).onPressed, isNull);
  });
}

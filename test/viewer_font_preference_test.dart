import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veloxmd/screens/viewer_screen.dart';
import 'package:veloxmd/services/font_service.dart';
import 'package:veloxmd/services/keybindings_service.dart';
import 'package:veloxmd/widgets/markdown_viewer.dart';
import 'package:veloxmd/widgets/source_viewer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const preferenceKey = 'flutter.use_opendyslexic';
  const preferencesChannel =
      MethodChannel('plugins.flutter.io/shared_preferences');
  late Map<String, Object> stored;
  late Directory tempDir;
  late KeybindingsService keybindings;
  bool rejectWrite = false;
  bool throwWrite = false;
  Completer<void>? readGate;
  Completer<void>? writeGate;
  int writes = 0;

  setUp(() async {
    stored = {};
    rejectWrite = false;
    throwWrite = false;
    readGate = null;
    writeGate = null;
    writes = 0;
    SharedPreferences.resetStatic();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(preferencesChannel, (call) async {
      if (call.method == 'getAll') {
        await readGate?.future;
        return Map<String, Object>.of(stored);
      }
      if (call.method == 'setBool') {
        writes++;
        await writeGate?.future;
        if (throwWrite) {
          throw PlatformException(
              code: 'storage_error', message: 'Disk unavailable');
        }
        if (rejectWrite) return false;
        final arguments = call.arguments as Map<Object?, Object?>;
        stored[arguments['key']! as String] = arguments['value']! as bool;
        return true;
      }
      if (call.method == 'setDouble') {
        final arguments = call.arguments as Map<Object?, Object?>;
        stored[arguments['key']! as String] = arguments['value']! as double;
        return true;
      }
      throw StateError('Unexpected preference operation: ${call.method}');
    });
    for (final channel in ['window_manager', 'desktop_drop']) {
      messenger.setMockMethodCallHandler(
        MethodChannel(channel),
        (call) async => call.method == 'isAlwaysOnTop' ? false : null,
      );
    }
    keybindings = await KeybindingsService.load();
    tempDir = await Directory.systemTemp.createTemp('veloxmd_font_');
    await File('${tempDir.path}/document.md').writeAsString(
      '# Heading\n\nBody **bold** and *italic* with `code`.\n',
    );
  });

  tearDown(() async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(preferencesChannel, null);
    for (final channel in ['window_manager', 'desktop_drop']) {
      messenger.setMockMethodCallHandler(MethodChannel(channel), null);
    }
    SharedPreferences.resetStatic();
    await tempDir.delete(recursive: true);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    bool openDocument = true,
    ThemeMode themeMode = ThemeMode.light,
    ValueChanged<ThemeMode>? onThemeModeChanged,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Inter'),
        darkTheme: ThemeData.dark().copyWith(
          textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Inter'),
        ),
        themeMode: themeMode,
        home: ViewerScreen(
          initialFile: openDocument ? '${tempDir.path}/document.md' : null,
          themeMode: themeMode,
          onThemeModeChanged: onThemeModeChanged ?? (_) {},
          keybindings: keybindings,
          fonts: const FontConfig(
            uiFontFamily: 'Inter',
            codeFontFamily: 'FiraCode',
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Finder toggleFinder() => find.byWidgetPredicate(
        (widget) =>
            widget is IconButton &&
            (widget.tooltip?.contains('OpenDyslexic') ?? false),
      );

  IconButton toggle(WidgetTester tester) =>
      tester.widget<IconButton>(toggleFinder());

  void expectMarkdownFonts(WidgetTester tester, bool enabled) {
    final viewer = tester.widget<MarkdownViewer>(find.byType(MarkdownViewer));
    expect(viewer.bodyFontFamily, enabled ? 'OpenDyslexic' : 'Inter');
    expect(viewer.codeFontFamily, enabled ? 'OpenDyslexic' : 'FiraCode');
    expect(toggle(tester).isSelected, enabled);
    final semantics = tester.widget<Semantics>(
      find.ancestor(of: toggleFinder(), matching: find.byType(Semantics)).first,
    );
    expect(semantics.properties.toggled, enabled);
    final appBar = tester.element(find.byType(AppBar));
    expect(Theme.of(appBar).textTheme.bodyMedium?.fontFamily, 'Inter');
  }

  testWidgets('defaults off, toggles both views and restores original fonts',
      (tester) async {
    await pumpScreen(tester);
    expectMarkdownFonts(tester, false);

    await tester.tap(toggleFinder());
    await settle(tester);
    expectMarkdownFonts(tester, true);
    expect(stored[preferenceKey], true);

    await tester.tap(find.byTooltip('View document source (Ctrl+U)'));
    await tester.pump();
    final source = tester.widget<SourceViewer>(find.byType(SourceViewer));
    expect(source.codeFontFamily, 'OpenDyslexic');
    expect(tester.widget<Text>(find.text(source.content)).style?.fontFamily,
        'OpenDyslexic');

    await tester.tap(toggleFinder());
    await settle(tester);
    expect(stored[preferenceKey], false);
    expect(
        tester.widget<SourceViewer>(find.byType(SourceViewer)).codeFontFamily,
        'FiraCode');
    await tester.tap(find.byTooltip('Render markdown (Ctrl+U)'));
    await tester.pump();
    expectMarkdownFonts(tester, false);
  });

  for (final enabled in [true, false]) {
    testWidgets('restores persisted $enabled across recreation',
        (tester) async {
      stored[preferenceKey] = enabled;
      await pumpScreen(tester);
      expectMarkdownFonts(tester, enabled);
      await tester.tap(toggleFinder());
      await settle(tester);
      await tester.pumpWidget(const SizedBox());
      SharedPreferences.resetStatic();
      await pumpScreen(tester);
      expectMarkdownFonts(tester, !enabled);
    });
  }

  testWidgets('toggle is available without a document', (tester) async {
    await pumpScreen(tester, openDocument: false);
    expect(toggle(tester).onPressed, isNotNull);
    await tester.tap(toggleFinder());
    await settle(tester);
    expect(toggle(tester).isSelected, true);
    expect(stored[preferenceKey], true);
    await tester.pumpWidget(const SizedBox());
    await pumpScreen(tester);
    expectMarkdownFonts(tester, true);
  });

  testWidgets('blocks changes during load and survives disposal',
      (tester) async {
    readGate = Completer<void>();
    await pumpScreen(tester, openDocument: false);
    expect(toggle(tester).onPressed, isNull);
    await tester.pumpWidget(const SizedBox());
    readGate!.complete();
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(writes, 0);
  });

  testWidgets('serializes rapid toggles and survives disposal during save',
      (tester) async {
    await pumpScreen(tester);
    writeGate = Completer<void>();
    await tester.tap(toggleFinder());
    await tester.pump();
    expect(toggle(tester).onPressed, isNull);
    await tester.tap(toggleFinder(), warnIfMissed: false);
    await tester.pump();
    expect(writes, 1);
    await tester.pumpWidget(const SizedBox());
    writeGate!.complete();
    await settle(tester);
    expect(stored[preferenceKey], true);
    expect(tester.takeException(), isNull);
  });

  for (final throws in [false, true]) {
    testWidgets('failed save ($throws) rolls back and reports an error',
        (tester) async {
      await pumpScreen(tester);
      rejectWrite = !throws;
      throwWrite = throws;
      await tester.tap(toggleFinder());
      await settle(tester);
      expectMarkdownFonts(tester, false);
      expect(find.textContaining('Failed to save document font preference'),
          findsOneWidget);
      expect(stored.containsKey(preferenceKey), false);
      expect(toggle(tester).onPressed, isNotNull);
      await tester.pumpWidget(const SizedBox());
      await pumpScreen(tester);
      expectMarkdownFonts(tester, false);
    });
  }

  testWidgets('invalid stored preference is reported and can be replaced',
      (tester) async {
    stored[preferenceKey] = 'invalid';
    await pumpScreen(tester);
    expectMarkdownFonts(tester, false);
    expect(find.textContaining('Failed to load document font preference'),
        findsOneWidget);
    await tester.tap(toggleFinder());
    await settle(tester);
    expectMarkdownFonts(tester, true);
    expect(stored[preferenceKey], true);
  });

  testWidgets('theme and font scale changes retain selected fonts',
      (tester) async {
    stored[preferenceKey] = true;
    await pumpScreen(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.equal);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(tester);
    final scaled =
        tester.widget<MarkdownViewer>(find.byType(MarkdownViewer)).fontScale;
    expect(scaled, greaterThan(1));
    await pumpScreen(tester, themeMode: ThemeMode.dark);
    expectMarkdownFonts(tester, true);
    expect(tester.widget<MarkdownViewer>(find.byType(MarkdownViewer)).fontScale,
        scaled);
  });

  test('all font styles and license are available in the asset bundle',
      () async {
    const paths = [
      'assets/fonts/OpenDyslexic-Regular.otf',
      'assets/fonts/OpenDyslexic-Bold.otf',
      'assets/fonts/OpenDyslexic-Italic.otf',
      'assets/fonts/OpenDyslexic-Bold-Italic.otf',
    ];
    for (final path in paths) {
      final data = await rootBundle.load(path);
      expect(data.lengthInBytes, greaterThan(1000));
      expect(
          ascii.decode(data.buffer.asUint8List(data.offsetInBytes, 4)), 'OTTO');
    }
    final license =
        await rootBundle.loadString('assets/fonts/OFL-OpenDyslexic.txt');
    expect(license, contains('SIL OPEN FONT LICENSE Version 1.1'));
    expect(license, contains('Reserved Font Name OpenDyslexic'));
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    final family = manifest.cast<Map<String, dynamic>>().singleWhere(
          (entry) => entry['family'] == FontService.openDyslexicFontFamily,
        );
    expect(family['fonts'], [
      {'asset': paths[0], 'weight': 400},
      {'asset': paths[1], 'weight': 700},
      {'asset': paths[2], 'weight': 400, 'style': 'italic'},
      {'asset': paths[3], 'weight': 700, 'style': 'italic'},
    ]);
  });
}

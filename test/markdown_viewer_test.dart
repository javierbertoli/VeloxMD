import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veloxmd/widgets/markdown_viewer.dart';
import 'package:veloxmd/widgets/mermaid_view.dart';

void main() {
  testWidgets(
      'uses selected document font across Markdown and highlighted code',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.binding.setSurfaceSize(const Size(1200, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Inter'),
        home: Scaffold(
          body: MarkdownViewer(
            content: '''
# Heading

Plain **bold** *italic* ***both*** [link](https://example.com) and `inline`.

> Quote

- List item

| Column |
| ------ |
| Cell   |

```dart
void main() {}
```
''',
            scrollController: controller,
            basePath: '.',
            bodyFontFamily: 'OpenDyslexic',
            codeFontFamily: 'OpenDyslexic',
            searchQuery: 'bold',
          ),
        ),
      ),
    );
    final rendered = <String, TextStyle>{};
    void collect(InlineSpan span, TextStyle inherited) {
      if (span is! TextSpan) return;
      final style = inherited.merge(span.style);
      if (span.text != null && span.text!.trim().isNotEmpty) {
        rendered[span.text!] = style;
      }
      for (final child in span.children ?? <InlineSpan>[]) {
        collect(child, style);
      }
    }

    for (final element in find.byType(SelectableText).evaluate()) {
      final widget = element.widget as SelectableText;
      if (widget.textSpan != null) {
        collect(widget.textSpan!, widget.style ?? const TextStyle());
      }
    }
    for (final element in find.byType(Text).evaluate()) {
      final widget = element.widget as Text;
      if (widget.textSpan != null) {
        collect(widget.textSpan!, widget.style ?? const TextStyle());
      } else if (widget.data != null) {
        rendered[widget.data!] = widget.style ?? const TextStyle();
      }
    }
    for (final text in [
      'Heading',
      'Plain ',
      'bold',
      'italic',
      'both',
      'link',
      'inline',
      'Quote',
      'List item',
      'Column',
      'Cell',
      'void',
    ]) {
      expect(rendered[text]?.fontFamily, 'OpenDyslexic', reason: text);
    }
    final code = rendered.entries.where((entry) => entry.key.contains('main'));
    expect(code, isNotEmpty);
    for (final entry in code) {
      expect(entry.value.fontFamily, 'OpenDyslexic', reason: entry.key);
    }
    expect(rendered['bold']?.fontWeight, FontWeight.bold);
    expect(rendered['bold']?.backgroundColor, isNotNull);
    expect(rendered['italic']?.fontStyle, FontStyle.italic);
    expect(rendered['both']?.fontWeight, FontWeight.bold);
    expect(rendered['both']?.fontStyle, FontStyle.italic);
  });

  testWidgets('highlights search matches without changing their case', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownViewer(
            content: 'Hello world and WORLD.',
            scrollController: controller,
            basePath: '.',
            searchQuery: 'world',
          ),
        ),
      ),
    );

    final highlightedText = tester.widgetList<Text>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            (widget.data == 'world' || widget.data == 'WORLD') &&
            widget.style?.backgroundColor != null,
      ),
    );

    expect(highlightedText.map((text) => text.data), ['world', 'WORLD']);
  });

  testWidgets('keeps markdown formatting while highlighting matches', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownViewer(
            content: '**Search this text**',
            scrollController: controller,
            basePath: '.',
            searchQuery: 'this',
          ),
        ),
      ),
    );

    final match = tester.widget<Text>(find.text('this'));
    expect(match.style?.backgroundColor, isNotNull);
    expect(match.style?.fontWeight, FontWeight.bold);
  });

  testWidgets('uses high-contrast highlight colors in light theme', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownViewer(
            content: 'one two two',
            scrollController: controller,
            basePath: '.',
            searchQuery: 'two',
            activeMatchIndex: 1,
          ),
        ),
      ),
    );

    final matches = tester
        .widgetList<Text>(
          find.byWidgetPredicate(
            (widget) =>
                widget is Text &&
                widget.data == 'two' &&
                widget.style?.backgroundColor != null,
          ),
        )
        .toList();

    expect(matches, hasLength(2));
    expect(matches[0].style?.backgroundColor, const Color(0xFFFFFBA7));
    expect(matches[1].style?.backgroundColor, const Color(0xFFFFEA6C));
  });

  testWidgets('inverts text color in dark theme while highlighting', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: MarkdownViewer(
            content: 'Dark world test',
            scrollController: controller,
            basePath: '.',
            searchQuery: 'world',
          ),
        ),
      ),
    );

    final match = tester.widget<Text>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.data == 'world' &&
            widget.style?.backgroundColor != null,
      ),
    );

    expect(match.style?.backgroundColor, const Color(0xFF89D4FF));
    expect(match.style?.color, Colors.black);
  });

  testWidgets('preserves heading style when highlight matches a heading', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownViewer(
            content: '## Problema',
            scrollController: controller,
            basePath: '.',
            searchQuery: 'Problema',
          ),
        ),
      ),
    );

    final match = tester.widget<Text>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.data == 'Problema' &&
            widget.style?.backgroundColor != null,
      ),
    );

    expect(match.style?.backgroundColor, isNotNull);
    expect(match.style?.fontWeight, FontWeight.bold);
    expect(match.style?.fontSize, greaterThan(20));
  });

  testWidgets('active match index changes the highlighted occurrence', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    Future<List<Text>> pumpWithIndex(int activeMatchIndex) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarkdownViewer(
              content: 'banana apple banana grape banana',
              scrollController: controller,
              basePath: '.',
              searchQuery: 'banana',
              activeMatchIndex: activeMatchIndex,
            ),
          ),
        ),
      );
      await tester.pump();

      return tester
          .widgetList<Text>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Text &&
                  widget.data == 'banana' &&
                  widget.style?.backgroundColor != null,
            ),
          )
          .toList();
    }

    final firstState = await pumpWithIndex(0);
    expect(
      firstState
          .where(
            (text) => text.style?.backgroundColor == const Color(0xFFFFEA6C),
          )
          .length,
      1,
    );
    expect(
      firstState
          .where(
            (text) => text.style?.backgroundColor == const Color(0xFFFFFBA7),
          )
          .length,
      2,
    );

    final secondState = await pumpWithIndex(1);
    expect(
      secondState
          .where(
            (text) => text.style?.backgroundColor == const Color(0xFFFFEA6C),
          )
          .length,
      1,
    );
    expect(
      secondState
          .where(
            (text) => text.style?.backgroundColor == const Color(0xFFFFFBA7),
          )
          .length,
      2,
    );
  });

  testWidgets('updates highlight when query changes without theme toggle', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    Future<void> pumpWithQuery(String query) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarkdownViewer(
              content: 'Texto con Problema visible',
              scrollController: controller,
              basePath: '.',
              searchQuery: query,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    await pumpWithQuery('');
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.data == 'Problema' &&
            widget.style?.backgroundColor != null,
      ),
      findsNothing,
    );

    await pumpWithQuery('Problema');
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.data == 'Problema' &&
            widget.style?.backgroundColor != null,
      ),
      findsWidgets,
    );
  });

  test('buildViewerMarkdownStyleSheet scales font sizes', () {
    final theme = ThemeData.light().copyWith(
      textTheme: const TextTheme(bodyMedium: TextStyle(fontSize: 14)),
    );

    final normal = buildViewerMarkdownStyleSheet(
      theme,
      isDark: false,
      bodyFontFamily: 'Inter',
      codeFontFamily: 'FiraCode',
      fontScale: 1.0,
    );
    final zoomed = buildViewerMarkdownStyleSheet(
      theme,
      isDark: false,
      bodyFontFamily: 'Inter',
      codeFontFamily: 'FiraCode',
      fontScale: 1.5,
    );

    expect(normal.p?.fontSize, 16);
    expect(zoomed.p?.fontSize, 24);
    expect(normal.h1?.fontSize, 32);
    expect(zoomed.h1?.fontSize, 48);
    expect(normal.code?.fontSize, 13.5);
    expect(zoomed.code?.fontSize, 20.25);
    expect(normal.tableBody?.fontSize, 16);
    expect(zoomed.tableBody?.fontSize, 24);
    expect(normal.tableHead?.fontSize, 16);
    expect(zoomed.tableHead?.fontSize, 24);
  });

  testWidgets('renders plain fenced code blocks', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownViewer(
            content: '''
```dart
void main() {}
```
''',
            scrollController: controller,
            basePath: '.',
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.byType(SelectableHighlightView), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SelectionArea),
        matching: find.byType(SelectableHighlightView),
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is RichText &&
            widget.text.toPlainText().contains('void main() {}'),
      ),
      findsWidgets,
    );
  });

  testWidgets('uses syntax highlighting for multiple code languages', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownViewer(
            content: '''
```dart
void main() {}
```

```sql
SELECT 1;
```
''',
            scrollController: controller,
            basePath: '.',
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.byType(SelectableHighlightView), findsNWidgets(2));
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is RichText &&
            widget.text.toPlainText().contains('void main() {}'),
      ),
      findsWidgets,
    );
  });

  testWidgets('fenced code blocks scale font size with fontScale', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownViewer(
            content: '''
```dart
void main() {}
```
''',
            scrollController: controller,
            basePath: '.',
            fontScale: 2.0,
          ),
        ),
      ),
    );

    await tester.pump();

    final highlightView = tester
        .widget<SelectableHighlightView>(find.byType(SelectableHighlightView));
    expect(highlightView.textStyle?.fontSize, 27.0);
  });

  testWidgets('renders mermaid diagram blocks with selectable code block', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownViewer(
            content: '''
```mermaid
graph TD
  A --> B
```
''',
            scrollController: controller,
            basePath: '.',
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.byType(MermaidView), findsOneWidget);
    expect(find.byType(SelectableHighlightView), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SelectionArea),
        matching: find.byType(SelectableHighlightView),
      ),
      findsOneWidget,
    );
  });

  testWidgets('renders copy button on code block and updates icon on click', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownViewer(
            content: '''
```dart
print("Hello World");
```
''',
            scrollController: controller,
            basePath: '.',
          ),
        ),
      ),
    );

    await tester.pump();

    final copyButtonFinder = find.byIcon(Icons.copy);
    expect(copyButtonFinder, findsOneWidget);

    final tooltipFinder = find.byWidgetPredicate(
      (widget) => widget is Tooltip && widget.message == 'Copy to clipboard',
    );
    expect(tooltipFinder, findsOneWidget);
  });
}

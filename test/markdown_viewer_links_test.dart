import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veloxmd/models/toc_entry.dart';
import 'package:veloxmd/widgets/markdown_viewer.dart';

/// Long document: a paragraph per section so headings are far apart.
String _longDocument() {
  final buffer = StringBuffer('[Jump](#section-8)\n\n');
  for (var i = 0; i < 10; i++) {
    buffer.writeln('## Section $i\n');
    buffer.writeln('${List.filled(80, 'filler').join(' ')}\n');
  }
  return buffer.toString();
}

/// Invokes the tap recognizer of the link span whose text is [text]. The
/// viewer renders selectable text, so spans live in [SelectableText] widgets.
void tapLink(WidgetTester tester, String text) {
  final spans = tester
      .widgetList<SelectableText>(find.byType(SelectableText))
      .map((w) => w.textSpan)
      .whereType<TextSpan>();
  for (final root in spans) {
    TapGestureRecognizer? recognizer;
    root.visitChildren((span) {
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

void main() {
  Future<void> pumpViewer(
    WidgetTester tester, {
    required String content,
    required ScrollController controller,
    HeadingKeys? headingKeys,
    ValueChanged<String>? onLinkTap,
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownViewer(
            content: content,
            scrollController: controller,
            basePath: '.',
            headingKeys: headingKeys,
            onLinkTap: onLinkTap,
          ),
        ),
      ),
    );
  }

  testWidgets('forwards tapped link hrefs to onLinkTap', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final tapped = <String>[];

    await pumpViewer(
      tester,
      content: 'See [other](docs/other.md#setup) and [top](#intro).',
      controller: controller,
      onLinkTap: tapped.add,
    );

    tapLink(tester, 'other');
    tapLink(tester, 'top');
    expect(tapped, ['docs/other.md#setup', '#intro']);
  });

  testWidgets('registers each built heading under its TOC index', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final keys = HeadingKeys(controller);
    const content = 'Title\n=====\n\n> ## Quoted\n\n```\n# code\n```\n\n### Last\n';

    await pumpViewer(
      tester,
      content: content,
      controller: controller,
      headingKeys: keys,
    );

    final entries = TocEntry.fromMarkdown(content);
    expect(entries, hasLength(3));
    for (final entry in entries) {
      expect(keys.isBuilt(entry.index), isTrue);
    }
    expect(keys.isBuilt(entries.length), isFalse);
  });

  testWidgets('scrollTo reaches a heading the lazy list has not built yet', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final keys = HeadingKeys(controller);
    final content = _longDocument();
    final entries = TocEntry.fromMarkdown(content);

    await pumpViewer(
      tester,
      content: content,
      controller: controller,
      headingKeys: keys,
    );
    expect(controller.offset, 0);

    final entry = entries.firstWhere((e) => e.anchor == 'section-8');
    expect(keys.isBuilt(entry.index), isFalse);
    final reached =
        keys.scrollTo(entry.index, headingCount: entries.length);
    await tester.pumpAndSettle();
    expect(await reached, isTrue);
    await tester.pumpAndSettle();

    expect(controller.offset, greaterThan(0));
    final headingTop = tester.getTopLeft(find.text('Section 8')).dy;
    final viewerTop = tester.getTopLeft(find.byType(MarkdownViewer)).dy;
    expect(headingTop - viewerTop, inInclusiveRange(0, 40));
  });

  testWidgets('scrollTo returns false for unknown headings', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final keys = HeadingKeys(controller);

    await pumpViewer(
      tester,
      content: '# Only',
      controller: controller,
      headingKeys: keys,
    );

    expect(await keys.scrollTo(5, headingCount: 1), isFalse);
  });

  testWidgets('heading search highlight still works with heading markers', (
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
            headingKeys: HeadingKeys(controller),
          ),
        ),
      ),
    );

    final match = tester.widget<Text>(
      find.byWidgetPredicate(
        (w) => w is Text && w.data == 'Problema' && w.style?.backgroundColor != null,
      ),
    );
    expect(match.style?.fontWeight, FontWeight.bold);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veloxmd/services/keybindings_service.dart';
import 'package:veloxmd/widgets/source_viewer.dart';

void main() {
  group('SourceViewer', () {
    testWidgets('renders raw content accurately and unrendered',
        (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      const rawMarkdown = '# Title\n\n**Bold text** and `inline code`';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SourceViewer(
              content: rawMarkdown,
              scrollController: controller,
              codeFontFamily: 'monospace',
              fontScale: 1.0,
            ),
          ),
        ),
      );

      // Raw Markdown symbols should be rendered as plain text
      expect(find.text(rawMarkdown), findsOneWidget);
    });

    testWidgets('respects fontScale and padding', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      const content = 'Plain markdown test';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SourceViewer(
              content: content,
              scrollController: controller,
              horizontalPadding: 48.0,
              fontScale: 1.5,
            ),
          ),
        ),
      );

      final textWidget = tester.widget<Text>(find.text(content));
      expect(textWidget.style?.fontSize, 14.0 * 1.5);

      final singleScrollView = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );
      expect(
        singleScrollView.padding,
        const EdgeInsets.symmetric(horizontal: 48.0, vertical: 24.0),
      );
    });

    testWidgets('uses the selected family for selectable source text',
        (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SourceViewer(
              content: '# Source\n\n**Bold** and `code`',
              scrollController: controller,
              codeFontFamily: 'OpenDyslexic',
              fontScale: 1.5,
            ),
          ),
        ),
      );
      final text =
          tester.widget<Text>(find.text('# Source\n\n**Bold** and `code`'));
      expect(text.style?.fontFamily, 'OpenDyslexic');
      expect(text.style?.fontSize, 21);
      expect(find.byType(SelectionArea), findsOneWidget);
    });

    test('KeyAction.toggleViewSource defaults to ctrl+u', () async {
      final service = await KeybindingsService.load();
      expect(service.labels(KeyAction.toggleViewSource), contains('Ctrl+U'));
      final activators = service[KeyAction.toggleViewSource];
      expect(
        activators.any(
          (a) =>
              a.trigger == LogicalKeyboardKey.keyU &&
              a.control &&
              !a.shift &&
              !a.alt &&
              !a.meta,
        ),
        isTrue,
      );
    });
  });
}

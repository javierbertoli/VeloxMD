import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veloxmd/models/toc_entry.dart';
import 'package:veloxmd/widgets/toc_panel.dart';

void main() {
  testWidgets('shows an empty state when there are no headings', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: TocPanel(entries: const [], onEntrySelected: (_) {}),
          ),
        ),
      ),
    );

    expect(find.text('No headings found in this document.'), findsOneWidget);
  });

  testWidgets('renders entries from the markdown outline', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: TocPanel(
              entries: const [
                TocEntry(
                  title: 'Intro',
                  level: 1,
                  anchor: 'intro',
                  index: 0,
                ),
                TocEntry(
                  title: 'Details',
                  level: 2,
                  anchor: 'details',
                  index: 1,
                ),
              ],
              onEntrySelected: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Intro'), findsOneWidget);
    expect(find.text('Details'), findsOneWidget);
  });
}

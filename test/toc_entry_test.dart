import 'package:flutter_test/flutter_test.dart';
import 'package:veloxmd/models/toc_entry.dart';

void main() {
  group('TocEntry.fromMarkdown', () {
    test('returns empty list for content with no headings', () {
      final entries = TocEntry.fromMarkdown('Hello world\n\nParagraph text.');
      expect(entries, isEmpty);
    });

    test('parses ATX headings of all levels', () {
      const markdown = '''
# Title
## Section 1
### Subsection
## Section 2
#### Deep
''';
      final entries = TocEntry.fromMarkdown(markdown);
      expect(entries.length, 5);
      expect(entries[0].level, 1);
      expect(entries[0].title, 'Title');
      expect(entries[1].level, 2);
      expect(entries[1].title, 'Section 1');
      expect(entries[2].level, 3);
      expect(entries[2].title, 'Subsection');
      expect(entries[4].level, 4);
    });

    test('assigns sequential index values', () {
      const markdown = '# A\n## B\n### C\n';
      final entries = TocEntry.fromMarkdown(markdown);
      expect(entries.map((e) => e.index), orderedEquals([0, 1, 2]));
    });

    test('generates lowercase hyphenated anchors', () {
      const markdown = '# Hello World\n## My Section\n';
      final entries = TocEntry.fromMarkdown(markdown);
      expect(entries[0].anchor, 'hello-world');
      expect(entries[1].anchor, 'my-section');
    });

    test('parses indented ATX headings and strips closing hashes', () {
      const markdown = '   # Indented heading ###\n# Real heading\n';
      final entries = TocEntry.fromMarkdown(markdown);
      expect(entries.length, 2);
      expect(entries.first.title, 'Indented heading');
      expect(entries.first.anchor, 'indented-heading');
      expect(entries.last.title, 'Real heading');
    });

    test('suffixes repeated anchors GitHub-style', () {
      const markdown = '# Usage\n## Usage\n## Usage\n# Usage 1\n';
      final anchors = TocEntry.fromMarkdown(markdown).map((e) => e.anchor);
      expect(anchors, ['usage', 'usage-1', 'usage-2', 'usage-1-1']);
    });

    test('ignores headings inside fenced code blocks', () {
      const markdown = '# Real\n\n```\n# not a heading\n```\n\n## Also real\n';
      final entries = TocEntry.fromMarkdown(markdown);
      expect(entries.map((e) => e.title), ['Real', 'Also real']);
    });

    test('parses setext and nested headings in document order', () {
      const markdown = 'Setext\n======\n\n> ## Quoted\n\nSub\n---\n';
      final entries = TocEntry.fromMarkdown(markdown);
      expect(entries.map((e) => e.title), ['Setext', 'Quoted', 'Sub']);
      expect(entries.map((e) => e.level), [1, 2, 2]);
      expect(entries.map((e) => e.index), [0, 1, 2]);
    });

    test('uses rendered text for titles and anchors', () {
      final entry = TocEntry.fromMarkdown('# Use **bold** `code`\n').single;
      expect(entry.title, 'Use bold code');
      expect(entry.anchor, 'use-bold-code');
    });
  });

  group('TocEntry.slugify', () {
    test('drops punctuation, keeps letters, digits, _ and -', () {
      expect(TocEntry.slugify('What\'s new in v1.2?'), 'whats-new-in-v12');
      expect(TocEntry.slugify('snake_case & kebab-case'), 'snake_case--kebab-case');
    });

    test('keeps non-ASCII letters', () {
      expect(TocEntry.slugify('Configuración rápida'), 'configuración-rápida');
    });
  });
}

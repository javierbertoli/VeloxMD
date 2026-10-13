import 'package:markdown/markdown.dart' as md;

/// A single entry in the table of contents extracted from Markdown headings.
class TocEntry {
  const TocEntry({
    required this.title,
    required this.level,
    required this.anchor,
    required this.index,
  });

  /// Heading text.
  final String title;

  /// Heading level (1–6).
  final int level;

  /// GitHub-style Anchor slug, unique within the document (`-1`, `-2`, …
  /// suffixes for repeated headings).
  final String anchor;

  /// Zero-based occurrence index of the heading in render order. Matches the
  /// index used by the viewer's heading keys for precise scrolling.
  final int index;

  /// Parse all headings (ATX and setext, including those nested in lists or
  /// blockquotes) from [markdown] in document order. Headings inside code
  /// blocks are ignored, matching what the viewer renders.
  static List<TocEntry> fromMarkdown(String markdown) {
    if (markdown.isEmpty) return const [];
    final document = md.Document(
      extensionSet: md.ExtensionSet.gitHubFlavored,
      encodeHtml: false,
    );
    final nodes = document.parseLines(markdown.split(RegExp(r'\r?\n')));

    final entries = <TocEntry>[];
    final used = <String, int>{};

    void walk(List<md.Node> ns) {
      for (final node in ns) {
        if (node is! md.Element) continue;
        final level = _headingLevels[node.tag];
        if (level != null) {
          final title = node.textContent.trim();
          entries.add(TocEntry(
            title: title,
            level: level,
            anchor: _unique(slugify(title), used),
            index: entries.length,
          ));
        } else if (node.children != null) {
          walk(node.children!);
        }
      }
    }

    walk(nodes);
    return entries;
  }

  static const _headingLevels = {
    'h1': 1,
    'h2': 2,
    'h3': 3,
    'h4': 4,
    'h5': 5,
    'h6': 6,
  };

  /// GitHub-style slug: lowercase, drop everything except letters, marks,
  /// numbers, connector punctuation (`_`), spaces and hyphens, then turn each
  /// space into a hyphen.
  static String slugify(String text) => text
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{M}\p{N}\p{Pc} -]', unicode: true), '')
      .replaceAll(' ', '-');

  static String _unique(String slug, Map<String, int> used) {
    if (!used.containsKey(slug)) {
      used[slug] = 0;
      return slug;
    }
    var n = used[slug]!;
    String candidate;
    do {
      n++;
      candidate = '$slug-$n';
    } while (used.containsKey(candidate));
    used[slug] = n;
    used[candidate] = 0;
    return candidate;
  }

  @override
  String toString() => 'TocEntry(level: $level, title: $title)';
}

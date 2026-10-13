import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'dart:convert';

import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:highlight/highlight.dart' show highlight, Node;

import 'mermaid_view.dart';

/// Stable [GlobalKey]s for rendered ```mermaid``` diagrams, keyed by diagram
/// source + theme. Searching re-parses the whole document (to recolour the
/// highlights), which would otherwise recreate every widget and re-initialise
/// each diagram's CEF webview. Reusing a GlobalKey lets Flutter *reparent* the
/// existing [MermaidView] element instead of rebuilding it, so the diagrams
/// keep their state and do not flicker/reload on every keystroke.
final Map<String, GlobalKey> _mermaidViewKeys = <String, GlobalKey>{};

GlobalKey _mermaidViewKey(String source, bool isDark) =>
    _mermaidViewKeys.putIfAbsent(
      '${source.hashCode}:$isDark',
      () => GlobalKey(debugLabel: 'mermaid:${source.hashCode}:$isDark'),
    );

/// Drops the cached diagram keys. Call when switching to a different document
/// so keys for diagrams that no longer exist do not accumulate.
void clearMermaidViewKeyCache() => _mermaidViewKeys.clear();

/// Tracks the rendered headings, indexed in render order (the same order as
/// [TocEntry.index]), so the viewer can scroll precisely to a Heading when
/// following an Anchor link or a table-of-contents entry.
///
/// The document is a lazily built list: headings far from the viewport are
/// not built yet. [scrollTo] therefore jumps towards the heading until it is
/// built, then reveals it exactly.
class HeadingKeys {
  HeadingKeys(this.scrollController);

  final ScrollController scrollController;
  final Map<int, BuildContext> _built = <int, BuildContext>{};

  /// Whether heading [index] is currently built.
  bool isBuilt(int index) => _built[index]?.mounted ?? false;

  void _register(int index, BuildContext context) => _built[index] = context;

  void _unregister(int index, BuildContext context) {
    if (identical(_built[index], context)) _built.remove(index);
  }

  /// Scrolls so heading [index] (of [headingCount]) sits at the top of the
  /// viewport. Returns false when the heading cannot be reached.
  Future<bool> scrollTo(
    int index, {
    required int headingCount,
    bool animate = true,
  }) async {
    if (index < 0 || index >= headingCount) return false;
    for (var attempt = 0; attempt < 200; attempt++) {
      final context = _built[index];
      if (context != null && context.mounted) {
        return _reveal(context, animate: animate);
      }
      if (!scrollController.hasClients) return false;
      final position = scrollController.position;
      final double next;
      if (attempt == 0) {
        // First guess: assume headings are spread evenly.
        next = position.maxScrollExtent * index / headingCount;
      } else {
        final builtIndices = _built.keys;
        final step = position.viewportDimension * 0.9;
        final goDown = builtIndices.isEmpty ||
            builtIndices.every((built) => built < index);
        next = position.pixels + (goDown ? step : -step);
      }
      final clamped =
          next.clamp(position.minScrollExtent, position.maxScrollExtent);
      if (attempt > 0 && clamped == position.pixels) return false;
      position.jumpTo(clamped);
      await WidgetsBinding.instance.endOfFrame;
    }
    return false;
  }

  bool _reveal(BuildContext context, {required bool animate}) {
    final renderObject = context.findRenderObject();
    final viewport = renderObject == null
        ? null
        : RenderAbstractViewport.maybeOf(renderObject);
    if (renderObject == null || viewport == null) return false;

    final position = Scrollable.of(context).position;
    final marker = context.widget as _HeadingMarker;
    // The marker sits vertically centred on the heading's first line; back off
    // half a line plus a small gap so the whole heading is visible.
    final target = (viewport.getOffsetToReveal(renderObject, 0).offset -
            marker.lineHeight / 2 -
            8)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if (animate) {
      position.animateTo(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      position.jumpTo(target);
    }
    return true;
  }
}

/// The Markdown extension set used by the viewer. When [query] is non-empty a
/// [_SearchHighlightSyntax] is prepended so every match is wrapped in a
/// highlight element. Shared between the rendered widget and
/// [countHighlightMatches] so the visible highlights and the reported match
/// count are guaranteed to agree.
md.ExtensionSet buildMarkdownExtensionSet(String query) => md.ExtensionSet(
      <md.BlockSyntax>[
        const _MermaidFenceSyntax(),
        const _CodeFenceSyntax(),
        ...md.ExtensionSet.gitHubFlavored.blockSyntaxes,
        // Same detection as the standard heading syntaxes (and therefore
        // TocEntry.fromMarkdown), but each heading gets a marker element so the
        // viewer can attach a scroll key to it. Extension syntaxes take
        // precedence over the standard ones.
        const _MarkedSetextHeaderSyntax(),
        const _MarkedHeaderSyntax(),
      ],
      <md.InlineSyntax>[
        if (query.isNotEmpty) _SearchHighlightSyntax(query),
        md.EmojiSyntax(),
        ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
      ],
    );

/// Counts how many occurrences of [query] would actually be highlighted in the
/// rendered [content]. Parses the document with the exact same extension set
/// the viewer uses and counts the emitted highlight elements, so matches inside
/// fenced code blocks (which are not inline-parsed) are correctly excluded and
/// the count matches what the user sees.
int countHighlightMatches(String content, String query) {
  final trimmed = query.trim();
  if (trimmed.isEmpty || content.isEmpty) return 0;

  final document = md.Document(
    extensionSet: buildMarkdownExtensionSet(trimmed),
    encodeHtml: false,
  );
  final nodes = document.parseLines(const LineSplitter().convert(content));

  var count = 0;
  void walk(List<md.Node> ns) {
    for (final node in ns) {
      if (node is md.Element) {
        if (node.tag == _SearchHighlightSyntax.tag) count++;
        final children = node.children;
        if (children != null) walk(children);
      }
    }
  }

  walk(nodes);
  return count;
}

MarkdownStyleSheet buildViewerMarkdownStyleSheet(
  ThemeData theme, {
  required bool isDark,
  String? bodyFontFamily,
  String? codeFontFamily,
  required double fontScale,
}) {
  final codeFont = TextStyle(
    fontFamily: codeFontFamily ?? 'monospace',
    fontSize: 13.5 * fontScale,
  );
  final bodyFont = bodyFontFamily == null
      ? const TextStyle()
      : TextStyle(fontFamily: bodyFontFamily);

  final codeBg = isDark
      ? theme.colorScheme.surfaceContainerHighest
      : const Color(0xFFF6F8FA);
  final blockquoteBorderColor = isDark
      ? theme.colorScheme.primary.withOpacity(0.6)
      : theme.colorScheme.primary;

  return MarkdownStyleSheet.fromTheme(theme).copyWith(
    p: bodyFont.copyWith(
      fontSize: 16 * fontScale,
      height: 1.7,
      color: theme.colorScheme.onSurface,
    ),
    h1: bodyFont.copyWith(
      fontSize: 32 * fontScale,
      fontWeight: FontWeight.bold,
      color: theme.colorScheme.onSurface,
    ),
    h2: bodyFont.copyWith(
      fontSize: 26 * fontScale,
      fontWeight: FontWeight.bold,
      color: theme.colorScheme.onSurface,
    ),
    h3: bodyFont.copyWith(
      fontSize: 22 * fontScale,
      fontWeight: FontWeight.bold,
      color: theme.colorScheme.onSurface,
    ),
    h4: bodyFont.copyWith(
      fontSize: 18 * fontScale,
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.onSurface,
    ),
    h5: bodyFont.copyWith(
      fontSize: 16 * fontScale,
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.onSurface,
    ),
    h6: bodyFont.copyWith(
      fontSize: 14 * fontScale,
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.onSurfaceVariant,
    ),
    code: codeFont.copyWith(
      backgroundColor: codeBg,
      color: isDark ? theme.colorScheme.primary : const Color(0xFFD63200),
    ),
    codeblockDecoration: BoxDecoration(
      color: codeBg,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: theme.colorScheme.outlineVariant, width: 1),
    ),
    codeblockPadding: const EdgeInsets.all(16),
    blockquoteDecoration: BoxDecoration(
      border: Border(
        left: BorderSide(color: blockquoteBorderColor, width: 4),
      ),
      color: blockquoteBorderColor.withOpacity(0.08),
    ),
    blockquotePadding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(
        top: BorderSide(color: theme.colorScheme.outlineVariant, width: 1),
      ),
    ),
    tableHead: bodyFont.copyWith(
      fontSize: 16 * fontScale,
      fontWeight: FontWeight.bold,
    ),
    tableBody: bodyFont.copyWith(fontSize: 16 * fontScale),
    tableBorder: TableBorder.all(
      color: theme.colorScheme.outlineVariant,
      width: 1,
    ),
    tableHeadAlign: TextAlign.left,
    a: bodyFont.copyWith(
      color: theme.colorScheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: theme.colorScheme.primary.withOpacity(0.5),
    ),
    listBullet: bodyFont.copyWith(
      fontSize: 16 * fontScale,
      color: theme.colorScheme.primary,
    ),
  );
}

/// A custom syntax-highlighted code block widget that uses [Text.rich]
/// to register itself with the ambient [SelectionArea] and support text selection.
class SelectableHighlightView extends StatelessWidget {
  SelectableHighlightView(
    String input, {
    super.key,
    this.language,
    this.theme = const {},
    this.padding,
    this.textStyle,
    int tabSize = 8,
  }) : source = input.replaceAll('\t', ' ' * tabSize);

  final String source;
  final String? language;
  final Map<String, TextStyle> theme;
  final EdgeInsetsGeometry? padding;
  final TextStyle? textStyle;

  List<TextSpan> _convert(List<Node> nodes) {
    final spans = <TextSpan>[];
    var currentSpans = spans;
    final stack = <List<TextSpan>>[];

    void traverse(Node node) {
      if (node.value != null) {
        currentSpans.add(node.className == null
            ? TextSpan(text: node.value)
            : TextSpan(text: node.value, style: theme[node.className!]));
      } else if (node.children != null) {
        final tmp = <TextSpan>[];
        currentSpans.add(TextSpan(children: tmp, style: theme[node.className!]));
        stack.add(currentSpans);
        currentSpans = tmp;

        for (final n in node.children!) {
          traverse(n);
          if (n == node.children!.last) {
            currentSpans = stack.isEmpty ? spans : stack.removeLast();
          }
        }
      }
    }

    for (final node in nodes) {
      traverse(node);
    }

    return spans;
  }

  static const _rootKey = 'root';
  static const _defaultFontColor = Color(0xff000000);
  static const _defaultBackgroundColor = Color(0xffffffff);
  static const _defaultFontFamily = 'monospace';

  @override
  Widget build(BuildContext context) {
    var effectiveTextStyle = TextStyle(
      fontFamily: _defaultFontFamily,
      color: theme[_rootKey]?.color ?? _defaultFontColor,
    );
    if (textStyle != null) {
      effectiveTextStyle = effectiveTextStyle.merge(textStyle);
    }

    return Container(
      color: theme[_rootKey]?.backgroundColor ?? _defaultBackgroundColor,
      padding: padding,
      width: double.infinity,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text.rich(
          TextSpan(
            style: effectiveTextStyle,
            children: _convert(highlight.parse(source, language: language).nodes ?? []),
          ),
        ),
      ),
    );
  }
}

/// Renders fenced code blocks with syntax highlighting via SelectableHighlightView.
class _CodeBlockBuilder extends MarkdownElementBuilder {
  _CodeBlockBuilder({
    required this.isDark,
    required this.codeBackground,
    required this.codeForeground,
    required this.codeFontFamily,
    required this.fontScale,
  });

  final bool isDark;
  final Color codeBackground;
  final Color codeForeground;
  final String codeFontFamily;
  final double fontScale;

  @override
  bool isBlockElement() => true;

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final code = (element.attributes['content'] ?? '').trimRight();
    if (code.isEmpty) return const SizedBox.shrink();

    final language = _normalizeCodeLanguage(element.attributes['language']);
    final baseFontSize =
        preferredStyle?.fontSize ?? parentStyle?.fontSize ?? 13.5;
    final effectiveFontSize = baseFontSize * fontScale;
    final effectiveFontFamily =
        (preferredStyle ?? parentStyle)?.fontFamily ?? codeFontFamily;
    final textStyle = (preferredStyle ?? parentStyle ?? const TextStyle())
        .copyWith(
          color: codeForeground,
          fontFamily: effectiveFontFamily,
          fontSize: effectiveFontSize,
        );
    final theme = Map<String, TextStyle>.from(
      isDark ? monokaiSublimeTheme : githubTheme,
    ).map(
      (token, style) => MapEntry(
        token,
        style.copyWith(
          fontFamily: effectiveFontFamily,
          fontSize: effectiveFontSize,
        ),
      ),
    );
    final rootStyle = (theme['root'] ?? const TextStyle()).copyWith(
      backgroundColor: Colors.transparent,
      color: codeForeground,
    );
    theme['root'] = rootStyle;

    return _CodeBlockContainer(
      code: code,
      language: language,
      theme: theme,
      codeBackground: codeBackground,
      codeForeground: codeForeground,
      textStyle: textStyle,
    );
  }
}

/// Container for code blocks that includes syntax highlighting via [SelectableHighlightView]
/// and a copy-to-clipboard button in the top-right corner.
class _CodeBlockContainer extends StatefulWidget {
  const _CodeBlockContainer({
    required this.code,
    required this.language,
    required this.theme,
    required this.codeBackground,
    required this.codeForeground,
    this.textStyle,
  });

  final String code;
  final String language;
  final Map<String, TextStyle> theme;
  final Color codeBackground;
  final Color codeForeground;
  final TextStyle? textStyle;

  @override
  State<_CodeBlockContainer> createState() => _CodeBlockContainerState();
}

class _CodeBlockContainerState extends State<_CodeBlockContainer> {
  bool _copied = false;

  Future<void> _copyToClipboard() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    setState(() => _copied = true);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard!'),
        duration: Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
        width: 200,
      ),
    );
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final outlineColor = Theme.of(context).colorScheme.outlineVariant;
    final buttonBg = _copied
        ? const Color(0xFF2EA043).withOpacity(0.15)
        : widget.codeForeground.withOpacity(0.08);
    final iconColor = _copied
        ? const Color(0xFF2EA043)
        : widget.codeForeground.withOpacity(0.7);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 4),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: widget.codeBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: outlineColor,
          width: 1,
        ),
      ),
      child: Stack(
        children: [
          SelectionArea(
            child: SelectableHighlightView(
              widget.code,
              language: widget.language,
              theme: widget.theme,
              padding: const EdgeInsets.fromLTRB(16, 16, 48, 16),
              textStyle: widget.textStyle,
            ),
          ),
          Positioned(
            top: 6,
            right: 6,
            child: Tooltip(
              message: _copied ? 'Copied!' : 'Copy to clipboard',
              child: Material(
                color: buttonBg,
                borderRadius: BorderRadius.circular(6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: _copyToClipboard,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      _copied ? Icons.check : Icons.copy,
                      size: 14,
                      color: iconColor,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _normalizeCodeLanguage(String? info) {
  final trimmed = info?.trim() ?? '';
  if (trimmed.isEmpty) return 'plaintext';
  final raw = trimmed.split(RegExp(r'\s+')).first.toLowerCase();
  return switch (raw) {
    'sh' || 'shell' || 'zsh' => 'bash',
    'js' => 'javascript',
    'ts' => 'typescript',
    'yml' => 'yaml',
    'text' || 'plain' || 'plaintext' => 'plaintext',
    _ => raw,
  };
}

/// A scrollable Markdown viewer with syntax-highlighted code blocks,
/// clickable links, ```mermaid``` diagram rendering, and image support
/// relative to [basePath].
///
/// Search matches are highlighted inline. [activeMatchIndex] marks the
/// currently focused occurrence with a distinct color and scrolls it into
/// view. [horizontalPadding] controls the left/right content margin.
class MarkdownViewer extends StatelessWidget {
  const MarkdownViewer({
    super.key,
    required this.content,
    required this.scrollController,
    required this.basePath,
    this.searchQuery = '',
    this.activeMatchIndex = 0,
    this.bodyFontFamily,
    this.codeFontFamily,
    this.horizontalPadding = 32,
    this.fontScale = 1.0,
    this.headingKeys,
    this.onLinkTap,
  });

  final String content;
  final ScrollController scrollController;
  final String basePath;
  final String searchQuery;
  final int activeMatchIndex;

  /// Body text font family, e.g. the desktop's detected sans-serif font.
  /// Null uses the ambient [Theme]'s default (no override).
  final String? bodyFontFamily;

  /// Code block font family, e.g. the desktop's detected monospace font.
  /// Null falls back to the platform's generic `monospace`.
  final String? codeFontFamily;
  final double horizontalPadding;
  final double fontScale;

  /// Receives a key per rendered heading, for precise Anchor scrolling.
  final HeadingKeys? headingKeys;

  /// Called with the raw href of a tapped Link. When null, links are handed
  /// straight to the system (url_launcher).
  final ValueChanged<String>? onLinkTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final query = searchQuery.trim();
    // Light mode: warm yellow highlight, keeping the default (dark) text color.
    // Dark mode: blue highlight with an inverted (dark) text color for contrast.
    final matchBackgroundColor = isDark
        ? const Color(0xFF44ACFF)
        : const Color(0xFFFFFBA7);
    final activeMatchBackgroundColor = isDark
        ? const Color(0xFF89D4FF)
        : const Color(0xFFFFEA6C);
    // In dark mode invert the text color so it stays legible over the blue
    // highlight; in light mode keep the document's own foreground (null).
    final matchForegroundColor = isDark ? Colors.black : null;
    final codeBackground = isDark
        ? theme.colorScheme.surfaceContainerHighest
        : const Color(0xFFF6F8FA);

    return Markdown(
      key: ValueKey<String>(searchQuery.trim()),
      controller: scrollController,
      data: content,
      selectable: true,
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: 24,
      ),
      imageDirectory: basePath,
      extensionSet: buildMarkdownExtensionSet(query),
      builders: <String, MarkdownElementBuilder>{
        'codeblock': _CodeBlockBuilder(
          isDark: isDark,
          codeBackground: codeBackground,
          codeForeground: theme.colorScheme.onSurface,
          codeFontFamily: codeFontFamily ?? 'monospace',
          fontScale: fontScale,
        ),
        'mermaid': _MermaidBlockBuilder(
          isDark: isDark,
          codeBackground: codeBackground,
          codeForeground: theme.colorScheme.onSurface,
          codeFontFamily: codeFontFamily ?? 'monospace',
          fontScale: fontScale,
        ),
        _headingMarkerTag: _HeadingMarkerBuilder(headingKeys),
        if (query.isNotEmpty)
          _SearchHighlightSyntax.tag: _SearchHighlightBuilder(
            backgroundColor: matchBackgroundColor,
            activeBackgroundColor: activeMatchBackgroundColor,
            foregroundColor: matchForegroundColor,
            activeMatchIndex: activeMatchIndex,
            scrollController: scrollController,
          ),
      },
      onTapLink: (text, href, title) async {
        if (href == null) return;
        if (onLinkTap != null) {
          onLinkTap!(href);
          return;
        }
        final uri = Uri.tryParse(href);
        if (uri != null && await canLaunchUrl(uri)) {
          await launchUrl(uri);
        }
      },
      styleSheet: _buildStyleSheet(context, isDark),
    );
  }

  MarkdownStyleSheet _buildStyleSheet(BuildContext context, bool isDark) {
    return buildViewerMarkdownStyleSheet(
      Theme.of(context),
      isDark: isDark,
      bodyFontFamily: bodyFontFamily,
      codeFontFamily: codeFontFamily,
      fontScale: fontScale,
    );
  }
}

/// Splits [text] into styled spans, applying a highlight background/foreground
/// to every case-insensitive occurrence of [query]. Exposed for unit testing.
TextSpan buildHighlightedTextSpan(
  String text,
  TextStyle? baseStyle,
  String query, {
  required Color highlightBackground,
  required Color highlightForeground,
}) {
  final trimmedQuery = query.trim();
  if (trimmedQuery.isEmpty || text.isEmpty) {
    return TextSpan(text: text, style: baseStyle);
  }

  final matches = RegExp(
    RegExp.escape(trimmedQuery),
    caseSensitive: false,
  ).allMatches(text);
  final spans = <InlineSpan>[];
  var lastIndex = 0;

  for (final match in matches) {
    if (match.start > lastIndex) {
      spans.add(TextSpan(
        text: text.substring(lastIndex, match.start),
        style: baseStyle,
      ));
    }

    spans.add(TextSpan(
      text: text.substring(match.start, match.end),
      style: baseStyle?.copyWith(
        backgroundColor: highlightBackground,
        color: highlightForeground,
      ),
    ));
    lastIndex = match.end;
  }

  if (spans.isEmpty) {
    return TextSpan(text: text, style: baseStyle);
  }

  if (lastIndex < text.length) {
    spans.add(TextSpan(
      text: text.substring(lastIndex),
      style: baseStyle,
    ));
  }

  return TextSpan(children: spans, style: baseStyle);
}

/// Inline syntax that wraps every search match in a [tag] element so it can be
/// rendered with a highlight by [_SearchHighlightBuilder].
class _SearchHighlightSyntax extends md.InlineSyntax {
  _SearchHighlightSyntax(String query)
      : super(RegExp.escape(query), caseSensitive: false);

  static const tag = 'search-highlight';

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text(tag, match[0]!));
    return true;
  }
}

const _headingMarkerTag = 'heading-marker';

/// Prepends an empty [_headingMarkerTag] element to a parsed heading.
T _markHeading<T extends md.Node?>(T node) {
  if (node is md.Element) {
    node.children?.insert(0, md.Element.empty(_headingMarkerTag));
  }
  return node;
}

class _MarkedHeaderSyntax extends md.HeaderSyntax {
  const _MarkedHeaderSyntax();

  @override
  md.Node parse(md.BlockParser parser) => _markHeading(super.parse(parser));
}

class _MarkedSetextHeaderSyntax extends md.SetextHeaderSyntax {
  const _MarkedSetextHeaderSyntax();

  @override
  md.Node? parse(md.BlockParser parser) => _markHeading(super.parse(parser));
}

/// Renders each heading marker as a zero-size [_HeadingMarker] registered
/// with [headingKeys], numbering headings in render order.
class _HeadingMarkerBuilder extends MarkdownElementBuilder {
  _HeadingMarkerBuilder(this.headingKeys);

  final HeadingKeys? headingKeys;
  int _headingIndex = 0;

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final style = parentStyle ?? preferredStyle;
    return _HeadingMarker(
      index: _headingIndex++,
      headingKeys: headingKeys,
      lineHeight: (style?.fontSize ?? 16) * (style?.height ?? 1.2),
    );
  }
}

class _HeadingMarker extends StatefulWidget {
  const _HeadingMarker({
    required this.index,
    required this.headingKeys,
    required this.lineHeight,
  });

  final int index;
  final HeadingKeys? headingKeys;
  final double lineHeight;

  @override
  State<_HeadingMarker> createState() => _HeadingMarkerState();
}

class _HeadingMarkerState extends State<_HeadingMarker> {
  @override
  void initState() {
    super.initState();
    widget.headingKeys?._register(widget.index, context);
  }

  @override
  void didUpdateWidget(_HeadingMarker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index ||
        oldWidget.headingKeys != widget.headingKeys) {
      oldWidget.headingKeys?._unregister(oldWidget.index, context);
      widget.headingKeys?._register(widget.index, context);
    }
  }

  @override
  void dispose() {
    widget.headingKeys?._unregister(widget.index, context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _MermaidFenceSyntax extends md.BlockSyntax {
  const _MermaidFenceSyntax();

  @override
  RegExp get pattern => const md.FencedCodeBlockSyntax().pattern;

  @override
  bool canParse(md.BlockParser parser) {
    final match = pattern.firstMatch(parser.current.content);
    if (match == null) return false;
    final info = (match.namedGroup('backtickInfo') ??
            match.namedGroup('tildeInfo') ??
            '')
        .trim();
    final language = info.split(' ').first;
    return language == 'mermaid';
  }

  @override
  md.Node? parse(md.BlockParser parser) {
    final match = pattern.firstMatch(parser.current.content);
    if (match == null) return null;

    final marker = match.namedGroup('backtick') ?? match.namedGroup('tilde');
    if (marker == null) return null;

    final indent = match[1]!.length;
    final childLines = const md.FencedCodeBlockSyntax().parseChildLines(
      parser,
      marker,
      indent,
    );

    var text = childLines.map((line) => line.content).join('\n');
    if (text.isNotEmpty) {
      text = '$text\n';
    }
    final element = md.Element.empty('mermaid');
    element.attributes['content'] = text;
    return element;
  }
}

class _CodeFenceSyntax extends md.BlockSyntax {
  const _CodeFenceSyntax();

  @override
  RegExp get pattern => const md.FencedCodeBlockSyntax().pattern;

  @override
  bool canParse(md.BlockParser parser) {
    final match = pattern.firstMatch(parser.current.content);
    if (match == null) return false;
    final info = (match.namedGroup('backtickInfo') ??
            match.namedGroup('tildeInfo') ??
            '')
        .trim();
    final language = info.split(RegExp(r'\s+')).first.toLowerCase();
    return language != 'mermaid';
  }

  @override
  md.Node? parse(md.BlockParser parser) {
    final openingFence = pattern.firstMatch(parser.current.content);
    if (openingFence == null) return null;

    final marker = openingFence.namedGroup('backtick') ??
        openingFence.namedGroup('tilde');
    if (marker == null) return null;

    final indent = openingFence[1]!.length;
    final childLines = const md.FencedCodeBlockSyntax().parseChildLines(
      parser,
      marker,
      indent,
    );

    final text = childLines.map((e) => e.content).join('\n');
    final element = md.Element.empty('codeblock');
    element.attributes['content'] = text;
    final info = (openingFence.namedGroup('backtickInfo') ??
            openingFence.namedGroup('tildeInfo') ??
            '')
        .trim();
    element.attributes['language'] = _normalizeCodeLanguage(info);
    return element;
  }
}

/// Renders a highlighted search match. The occurrence at [activeMatchIndex]
/// gets [activeBackgroundColor] and is scrolled into view; the rest use
/// [backgroundColor].
class _SearchHighlightBuilder extends MarkdownElementBuilder {
  _SearchHighlightBuilder({
    required this.backgroundColor,
    required this.activeBackgroundColor,
    required this.activeMatchIndex,
    required this.scrollController,
    this.foregroundColor,
  });

  final Color backgroundColor;
  final Color activeBackgroundColor;
  final Color? foregroundColor;
  final int activeMatchIndex;
  final ScrollController scrollController;
  int _matchIndex = 0;

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final currentMatchIndex = _matchIndex++;
    final isActive = currentMatchIndex == activeMatchIndex;

    if (isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!scrollController.hasClients) return;
        final context = _activeMatchKey.currentContext;
        if (context != null) {
          Scrollable.ensureVisible(
            context,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            alignment: 0.2,
          );
        }
      });
    }

    final baseStyle = preferredStyle ?? parentStyle ?? const TextStyle();

    return Text(
      key: isActive ? _activeMatchKey : null,
      element.textContent,
      // copyWith(color: null) keeps the base foreground, so light mode retains
      // the document's own text color while dark mode inverts it.
      style: baseStyle.copyWith(
        backgroundColor: isActive ? activeBackgroundColor : backgroundColor,
        color: foregroundColor,
      ),
    );
  }

  final GlobalKey _activeMatchKey = GlobalKey();
}

/// Renders Mermaid fenced code blocks as diagrams via [MermaidView].
class _MermaidBlockBuilder extends MarkdownElementBuilder {
  _MermaidBlockBuilder({
    required this.isDark,
    required this.codeBackground,
    required this.codeForeground,
    required this.codeFontFamily,
    required this.fontScale,
  });

  final bool isDark;
  final Color codeBackground;
  final Color codeForeground;
  final String codeFontFamily;
  final double fontScale;

  @override
  bool isBlockElement() => true;

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final code = decodeHtmlEntities(element.attributes['content'] ?? '')
        .trimRight();
    if (code.isEmpty) return const SizedBox.shrink();

    final baseFontSize =
        preferredStyle?.fontSize ?? parentStyle?.fontSize ?? 13.5;
    final effectiveFontSize = baseFontSize * fontScale;
    final effectiveFontFamily =
        (preferredStyle ?? parentStyle)?.fontFamily ?? codeFontFamily;
    final textStyle = (preferredStyle ?? parentStyle ?? const TextStyle())
        .copyWith(
          color: codeForeground,
          fontFamily: effectiveFontFamily,
          fontSize: effectiveFontSize,
        );
    final theme = Map<String, TextStyle>.from(
      isDark ? monokaiSublimeTheme : githubTheme,
    ).map(
      (token, style) => MapEntry(
        token,
        style.copyWith(
          fontFamily: effectiveFontFamily,
          fontSize: effectiveFontSize,
        ),
      ),
    );
    final rootStyle = (theme['root'] ?? const TextStyle()).copyWith(
      backgroundColor: Colors.transparent,
      color: codeForeground,
    );
    theme['root'] = rootStyle;

    final codeBlockWidget = _CodeBlockContainer(
      code: code,
      language: 'mermaid',
      theme: theme,
      codeBackground: codeBackground,
      codeForeground: codeForeground,
      textStyle: textStyle,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MermaidView(
          key: _mermaidViewKey(code, isDark),
          code: code,
          isDark: isDark,
          backgroundColor: codeBackground,
          foregroundColor: codeForeground,
          fontScale: fontScale,
          codeFontFamily: codeFontFamily,
        ),
        const SizedBox(height: 8),
        codeBlockWidget,
      ],
    );
  }
}

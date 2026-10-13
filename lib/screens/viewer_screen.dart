import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:window_manager/window_manager.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path/path.dart' as p;
import '../widgets/markdown_viewer.dart';
import '../widgets/source_viewer.dart';
import '../widgets/search_panel.dart';
import '../widgets/toc_panel.dart';
import '../widgets/document_footer.dart';
import '../dialogs/about_dialog.dart';
import '../models/toc_entry.dart';
import '../models/document_stats.dart';
import '../models/navigation_history.dart';
import '../services/file_service.dart';
import '../services/font_service.dart';
import '../services/keybindings_service.dart';
import '../services/link_resolver.dart';
import '../services/pdf_export_service.dart';

class ViewerScreen extends StatefulWidget {
  const ViewerScreen({
    super.key,
    this.initialFile,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.keybindings,
    required this.fonts,
  });

  final String? initialFile;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final KeybindingsService keybindings;
  final FontConfig fonts;

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> with WindowListener {
  String? _filePath;
  String _markdownContent = '';
  bool _isLoading = false;
  String? _errorMessage;
  bool _showSource = false;
  bool _tocVisible = false;
  List<TocEntry> _tocEntries = [];
  DocumentStats _stats = DocumentStats.fromMarkdown('');
  final String _version = VeloxAboutDialog.version;
  double _horizontalMargin = 32;
  static const double _minMargin = 0;
  static const double _maxMargin = 320;
  double _fontScale = 1.0;
  static const double _minFontScale = 0.5;
  static const double _maxFontScale = 3.0;
  static const double _fontScaleStep = 0.1;
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  int _activeMatchIndex = 0;
  int _matchCount = 0;
  StreamSubscription<FileSystemEvent>? _fileWatchSub;
  bool _isPickerOpen = false;
  bool _isExportingPdf = false;
  final _history = NavigationHistory();
  late final _headingKeys = HeadingKeys(_scrollController);

  /// Debounced search query actually applied to the rendered view and the match
  /// count. Typing updates the text field immediately, but re-parsing/rendering
  /// the whole document is deferred until the user pauses, avoiding a full
  /// re-parse on every keystroke on large documents.
  String _searchQuery = '';
  bool _searchVisible = false;
  Timer? _searchDebounce;
  static const Duration _searchDebounceDelay = Duration(milliseconds: 180);

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _loadMarginPreference();
    _loadFontScalePreference();
    if (widget.initialFile != null) {
      _openFile(widget.initialFile!);
    }
  }

  Future<void> _loadMarginPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getDouble('horizontal_margin');
    if (value != null && mounted) {
      setState(() => _horizontalMargin = value.clamp(_minMargin, _maxMargin));
    }
  }

  Future<void> _setHorizontalMargin(double value) async {
    final clamped = value.clamp(_minMargin, _maxMargin).toDouble();
    setState(() => _horizontalMargin = clamped);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('horizontal_margin', clamped);
  }

  Future<void> _loadFontScalePreference() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getDouble('font_scale');
    if (value != null && mounted) {
      setState(
        () => _fontScale = value.clamp(_minFontScale, _maxFontScale).toDouble(),
      );
    }
  }

  Future<void> _setFontScale(double value) async {
    final clamped = value.clamp(_minFontScale, _maxFontScale).toDouble();
    setState(() => _fontScale = clamped);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('font_scale', clamped);
  }

  Future<void> _changeFontScale(double delta) =>
      _setFontScale(_fontScale + delta);

  @override
  void dispose() {
    windowManager.removeListener(this);
    _fileWatchSub?.cancel();
    _searchDebounce?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // File handling
  // ---------------------------------------------------------------------------

  Future<void> _pickAndOpenFile() async {
    // Prevent multiple file picker dialogs from stacking when the button is
    // clicked repeatedly or the Ctrl+O shortcut fires while one is already open.
    if (_isPickerOpen) return;
    _isPickerOpen = true;

    try {
      String? selectedPath;
      var usedNativeChannel = false;

      if (Platform.isLinux) {
        try {
          const channel = MethodChannel('com.veloxmd/file_picker');
          selectedPath = await channel.invokeMethod<String>('pickFile');
          usedNativeChannel = true;
        } on MissingPluginException {
          usedNativeChannel = false;
        } catch (_) {
          usedNativeChannel = false;
        }
      }

      if (!usedNativeChannel) {
        final bool wasAlwaysOnTop = await windowManager.isAlwaysOnTop();
        if (wasAlwaysOnTop) {
          await windowManager.setAlwaysOnTop(false);
        }
        try {
          final result = await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: ['md', 'markdown', 'mdc', 'txt'],
            dialogTitle: 'Open Markdown file',
            lockParentWindow: true,
          );
          selectedPath = result?.files.single.path;
        } finally {
          if (wasAlwaysOnTop) {
            await windowManager.setAlwaysOnTop(true);
          }
          await windowManager.focus();
        }
      }

      if (selectedPath != null) {
        await _openFile(selectedPath);
      }
    } finally {
      _isPickerOpen = false;
    }
  }

  /// Opens [path] as a new Navigation History entry (file picker, drop,
  /// command line). Failures replace the view with an error screen.
  Future<void> _openFile(String path) => _navigateTo(path);

  /// Opens the Document at [path], optionally scrolling to [anchor], and
  /// pushes it onto the Navigation History when it loads. With [fromLink],
  /// failures are reported as a notice and the current Document stays open.
  Future<void> _navigateTo(
    String path, {
    String? anchor,
    bool fromLink = false,
  }) async {
    _rememberScroll();
    final loaded = await _loadDocument(
      path,
      anchor: anchor,
      reportErrorsAsNotice: fromLink,
    );
    if (loaded && mounted) setState(() => _history.visit(path));
  }

  Future<bool> _loadDocument(
    String path, {
    double scrollOffset = 0,
    String? anchor,
    bool reportErrorsAsNotice = false,
  }) async {
    if (!reportErrorsAsNotice) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final content = await FileService.readMarkdown(path);

      final statsFuture =
          Future.microtask(() => DocumentStats.fromMarkdown(content));
      // Full Markdown parse (must match what the viewer renders): run it off
      // the UI thread so large documents do not freeze the window.
      final tocFuture = compute(computeTocEntries, content);

      final stats = await statsFuture;
      final tocEntries = await tocFuture;

      if (!mounted) return false;

      // Different document: drop cached diagram keys from the previous file so
      // stale GlobalKeys do not accumulate across opens.
      if (path != _filePath) {
        clearMermaidViewKeyCache();
      }
      _watchFile(path);
      setState(() {
        _filePath = path;
        _markdownContent = content;
        _stats = stats;
        _isLoading = false;
        _errorMessage = null;
        _tocEntries = tocEntries;
        _recomputeMatchCount();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (anchor != null) {
          _scrollToAnchor(anchor, animate: false);
        } else {
          _jumpToOffset(scrollOffset);
        }
      });
      try {
        await windowManager.setTitle(p.basename(path));
      } catch (_) {}
      return true;
    } catch (e) {
      if (!mounted) return false;
      final message =
          e is FileServiceException ? e.message : 'Error opening file: $e';
      if (reportErrorsAsNotice) {
        _showNotice(message);
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = message;
        });
      }
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Links and Navigation History
  // ---------------------------------------------------------------------------

  Future<void> _onLinkTap(String href) async {
    final currentPath = _filePath;
    if (currentPath == null) return;
    final target = await LinkResolver.resolve(href, currentPath: currentPath);
    if (!mounted) return;

    switch (target) {
      case AnchorTarget(:final anchor):
        _followAnchor(anchor, href);
      case DocumentTarget(:final path, :final anchor):
        await _navigateTo(path, anchor: anchor, fromLink: true);
      case ExternalTarget(:final uri):
        var launched = false;
        try {
          launched = await launchUrl(uri);
        } on Exception {
          launched = false;
        }
        if (!launched) _showNotice('Could not open link: $href');
      case UnreachableTarget():
        _showNotice('Link target not found: $href');
    }
  }

  /// Follows an Anchor link in the current Document.
  void _followAnchor(String anchor, String href) {
    final entry = _findHeading(anchor);
    if (entry == null) {
      _showNotice('Link target not found: $href');
      return;
    }
    _jumpToHeading(entry);
  }

  /// Scrolls to [entry] as a new history entry (Anchor links and TOC).
  void _jumpToHeading(TocEntry entry) {
    if (_showSource) return;
    _rememberScroll();
    setState(() => _history.visit(_filePath!));
    _headingKeys.scrollTo(entry.index, headingCount: _tocEntries.length);
  }

  /// Scrolls to [anchor] without touching history. Reports a missing anchor.
  void _scrollToAnchor(String anchor, {bool animate = true}) {
    if (_showSource) return;
    final entry = _findHeading(anchor);
    if (entry == null) {
      _showNotice('Link target not found: #$anchor');
      return;
    }
    _headingKeys.scrollTo(
      entry.index,
      headingCount: _tocEntries.length,
      animate: animate,
    );
  }

  TocEntry? _findHeading(String anchor) {
    final wanted = anchor.toLowerCase();
    return _tocEntries.where((e) => e.anchor == wanted).firstOrNull;
  }

  void _rememberScroll() {
    if (_scrollController.hasClients) {
      _history.updateCurrentScroll(_scrollController.offset);
    }
  }

  void _jumpToOffset(double offset) {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    _scrollController.jumpTo(
      offset.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
  }

  Future<void> _goBack() => _travel(_history.back);

  Future<void> _goForward() => _travel(_history.forward);

  Future<void> _travel(HistoryEntry? Function() move) async {
    _rememberScroll();
    final entry = move();
    if (entry == null) return;
    setState(() {});
    if (entry.path == _filePath && _errorMessage == null) {
      _jumpToOffset(entry.scrollOffset);
    } else {
      await _loadDocument(entry.path, scrollOffset: entry.scrollOffset);
    }
  }

  void _showNotice(String message) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _watchFile(String path) {
    _fileWatchSub?.cancel();
    _fileWatchSub = File(path)
        .watch(events: FileSystemEvent.modify)
        .listen((_) => _reloadFile());
  }

  Future<void> _reloadFile() async {
    if (_filePath == null) return;
    try {
      final content = await FileService.readMarkdown(_filePath!);
      final statsFuture =
          Future.microtask(() => DocumentStats.fromMarkdown(content));
      // Full Markdown parse (must match what the viewer renders): run it off
      // the UI thread so large documents do not freeze the window.
      final tocFuture = compute(computeTocEntries, content);

      final stats = await statsFuture;
      final tocEntries = await tocFuture;

      if (!mounted) return;

      setState(() {
        _markdownContent = content;
        _stats = stats;
        _tocEntries = tocEntries;
        _recomputeMatchCount();
      });
    } catch (_) {
      // Silently ignore reload errors
    }
  }

  Future<void> _exportToPdf() async {
    if (_filePath == null || _markdownContent.isEmpty || _isExportingPdf) {
      return;
    }

    setState(() => _isExportingPdf = true);

    try {
      final baseName = p.basenameWithoutExtension(_filePath!);
      final defaultFileName = '$baseName.pdf';
      String? savePath;

      if (Platform.isLinux) {
        try {
          const channel = MethodChannel('com.veloxmd/file_picker');
          savePath = await channel.invokeMethod<String>('saveFile', {
            'fileName': defaultFileName,
            'dialogTitle': 'Export to PDF',
          });
        } on MissingPluginException {
          savePath = null;
        } catch (_) {
          savePath = null;
        }
      }

      if (savePath == null) {
        final bool wasAlwaysOnTop = await windowManager.isAlwaysOnTop();
        if (wasAlwaysOnTop) {
          await windowManager.setAlwaysOnTop(false);
        }
        try {
          savePath = await FilePicker.platform.saveFile(
            dialogTitle: 'Export to PDF',
            fileName: defaultFileName,
            type: FileType.custom,
            allowedExtensions: ['pdf'],
            lockParentWindow: true,
          );
        } finally {
          if (wasAlwaysOnTop) {
            await windowManager.setAlwaysOnTop(true);
          }
          await windowManager.focus();
        }
      }

      if (savePath == null || !mounted) return;

      if (!savePath.toLowerCase().endsWith('.pdf')) {
        savePath = '$savePath.pdf';
      }

      await PdfExportService.exportToFile(
        markdown: _markdownContent,
        outputPath: savePath,
        title: p.basename(_filePath!),
        basePath: p.dirname(_filePath!),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Exported to ${p.basename(savePath)}'),
          action: SnackBarAction(
            label: 'Open',
            onPressed: () async {
              final uri = Uri.file(savePath!);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri);
              }
            },
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to export PDF: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isExportingPdf = false);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Search navigation
  // ---------------------------------------------------------------------------

  /// Called when the query text changes. Debounced: re-parsing the document to
  /// count matches and rebuilding the rendered view is deferred until the user
  /// pauses typing, so fast typing does not trigger a full re-parse per
  /// keystroke. Resets the active occurrence to the first match.
  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(_searchDebounceDelay, () {
      if (!mounted) return;
      _commitSearchQuery(query);
    });
  }

  void _commitSearchQuery(String query) {
    setState(() {
      _searchQuery = query;
      _matchCount = countHighlightMatches(_markdownContent, query);
      _activeMatchIndex = 0;
    });
  }

  void _flushPendingSearchQuery() {
    if (_searchDebounce?.isActive ?? false) {
      _searchDebounce!.cancel();
    }
    _commitSearchQuery(_searchController.text);
  }

  /// Recomputes the match count for the current query against the current
  /// document and clamps the active index into range. Call after the document
  /// content changes (open/reload) so the counter stays accurate.
  void _recomputeMatchCount() {
    final count = countHighlightMatches(_markdownContent, _searchQuery);
    _matchCount = count;
    if (count == 0) {
      _activeMatchIndex = 0;
    } else if (_activeMatchIndex >= count) {
      _activeMatchIndex = count - 1;
    }
  }

  /// Advances the focused highlight to the next match, wrapping around to the
  /// first after the last. Invoked when the user presses Enter in the search
  /// field. Focus stays in the field so repeated Enter keeps jumping.
  void _goToNextMatch() {
    _flushPendingSearchQuery();
    if (_matchCount == 0) return;
    setState(() {
      _activeMatchIndex = (_activeMatchIndex + 1) % _matchCount;
    });
    _searchFocusNode.requestFocus();
  }

  void _goToPreviousMatch() {
    _flushPendingSearchQuery();
    if (_matchCount == 0) return;
    setState(() {
      _activeMatchIndex = (_activeMatchIndex - 1 + _matchCount) % _matchCount;
    });
    _searchFocusNode.requestFocus();
  }

  void _clearSearch() {
    _searchController.clear();
    _searchDebounce?.cancel();
    setState(() {
      _searchQuery = '';
      _activeMatchIndex = 0;
      _matchCount = 0;
    });
    _searchFocusNode.requestFocus();
  }

  void _showSearchPanel() {
    if (_filePath == null) return;
    if (!_searchVisible) {
      setState(() => _searchVisible = true);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  void _toggleSearchPanel() {
    if (_filePath == null) return;
    if (_searchVisible) {
      setState(() => _searchVisible = false);
      _searchFocusNode.unfocus();
    } else {
      _showSearchPanel();
    }
  }

  // ---------------------------------------------------------------------------
  // Keyboard intents
  // ---------------------------------------------------------------------------

  Map<ShortcutActivator, Intent> get _shortcuts => {
        for (final a in widget.keybindings[KeyAction.openFile])
          a: const _OpenFileIntent(),
        for (final a in widget.keybindings[KeyAction.reload])
          a: const _ReloadIntent(),
        for (final a in widget.keybindings[KeyAction.toggleToc])
          a: const _ToggleTocIntent(),
        for (final a in widget.keybindings[KeyAction.toggleViewSource])
          a: const _ToggleViewSourceIntent(),
        for (final a in widget.keybindings[KeyAction.focusSearch])
          a: const _FocusSearchIntent(),
        for (final a in widget.keybindings[KeyAction.increaseFontSize])
          a: const _IncreaseFontSizeIntent(),
        for (final a in widget.keybindings[KeyAction.decreaseFontSize])
          a: const _DecreaseFontSizeIntent(),
        for (final a in widget.keybindings[KeyAction.resetFontSize])
          a: const _ResetFontSizeIntent(),
        for (final a in widget.keybindings[KeyAction.exportPdf])
          a: const _ExportPdfIntent(),
        for (final a in widget.keybindings[KeyAction.navigateBack])
          a: const _BackIntent(),
        for (final a in widget.keybindings[KeyAction.navigateForward])
          a: const _ForwardIntent(),
      };

  Map<Type, Action<Intent>> get _actions => {
        _OpenFileIntent: CallbackAction<_OpenFileIntent>(
          onInvoke: (_) => _pickAndOpenFile(),
        ),
        _ReloadIntent: CallbackAction<_ReloadIntent>(
          onInvoke: (_) => _reloadFile(),
        ),
        _ToggleTocIntent: CallbackAction<_ToggleTocIntent>(
          onInvoke: (_) => setState(() => _tocVisible = !_tocVisible),
        ),
        _ToggleViewSourceIntent: CallbackAction<_ToggleViewSourceIntent>(
          onInvoke: (_) => setState(() => _showSource = !_showSource),
        ),
        _FocusSearchIntent: CallbackAction<_FocusSearchIntent>(
          onInvoke: (_) {
            _showSearchPanel();
            return null;
          },
        ),
        _IncreaseFontSizeIntent: CallbackAction<_IncreaseFontSizeIntent>(
          onInvoke: (_) => _changeFontScale(_fontScaleStep),
        ),
        _DecreaseFontSizeIntent: CallbackAction<_DecreaseFontSizeIntent>(
          onInvoke: (_) => _changeFontScale(-_fontScaleStep),
        ),
        _ResetFontSizeIntent: CallbackAction<_ResetFontSizeIntent>(
          onInvoke: (_) => _setFontScale(1.0),
        ),
        _ExportPdfIntent: CallbackAction<_ExportPdfIntent>(
          onInvoke: (_) => _exportToPdf(),
        ),
        _BackIntent: CallbackAction<_BackIntent>(onInvoke: (_) => _goBack()),
        _ForwardIntent: CallbackAction<_ForwardIntent>(
          onInvoke: (_) => _goForward(),
        ),
      };

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: _shortcuts,
      child: Actions(
        actions: _actions,
        child: Focus(
          autofocus: true,
          child: DropTarget(
            onDragDone: (details) {
              final file = details.files.firstOrNull;
              if (file != null) _openFile(file.path);
            },
            child: Listener(
              // Mouse side buttons navigate the history like a browser.
              onPointerDown: (event) {
                if (event.buttons & kBackMouseButton != 0) {
                  _goBack();
                } else if (event.buttons & kForwardMouseButton != 0) {
                  _goForward();
                }
              },
              child: Scaffold(
                appBar: _buildAppBar(context),
                body: _buildBody(context),
                bottomNavigationBar: _filePath != null
                    ? DocumentFooter(stats: _stats, version: _version)
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }

  AppBar _buildAppBar(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AppBar(
      title: Text(
        _filePath != null ? p.basename(_filePath!) : 'VeloxMD',
        style: const TextStyle(fontSize: 16),
      ),
      actions: [
        if (_filePath != null) ...[
          IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip:
                'Back (${widget.keybindings.label(KeyAction.navigateBack)})',
            onPressed: _history.canGoBack ? _goBack : null,
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward),
            tooltip:
                'Forward (${widget.keybindings.label(KeyAction.navigateForward)})',
            onPressed: _history.canGoForward ? _goForward : null,
          ),
        ],
        if (_filePath != null)
          IconButton(
            icon: Icon(_searchVisible ? Icons.search_off : Icons.search),
            tooltip: _searchVisible
                ? 'Hide search panel'
                : 'Show search panel (Ctrl+F)',
            onPressed: _toggleSearchPanel,
          ),
        if (_filePath != null)
          IconButton(
            icon: Icon(_tocVisible ? Icons.list_alt : Icons.list),
            tooltip:
                'Toggle Table of Contents (${widget.keybindings.label(KeyAction.toggleToc)})',
            onPressed: () => setState(() => _tocVisible = !_tocVisible),
          ),
        if (_filePath != null)
          IconButton(
            icon: Icon(_showSource ? Icons.visibility : Icons.code),
            tooltip: _showSource
                ? 'Render markdown (${widget.keybindings.label(KeyAction.toggleViewSource)})'
                : 'View document source (${widget.keybindings.label(KeyAction.toggleViewSource)})',
            onPressed: () => setState(() => _showSource = !_showSource),
          ),
        if (_filePath != null) _buildMarginControl(context),
        if (_filePath != null)
          IconButton(
            icon: _isExportingPdf
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf),
            tooltip: _isExportingPdf
                ? 'Exporting to PDF...'
                : 'Export to PDF (${widget.keybindings.label(KeyAction.exportPdf)})',
            onPressed: _isExportingPdf ? null : _exportToPdf,
          ),
        IconButton(
          icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
          tooltip: 'Toggle theme',
          onPressed: () => widget.onThemeModeChanged(
            isDark ? ThemeMode.light : ThemeMode.dark,
          ),
        ),
        if (_filePath != null)
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip:
                'Reload (${widget.keybindings.labels(KeyAction.reload).join(' / ')})',
            onPressed: _reloadFile,
          ),
        IconButton(
          icon: const Icon(Icons.folder_open),
          tooltip:
              'Open file (${widget.keybindings.label(KeyAction.openFile)})',
          onPressed: _pickAndOpenFile,
        ),
        IconButton(
          icon: const Icon(Icons.info_outline),
          tooltip: 'About VeloxMD',
          onPressed: () => showDialog(
            context: context,
            builder: (context) => const VeloxAboutDialog(),
          ),
        ),
      ],
    );
  }

  Widget _buildMarginControl(BuildContext context) {
    return PopupMenuButton<void>(
      tooltip: 'Text margins',
      icon: const Icon(Icons.format_indent_increase),
      itemBuilder: (context) => [
        PopupMenuItem<void>(
          enabled: false,
          child: StatefulBuilder(
            builder: (context, setInner) {
              void update(double value) {
                setInner(() {});
                _setHorizontalMargin(value);
              }

              return SizedBox(
                width: 260,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Text margins'),
                        Text('${_horizontalMargin.round()} px'),
                      ],
                    ),
                    Slider(
                      min: _minMargin,
                      max: _maxMargin,
                      divisions: ((_maxMargin - _minMargin) / 8).round(),
                      value: _horizontalMargin,
                      label: '${_horizontalMargin.round()} px',
                      onChanged: update,
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => update(32),
                        icon: const Icon(Icons.restart_alt, size: 18),
                        label: const Text('Reset'),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(_errorMessage!, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _pickAndOpenFile,
              icon: const Icon(Icons.folder_open),
              label: const Text('Open another file'),
            ),
          ],
        ),
      );
    }

    if (_filePath == null) {
      return _buildWelcome(context);
    }

    return Row(
      children: [
        if (_tocVisible)
          TocPanel(
            entries: _tocEntries,
            onEntrySelected: _jumpToHeading,
          ),
        if (_searchVisible && _filePath != null)
          SearchPanel(
            controller: _searchController,
            focusNode: _searchFocusNode,
            matchCount: _matchCount,
            activeMatchIndex: _activeMatchIndex,
            onChanged: _onSearchChanged,
            onNext: _goToNextMatch,
            onPrevious: _goToPreviousMatch,
            onClear: _clearSearch,
          ),
        Expanded(
          child: _showSource
              ? SourceViewer(
                  content: _markdownContent,
                  scrollController: _scrollController,
                  horizontalPadding: _horizontalMargin,
                  fontScale: _fontScale,
                  codeFontFamily: widget.fonts.codeFontFamily,
                )
              : MarkdownViewer(
                  content: _markdownContent,
                  scrollController: _scrollController,
                  basePath: p.dirname(_filePath!),
                  searchQuery: _searchQuery,
                  activeMatchIndex: _activeMatchIndex,
                  horizontalPadding: _horizontalMargin,
                  fontScale: _fontScale,
                  bodyFontFamily: widget.fonts.uiFontFamily,
                  codeFontFamily: widget.fonts.codeFontFamily,
                  headingKeys: _headingKeys,
                  onLinkTap: _onLinkTap,
                ),
        ),
      ],
    );
  }

  Widget _buildWelcome(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.description_outlined,
            size: 80,
            color: theme.colorScheme.primary.withOpacity(0.6),
          ),
          const SizedBox(height: 24),
          Text(
            'VeloxMD',
            style: theme.textTheme.headlineLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Fast Markdown viewer for Linux',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: _pickAndOpenFile,
            icon: const Icon(Icons.folder_open),
            label: const Text('Open Markdown file'),
          ),
          const SizedBox(height: 12),
          Text(
            'or drop a .md / .mdc file anywhere\n'
            'Keyboard: ${widget.keybindings.label(KeyAction.openFile)}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

// Intent classes
class _OpenFileIntent extends Intent {
  const _OpenFileIntent();
}

class _ReloadIntent extends Intent {
  const _ReloadIntent();
}

class _ToggleTocIntent extends Intent {
  const _ToggleTocIntent();
}

class _FocusSearchIntent extends Intent {
  const _FocusSearchIntent();
}

class _IncreaseFontSizeIntent extends Intent {
  const _IncreaseFontSizeIntent();
}

class _DecreaseFontSizeIntent extends Intent {
  const _DecreaseFontSizeIntent();
}

class _ResetFontSizeIntent extends Intent {
  const _ResetFontSizeIntent();
}

class _ToggleViewSourceIntent extends Intent {
  const _ToggleViewSourceIntent();
}

class _ExportPdfIntent extends Intent {
  const _ExportPdfIntent();
}

DocumentStats computeDocumentStats(String content) =>
    DocumentStats.fromMarkdown(content);

List<TocEntry> computeTocEntries(String content) =>
    TocEntry.fromMarkdown(content);

class _BackIntent extends Intent {
  const _BackIntent();
}

class _ForwardIntent extends Intent {
  const _ForwardIntent();
}

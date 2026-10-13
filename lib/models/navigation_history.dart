/// A visited Document and the scroll position the user left it at.
class HistoryEntry {
  HistoryEntry(this.path, {this.scrollOffset = 0});

  final String path;
  double scrollOffset;

  @override
  String toString() => 'HistoryEntry($path @ $scrollOffset)';
}

/// Browser-like Back/Forward history of visited Documents within one window.
///
/// Visiting a new entry drops any Forward entries. Before moving, callers
/// should record the current scroll position with [updateCurrentScroll] so
/// going back/forward can restore it.
class NavigationHistory {
  final List<HistoryEntry> _entries = <HistoryEntry>[];
  int _index = -1;

  HistoryEntry? get current => _index >= 0 ? _entries[_index] : null;
  bool get canGoBack => _index > 0;
  bool get canGoForward => _index < _entries.length - 1;
  int get length => _entries.length;

  /// Pushes [path] as the new current entry, discarding Forward entries.
  void visit(String path, {double scrollOffset = 0}) {
    if (_index < _entries.length - 1) {
      _entries.removeRange(_index + 1, _entries.length);
    }
    _entries.add(HistoryEntry(path, scrollOffset: scrollOffset));
    _index = _entries.length - 1;
  }

  /// Records the scroll position of the current entry.
  void updateCurrentScroll(double offset) => current?.scrollOffset = offset;

  /// Moves one entry back and returns it, or null when at the start.
  HistoryEntry? back() {
    if (!canGoBack) return null;
    return _entries[--_index];
  }

  /// Moves one entry forward and returns it, or null when at the end.
  HistoryEntry? forward() {
    if (!canGoForward) return null;
    return _entries[++_index];
  }
}

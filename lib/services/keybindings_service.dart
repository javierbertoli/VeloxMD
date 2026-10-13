import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show SingleActivator;
import 'package:path/path.dart' as p;

import 'xdg_config.dart';

/// Logical actions the app can trigger via a keyboard shortcut.
///
/// Bindings are NOT hardcoded key combinations in source. They are resolved
/// from a user-editable config file following the XDG Base Directory
/// Specification: `$XDG_CONFIG_HOME/veloxmd/keybindings.json`, falling back
/// to `~/.config/veloxmd/keybindings.json` on Linux/macOS, and
/// `%APPDATA%\veloxmd\keybindings.json` on Windows. The file is created
/// with sane defaults on first run so it's discoverable and editable.
enum KeyAction {
  openFile('open_file'),
  reload('reload'),
  toggleToc('toggle_toc'),
  toggleViewSource('toggle_view_source'),
  focusSearch('focus_search'),
  increaseFontSize('increase_font_size'),
  decreaseFontSize('decrease_font_size'),
  resetFontSize('reset_font_size'),
  exportPdf('export_pdf'),
  navigateBack('navigate_back'),
  navigateForward('navigate_forward'),
  quit('quit');

  const KeyAction(this.configKey);
  final String configKey;
}

class _Binding {
  const _Binding(this.combos, this.activators);
  final List<String> combos;
  final List<SingleActivator> activators;
}

/// Loads, persists and resolves user-configurable keyboard shortcuts.
class KeybindingsService {
  KeybindingsService._(this._bindings);

  final Map<KeyAction, _Binding> _bindings;

  static const Map<KeyAction, List<String>> _defaults = {
    KeyAction.openFile: ['ctrl+o'],
    KeyAction.reload: ['ctrl+r', 'f5'],
    KeyAction.toggleToc: ['ctrl+t'],
    KeyAction.toggleViewSource: ['ctrl+u'],
    KeyAction.focusSearch: ['ctrl+f'],
    KeyAction.increaseFontSize: ['ctrl+plus'],
    KeyAction.decreaseFontSize: ['ctrl+minus'],
    KeyAction.resetFontSize: ['ctrl+zero'],
    KeyAction.exportPdf: ['ctrl+p', 'ctrl+e'],
    KeyAction.navigateBack: ['alt+arrowleft'],
    KeyAction.navigateForward: ['alt+arrowright'],
    KeyAction.quit: ['ctrl+q'],
  };

  static File configFile() =>
      File(p.join(veloxmdConfigDir().path, 'keybindings.json'));

  /// Loads bindings from the user's config file, writing the defaults out
  /// as a starter file the first time the app runs. Falls back to built-in
  /// defaults if the file is missing, unreadable, or malformed (and for any
  /// action left unspecified in a partial file).
  static Future<KeybindingsService> load() async {
    Map<String, dynamic> raw = {};
    try {
      final file = configFile();
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, dynamic>) raw = decoded;
      } else {
        await file.parent.create(recursive: true);
        await file.writeAsString(_encodeDefaults());
      }
    } catch (_) {
      // Unreadable/malformed config: fall through and use defaults.
    }

    final bindings = <KeyAction, _Binding>{};
    for (final action in KeyAction.values) {
      final fromFile = raw[action.configKey];
      final combos = fromFile is List
          ? fromFile.whereType<String>().toList()
          : <String>[];
      final effective = combos.isNotEmpty ? combos : _defaults[action]!;
      final activators = effective.expand(_parseCombo).toList();
      bindings[action] = _Binding(
        activators.isNotEmpty ? effective : _defaults[action]!,
        activators.isNotEmpty
            ? activators
            : _defaults[action]!.expand(_parseCombo).toList(),
      );
    }
    return KeybindingsService._(bindings);
  }

  static String _encodeDefaults() {
    final map = {
      for (final entry in _defaults.entries) entry.key.configKey: entry.value,
    };
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  /// All configured activators for [action] (may be more than one, e.g.
  /// reload is bound to both a Ctrl combo and a bare function key).
  List<SingleActivator> operator [](KeyAction action) =>
      _bindings[action]?.activators ?? const [];

  /// Human-readable labels for every combo bound to [action], e.g.
  /// `['Ctrl+R', 'F5']`, for use in tooltips/help text.
  List<String> labels(KeyAction action) =>
      (_bindings[action]?.combos ?? const []).map(_formatCombo).toList();

  /// The primary (first) human-readable label for [action], e.g. `'Ctrl+O'`.
  String label(KeyAction action) {
    final all = labels(action);
    return all.isEmpty ? '' : all.first;
  }

  static String _formatCombo(String combo) {
    return _splitCombo(combo.trim()).map(_formatToken).join('+');
  }

  /// Splits a combo string on `+`, with one special case: a trailing `++`
  /// means "the last modifier, plus the literal Plus key" (e.g.
  /// `ctrl+shift++` is Ctrl+Shift+Plus, not Ctrl+Shift with a dangling
  /// empty token) rather than being swallowed as an empty split segment.
  static List<String> _splitCombo(String combo) {
    if (combo.endsWith('++')) {
      final modifiers = combo
          .substring(0, combo.length - 1)
          .split('+')
          .where((t) => t.isNotEmpty);
      return [...modifiers, '+'];
    }
    return combo.split('+').where((t) => t.isNotEmpty).toList();
  }

  static String _formatToken(String token) {
    final t = token.toLowerCase();
    const specials = {
      'ctrl': 'Ctrl',
      'control': 'Ctrl',
      'shift': 'Shift',
      'alt': 'Alt',
      'meta': 'Meta',
      'super': 'Meta',
      'cmd': 'Meta',
      'equal': '=',
      'minus': '-',
      'plus': '+',
      'zero': '0',
      'numpadadd': '+',
      'numpadsubtract': '-',
      'arrowleft': 'Left',
      'arrowright': 'Right',
      'arrowup': 'Up',
      'arrowdown': 'Down',
    };
    if (specials.containsKey(t)) return specials[t]!;
    if (RegExp(r'^f\d{1,2}$').hasMatch(t)) return t.toUpperCase();
    if (t.startsWith('digit') && t.length == 6) return t.substring(5);
    if (t.startsWith('numpad') && t.length > 6) {
      return 'Numpad ${t.substring(6).toUpperCase()}';
    }
    if (t.length == 1) return t.toUpperCase();
    return t[0].toUpperCase() + t.substring(1);
  }

  /// Parses one combo string into its activator(s). Normally one token maps
  /// to one physical key, but an alias like `plus` stands for "any of the
  /// keys a keyboard labels +" (main-row `=`/`+` and the numpad's `+`), and
  /// similarly for `equal`, `minus` and `zero` — each expands to an
  /// activator per key in [_aliasKeyMap] so main-row and numpad variants
  /// don't need to be spelled out as separate combos.
  static Iterable<SingleActivator> _parseCombo(String combo) {
    final tokens = _splitCombo(combo.trim().toLowerCase());
    if (tokens.isEmpty) return const [];
    final keyToken = tokens.removeLast();
    final keys = _aliasKeyMap[keyToken] ??
        (_keyMap[keyToken] == null ? const [] : [_keyMap[keyToken]!]);
    if (keys.isEmpty) return const [];
    final control = tokens.contains('ctrl') || tokens.contains('control');
    final shift = tokens.contains('shift');
    final alt = tokens.contains('alt');
    final meta = tokens.contains('meta') ||
        tokens.contains('super') ||
        tokens.contains('cmd');
    return [
      for (final key in keys)
        SingleActivator(key, control: control, shift: shift, alt: alt, meta: meta),
    ];
  }

  /// Tokens that stand for more than one physical key (main-row + numpad).
  static const Map<String, List<LogicalKeyboardKey>> _aliasKeyMap = {
    'plus': [LogicalKeyboardKey.equal, LogicalKeyboardKey.numpadAdd],
    'equal': [LogicalKeyboardKey.equal, LogicalKeyboardKey.numpadEqual],
    'minus': [LogicalKeyboardKey.minus, LogicalKeyboardKey.numpadSubtract],
    'zero': [LogicalKeyboardKey.digit0, LogicalKeyboardKey.numpad0],
  };

  static final Map<String, LogicalKeyboardKey> _keyMap = {
    'a': LogicalKeyboardKey.keyA,
    'b': LogicalKeyboardKey.keyB,
    'c': LogicalKeyboardKey.keyC,
    'd': LogicalKeyboardKey.keyD,
    'e': LogicalKeyboardKey.keyE,
    'f': LogicalKeyboardKey.keyF,
    'g': LogicalKeyboardKey.keyG,
    'h': LogicalKeyboardKey.keyH,
    'i': LogicalKeyboardKey.keyI,
    'j': LogicalKeyboardKey.keyJ,
    'k': LogicalKeyboardKey.keyK,
    'l': LogicalKeyboardKey.keyL,
    'm': LogicalKeyboardKey.keyM,
    'n': LogicalKeyboardKey.keyN,
    'o': LogicalKeyboardKey.keyO,
    'p': LogicalKeyboardKey.keyP,
    'q': LogicalKeyboardKey.keyQ,
    'r': LogicalKeyboardKey.keyR,
    's': LogicalKeyboardKey.keyS,
    't': LogicalKeyboardKey.keyT,
    'u': LogicalKeyboardKey.keyU,
    'v': LogicalKeyboardKey.keyV,
    'w': LogicalKeyboardKey.keyW,
    'x': LogicalKeyboardKey.keyX,
    'y': LogicalKeyboardKey.keyY,
    'z': LogicalKeyboardKey.keyZ,
    'digit0': LogicalKeyboardKey.digit0,
    'digit1': LogicalKeyboardKey.digit1,
    'digit2': LogicalKeyboardKey.digit2,
    'digit3': LogicalKeyboardKey.digit3,
    'digit4': LogicalKeyboardKey.digit4,
    'digit5': LogicalKeyboardKey.digit5,
    'digit6': LogicalKeyboardKey.digit6,
    'digit7': LogicalKeyboardKey.digit7,
    'digit8': LogicalKeyboardKey.digit8,
    'digit9': LogicalKeyboardKey.digit9,
    '0': LogicalKeyboardKey.digit0,
    '1': LogicalKeyboardKey.digit1,
    '2': LogicalKeyboardKey.digit2,
    '3': LogicalKeyboardKey.digit3,
    '4': LogicalKeyboardKey.digit4,
    '5': LogicalKeyboardKey.digit5,
    '6': LogicalKeyboardKey.digit6,
    '7': LogicalKeyboardKey.digit7,
    '8': LogicalKeyboardKey.digit8,
    '9': LogicalKeyboardKey.digit9,
    'numpad0': LogicalKeyboardKey.numpad0,
    'numpad1': LogicalKeyboardKey.numpad1,
    'numpad2': LogicalKeyboardKey.numpad2,
    'numpad3': LogicalKeyboardKey.numpad3,
    'numpad4': LogicalKeyboardKey.numpad4,
    'numpad5': LogicalKeyboardKey.numpad5,
    'numpad6': LogicalKeyboardKey.numpad6,
    'numpad7': LogicalKeyboardKey.numpad7,
    'numpad8': LogicalKeyboardKey.numpad8,
    'numpad9': LogicalKeyboardKey.numpad9,
    'numpadadd': LogicalKeyboardKey.numpadAdd,
    'numpadsubtract': LogicalKeyboardKey.numpadSubtract,
    'numpadmultiply': LogicalKeyboardKey.numpadMultiply,
    'numpaddivide': LogicalKeyboardKey.numpadDivide,
    'numpaddecimal': LogicalKeyboardKey.numpadDecimal,
    'f1': LogicalKeyboardKey.f1,
    'f2': LogicalKeyboardKey.f2,
    'f3': LogicalKeyboardKey.f3,
    'f4': LogicalKeyboardKey.f4,
    'f5': LogicalKeyboardKey.f5,
    'f6': LogicalKeyboardKey.f6,
    'f7': LogicalKeyboardKey.f7,
    'f8': LogicalKeyboardKey.f8,
    'f9': LogicalKeyboardKey.f9,
    'f10': LogicalKeyboardKey.f10,
    'f11': LogicalKeyboardKey.f11,
    'f12': LogicalKeyboardKey.f12,
    '=': LogicalKeyboardKey.equal,
    '+': LogicalKeyboardKey.equal,
    '-': LogicalKeyboardKey.minus,
    'space': LogicalKeyboardKey.space,
    'tab': LogicalKeyboardKey.tab,
    'enter': LogicalKeyboardKey.enter,
    'return': LogicalKeyboardKey.enter,
    'escape': LogicalKeyboardKey.escape,
    'esc': LogicalKeyboardKey.escape,
    'backspace': LogicalKeyboardKey.backspace,
    'delete': LogicalKeyboardKey.delete,
    'home': LogicalKeyboardKey.home,
    'end': LogicalKeyboardKey.end,
    'pageup': LogicalKeyboardKey.pageUp,
    'pagedown': LogicalKeyboardKey.pageDown,
    'arrowup': LogicalKeyboardKey.arrowUp,
    'arrowdown': LogicalKeyboardKey.arrowDown,
    'arrowleft': LogicalKeyboardKey.arrowLeft,
    'arrowright': LogicalKeyboardKey.arrowRight,
    'comma': LogicalKeyboardKey.comma,
    'period': LogicalKeyboardKey.period,
    'slash': LogicalKeyboardKey.slash,
    'semicolon': LogicalKeyboardKey.semicolon,
    'quote': LogicalKeyboardKey.quote,
    'bracketleft': LogicalKeyboardKey.bracketLeft,
    'bracketright': LogicalKeyboardKey.bracketRight,
    'backslash': LogicalKeyboardKey.backslash,
  };
}

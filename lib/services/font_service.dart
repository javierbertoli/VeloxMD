import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'xdg_config.dart';

/// Resolved font families the app should render with.
class FontConfig {
  const FontConfig({required this.uiFontFamily, required this.codeFontFamily});

  /// Body text / UI chrome font family (e.g. the desktop's sans-serif font).
  final String uiFontFamily;

  /// Code block / monospace font family (e.g. the desktop's monospace font).
  final String codeFontFamily;
}

/// Resolves the fonts VeloxMD renders with.
///
/// By default it follows the desktop's own configured fonts — queried live
/// via `fc-match` (fontconfig) on Linux, or the platform's well-known
/// default on Windows — instead of always forcing the bundled Inter/FiraCode
/// fonts. A user can pin a specific font by editing
/// `$XDG_CONFIG_HOME/veloxmd/fonts.json` (falling back to
/// `~/.config/veloxmd/fonts.json` on Linux/macOS, and
/// `%APPDATA%\veloxmd\fonts.json` on Windows); an empty/missing entry there
/// means "keep following the desktop".
class FontService {
  static const String openDyslexicFontFamily = 'OpenDyslexic';

  /// Bundled fallback used when there's no override and the desktop's font
  /// can't be determined (e.g. `fc-match` isn't installed).
  static const String fallbackUiFontFamily = 'Inter';
  static const String fallbackCodeFontFamily = 'FiraCode';

  static File configFile() =>
      File(p.join(veloxmdConfigDir().path, 'fonts.json'));

  /// Loads the effective font config: a user override from the config file
  /// takes precedence per-family, otherwise the desktop's current font is
  /// detected live. Never throws — falls back to the bundled fonts on any
  /// error so a missing `fc-match` or malformed config never blocks startup.
  static Future<FontConfig> load() async {
    String? uiOverride;
    String? codeOverride;
    try {
      final file = configFile();
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, dynamic>) {
          uiOverride = _nonEmpty(decoded['ui_font']);
          codeOverride = _nonEmpty(decoded['mono_font']);
        }
      } else {
        await file.parent.create(recursive: true);
        await file.writeAsString(const JsonEncoder.withIndent('  ').convert({
          'ui_font': null,
          'mono_font': null,
        }));
      }
    } catch (_) {
      // Unreadable/malformed config: fall through to live detection.
    }

    return FontConfig(
      uiFontFamily:
          uiOverride ?? await _detectFont('sans-serif') ?? fallbackUiFontFamily,
      codeFontFamily: codeOverride ??
          await _detectFont('monospace') ??
          fallbackCodeFontFamily,
    );
  }

  static String? _nonEmpty(dynamic value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// The desktop's currently configured font for [genericFamily]
  /// (`sans-serif` or `monospace`). Returns null if it can't be determined.
  static Future<String?> _detectFont(String genericFamily) async {
    if (Platform.isWindows) {
      return genericFamily == 'monospace' ? 'Consolas' : 'Segoe UI';
    }
    if (!Platform.isLinux) return null;
    try {
      final result = await Process.run(
        'fc-match',
        ['--format=%{family}', genericFamily],
      );
      if (result.exitCode != 0) return null;
      final family = (result.stdout as String).split(',').first.trim();
      return family.isEmpty ? null : family;
    } catch (_) {
      // fc-match not installed or failed to run.
      return null;
    }
  }
}

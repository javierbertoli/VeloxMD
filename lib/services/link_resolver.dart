import 'dart:io';

import 'package:path/path.dart' as p;

import 'file_service.dart';

/// Where a Markdown Link points to. See CONTEXT.md.
sealed class LinkTarget {
  const LinkTarget();
}

/// A Heading in the current Document.
class AnchorTarget extends LinkTarget {
  const AnchorTarget(this.anchor);

  /// URL-decoded, lowercased Anchor.
  final String anchor;
}

/// Another Document, optionally with an Anchor inside it.
class DocumentTarget extends LinkTarget {
  const DocumentTarget(this.path, {this.anchor});

  /// Absolute, normalized path.
  final String path;
  final String? anchor;
}

/// Handed to the system default app (browser, mail client, file opener).
class ExternalTarget extends LinkTarget {
  const ExternalTarget(this.uri);

  final Uri uri;
}

/// The Link target does not exist or uses an unsupported scheme.
class UnreachableTarget extends LinkTarget {
  const UnreachableTarget(this.href);

  final String href;
}

/// Resolves Link hrefs found in a Document to a [LinkTarget].
class LinkResolver {
  LinkResolver._();

  static const _externalSchemes = {'http', 'https', 'mailto'};

  /// Resolves [href] relative to the Document at [currentPath].
  ///
  /// A link to [currentPath] itself is returned as an [AnchorTarget] (or a
  /// [DocumentTarget] without anchor when there is no fragment).
  static Future<LinkTarget> resolve(
    String href, {
    required String currentPath,
  }) async {
    final trimmed = href.trim();
    if (trimmed.isEmpty) return UnreachableTarget(href);

    final hashIndex = trimmed.indexOf('#');
    final pathPart = hashIndex == -1 ? trimmed : trimmed.substring(0, hashIndex);
    final fragment = hashIndex == -1 ? null : trimmed.substring(hashIndex + 1);
    final anchor =
        fragment == null || fragment.isEmpty ? null : normalizeAnchor(fragment);

    if (pathPart.isEmpty) {
      return anchor == null ? UnreachableTarget(href) : AnchorTarget(anchor);
    }

    final schemeMatch = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.-]+):').firstMatch(pathPart);
    final scheme = schemeMatch?.group(1)?.toLowerCase();

    String path;
    if (scheme == null) {
      path = _decode(pathPart.split('?').first);
    } else if (_externalSchemes.contains(scheme)) {
      final uri = Uri.tryParse(trimmed);
      return uri == null ? UnreachableTarget(href) : ExternalTarget(uri);
    } else if (scheme == 'file') {
      final uri = Uri.tryParse(pathPart);
      if (uri == null) return UnreachableTarget(href);
      try {
        path = uri.toFilePath();
      } on UnsupportedError {
        return UnreachableTarget(href);
      }
    } else {
      return UnreachableTarget(href);
    }

    final resolved = p.normalize(
      p.isAbsolute(path) ? path : p.join(p.dirname(currentPath), path),
    );

    if (await File(resolved).exists()) {
      if (FileService.isSupported(resolved)) {
        if (p.equals(resolved, p.normalize(currentPath)) && anchor != null) {
          return AnchorTarget(anchor);
        }
        return DocumentTarget(resolved, anchor: anchor);
      }
      return ExternalTarget(Uri.file(resolved));
    }
    if (await Directory(resolved).exists()) {
      return ExternalTarget(Uri.directory(resolved));
    }
    return UnreachableTarget(href);
  }

  /// URL-decodes and lowercases an Anchor so it can be compared against the
  /// Heading slugs produced by `TocEntry.slugify`.
  static String normalizeAnchor(String fragment) =>
      _decode(fragment).toLowerCase();

  static String _decode(String value) {
    try {
      return Uri.decodeComponent(value);
    } on ArgumentError {
      return value;
    }
  }
}

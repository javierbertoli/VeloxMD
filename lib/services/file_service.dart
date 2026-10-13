import 'dart:io';

class FileServiceException implements Exception {
  const FileServiceException(this.message);

  final String message;

  @override
  String toString() => 'FileServiceException: $message';
}

/// Provides fast, async markdown file reading with basic validation.
class FileService {
  FileService._();

  static const _maxFileSizeBytes = 50 * 1024 * 1024; // 50 MB
  static const _supportedExtensions = {'.md', '.markdown', '.mdc', '.txt'};

  /// Whether [path] has an extension VeloxMD opens as a Document.
  static bool isSupported(String path) =>
      _supportedExtensions.contains(_extension(path));

  static Future<String> readMarkdown(String path) async {
    final file = File(path);

    if (!await file.exists()) {
      throw FileServiceException('File not found: $path');
    }

    final ext = _extension(path);
    if (!_supportedExtensions.contains(ext)) {
      throw FileServiceException(
        'Unsupported file type "$ext". '
        'Supported: ${_supportedExtensions.join(', ')}',
      );
    }

    final stat = await file.stat();
    if (stat.size > _maxFileSizeBytes) {
      throw FileServiceException(
        'File is too large (${(stat.size / 1024 / 1024).toStringAsFixed(1)} MB). '
        'Maximum supported size is 50 MB.',
      );
    }

    return file.readAsString();
  }

  static String _extension(String path) {
    final dot = path.lastIndexOf('.');
    if (dot == -1) return '';
    return path.substring(dot).toLowerCase();
  }
}

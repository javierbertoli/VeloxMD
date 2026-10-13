import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/update_checker.dart';

class VeloxAboutDialog extends StatefulWidget {
  const VeloxAboutDialog({super.key});

  static const String version = '1.1.0';
  static const String repositoryUrl = 'https://github.com/lbonomo/VeloxMD';
  static const String issuesUrl = '$repositoryUrl/issues';
  static const String discussionsUrl = '$repositoryUrl/discussions';
  static const String repoOwner = 'lbonomo';
  static const String repoName = 'VeloxMD';
  static const String developerName = 'Lucas Bonomo';
  static const String developerWebsite = 'https://lucasbonomo.com';
  static const String developerGithub = 'https://github.com/lbonomo';
  static const String developerLinkedin = 'https://www.linkedin.com/in/lbonomo/';
  static const String collaboratorName = 'Javier Bértoli';
  static const String collaboratorGithub = 'https://github.com/javierbertoli';

  @override
  State<VeloxAboutDialog> createState() => _VeloxAboutDialogState();
}

class _VeloxAboutDialogState extends State<VeloxAboutDialog> {
  bool _checking = false;
  String? _errorMessage;
  UpdateCheckResult? _result;

  Future<void> _launchUrl(String url) async {
    if (!await launchUrl(Uri.parse(url),
        mode: LaunchMode.externalApplication)) {
      throw 'Could not launch $url';
    }
  }

  Future<void> _checkForUpdates() async {
    setState(() {
      _checking = true;
      _errorMessage = null;
      _result = null;
    });

    try {
      final result = await UpdateChecker.checkGitHubUpdate(
        owner: VeloxAboutDialog.repoOwner,
        repo: VeloxAboutDialog.repoName,
        currentVersion: VeloxAboutDialog.version,
      );
      if (!mounted) return;
      setState(() => _result = result);
    } on UpdateCheckException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Error inesperado: $e');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Widget _buildUpdateSection(ThemeData theme) {
    final children = <Widget>[
      OutlinedButton.icon(
        onPressed: _checking ? null : _checkForUpdates,
        icon: _checking
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.system_update_alt, size: 16),
        label: Text(_checking ? 'Checking…' : 'Check for updates'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
      ),
    ];

    if (_errorMessage != null) {
      children.add(const SizedBox(height: 8));
      children.add(Text(
        _errorMessage!,
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
      ));
    } else if (_result != null) {
      final r = _result!;
      children.add(const SizedBox(height: 8));
      if (r.updateAvailable) {
        children.add(Text(
          'New version v${r.latestVersion} available '
          '(you have v${r.currentVersion}).',
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.primary,
          ),
        ));
        if (r.downloadUrl != null) {
          children.add(const SizedBox(height: 8));
          children.add(FilledButton.icon(
            onPressed: () => _launchUrl(r.downloadUrl!),
            icon: const Icon(Icons.download, size: 16),
            label: Text('Download v${r.latestVersion}'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ));
        }
      } else {
        children.add(Text(
          "You're on the latest version (v${r.currentVersion}).",
          style: theme.textTheme.bodySmall,
        ));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const version = VeloxAboutDialog.version;
    const repositoryUrl = VeloxAboutDialog.repositoryUrl;
    const issuesUrl = VeloxAboutDialog.issuesUrl;
    const discussionsUrl = VeloxAboutDialog.discussionsUrl;
    const developerName = VeloxAboutDialog.developerName;
    const developerWebsite = VeloxAboutDialog.developerWebsite;
    const developerGithub = VeloxAboutDialog.developerGithub;
    const developerLinkedin = VeloxAboutDialog.developerLinkedin;
    const collaboratorName = VeloxAboutDialog.collaboratorName;
    const collaboratorGithub = VeloxAboutDialog.collaboratorGithub;

    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'VeloxMD',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      Text(
                        'v$version',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Update checker
              _buildUpdateSection(theme),
              const SizedBox(height: 20),

              // Project Goal
              _Section(
                title: '📋 Project Goal',
                content:
                    'VeloxMD is a fast, lightweight Markdown viewer built with Flutter for the Linux desktop. '
                    'It provides an efficient way to view and navigate Markdown documents with real-time file watching.',
                theme: theme,
              ),
              const SizedBox(height: 16),

              // Key Features
              _Section(
                title: '⚡ Key Features',
                content:
                    '• Instant rendering of .md, .markdown, and .txt files\n'
                    '• Native Linux desktop integration (GTK, Wayland/X11)\n'
                    '• Auto-generated Table of Contents\n'
                    '• Raw source document view (Ctrl+U)\n'
                    '• Live file reloading\n'
                    '• Dark/Light theme support\n'
                    '• GitHub-Flavoured Markdown (tables, strikethrough, tasks)\n'
                    '• Drag-and-drop file opening\n'
                    '• Document statistics (words, lines, tokens, etc.)',
                theme: theme,
              ),
              const SizedBox(height: 16),

              // Development Stack
              _Section(
                title: '🛠️ Development Stack',
                content:
                    '• Framework: Flutter 3.10+\n'
                    '• Language: Dart\n'
                    '• UI: Material Design 3\n'
                    '• Build Target: Linux Desktop\n'
                    '• Package Manager: Pub',
                theme: theme,
              ),
              const SizedBox(height: 16),

              // Getting Started
              _Section(
                title: '🚀 Getting Started',
                content:
                    'Build: flutter build linux --release\n'
                    'Run: ./build/linux/x64/release/bundle/veloxmd\n'
                    'Dev: flutter run -d linux',
                theme: theme,
              ),
              const SizedBox(height: 24),

              // Developer Section
              Text(
                '👨‍💻 Developer',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      developerName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _LinkButton(
                          label: 'Website',
                          icon: Icons.language,
                          onPressed: () => _launchUrl(developerWebsite),
                          theme: theme,
                        ),
                        _LinkButton(
                          label: 'GitHub Profile',
                          icon: Icons.person,
                          onPressed: () => _launchUrl(developerGithub),
                          theme: theme,
                        ),
                        _LinkButton(
                          label: 'LinkedIn',
                          icon: Icons.work,
                          onPressed: () => _launchUrl(developerLinkedin),
                          theme: theme,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Collaborators Section
              Text(
                '🤝 Collaborators',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Text(
                      collaboratorName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    _LinkButton(
                      label: 'GitHub Profile',
                      icon: Icons.person,
                      onPressed: () => _launchUrl(collaboratorGithub),
                      theme: theme,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Links Section
              Text(
                '🔗 Resources',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _LinkButton(
                    label: 'GitHub Repository',
                    icon: Icons.code,
                    onPressed: () => _launchUrl(repositoryUrl),
                    theme: theme,
                  ),
                  _LinkButton(
                    label: 'Report Issue',
                    icon: Icons.bug_report,
                    onPressed: () => _launchUrl(issuesUrl),
                    theme: theme,
                  ),
                  _LinkButton(
                    label: 'Discussions',
                    icon: Icons.chat_bubble,
                    onPressed: () => _launchUrl(discussionsUrl),
                    theme: theme,
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Footer
              Text(
                'Made with ❤️ for the Linux community',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Licensed under MIT',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.content,
    required this.theme,
  });

  final String title;
  final String content;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          content,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _LinkButton extends StatelessWidget {
  const _LinkButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    required this.theme,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }
}

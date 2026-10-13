import 'package:flutter/material.dart';
import '../models/toc_entry.dart';

/// A side panel showing a table of contents extracted from heading levels.
class TocPanel extends StatelessWidget {
  const TocPanel({
    super.key,
    required this.entries,
    required this.onEntrySelected,
  });

  final List<TocEntry> entries;

  /// Called when the user taps an entry; the owner scrolls to its heading.
  final ValueChanged<TocEntry> onEntrySelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 1,
      child: SizedBox(
        width: 260,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Contents',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            const Divider(height: 1),
            if (entries.isEmpty)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'No headings found in this document.',
                      style: theme.textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: entries.length,
                  itemBuilder: (context, i) => _TocItem(
                    entry: entries[i],
                    onTap: () => onEntrySelected(entries[i]),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TocItem extends StatelessWidget {
  const _TocItem({required this.entry, required this.onTap});

  final TocEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final indent = (entry.level - 1) * 12.0;
    final isTopLevel = entry.level == 1;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16 + indent,
          right: 16,
          top: 4,
          bottom: 4,
        ),
        child: Text(
          entry.title,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: isTopLevel ? FontWeight.w600 : FontWeight.normal,
            color: isTopLevel
                ? theme.colorScheme.onSurface
                : theme.colorScheme.onSurfaceVariant,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

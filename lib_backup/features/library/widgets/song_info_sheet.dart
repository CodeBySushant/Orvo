import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/utils/formatters.dart';
import '../domain/entities.dart';

/// Read-only metadata sheet: everything the media store knows about a track.
/// (Tag *editing* is deferred — it needs per-file write requests under
/// scoped storage plus a tag-writing pipeline.)
class SongInfoSheet extends StatelessWidget {
  const SongInfoSheet({super.key, required this.song});

  final Song song;

  static Future<void> show(BuildContext context, Song song) {
    return showModalBottomSheet<void>(
      context: context,
      builder: (context) => SongInfoSheet(song: song),
    );
  }

  String _fileSize() {
    try {
      final bytes = File(song.path).lengthSync();
      if (bytes >= 1024 * 1024) {
        return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
      }
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    } catch (_) {
      return '—';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final added = song.dateAdded > 0
        ? DateTime.fromMillisecondsSinceEpoch(song.dateAdded * 1000)
        : null;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Song info', style: theme.textTheme.titleLarge),
            const SizedBox(height: 14),
            _InfoRow('Title', song.title),
            _InfoRow('Artist', song.artist),
            _InfoRow('Album', song.album),
            _InfoRow('Duration', Formatters.duration(song.duration)),
            if (song.track != null)
              _InfoRow('Track', '${song.track! % 1000}'),
            _InfoRow('Size', _fileSize()),
            if (added != null)
              _InfoRow('Added',
                  '${added.day}/${added.month}/${added.year}'),
            _InfoRow('Path', song.path, copyable: true),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value, {this.copyable = false});

  final String label;
  final String value;
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(label, style: theme.textTheme.labelMedium),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          if (copyable)
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.copy_rounded, size: 16),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Path copied')),
                );
              },
            ),
        ],
      ),
    );
  }
}

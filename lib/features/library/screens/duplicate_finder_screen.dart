import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart' show ArtworkType;

import '../../../core/i18n/l10n.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/artwork.dart';
import '../../system/system_channel.dart';
import '../domain/entities.dart';
import '../providers/genre_providers.dart';
import '../providers/library_providers.dart';

// ---------------------------------------------------------------------------
// FEATURE (duplicate finder): find the same song stored more than once
// (typically the same file downloaded into two folders) and remove the
// extra copies from the device.
//
// DESIGN — detection is deliberately conservative: two songs are duplicates
// only when title + artist (case-insensitive) AND duration (to the second)
// all match. A missed duplicate costs nothing; a false positive deletes the
// wrong file, so precision beats recall here.
//
// DESIGN — the user stays in control. Nothing is pre-selected; "Select
// extras" keeps the OLDEST copy of each group (the original) and ticks the
// rest, and every checkbox can be changed before deleting. Deletion goes
// through the same scoped-storage system dialog as everywhere else in Orvo
// (one dialog for the whole batch on Android 11+), and the existing cleanup
// pass (#16) then purges stats / playlist rows / favorites of removed files
// automatically.
// ---------------------------------------------------------------------------

/// Groups of duplicate songs (each group ≥ 2 copies), oldest copy first.
final duplicateGroupsProvider = Provider<AsyncValue<List<List<Song>>>>((ref) {
  return ref.watch(songsProvider).whenData((songs) {
    String norm(String s) =>
        s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    final map = <String, List<Song>>{};
    for (final s in songs) {
      final key =
          '${norm(s.title)}|${norm(s.artist)}|${(s.duration.inMilliseconds / 1000).round()}';
      map.putIfAbsent(key, () => []).add(s);
    }
    final groups = <List<Song>>[
      for (final g in map.values)
        if (g.length > 1)
          (List<Song>.from(g)..sort((a, b) => a.dateAdded.compareTo(b.dateAdded))),
    ];
    groups.sort((a, b) =>
        a.first.title.toLowerCase().compareTo(b.first.title.toLowerCase()));
    return groups;
  });
});

class DuplicateFinderScreen extends ConsumerStatefulWidget {
  const DuplicateFinderScreen({super.key});

  @override
  ConsumerState<DuplicateFinderScreen> createState() =>
      _DuplicateFinderScreenState();
}

class _DuplicateFinderScreenState
    extends ConsumerState<DuplicateFinderScreen> {
  final Set<int> _selected = <int>{};
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = ref.watch(l10nProvider);
    final groupsAsync = ref.watch(duplicateGroupsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(t.duplicateFinder),
        actions: [
          groupsAsync.maybeWhen(
            data: (groups) => groups.isEmpty
                ? const SizedBox.shrink()
                : TextButton(
                    onPressed: _busy ? null : () => _selectExtras(groups),
                    child: const Text('Select extras'),
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: groupsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            Center(child: Text(t.scanning, style: theme.textTheme.bodySmall)),
        data: (groups) {
          if (groups.isEmpty) return const _NoDuplicates();

          final extraCopies = groups.fold<int>(0, (n, g) => n + g.length - 1);

          return ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 120),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Text(
                  '${groups.length} songs have more than one copy — '
                  '$extraCopies extra ${extraCopies == 1 ? 'file' : 'files'} '
                  'in total. Tick the copies you want to remove; '
                  '"Select extras" keeps the oldest copy of each song. '
                  'Deleting removes the files from this device permanently.',
                  style: theme.textTheme.bodySmall!.copyWith(height: 1.5),
                ),
              ),
              for (final group in groups) _DuplicateGroupCard(
                group: group,
                selected: _selected,
                enabled: !_busy,
                onToggle: (id) => setState(() {
                  _selected.contains(id)
                      ? _selected.remove(id)
                      : _selected.add(id);
                }),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: groupsAsync.maybeWhen(
        data: (groups) {
          if (groups.isEmpty) return null;
          final validIds = {for (final g in groups) ...g.map((s) => s.id)};
          final count = _selected.where(validIds.contains).length;
          return SafeArea(
            minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: count == 0 || _busy
                  ? null
                  : () => _deleteSelected(groups),
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_outline_rounded),
              label: Text(count == 0
                  ? 'Delete selected'
                  : 'Delete $count selected ${count == 1 ? 'file' : 'files'}'),
            ),
          );
        },
        orElse: () => null,
      ),
    );
  }

  /// Keeps the oldest copy of each group, selects the rest.
  void _selectExtras(List<List<Song>> groups) {
    setState(() {
      _selected.clear();
      for (final group in groups) {
        for (final song in group.skip(1)) {
          _selected.add(song.id);
        }
      }
    });
  }

  Future<void> _deleteSelected(List<List<Song>> groups) async {
    final byId = {
      for (final g in groups)
        for (final s in g) s.id: s,
    };
    final targets = [
      for (final id in _selected)
        if (byId[id] != null) byId[id]!,
    ];
    if (targets.isEmpty) return;

    // Extra guard: warn when EVERY copy of some song is ticked — that's no
    // longer de-duplication, the song vanishes entirely.
    final wipesWhole = groups
        .any((g) => g.every((s) => _selected.contains(s.id)));
    final wipeWarning = wipesWhole
        ? 'Heads up: for at least one song you selected ALL of its copies, '
            'so that song will be removed completely.\n\n'
        : '';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
            'Delete ${targets.length} ${targets.length == 1 ? 'file' : 'files'}?'),
        content: Text(
          '${wipeWarning}The selected files will be permanently removed '
          'from this device. Playlists, favorites and stats clean '
          'themselves up automatically.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final ok = await SystemChannel.deleteSongs(
      [for (final s in targets) s.uri],
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) _selected.clear();
    });

    if (ok) {
      // Rescan; the cleanup pass (#16) purges stats / playlists / favorites
      // of the removed files on its own.
      ref.invalidate(rawSongsProvider);
      ref.invalidate(albumsProvider);
      ref.invalidate(artistsProvider);
      ref.invalidate(genresProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Deleted ${targets.length} ${targets.length == 1 ? 'file' : 'files'}')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Delete was cancelled or failed')),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Pieces
// ---------------------------------------------------------------------------

class _DuplicateGroupCard extends StatelessWidget {
  const _DuplicateGroupCard({
    required this.group,
    required this.selected,
    required this.onToggle,
    required this.enabled,
  });

  final List<Song> group;
  final Set<int> selected;
  final ValueChanged<int> onToggle;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final first = group.first;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Group header: artwork + title / artist / duration.
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Row(
              children: [
                Artwork(
                  id: first.id,
                  type: ArtworkType.AUDIO,
                  fallbackText: first.title,
                  size: 44,
                  radius: 10,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(first.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium!
                              .copyWith(fontWeight: FontWeight.w700)),
                      Text(
                        '${first.artist} · ${Formatters.duration(first.duration)}'
                        ' · ${group.length} copies',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // One row per copy — checkbox + folder path.
          for (var i = 0; i < group.length; i++)
            CheckboxListTile(
              value: selected.contains(group[i].id),
              onChanged: enabled ? (_) => onToggle(group[i].id) : null,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: const EdgeInsets.only(left: 6, right: 14),
              title: Text(
                _folderOf(group[i].path),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
              subtitle: i == 0
                  ? Text('Oldest copy',
                      style: theme.textTheme.labelSmall!
                          .copyWith(color: theme.colorScheme.primary))
                  : null,
            ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  static String _folderOf(String path) {
    final slash = path.lastIndexOf('/');
    if (slash <= 0) return path;
    final folder = path.substring(0, slash);
    final file = path.substring(slash + 1);
    // Show a compact "…/Music/Downloads · file.mp3" style line.
    final parts = folder.split('/');
    final tail =
        parts.length <= 2 ? folder : '…/${parts.sublist(parts.length - 2).join('/')}';
    return '$tail · $file';
  }
}

class _NoDuplicates extends StatelessWidget {
  const _NoDuplicates();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.task_alt_rounded,
                size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('No duplicates found',
                style: theme.textTheme.titleMedium!
                    .copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              'Every song in your library exists exactly once. Nice and tidy.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

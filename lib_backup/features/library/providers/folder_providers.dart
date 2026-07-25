import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/entities.dart';
import 'library_providers.dart';

/// A directory on the device containing at least one song.
class MusicFolder {
  const MusicFolder({
    required this.path,
    required this.name,
    required this.songCount,
  });

  final String path;
  final String name;
  final int songCount;
}

String _dirname(String path) {
  final i = path.lastIndexOf(RegExp(r'[/\\]'));
  return i <= 0 ? path : path.substring(0, i);
}

String _basename(String path) {
  final i = path.lastIndexOf(RegExp(r'[/\\]'));
  return i < 0 ? path : path.substring(i + 1);
}

/// Folders derived from the in-memory song list — no extra media queries.
final foldersProvider = Provider<AsyncValue<List<MusicFolder>>>((ref) {
  return ref.watch(songsProvider).whenData((songs) {
    final counts = <String, int>{};
    for (final song in songs) {
      final dir = _dirname(song.path);
      counts[dir] = (counts[dir] ?? 0) + 1;
    }
    final folders = [
      for (final entry in counts.entries)
        MusicFolder(
          path: entry.key,
          name: _basename(entry.key),
          songCount: entry.value,
        ),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return folders;
  });
});

/// Songs inside one folder, keeping library (date-added) order.
final folderSongsProvider =
    Provider.family<AsyncValue<List<Song>>, String>((ref, folderPath) {
  return ref.watch(songsProvider).whenData((songs) => [
        for (final song in songs)
          if (_dirname(song.path) == folderPath) song,
      ]);
});

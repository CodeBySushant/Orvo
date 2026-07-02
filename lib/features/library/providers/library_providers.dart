import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';

import '../data/library_repository_impl.dart';
import '../domain/entities.dart';
import '../domain/library_repository.dart';

final libraryRepositoryProvider = Provider<LibraryRepository>(
  (ref) => LibraryRepositoryImpl(OnAudioQuery()),
);

/// Flipped to true by the PermissionGate once media access is granted.
/// Until then, every library query stays dormant so the query plugin is
/// never called without permission (which crashes it).
final permissionGrantedProvider = StateProvider<bool>((ref) => false);

/// Master song list, newest first. Refresh with ref.invalidate(songsProvider).
final songsProvider = FutureProvider<List<Song>>((ref) async {
  if (!ref.watch(permissionGrantedProvider)) return const [];
  return ref.watch(libraryRepositoryProvider).songs();
});

final albumsProvider = FutureProvider<List<Album>>((ref) async {
  if (!ref.watch(permissionGrantedProvider)) return const [];
  return ref.watch(libraryRepositoryProvider).albums();
});

final artistsProvider = FutureProvider<List<Artist>>((ref) async {
  if (!ref.watch(permissionGrantedProvider)) return const [];
  return ref.watch(libraryRepositoryProvider).artists();
});

final albumSongsProvider = FutureProvider.family<List<Song>, int>(
  (ref, albumId) => ref.watch(libraryRepositoryProvider).albumSongs(albumId),
);

final artistSongsProvider = FutureProvider.family<List<Song>, int>(
  (ref, artistId) => ref.watch(libraryRepositoryProvider).artistSongs(artistId),
);

final albumByIdProvider = Provider.family<Album?, int>((ref, id) {
  final albums = ref.watch(albumsProvider).valueOrNull ?? const [];
  for (final a in albums) {
    if (a.id == id) return a;
  }
  return null;
});

final artistByIdProvider = Provider.family<Artist?, int>((ref, id) {
  final artists = ref.watch(artistsProvider).valueOrNull ?? const [];
  for (final a in artists) {
    if (a.id == id) return a;
  }
  return null;
});

// ---------------------------------------------------------------------------
// Sorting
// ---------------------------------------------------------------------------

enum SongSort {
  recentlyAdded('Recently added'),
  title('Title'),
  artist('Artist'),
  duration('Duration');

  const SongSort(this.label);
  final String label;
}

final songSortProvider = StateProvider<SongSort>((_) => SongSort.recentlyAdded);

final sortedSongsProvider = Provider<AsyncValue<List<Song>>>((ref) {
  final sort = ref.watch(songSortProvider);
  return ref.watch(songsProvider).whenData((songs) {
    final list = List<Song>.from(songs); // source is date-added desc
    switch (sort) {
      case SongSort.recentlyAdded:
        break;
      case SongSort.title:
        list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case SongSort.artist:
        list.sort((a, b) => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()));
      case SongSort.duration:
        list.sort((a, b) => b.duration.compareTo(a.duration));
    }
    return list;
  });
});

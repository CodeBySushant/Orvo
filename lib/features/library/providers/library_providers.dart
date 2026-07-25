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

// FEATURE (#9): Albums and Artists tabs get sort options too — previously
// only the Songs tab could be sorted.

enum AlbumSort {
  title('Title'),
  artist('Artist'),
  songCount('Song count');

  const AlbumSort(this.label);
  final String label;
}

final albumSortProvider = StateProvider<AlbumSort>((_) => AlbumSort.title);

final sortedAlbumsProvider = Provider<AsyncValue<List<Album>>>((ref) {
  final sort = ref.watch(albumSortProvider);
  return ref.watch(albumsProvider).whenData((albums) {
    final list = List<Album>.from(albums); // source is title asc
    switch (sort) {
      case AlbumSort.title:
        break;
      case AlbumSort.artist:
        list.sort((a, b) {
          final byArtist =
              a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
          if (byArtist != 0) return byArtist;
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        });
      case AlbumSort.songCount:
        list.sort((a, b) {
          final byCount = b.songCount.compareTo(a.songCount);
          if (byCount != 0) return byCount;
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        });
    }
    return list;
  });
});

enum ArtistSort {
  name('Name'),
  trackCount('Song count'),
  albumCount('Album count');

  const ArtistSort(this.label);
  final String label;
}

final artistSortProvider = StateProvider<ArtistSort>((_) => ArtistSort.name);

final sortedArtistsProvider = Provider<AsyncValue<List<Artist>>>((ref) {
  final sort = ref.watch(artistSortProvider);
  return ref.watch(artistsProvider).whenData((artists) {
    final list = List<Artist>.from(artists); // source is name asc
    switch (sort) {
      case ArtistSort.name:
        break;
      case ArtistSort.trackCount:
        list.sort((a, b) {
          final byCount = b.trackCount.compareTo(a.trackCount);
          if (byCount != 0) return byCount;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
      case ArtistSort.albumCount:
        list.sort((a, b) {
          final byCount = b.albumCount.compareTo(a.albumCount);
          if (byCount != 0) return byCount;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
    }
    return list;
  });
});

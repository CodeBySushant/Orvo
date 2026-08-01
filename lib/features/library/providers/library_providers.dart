import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';

import '../../metadata/online_artwork.dart'
    show OnlineMeta, onlineMetaMapProvider;
import '../data/library_repository_impl.dart';
import '../domain/entities.dart';
import 'exclusions_provider.dart';
import '../domain/library_repository.dart';

final libraryRepositoryProvider = Provider<LibraryRepository>(
  (ref) => LibraryRepositoryImpl(OnAudioQuery()),
);

/// Flipped to true by the PermissionGate once media access is granted.
/// Until then, every library query stays dormant so the query plugin is
/// never called without permission (which crashes it).
final permissionGrantedProvider = StateProvider<bool>((ref) => false);

/// FEATURE (#25): the RAW scan — every audio file on the device, before
/// folder exclusions. Cleanup (#16) and the exclusion screen use this so
/// excluding a folder never destroys favorites / playlists / stats.
/// Refresh with ref.invalidate(rawSongsProvider).
final rawSongsProvider = FutureProvider<List<Song>>((ref) async {
  if (!ref.watch(permissionGrantedProvider)) return const [];
  return ref.watch(libraryRepositoryProvider).songs();
});

/// Master song list, newest first, with excluded folders filtered out.
/// Everything downstream (albums shelf order, search, home, folders tab,
/// genres, shuffle) derives from this, so exclusions apply everywhere.
/// True for tags the media store couldn't read.
bool _isUnknownTag(String s) {
  final l = s.trim().toLowerCase();
  return l.isEmpty ||
      l == '<unknown>' ||
      l == 'unknown' ||
      l == 'unknown artist' ||
      l == 'unknown album';
}

/// FIX (sync Issues 3 & 4): normalized grouping key — trims, collapses
/// spaces, ignores case, drops trailing punctuation. "Divide", "divide "
/// and "DIVIDE." all group together. Empty = unknown.
String _groupKey(String raw) {
  var s = raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  s = s.replaceAll(RegExp(r'[\s\.\,\!\?\:\;\-\_]+$'), '');
  return _isUnknownTag(s) ? '' : s;
}

/// Deterministic positive id from a scoped group key (FNV-1a). Stable for
/// the whole session, so routes like /artist/:id and /album/:id keep
/// working with derived groups.
int _stableId(String scopedKey) {
  var h = 0x811C9DC5;
  for (final c in scopedKey.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0x7FFFFFFF;
  }
  return h == 0 ? 1 : h;
}

int _artistGroupId(String artist) =>
    _stableId('artist:${_groupKey(artist).isEmpty ? '<unknown>' : _groupKey(artist)}');
int _albumGroupId(String album) =>
    _stableId('album:${_groupKey(album).isEmpty ? '<unknown>' : _groupKey(album)}');

/// Master song list, newest first, with excluded folders filtered out.
/// Everything downstream (albums shelf order, search, home, folders tab,
/// genres, shuffle) derives from this, so exclusions apply everywhere.
final songsProvider = FutureProvider<List<Song>>((ref) async {
  final songs = await ref.watch(rawSongsProvider.future);
  final excluded = ref.watch(excludedFoldersProvider);
  // FEATURE (online metadata): artist / album detected from MusicBrainz,
  // overlaid ONLY where the local tag is `<unknown>`. Everything downstream
  // (tiles, Now Playing, search, song info, media notification, the
  // DERIVED artist and album groups below) shows the detected values
  // automatically because it all derives from this list.
  final meta = await ref.watch(onlineMetaMapProvider.future);

  Song resolve(Song s) {
    final OnlineMeta? m = meta[s.id];
    var artist = s.artist;
    var album = s.album;
    if (m != null) {
      if (_isUnknownTag(artist) && (m.artist?.isNotEmpty ?? false)) {
        artist = m.artist!;
      }
      if (_isUnknownTag(album) && (m.album?.isNotEmpty ?? false)) {
        album = m.album!;
      }
    }
    // FIX (sync Issues 3 & 4): artistId / albumId are REWRITTEN to derived
    // group ids based on the RESOLVED names, so grouping is consistent
    // everywhere and enriched songs leave "Unknown Artist" automatically.
    return Song(
      id: s.id,
      title: s.title,
      artist: artist,
      album: album,
      albumId: _albumGroupId(album),
      artistId: _artistGroupId(artist),
      duration: s.duration,
      uri: s.uri,
      path: s.path,
      dateAdded: s.dateAdded,
      track: s.track,
    );
  }

  return [
    for (final s in songs)
      if (excluded.isEmpty || !isExcludedPath(s.path, excluded)) resolve(s),
  ];
});

/// FIX (sync Issue 3): artists are DERIVED from the resolved song list —
/// online-detected artists count, "Unknown Artist" only contains songs
/// where both local and online artist are unavailable, and the list
/// rebuilds automatically after every metadata enrichment.
final artistsProvider = FutureProvider<List<Artist>>((ref) async {
  final songs = await ref.watch(songsProvider.future);
  final names = <int, String>{};
  final trackCounts = <int, int>{};
  final albumSets = <int, Set<int>>{};
  for (final s in songs) {
    final id = s.artistId;
    names.putIfAbsent(
        id, () => _isUnknownTag(s.artist) ? 'Unknown Artist' : s.artist.trim());
    trackCounts[id] = (trackCounts[id] ?? 0) + 1;
    (albumSets[id] ??= <int>{}).add(s.albumId);
  }
  final list = [
    for (final id in names.keys)
      Artist(
        id: id,
        name: names[id]!,
        trackCount: trackCounts[id]!,
        albumCount: albumSets[id]!.length,
      ),
  ];
  list.sort((a, b) {
    final au = a.name == 'Unknown Artist', bu = b.name == 'Unknown Artist';
    if (au != bu) return au ? 1 : -1; // Unknown Artist last
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return list;
});

/// FIX (sync Issue 4): albums are DERIVED from the resolved song list,
/// grouped by normalized name — no more duplicate "Divide"/"divide"
/// albums, and each album's artwork comes from its first member song
/// (which includes online-fetched covers).
final albumsProvider = FutureProvider<List<Album>>((ref) async {
  final songs = await ref.watch(songsProvider.future);
  final titles = <int, String>{};
  final artistNames = <int, Set<String>>{};
  final counts = <int, int>{};
  final artSong = <int, int>{};
  for (final s in songs) {
    final id = s.albumId;
    titles.putIfAbsent(
        id, () => _isUnknownTag(s.album) ? 'Unknown Album' : s.album.trim());
    (artistNames[id] ??= <String>{})
        .add(_isUnknownTag(s.artist) ? 'Unknown Artist' : s.artist.trim());
    counts[id] = (counts[id] ?? 0) + 1;
    artSong.putIfAbsent(id, () => s.id);
  }
  final list = [
    for (final id in titles.keys)
      Album(
        id: id,
        title: titles[id]!,
        artist: artistNames[id]!.length == 1
            ? artistNames[id]!.first
            : 'Various Artists',
        songCount: counts[id]!,
        artSongId: artSong[id],
      ),
  ];
  list.sort((a, b) {
    final au = a.title == 'Unknown Album', bu = b.title == 'Unknown Album';
    if (au != bu) return au ? 1 : -1; // Unknown Album last
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  });
  return list;
});

/// Songs of a derived album, in disc/track order.
final albumSongsProvider = FutureProvider.family<List<Song>, int>(
  (ref, albumId) async {
    final songs = await ref.watch(songsProvider.future);
    final list = [
      for (final s in songs)
        if (s.albumId == albumId) s,
    ];
    list.sort((a, b) {
      final at = a.track, bt = b.track;
      if (at != null && bt != null && at != bt) return at.compareTo(bt);
      if ((at == null) != (bt == null)) return at == null ? 1 : -1;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return list;
  },
);

/// Songs of a derived artist, grouped by album then track order.
final artistSongsProvider = FutureProvider.family<List<Song>, int>(
  (ref, artistId) async {
    final songs = await ref.watch(songsProvider.future);
    final list = [
      for (final s in songs)
        if (s.artistId == artistId) s,
    ];
    list.sort((a, b) {
      final byAlbum =
          a.album.toLowerCase().compareTo(b.album.toLowerCase());
      if (byAlbum != 0) return byAlbum;
      final at = a.track, bt = b.track;
      if (at != null && bt != null && at != bt) return at.compareTo(bt);
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return list;
  },
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

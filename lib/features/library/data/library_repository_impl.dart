import 'package:flutter/foundation.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';

import '../domain/entities.dart';
import '../domain/library_repository.dart';

/// Media-store backed implementation. on_audio_query already runs its queries
/// on the platform side, off the UI thread, so scanning never blocks frames.
///
/// FIX (#3): only READ_MEDIA_AUDIO is required. Photo access (album art) is
/// optional — denying it must never produce an empty library. All queries
/// stay wrapped in try/catch so a plugin-side permission complaint degrades
/// to an empty result instead of crashing.
class LibraryRepositoryImpl implements LibraryRepository {
  LibraryRepositoryImpl(this._query);

  final OnAudioQuery _query;

  /// Filter out notification blips / voice notes shorter than this.
  static const _minDuration = Duration(seconds: 20);

  Future<bool> _hasPermission() async {
    try {
      // FIX (#19): mirror the plugin's OWN internal check (READ + WRITE
      // external storage on Android ≤ 12; READ_MEDIA_AUDIO + IMAGES on 13+)
      // instead of permission_handler's view of the world. Queries must
      // never run while this is false — the fork's MissingPermissions error
      // path double-replies on the platform channel and crashes the app
      // natively ("Reply already submitted").
      final granted = await _query.permissionsStatus();
      if (!granted) debugPrint('[Orvo] repo: plugin permission not granted');
      return granted;
    } catch (e) {
      debugPrint('[Orvo] repo permission ERROR: $e');
      return false;
    }
  }

  /// FIX (#11): one shared music filter for every song query, so voice notes
  /// / short clips excluded from the Songs tab can't reappear inside album
  /// or artist detail screens.
  bool _isRealMusic(SongModel m) =>
      (m.isMusic ?? true) &&
      m.uri != null &&
      (m.duration ?? 0) > _minDuration.inMilliseconds;

  @override
  Future<List<Song>> songs() async {
    if (!await _hasPermission()) return const [];
    try {
      final models = await _query.querySongs(
        sortType: SongSortType.DATE_ADDED,
        orderType: OrderType.DESC_OR_GREATER,
        uriType: UriType.EXTERNAL,
        ignoreCase: true,
      );
      debugPrint('[Orvo] querySongs raw=${models.length}');
      final filtered =
          models.where(_isRealMusic).map(_toSong).toList(growable: false);
      debugPrint('[Orvo] after filter=${filtered.length}');
      return filtered;
    } catch (e) {
      debugPrint('[Orvo] querySongs ERROR: $e');
      return const [];
    }
  }

  @override
  Future<List<Album>> albums() async {
    if (!await _hasPermission()) return const [];
    try {
      final models = await _query.queryAlbums(
        sortType: AlbumSortType.ALBUM,
        orderType: OrderType.ASC_OR_SMALLER,
        ignoreCase: true,
      );
      return models
          .map((m) => Album(
                id: m.id,
                title: m.album,
                artist: m.artist ?? 'Unknown artist',
                songCount: m.numOfSongs,
              ))
          .toList(growable: false);
    } catch (e) {
      debugPrint('[Orvo] queryAlbums ERROR: $e');
      return const [];
    }
  }

  @override
  Future<List<Artist>> artists() async {
    if (!await _hasPermission()) return const [];
    try {
      final models = await _query.queryArtists(
        sortType: ArtistSortType.ARTIST,
        orderType: OrderType.ASC_OR_SMALLER,
        ignoreCase: true,
      );
      return models
          .map((m) => Artist(
                id: m.id,
                name: m.artist,
                trackCount: m.numberOfTracks ?? 0,
                albumCount: m.numberOfAlbums ?? 0,
              ))
          .toList(growable: false);
    } catch (e) {
      debugPrint('[Orvo] queryArtists ERROR: $e');
      return const [];
    }
  }

  @override
  Future<List<Song>> albumSongs(int albumId) async {
    if (!await _hasPermission()) return const [];
    try {
      final models = await _query.queryAudiosFrom(
        AudiosFromType.ALBUM_ID,
        albumId,
        sortType: SongSortType.TITLE,
        orderType: OrderType.ASC_OR_SMALLER,
      );
      final songs = models.where(_isRealMusic).map(_toSong).toList();
      songs.sort((a, b) => (a.track ?? 1 << 20).compareTo(b.track ?? 1 << 20));
      return songs;
    } catch (e) {
      debugPrint('[Orvo] albumSongs ERROR: $e');
      return const [];
    }
  }

  @override
  Future<List<Song>> artistSongs(int artistId) async {
    if (!await _hasPermission()) return const [];
    try {
      final models = await _query.queryAudiosFrom(
        AudiosFromType.ARTIST_ID,
        artistId,
        sortType: SongSortType.TITLE,
        orderType: OrderType.ASC_OR_SMALLER,
      );
      return models.where(_isRealMusic).map(_toSong).toList();
    } catch (e) {
      debugPrint('[Orvo] artistSongs ERROR: $e');
      return const [];
    }
  }

  Song _toSong(SongModel m) => Song(
        id: m.id,
        title: m.title,
        artist: m.artist ?? 'Unknown artist',
        album: m.album ?? 'Unknown album',
        albumId: m.albumId ?? -1,
        artistId: m.artistId ?? -1,
        duration: Duration(milliseconds: m.duration ?? 0),
        uri: m.uri!,
        path: m.data,
        dateAdded: m.dateAdded ?? 0,
        track: m.track,
      );
}

import 'package:flutter/foundation.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';

import '../domain/entities.dart';
import '../domain/library_repository.dart';

/// Media-store backed implementation. on_audio_query already runs its queries
/// on the platform side, off the UI thread, so scanning never blocks frames.
///
/// Permission NOTE: the plugin's native check on Android 13+ requires BOTH
/// READ_MEDIA_AUDIO and READ_MEDIA_IMAGES, and calling any query without them
/// triggers a double-reply crash inside the plugin. So this class verifies
/// (never requests) via permission_handler before every query. The
/// PermissionGate owns requesting; this defensive check exists because
/// Android Auto enters through here directly.
class LibraryRepositoryImpl implements LibraryRepository {
  LibraryRepositoryImpl(this._query);

  final OnAudioQuery _query;

  /// Filter out notification blips / voice notes shorter than this.
  static const _minDuration = Duration(seconds: 20);

  Future<bool> _hasPermission() async {
    try {
      // Android 13+: audio -> READ_MEDIA_AUDIO, photos -> READ_MEDIA_IMAGES.
      // Android <=12: permission_handler maps both to READ_EXTERNAL_STORAGE.
      final audio = await Permission.audio.status;
      final photos = await Permission.photos.status;
      final ok = audio.isGranted && photos.isGranted;
      if (!ok) {
        debugPrint('[Orvo] repo status: audio=$audio photos=$photos');
      }
      return ok;
    } catch (e) {
      debugPrint('[Orvo] repo permission ERROR: $e');
      return false;
    }
  }

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
      final filtered = models
          .where((m) =>
              (m.isMusic ?? true) &&
              m.uri != null &&
              (m.duration ?? 0) > _minDuration.inMilliseconds)
          .map(_toSong)
          .toList(growable: false);
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
    final models = await _query.queryAudiosFrom(
      AudiosFromType.ALBUM_ID,
      albumId,
      sortType: SongSortType.TITLE,
      orderType: OrderType.ASC_OR_SMALLER,
    );
    final songs = models.where((m) => m.uri != null).map(_toSong).toList();
    songs.sort((a, b) => (a.track ?? 1 << 20).compareTo(b.track ?? 1 << 20));
    return songs;
  }

  @override
  Future<List<Song>> artistSongs(int artistId) async {
    if (!await _hasPermission()) return const [];
    final models = await _query.queryAudiosFrom(
      AudiosFromType.ARTIST_ID,
      artistId,
      sortType: SongSortType.TITLE,
      orderType: OrderType.ASC_OR_SMALLER,
    );
    return models.where((m) => m.uri != null).map(_toSong).toList();
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
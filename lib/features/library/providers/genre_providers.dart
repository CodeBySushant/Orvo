import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';

import '../domain/entities.dart';
import 'library_providers.dart';

/// FEATURE (#10 — genres): media-store genre browsing, powering the Home
/// "Browse by Genre" row and the Genres screens.
class GenreInfo {
  const GenreInfo({required this.id, required this.name, required this.songCount});

  final int id;
  final String name;
  final int songCount;
}

final _query = OnAudioQuery();

Future<bool> _hasAudioPermission() async {
  try {
    return (await Permission.audio.status).isGranted;
  } catch (_) {
    return false;
  }
}

/// All genres with at least one track, alphabetical.
final genresProvider = FutureProvider<List<GenreInfo>>((ref) async {
  if (!ref.watch(permissionGrantedProvider)) return const [];
  if (!await _hasAudioPermission()) return const [];
  try {
    final models = await _query.queryGenres(
      sortType: GenreSortType.GENRE,
      orderType: OrderType.ASC_OR_SMALLER,
      ignoreCase: true,
    );
    final genres = [
      for (final m in models)
        if ((m.numOfSongs) > 0 && m.genre.trim().isNotEmpty)
          GenreInfo(id: m.id, name: m.genre, songCount: m.numOfSongs),
    ];
    return genres;
  } catch (e) {
    debugPrint('[Orvo] queryGenres ERROR: $e');
    return const [];
  }
});

/// Songs in one genre, with the same short-clip / non-music filtering as the
/// rest of the library.
final genreSongsProvider =
    FutureProvider.family<List<Song>, int>((ref, genreId) async {
  if (!await _hasAudioPermission()) return const [];
  try {
    final models = await _query.queryAudiosFrom(
      AudiosFromType.GENRE_ID,
      genreId,
      sortType: SongSortType.TITLE,
      orderType: OrderType.ASC_OR_SMALLER,
    );
    return [
      for (final m in models)
        if ((m.isMusic ?? true) &&
            m.uri != null &&
            (m.duration ?? 0) > 20000)
          Song(
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
          ),
    ];
  } catch (e) {
    debugPrint('[Orvo] genreSongs ERROR: $e');
    return const [];
  }
});

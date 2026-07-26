import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import '../../core/db/app_database.dart';
import 'lyrics_parser.dart';

/// FEATURE (#21): opt-in online lyrics via LRCLIB (lrclib.net) — a free,
/// open lyrics database that returns LRC-timestamped ("synced") lyrics,
/// which plug straight into Orvo's existing karaoke display.
///
/// Fetch-once, cache-forever: results (including "nothing found") land in
/// the lyrics_cache sqflite table keyed by media-store song id, so a song is
/// looked up at most once and then works fully offline. Negative results
/// expire after 3 days (LRCLIB grows daily), and the sheet's Retry button
/// can clear a row explicitly via [forget].
abstract final class OnlineLyrics {
  static const _get = 'https://lrclib.net/api/get';
  static const _search = 'https://lrclib.net/api/search';
  static const _headers = {
    'User-Agent': 'Orvo/0.1.0 (offline music player; lyrics lookup)',
  };
  static const _timeout = Duration(seconds: 8);
  static const _negativeCacheTtl = Duration(days: 3);

  /// Returns the lyrics, [Lyrics.none] when the service has none for this
  /// track, or `null` when the lookup could not run at all (offline, timed
  /// out, server error) — so the UI can tell "no lyrics exist" apart from
  /// "couldn't check, try again".
  static Future<Lyrics?> load({
    required int songId,
    required String title,
    String? artist,
    String? album,
    int? durationSec,
  }) async {
    final db = await AppDatabase.instance.database;

    // 1. Cache
    final rows = await db.query('lyrics_cache',
        where: 'song_id = ?', whereArgs: [songId], limit: 1);
    if (rows.isNotEmpty) {
      final row = rows.first;
      if ((row['found'] as int) == 1) {
        final cached = _toLyrics(row['synced'] as String?, row['plain'] as String?);
        if (cached != null) return cached;
        // Corrupt row — fall through and refetch.
      } else {
        final fetchedAt =
            DateTime.fromMillisecondsSinceEpoch(row['fetched_at'] as int);
        if (DateTime.now().difference(fetchedAt) < _negativeCacheTtl) {
          return Lyrics.none;
        }
      }
    }

    // 2. Network. Media-store metadata uses "<unknown>" for missing artists;
    // treat that as absent so it doesn't poison the match.
    final cleanArtist =
        (artist == null || artist.trim().isEmpty || artist == '<unknown>')
            ? null
            : artist.trim();
    try {
      var result = cleanArtist == null
          ? null
          : await _fetchExact(
              title: title,
              artist: cleanArtist,
              album: album,
              durationSec: durationSec);
      // Exact match missed (or no artist to match with): fuzzy search,
      // pick the hit whose duration is closest (within 4s).
      result ??= await _fetchSearch(
          title: title, artist: cleanArtist, durationSec: durationSec);

      final (synced, plain) = result ?? (null, null);
      final lyrics = _toLyrics(synced, plain);
      await _store(db, songId, synced: synced, plain: plain, found: lyrics != null);
      return lyrics ?? Lyrics.none;
    } on _LookupUnavailable {
      return null; // offline / timeout / server error — don't cache
    } catch (_) {
      return null;
    }
  }

  /// Clears a cached row so the next load hits the network again (Retry).
  static Future<void> forget(int songId) async {
    final db = await AppDatabase.instance.database;
    await db.delete('lyrics_cache', where: 'song_id = ?', whereArgs: [songId]);
  }

  // -------------------------------------------------------------------------

  static Future<(String?, String?)?> _fetchExact({
    required String title,
    required String artist,
    String? album,
    int? durationSec,
  }) async {
    final uri = Uri.parse(_get).replace(queryParameters: {
      'track_name': title,
      'artist_name': artist,
      if (album != null && album.isNotEmpty && album != '<unknown>')
        'album_name': album,
      if (durationSec != null && durationSec > 0) 'duration': '$durationSec',
    });
    final res = await _request(uri);
    if (res == null) return null; // 404 — not found via exact match
    return (res['syncedLyrics'] as String?, res['plainLyrics'] as String?);
  }

  static Future<(String?, String?)?> _fetchSearch({
    required String title,
    String? artist,
    int? durationSec,
  }) async {
    final uri = Uri.parse(_search).replace(queryParameters: {
      'track_name': title,
      if (artist != null) 'artist_name': artist,
    });
    final list = await _requestList(uri);
    if (list == null || list.isEmpty) return null;

    Map<String, dynamic>? best;
    var bestDelta = 1 << 30;
    for (final item in list.whereType<Map<String, dynamic>>()) {
      final d = (item['duration'] as num?)?.round();
      final delta =
          (durationSec == null || d == null) ? 0 : (d - durationSec).abs();
      final hasSynced = (item['syncedLyrics'] as String?)?.isNotEmpty ?? false;
      // Prefer synced results; among those, closest duration wins.
      final score = delta + (hasSynced ? 0 : 1000);
      if (score < bestDelta) {
        bestDelta = score;
        best = item;
      }
    }
    if (best == null) return null;
    if (durationSec != null) {
      final d = (best['duration'] as num?)?.round();
      if (d != null && (d - durationSec).abs() > 4) return null; // wrong song
    }
    return (best['syncedLyrics'] as String?, best['plainLyrics'] as String?);
  }

  static Future<Map<String, dynamic>?> _request(Uri uri) async {
    final res = await http.get(uri, headers: _headers).timeout(_timeout);
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    if (res.statusCode == 404) return null;
    throw const _LookupUnavailable();
  }

  static Future<List<dynamic>?> _requestList(Uri uri) async {
    final res = await http.get(uri, headers: _headers).timeout(_timeout);
    if (res.statusCode == 200) return jsonDecode(res.body) as List<dynamic>;
    if (res.statusCode == 404) return const [];
    throw const _LookupUnavailable();
  }

  static Lyrics? _toLyrics(String? synced, String? plain) {
    if (synced != null && synced.trim().isNotEmpty) {
      final parsed = LyricsLoader.parseLrc(synced);
      if (!parsed.isEmpty) return parsed;
    }
    if (plain != null && plain.trim().isNotEmpty) {
      return Lyrics(unsynced: plain.trim());
    }
    return null;
  }

  static Future<void> _store(
    Database db,
    int songId, {
    String? synced,
    String? plain,
    required bool found,
  }) {
    return db.insert(
      'lyrics_cache',
      {
        'song_id': songId,
        'synced': synced,
        'plain': plain,
        'found': found ? 1 : 0,
        'fetched_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}

class _LookupUnavailable implements Exception {
  const _LookupUnavailable();
}

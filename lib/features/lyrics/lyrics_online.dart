import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import '../../core/db/app_database.dart';
import 'lyrics_parser.dart';

/// FEATURE (#21): opt-in online lyrics via LRCLIB (lrclib.net) — a free,
/// open lyrics database that returns LRC-timestamped ("synced") lyrics,
/// which plug straight into Orvo's existing karaoke display.
///
/// FIX (#28): smart matching. Local files — especially downloaded ones —
/// carry junk metadata ("Song (Full Video) | 320Kbps - SomeSite.com"),
/// which made even famous songs come back empty. The lookup now:
///  1. CLEANS the title / artist (strips bracketed junk, quality tags,
///     website names, "official video" noise, track numbers, feat. lists);
///  2. tries a LADDER of queries — exact match, field search, free-text
///     search with and without the artist, and finally a title derived
///     from the FILENAME when the tag title looks unusable;
///  3. picks the best candidate by title similarity + duration closeness
///     (tolerance widened to 10s), preferring synced lyrics.
///
/// Fetch-once, cache-forever: results (including "nothing found") land in
/// the lyrics_cache sqflite table keyed by media-store song id. Negative
/// results expire after 3 days, and the sheet's Retry button can clear a
/// row explicitly via [forget]. Old negative rows cached by the previous,
/// weaker matcher are purged once on first run (see [_migrate]).
abstract final class OnlineLyrics {
  static const _get = 'https://lrclib.net/api/get';
  static const _search = 'https://lrclib.net/api/search';
  static const _headers = {
    'User-Agent': 'Orvo/0.1.0 (offline music player; lyrics lookup)',
  };
  static const _timeout = Duration(seconds: 8);
  static const _negativeCacheTtl = Duration(days: 3);

  /// Marker row (impossible song id) — its presence means the one-time
  /// negative-cache purge for the smart matcher has already run.
  static const _migrationMarkerId = -28;
  static bool _migrated = false;

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
    String? path,
  }) async {
    final db = await AppDatabase.instance.database;
    await _migrate(db);

    // 1. Cache
    final rows = await db.query('lyrics_cache',
        where: 'song_id = ?', whereArgs: [songId], limit: 1);
    if (rows.isNotEmpty) {
      final row = rows.first;
      if ((row['found'] as int) == 1) {
        final cached =
            _toLyrics(row['synced'] as String?, row['plain'] as String?);
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

    // 2. Build cleaned query candidates.
    final cleanTitle = _cleanTitle(title);
    final cleanArtist = _cleanArtist(artist);
    final primaryArtist = _primaryArtist(cleanArtist);
    final fileTitle = _titleFromFilename(path);

    // The tag title after cleaning may still be junk (empty, or pure noise
    // like "AUD-20240101"); the filename version can rescue those.
    final titles = <String>[
      if (cleanTitle.isNotEmpty) cleanTitle,
      if (fileTitle != null &&
          fileTitle.isNotEmpty &&
          !_similar(fileTitle, cleanTitle))
        fileTitle,
    ];
    if (titles.isEmpty) return Lyrics.none;

    try {
      (String?, String?)? result;

      // 3. Query ladder — stop at the first usable hit.
      for (final qTitle in titles) {
        // a. Exact match (fast path when tags are clean).
        if (cleanArtist != null) {
          result = await _fetchExact(
            title: qTitle,
            artist: cleanArtist,
            album: _cleanAlbum(album),
            durationSec: durationSec,
          );
          if (result != null) break;
        }
        // b. Field search with full artist, then primary artist only
        //    ("A, B & C" tags rarely match LRCLIB's single-artist entries).
        result = await _fetchSearch(
            title: qTitle, artist: cleanArtist, durationSec: durationSec);
        if (result != null) break;
        if (primaryArtist != null && primaryArtist != cleanArtist) {
          result = await _fetchSearch(
              title: qTitle, artist: primaryArtist, durationSec: durationSec);
          if (result != null) break;
        }
        // c. Free-text search — LRCLIB's q= is the most forgiving matcher.
        result = await _fetchFreeText(
          query: primaryArtist == null ? qTitle : '$qTitle $primaryArtist',
          wantTitle: qTitle,
          durationSec: durationSec,
        );
        if (result != null) break;
        // d. Free-text, title only — the artist tag itself may be wrong.
        if (primaryArtist != null) {
          result = await _fetchFreeText(
              query: qTitle, wantTitle: qTitle, durationSec: durationSec);
          if (result != null) break;
        }
      }

      final (synced, plain) = result ?? (null, null);
      final lyrics = _toLyrics(synced, plain);
      await _store(db, songId,
          synced: synced, plain: plain, found: lyrics != null);
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

  /// FIX (#28): the old matcher cached "not found" for songs the new one
  /// CAN find. Purge negative rows once, then leave a marker row so this
  /// never runs again.
  static Future<void> _migrate(Database db) async {
    if (_migrated) return;
    _migrated = true;
    final marker = await db.query('lyrics_cache',
        where: 'song_id = ?', whereArgs: [_migrationMarkerId], limit: 1);
    if (marker.isNotEmpty) return;
    await db.delete('lyrics_cache', where: 'found = 0');
    await db.insert('lyrics_cache', {
      'song_id': _migrationMarkerId,
      'synced': null,
      'plain': 'migration marker — smart matcher v1',
      'found': 1,
      'fetched_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // --- Metadata cleaning ---------------------------------------------------

  /// Junk words that mark a bracketed segment (or trailing chunk) as noise.
  static final _junkWords = RegExp(
    r'official|video|audio|lyric|lyrical|visuali[sz]er|full\s*song|'
    r'full\s*hd|[48]k|hd|hq|\d{2,3}\s*kbps|mp3|m4a|flac|rip|download|'
    r'from\s+the\s+movie|soundtrack|promo|teaser|trailer|out\s*now|'
    r'new\s*song\s*\d{4}|whatsapp|status',
    caseSensitive: false,
  );

  /// Website / release-group names glued onto titles by download sites.
  static final _siteTag = RegExp(
    r'[\(\[\{\|\-–—\s]*(?:www\.)?[a-z0-9\-_]+\.(?:com|in|net|org|xyz|me|cc|io)\S*',
    caseSensitive: false,
  );

  static String _cleanTitle(String raw) {
    var s = raw.trim();
    if (s.isEmpty || s.toLowerCase() == '<unknown>') return '';

    // Website tags anywhere ("- PagalWorld.Com", "(Mr-Jatt.com)").
    s = s.replaceAll(_siteTag, ' ');

    // Bracketed segments that are pure noise — keep meaningful ones like
    // "(Reprise)" or "(Slowed)" since they distinguish real versions.
    s = s.replaceAllMapped(RegExp(r'[\(\[\{]([^\)\]\}]*)[\)\]\}]'), (m) {
      final inner = m[1] ?? '';
      return _junkWords.hasMatch(inner) || RegExp(r'^\s*$').hasMatch(inner)
          ? ' '
          : m[0]!;
    });

    // "feat. X" / "ft. X" — LRCLIB titles rarely carry the feature list.
    s = s.replaceAll(
        RegExp(r'\b(?:feat|ft)\.?\s+[^\-\|\(\[]+', caseSensitive: false), ' ');

    // Leading track numbers ("01 - ", "07. ").
    s = s.replaceFirst(RegExp(r'^\s*\d{1,3}\s*[\.\-]\s*'), '');

    // Noise phrases after a separator ("Song - Official Video").
    final parts = s.split(RegExp(r'\s*[\|\u2022]\s*|\s+-\s+'));
    if (parts.length > 1) {
      final kept = [
        for (final p in parts)
          if (!_junkWords.hasMatch(p) && p.trim().isNotEmpty) p.trim(),
      ];
      if (kept.isNotEmpty) s = kept.first; // first segment = the title
    }

    // Trailing quality tags with no separator ("Song Full HD 320Kbps").
    s = s.replaceAll(
        RegExp(r'(?:\b(?:full\s*hd|hd|hq|[48]k|\d{2,3}\s*kbps|mp3)\s*)+$',
            caseSensitive: false),
        ' ');

    return _collapse(s);
  }

  static String? _cleanArtist(String? raw) {
    var s = (raw ?? '').trim();
    if (s.isEmpty ||
        s.toLowerCase() == '<unknown>' ||
        s.toLowerCase() == 'unknown artist' ||
        s.toLowerCase() == 'various artists') {
      return null;
    }
    s = s.replaceAll(_siteTag, ' ');
    s = _collapse(s);
    return s.isEmpty ? null : s;
  }

  /// "Arijit Singh, Shreya Ghoshal & Pritam" → "Arijit Singh".
  static String? _primaryArtist(String? cleaned) {
    if (cleaned == null) return null;
    final first = cleaned
        .split(RegExp(r'\s*(?:,|&|;|/|\bfeat\.?\b|\bft\.?\b|\bx\b)\s*',
            caseSensitive: false))
        .first
        .trim();
    return first.isEmpty ? null : first;
  }

  static String? _cleanAlbum(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty || s.toLowerCase() == '<unknown>') return null;
    // Junky albums ("Downloaded from …", site names) hurt exact matching.
    if (_siteTag.hasMatch(s) || _junkWords.hasMatch(s)) return null;
    return s;
  }

  /// Derives a title from the file name — the rescue path for files whose
  /// TAG title is junk. Handles the common "Artist - Title.mp3" pattern by
  /// taking the part after the last " - ".
  static String? _titleFromFilename(String? path) {
    if (path == null || path.isEmpty) return null;
    var name = path.split('/').last;
    final dot = name.lastIndexOf('.');
    if (dot > 0) name = name.substring(0, dot);
    name = _cleanTitle(name.replaceAll('_', ' '));
    if (name.isEmpty) return null;
    final parts = name.split(RegExp(r'\s+-\s+'));
    if (parts.length >= 2 && parts.last.trim().length > 2) {
      return _collapse(parts.last);
    }
    return name;
  }

  static String _collapse(String s) => s
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .replaceAll(RegExp(r'^[\s\-\|,\.]+|[\s\-\|,\.]+$'), '')
      .trim();

  /// Loose normalized-token similarity for candidate scoring.
  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\u0900-\u097F]+'), ' ').trim();

  static bool _similar(String a, String b) {
    final na = _norm(a), nb = _norm(b);
    if (na.isEmpty || nb.isEmpty) return false;
    if (na == nb || na.contains(nb) || nb.contains(na)) return true;
    final ta = na.split(' ').toSet(), tb = nb.split(' ').toSet();
    final overlap = ta.intersection(tb).length;
    return overlap / (ta.length < tb.length ? ta.length : tb.length) >= .6;
  }

  // --- Network -------------------------------------------------------------

  static Future<(String?, String?)?> _fetchExact({
    required String title,
    required String artist,
    String? album,
    int? durationSec,
  }) async {
    final uri = Uri.parse(_get).replace(queryParameters: {
      'track_name': title,
      'artist_name': artist,
      if (album != null) 'album_name': album,
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
    return _pickBest(await _requestList(uri),
        wantTitle: title, durationSec: durationSec);
  }

  /// LRCLIB's q= parameter — its most forgiving, typo-tolerant matcher.
  static Future<(String?, String?)?> _fetchFreeText({
    required String query,
    required String wantTitle,
    int? durationSec,
  }) async {
    final uri = Uri.parse(_search).replace(queryParameters: {'q': query});
    return _pickBest(await _requestList(uri),
        wantTitle: wantTitle, durationSec: durationSec);
  }

  /// Scores candidates: title similarity is required, duration closeness
  /// (10s tolerance — different rips/edits drift) and synced availability
  /// break ties.
  static (String?, String?)? _pickBest(
    List<dynamic>? list, {
    required String wantTitle,
    int? durationSec,
  }) {
    if (list == null || list.isEmpty) return null;

    Map<String, dynamic>? best;
    var bestScore = 1 << 30;
    for (final item in list.whereType<Map<String, dynamic>>()) {
      final candidateTitle = (item['trackName'] as String?) ?? '';
      if (!_similar(candidateTitle, wantTitle)) continue; // wrong song

      final d = (item['duration'] as num?)?.round();
      final delta =
          (durationSec == null || d == null) ? 5 : (d - durationSec).abs();
      if (delta > 10) continue; // wrong version

      final hasSynced = (item['syncedLyrics'] as String?)?.isNotEmpty ?? false;
      final hasPlain = (item['plainLyrics'] as String?)?.isNotEmpty ?? false;
      if (!hasSynced && !hasPlain) continue; // instrumental / empty entry

      final score = delta + (hasSynced ? 0 : 100);
      if (score < bestScore) {
        bestScore = score;
        best = item;
      }
    }
    if (best == null) return null;
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

import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import '../../core/db/app_database.dart';
import '../../core/theme/theme_provider.dart' show sharedPreferencesProvider;
import '../../core/widgets/artwork.dart';
import '../library/providers/library_providers.dart';

// ---------------------------------------------------------------------------
// FEATURE (online artwork): fills in missing album covers from MusicBrainz +
// the Cover Art Archive.
//
// LEGAL DESIGN — this is the copyright-safe architecture:
//  - Metadata comes from MusicBrainz, whose core data is CC0 (public
//    domain) — free for commercial / ad-supported use, no key needed.
//  - Artwork is fetched by the USER'S DEVICE directly from the Cover Art
//    Archive (hosted by the Internet Archive) purely to identify music the
//    user already owns; Orvo never hosts, redistributes, bundles or resells
//    any image. Fetched art lives only in the app's private database and is
//    deliberately excluded from Orvo's own backup files.
//
// TECHNICAL DESIGN — strictly on-demand and rate-limit-polite:
//  - Nothing is fetched for tracks that already have embedded / media-store
//    artwork. The fallback fires only when the Artwork widget comes up
//    empty (see ArtworkCache.onlineFallback).
//  - One global queue serializes MusicBrainz calls with >= 1.1s spacing
//    (MB asks for 1 req/sec) and a descriptive User-Agent. The queue is
//    LIFO so whatever the user is LOOKING AT resolves first while older
//    backlog waits.
//  - Fetch-once, cache-forever in sqflite (online_art table, DB v5):
//    found=1 rows hold the image bytes; found=0 is a negative cache with a
//    14-day TTL so instrumentum-less tracks don't hammer the API. Network
//    failures are NOT cached — they retry next session.
//  - Matching is conservative (title similarity + duration within 10s,
//    same philosophy as the lyrics matcher, FIX #28): wrong artwork is
//    worse than no artwork.
// ---------------------------------------------------------------------------

const _kOnlineArtworkKey = 'orvo.onlineArtwork';

/// FEATURE (online artwork): ON by default, like online lyrics — covers work
/// out of the box; the Settings toggle turns all network lookups off.
class OnlineArtworkNotifier extends Notifier<bool> {
  @override
  bool build() =>
      ref.read(sharedPreferencesProvider).getBool(_kOnlineArtworkKey) ?? true;

  void set(bool value) {
    state = value;
    ref.read(sharedPreferencesProvider).setBool(_kOnlineArtworkKey, value);
    OnlineArtwork.enabled = value;
    if (value) {
      // Tiles that resolved to "no art" while the toggle was off are cached
      // in memory; drop them so they can hit the online path now.
      ArtworkCache.instance.clear();
    }
  }
}

final onlineArtworkProvider =
    NotifierProvider<OnlineArtworkNotifier, bool>(OnlineArtworkNotifier.new);

/// Wires the online fallback into ArtworkCache once per app session, keeps
/// the enabled flag in sync with the persisted setting, and feeds the
/// fetcher the id → (title, artist, duration) catalog it needs to build
/// MusicBrainz queries (ArtworkCache itself only knows media-store ids).
/// Kept alive by the app shell (like the play tracker and widget updater).
final onlineArtworkBinderProvider = Provider<void>((ref) {
  OnlineArtwork.enabled = ref.watch(onlineArtworkProvider);
  ArtworkCache.onlineFallback = OnlineArtwork.loadForSong;
  ref.onDispose(() => ArtworkCache.onlineFallback = null);

  // RAW list so songs in excluded folders still resolve their artwork.
  ref.listen(rawSongsProvider, (previous, next) {
    final songs = next.valueOrNull;
    if (songs == null) return;
    final hadCatalog = OnlineArtwork.catalog.isNotEmpty;
    OnlineArtwork.catalog = {
      for (final s in songs)
        s.id: (
          title: s.title,
          artist: s.artist,
          durationMs: s.duration.inMilliseconds,
        ),
    };
    // Tiles rendered before the first scan finished cached "no art" in the
    // in-memory LRU (the catalog wasn't there yet, so the online path was
    // skipped). Drop the LRU once so those tiles can resolve properly.
    if (!hadCatalog && songs.isNotEmpty) ArtworkCache.instance.clear();
  }, fireImmediately: true);
});

// ---------------------------------------------------------------------------
// Fetcher
// ---------------------------------------------------------------------------

abstract final class OnlineArtwork {
  static const _mbSearch = 'https://musicbrainz.org/ws/2/recording/';
  static const _caa = 'https://coverartarchive.org';
  static const _headers = {
    // MusicBrainz requires a meaningful User-Agent identifying the app.
    'User-Agent': 'Orvo/0.1.0 (offline music player; cover art lookup)',
    'Accept': 'application/json',
  };
  static const _timeout = Duration(seconds: 10);
  static const _negativeCacheTtl = Duration(days: 14);

  /// MusicBrainz asks for at most 1 request per second.
  static const _mbSpacing = Duration(milliseconds: 1100);

  /// Flipped by the settings notifier; when false the fallback only serves
  /// what's already cached in the DB and never touches the network.
  static bool enabled = true;

  /// id → tag metadata, pushed in by [onlineArtworkBinderProvider] after
  /// every library scan. Needed because ArtworkCache only knows ids.
  static Map<int, ({String title, String artist, int durationMs})> catalog =
      const {};

  // --- Queue: serialized, LIFO, de-duplicated ------------------------------

  static final ListQueue<_Task> _stack = ListQueue();
  static final Map<int, Future<Uint8List?>> _inflight = {};
  static bool _draining = false;
  static DateTime _lastMbCall =
      DateTime.fromMillisecondsSinceEpoch(0);

  /// Entry point installed as [ArtworkCache.onlineFallback]. Returns image
  /// bytes, or null when there's (currently) nothing to show. Every non-null
  /// and negative-cache result is definitive; plain network failures return
  /// null WITHOUT being cached in the DB so they retry next session.
  static Future<Uint8List?> loadForSong(int songId) async {
    try {
      final db = await AppDatabase.instance.database;

      // 1. Local cache.
      final rows = await db.query('online_art',
          where: 'song_id = ?', whereArgs: [songId], limit: 1);
      if (rows.isNotEmpty) {
        final row = rows.first;
        if ((row['found'] as int) == 1) {
          final art = row['art'] as Uint8List?;
          if (art != null && art.isNotEmpty) return art;
        } else {
          final fetchedAt =
              DateTime.fromMillisecondsSinceEpoch(row['fetched_at'] as int);
          if (DateTime.now().difference(fetchedAt) < _negativeCacheTtl) {
            return null; // definitive "nothing found", still fresh
          }
        }
      }

      // 2. Network — only when the user has the feature on and the song is
      //    known to the library catalog.
      if (!enabled) return null;
      final meta = catalog[songId];
      if (meta == null) return null;

      final cleanTitle = _cleanTitle(meta.title);
      if (cleanTitle.isEmpty) return null;

      return _inflight[songId] ??= _enqueue(_Task(
        songId: songId,
        title: cleanTitle,
        artist: _cleanArtist(meta.artist),
        durationMs: meta.durationMs,
      )).whenComplete(() => _inflight.remove(songId));
    } catch (_) {
      return null; // never let artwork lookups break the UI
    }
  }

  static Future<Uint8List?> _enqueue(_Task task) {
    _stack.addLast(task);
    _drain();
    return task.completer.future;
  }

  static Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (_stack.isNotEmpty) {
        // LIFO: the most recently requested tile is what's on screen.
        final task = _stack.removeLast();
        Uint8List? art;
        try {
          art = await _fetch(task);
        } catch (_) {
          art = null; // network failure — not cached, retries next session
        }
        task.completer.complete(art);
      }
    } finally {
      _draining = false;
    }
  }

  // --- The lookup itself ---------------------------------------------------

  static Future<Uint8List?> _fetch(_Task task) async {
    // Respect the MusicBrainz rate limit across the whole app session.
    final wait = _mbSpacing - DateTime.now().difference(_lastMbCall);
    if (wait > Duration.zero) await Future<void>.delayed(wait);
    _lastMbCall = DateTime.now();

    if (!enabled) return null; // toggled off while queued

    // 1. Find matching recordings on MusicBrainz.
    final groupIds = await _searchReleaseGroups(task);
    if (groupIds == null) return null; // lookup unavailable — don't cache
    if (groupIds.isEmpty) {
      await _store(task.songId, null); // definitive: no match
      return null;
    }

    // 2. Try the Cover Art Archive for up to 3 candidate release groups.
    for (final id in groupIds.take(3)) {
      final art = await _fetchCover(id);
      if (art != null && art.isNotEmpty) {
        await _store(task.songId, art);
        return art;
      }
    }
    await _store(task.songId, null); // matched, but no art exists
    return null;
  }

  /// Returns candidate release-group ids best-first, an empty list for a
  /// definitive "no match", or null when MusicBrainz couldn't be reached.
  static Future<List<String>?> _searchReleaseGroups(_Task task) async {
    String esc(String s) => s.replaceAll(r'\', ' ').replaceAll('"', ' ');
    final query = task.artist == null
        ? 'recording:"${esc(task.title)}"'
        : 'recording:"${esc(task.title)}" AND artist:"${esc(task.artist!)}"';
    final uri = Uri.parse(_mbSearch).replace(queryParameters: {
      'query': query,
      'fmt': 'json',
      'limit': '8',
    });

    final http.Response res;
    try {
      res = await http.get(uri, headers: _headers).timeout(_timeout);
    } catch (_) {
      return null;
    }
    if (res.statusCode != 200) return null;

    final Object? decoded;
    try {
      decoded = jsonDecode(res.body);
    } catch (_) {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    final recordings = decoded['recordings'];
    if (recordings is! List) return const [];

    final wantSec = (task.durationMs / 1000).round();
    final ids = <String>[];
    for (final rec in recordings.whereType<Map<String, dynamic>>()) {
      final recTitle = (rec['title'] as String?) ?? '';
      if (!_similar(recTitle, task.title)) continue; // wrong song

      // Different rips drift a little; > 10s apart = wrong version.
      final lengthMs = rec['length'];
      if (lengthMs is int && wantSec > 0) {
        if (((lengthMs / 1000).round() - wantSec).abs() > 10) continue;
      }

      final releases = rec['releases'];
      if (releases is! List) continue;
      for (final rel in releases.whereType<Map<String, dynamic>>()) {
        final group = rel['release-group'];
        if (group is Map<String, dynamic>) {
          final id = group['id'];
          if (id is String && id.isNotEmpty && !ids.contains(id)) {
            ids.add(id);
          }
        }
      }
    }
    return ids;
  }

  /// Cover Art Archive: canonical front image of a release group at 500px.
  /// 404 = this group has no art; the http client follows the 307 redirect
  /// to the Internet Archive automatically.
  static Future<Uint8List?> _fetchCover(String releaseGroupId) async {
    final uri = Uri.parse('$_caa/release-group/$releaseGroupId/front-500');
    try {
      final res = await http.get(uri, headers: {
        'User-Agent': _headers['User-Agent']!,
      }).timeout(_timeout);
      if (res.statusCode != 200) return null;
      final bytes = res.bodyBytes;
      // Sanity check: JPEG (FF D8) or PNG (89 50) magic bytes.
      if (bytes.length < 4) return null;
      final jpeg = bytes[0] == 0xFF && bytes[1] == 0xD8;
      final png = bytes[0] == 0x89 && bytes[1] == 0x50;
      if (!jpeg && !png) return null;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _store(int songId, Uint8List? art) async {
    final db = await AppDatabase.instance.database;
    await db.insert(
      'online_art',
      {
        'song_id': songId,
        'art': art,
        'found': art == null ? 0 : 1,
        'fetched_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // --- Metadata cleaning (compact cousin of the lyrics matcher, FIX #28) ---

  static final _junkWords = RegExp(
    r'official|video|audio|lyric|lyrical|visuali[sz]er|full\s*song|'
    r'full\s*hd|[48]k|hd|hq|\d{2,3}\s*kbps|mp3|m4a|flac|rip|download|'
    r'from\s+the\s+movie|soundtrack|promo|teaser|trailer|out\s*now|'
    r'whatsapp|status',
    caseSensitive: false,
  );

  static final _siteTag = RegExp(
    r'[\(\[\{\|\-–—\s]*(?:www\.)?[a-z0-9\-_]+\.(?:com|in|net|org|xyz|me|cc|io)\S*',
    caseSensitive: false,
  );

  static String _cleanTitle(String raw) {
    var s = raw.trim();
    if (s.isEmpty || s.toLowerCase() == '<unknown>') return '';
    s = s.replaceAll(_siteTag, ' ');
    s = s.replaceAllMapped(RegExp(r'[\(\[\{]([^\)\]\}]*)[\)\]\}]'), (m) {
      final inner = m[1] ?? '';
      return _junkWords.hasMatch(inner) || RegExp(r'^\s*$').hasMatch(inner)
          ? ' '
          : m[0]!;
    });
    s = s.replaceAll(
        RegExp(r'\b(?:feat|ft)\.?\s+[^\-\|\(\[]+', caseSensitive: false), ' ');
    s = s.replaceFirst(RegExp(r'^\s*\d{1,3}\s*[\.\-]\s*'), '');
    final parts = s.split(RegExp(r'\s*[\|\u2022]\s*|\s+-\s+'));
    if (parts.length > 1) {
      final kept = [
        for (final p in parts)
          if (!_junkWords.hasMatch(p) && p.trim().isNotEmpty) p.trim(),
      ];
      if (kept.isNotEmpty) s = kept.first;
    }
    return _collapse(s);
  }

  static String? _cleanArtist(String raw) {
    var s = raw.trim();
    if (s.isEmpty ||
        s.toLowerCase() == '<unknown>' ||
        s.toLowerCase() == 'unknown artist' ||
        s.toLowerCase() == 'various artists') {
      return null;
    }
    s = _collapse(s.replaceAll(_siteTag, ' '));
    if (s.isEmpty) return null;
    // "A, B & C" tags rarely match MB's artist credits — use the first.
    final first = s
        .split(RegExp(r'\s*(?:,|&|;|/|\bfeat\.?\b|\bft\.?\b)\s*',
            caseSensitive: false))
        .first
        .trim();
    return first.isEmpty ? null : first;
  }

  static String _collapse(String s) => s
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .replaceAll(RegExp(r'^[\s\-\|,\.]+|[\s\-\|,\.]+$'), '')
      .trim();

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\u0900-\u097F]+'), ' ')
      .trim();

  static bool _similar(String a, String b) {
    final na = _norm(a), nb = _norm(b);
    if (na.isEmpty || nb.isEmpty) return false;
    if (na == nb || na.contains(nb) || nb.contains(na)) return true;
    final ta = na.split(' ').toSet(), tb = nb.split(' ').toSet();
    final overlap = ta.intersection(tb).length;
    return overlap / (ta.length < tb.length ? ta.length : tb.length) >= .6;
  }
}

class _Task {
  _Task({
    required this.songId,
    required this.title,
    required this.artist,
    required this.durationMs,
  });

  final int songId;
  final String title;
  final String? artist;
  final int durationMs;
  final Completer<Uint8List?> completer = Completer();
}

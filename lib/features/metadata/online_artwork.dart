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
// FEATURE (online artwork + metadata): fills in missing album covers AND
// missing artist / album / year tags from MusicBrainz + the Cover Art
// Archive. No other services are used.
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
// ACCURACY REWRITE (v2) — why the old matcher got ~30% of covers wrong and
// missed many famous songs, and what changed:
//  1. It ignored MusicBrainz's relevance `score` and took candidates in
//     arrival order.               → Now every recording gets a combined
//     score (MB score + title similarity + artist match + duration match)
//     and candidates are tried best-first.
//  2. With no usable artist tag it searched by TITLE ALONE and accepted
//     any 60%-token-overlap hit — generic titles matched the wrong song
//     entirely.                    → Title-only mode is now STRICT: it
//     requires MB score ≥ 90, an (almost) exact normalized title, and
//     duration within 5s. Wrong artwork is worse than no artwork.
//  3. It never preferred official Album / Single releases, so compilations
//     and bootlegs (with wrong art) won.
//                                  → Releases are scored: Official status,
//     primary-type Album/Single, and a big bonus when the release title
//     matches the LOCAL album tag; Compilation / Live / Remix secondary
//     types are penalized.
//  4. It only tried release-GROUP art for 3 candidates. Lots of famous
//     songs have art on the RELEASE but not the group, or on the 4th+
//     candidate.                   → Up to 6 candidates, each trying
//     release-group front THEN release front, plus a final release-group
//     search by the local ALBUM tag when the recording path finds nothing.
//  5. It threw the matched metadata away.
//                                  → The best match's artist credit, album
//     title and year are stored in `online_meta` and overlaid onto songs
//     whose local tags are `<unknown>` (see onlineMetaMapProvider).
//
// TECHNICAL DESIGN — strictly on-demand and rate-limit-polite:
//  - Nothing is fetched for tracks that already have embedded / media-store
//    artwork. The fallback fires only when the Artwork widget comes up
//    empty (see ArtworkCache.onlineFallback).
//  - One global queue serializes lookups; EVERY MusicBrainz call (recording
//    search and the album fallback search) goes through _mbGet, which
//    enforces >= 1.1s spacing (MB asks for 1 req/sec) and a descriptive
//    User-Agent. The queue is LIFO so whatever the user is LOOKING AT
//    resolves first while older backlog waits.
//  - Fetch-once, cache-forever in sqflite (online_art table): found=1 rows
//    hold the image bytes; found=0 is a negative cache with a 14-day TTL.
//    Network failures are NOT cached — they retry next session.
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

// ---------------------------------------------------------------------------
// Metadata overlay — artist / album / year detected online
// ---------------------------------------------------------------------------

/// One row of the `online_meta` table: tags detected from the best
/// MusicBrainz match for a song. Overlaid in songsProvider ONLY where the
/// local tag is `<unknown>` — real local tags are never overwritten.
class OnlineMeta {
  const OnlineMeta({this.artist, this.album, this.year});
  final String? artist;
  final String? album;
  final int? year;
}

/// Bumped (debounced) by the binder whenever the fetcher writes new
/// metadata, so the map below re-reads and the library re-enriches.
final onlineMetaRevisionProvider = StateProvider<int>((_) => 0);

/// song id → detected metadata, loaded from sqflite. songsProvider watches
/// this to fill `<unknown>` artist / album tags (FEATURE: artist detection).
final onlineMetaMapProvider =
    FutureProvider<Map<int, OnlineMeta>>((ref) async {
  ref.watch(onlineMetaRevisionProvider);
  final db = await AppDatabase.instance.database;
  final rows = await db.query('online_meta');
  return {
    for (final r in rows)
      r['song_id'] as int: OnlineMeta(
        artist: r['artist'] as String?,
        album: r['album'] as String?,
        year: r['year'] as int?,
      ),
  };
});

/// Wires the online fallback into ArtworkCache once per app session, keeps
/// the enabled flag in sync with the persisted setting, feeds the fetcher
/// the id → (title, artist, album, duration) catalog it needs to build
/// MusicBrainz queries, and relays "new metadata written" events into
/// Riverpod (debounced so the initial backfill doesn't rebuild the library
/// on every single song). Kept alive by the app shell.
final onlineArtworkBinderProvider = Provider<void>((ref) {
  OnlineArtwork.enabled = ref.watch(onlineArtworkProvider);
  ArtworkCache.onlineFallback = OnlineArtwork.loadForSong;

  // Debounced meta → provider bridge.
  Timer? debounce;
  void onMetaWritten() {
    debounce?.cancel();
    debounce = Timer(const Duration(seconds: 2), () {
      ref.read(onlineMetaRevisionProvider.notifier).state++;
    });
  }

  OnlineArtwork.metaRevision.addListener(onMetaWritten);
  ref.onDispose(() {
    OnlineArtwork.metaRevision.removeListener(onMetaWritten);
    debounce?.cancel();
    ArtworkCache.onlineFallback = null;
  });

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
          album: s.album,
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
  static const _mbRecordingSearch = 'https://musicbrainz.org/ws/2/recording/';
  static const _mbReleaseGroupSearch =
      'https://musicbrainz.org/ws/2/release-group/';
  static const _caa = 'https://coverartarchive.org';
  static const _headers = {
    // MusicBrainz requires a meaningful User-Agent identifying the app.
    'User-Agent': 'Orvo/0.1.0 (offline music player; cover art lookup)',
    'Accept': 'application/json',
  };
  static const _timeout = Duration(seconds: 10);

  /// Cover Art Archive (Internet Archive) can be very slow from some
  /// regions; a long timeout here blocks the whole serialized queue, which
  /// looks like "no artwork anywhere". Fail fast and move on.
  static const _caaTimeout = Duration(seconds: 8);
  static const _negativeCacheTtl = Duration(days: 14);

  /// MusicBrainz asks for at most 1 request per second.
  static const _mbSpacing = Duration(milliseconds: 1100);

  /// Flipped by the settings notifier; when false the fallback only serves
  /// what's already cached in the DB and never touches the network.
  static bool enabled = true;

  /// Fires (value bumps) whenever a new `online_meta` row is written. The
  /// binder relays this into [onlineMetaRevisionProvider], debounced.
  static final ValueNotifier<int> metaRevision = ValueNotifier(0);

  /// id → tag metadata, pushed in by [onlineArtworkBinderProvider] after
  /// every library scan. Needed because ArtworkCache only knows ids.
  static Map<int,
          ({String title, String artist, String album, int durationMs})>
      catalog = const {};

  // --- Queue: serialized, LIFO, de-duplicated ------------------------------

  static final ListQueue<_Task> _stack = ListQueue();
  static final Map<int, Future<Uint8List?>> _inflight = {};
  static bool _draining = false;
  static DateTime _lastMbCall = DateTime.fromMillisecondsSinceEpoch(0);

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
        album: _cleanAlbum(meta.album),
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
    if (!enabled) return null; // toggled off while queued

    // 1. Search + score recordings on MusicBrainz.
    final recs = await _searchRecordings(task);
    if (recs == null) return null; // MB unreachable — don't cache, retry

    // 2. Persist detected metadata from the single best match, so
    //    `<unknown>` artist / album tags get filled even when no cover
    //    image exists anywhere.
    if (recs.isNotEmpty) {
      await _storeMeta(task.songId, recs.first);
    }

    // 3. Try the Cover Art Archive: candidates from ALL accepted
    //    recordings, best-first, de-duplicated — release-group front
    //    first, then the specific release's front. Capped at 3 candidates
    //    (max ~6 quick requests) so one art-less song can't stall the
    //    queue behind slow Internet Archive responses.
    final seen = <String>{};
    var tried = 0;
    for (final rec in recs) {
      for (final cand in rec.candidates) {
        if (!seen.add(cand.key)) continue;
        if (++tried > 3) break;
        final art = await _artFor(cand);
        if (art != null) {
          _log('art FOUND for "${task.title}" '
              '(candidate $tried: ${cand.releaseTitle ?? cand.key})');
          await _store(task.songId, art);
          return art;
        }
      }
      if (tried > 3) break;
    }

    // 4. Fallback: search release-groups by the LOCAL ALBUM TAG. Covers the
    //    common case where the recording path matched nothing (messy title)
    //    or its release-groups have no art, but the album itself does.
    if (task.album != null) {
      final groups = await _searchAlbumGroups(task);
      if (groups == null) return null; // MB unreachable mid-way — retry later
      for (final id in groups.take(2)) {
        final art = await _fetchCover('release-group', id);
        if (art != null) {
          _log('art FOUND for "${task.title}" via album "${task.album}"');
          await _store(task.songId, art);
          return art;
        }
      }
    }

    // Definitive: matched (or definitively didn't), but no art exists.
    _log('no art for "${task.title}" — negative-cached '
        '(${recs.length} accepted recording(s), $tried candidate(s) tried)');
    await _store(task.songId, null);
    return null;
  }

  /// One rate-limited, header-correct MusicBrainz GET. Returns the decoded
  /// JSON object, or null when MB couldn't be reached / answered non-200.
  static Future<Map<String, dynamic>?> _mbGet(Uri uri) async {
    final wait = _mbSpacing - DateTime.now().difference(_lastMbCall);
    if (wait > Duration.zero) await Future<void>.delayed(wait);
    _lastMbCall = DateTime.now();

    final http.Response res;
    try {
      res = await http.get(uri, headers: _headers).timeout(_timeout);
    } catch (e) {
      _log('MusicBrainz UNREACHABLE (${e.runtimeType}) — will retry later');
      return null;
    }
    if (res.statusCode != 200) {
      _log('MusicBrainz HTTP ${res.statusCode} — will retry later');
      return null;
    }
    try {
      final decoded = jsonDecode(res.body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  /// Searches recordings and returns accepted candidates sorted by combined
  /// score (best first). Empty list = definitive "no acceptable match";
  /// null = MusicBrainz unreachable (don't cache).
  static Future<List<_ScoredRec>?> _searchRecordings(_Task task) async {
    String esc(String s) => s.replaceAll(r'\', ' ').replaceAll('"', ' ');
    // FIX (log-driven, "Sajni" case): common one-word titles return 15
    // wrong versions and the right one never even makes the result page.
    // Sending the local file's duration as a server-side filter
    // (dur:[min TO max], ±12s) makes the result page contain the right
    // VERSIONS in the first place.
    final parts = <String>['recording:"${esc(task.title)}"'];
    if (task.artist != null) parts.add('artist:"${esc(task.artist!)}"');
    if (task.durationMs > 30000) {
      parts.add('dur:[${task.durationMs - 12000} TO ${task.durationMs + 12000}]');
    }
    final uri = Uri.parse(_mbRecordingSearch).replace(queryParameters: {
      'query': parts.join(' AND '),
      'fmt': 'json',
      'limit': '15',
    });

    final decoded = await _mbGet(uri);
    if (decoded == null) return null;
    final recordings = decoded['recordings'];
    if (recordings is! List) return const [];

    final wantSec = (task.durationMs / 1000).round();
    final accepted = <_ScoredRec>[];

    for (final rec in recordings.whereType<Map<String, dynamic>>()) {
      final mbScore = (rec['score'] as num?)?.toDouble() ?? 0;
      final recTitle = (rec['title'] as String?) ?? '';
      final recId = rec['id'] as String?;

      // FIX (log-driven, "Kismat Se (From "Raunaq") [feat. …]" case):
      // MusicBrainz's own titles carry decorations too. Compare against the
      // CLEANED MB title as well, otherwise the exact-title check fails on
      // recordings that ARE the right song.
      final cleanedRecTitle = _cleanTitle(recTitle);

      // -- Title gate ------------------------------------------------------
      final simRaw = _titleSimilarity(recTitle, task.title);
      final simClean = _titleSimilarity(cleanedRecTitle, task.title);
      final titleSim = simRaw > simClean ? simRaw : simClean;
      if (titleSim < .6) {
        _log('reject "$recTitle": title sim '
            '${titleSim.toStringAsFixed(2)} vs "${task.title}"');
        continue; // wrong song
      }

      // -- Duration gate ---------------------------------------------------
      // Different rips drift a little; > 10s apart = wrong version.
      final lengthMs = rec['length'];
      int? secDiff;
      if (lengthMs is int && wantSec > 0) {
        secDiff = ((lengthMs / 1000).round() - wantSec).abs();
        if (secDiff > 10) {
          _log('reject "$recTitle": duration diff ${secDiff}s');
          continue;
        }
      }

      // -- Artist gate -----------------------------------------------------
      final creditNames = <String>[];
      var joinedCredit = '';
      final credits = rec['artist-credit'];
      if (credits is List) {
        for (final c in credits.whereType<Map<String, dynamic>>()) {
          final name = (c['name'] as String?) ??
              ((c['artist'] is Map<String, dynamic>)
                  ? (c['artist']['name'] as String?)
                  : null) ??
              '';
          if (name.isNotEmpty) creditNames.add(name);
          joinedCredit += name + ((c['joinphrase'] as String?) ?? '');
        }
      }

      var artistMatched = false;
      if (task.artist != null) {
        // We HAVE a local artist tag: the match must agree with it. This is
        // the single biggest fix for wrong covers.
        artistMatched = creditNames.any((n) => _artistSimilar(n, task.artist!)) ||
            _artistSimilar(joinedCredit, task.artist!);
        if (!artistMatched) {
          _log('reject "$recTitle": artist "$joinedCredit" '
              '!= tag "${task.artist}"');
          continue;
        }
      } else {
        // Title-only mode: only accept a near-certain hit. Missing this is
        // fine; showing the wrong band's cover is not.
        // FIX (log-driven, "Sooiyan" case): exactness is judged on the
        // CLEANED titles, and duration up to 10s off is accepted when the
        // title is exact — the query is already duration-filtered
        // server-side, so these are the right versions.
        final exactTitle = _norm(recTitle) == _norm(task.title) ||
            _norm(cleanedRecTitle) == _norm(task.title);
        final durOk = secDiff != null ? secDiff <= 10 : mbScore >= 95;
        if (mbScore < 90 || !exactTitle || !durOk) {
          _log('reject "$recTitle": title-only strict gate '
              '(score $mbScore, exact $exactTitle, dur ${secDiff ?? "?"}s)');
          continue;
        }
      }

      // -- Score + collect art candidates ---------------------------------
      final releases = rec['releases'];
      final candidates = <_ArtCandidate>[];
      var albumTagHit = false;
      String? bestAlbum;
      int? bestYear;
      if (releases is List) {
        for (final rel in releases.whereType<Map<String, dynamic>>()) {
          final scored = _scoreRelease(rel, task.album);
          if (scored == null) continue;
          candidates.add(scored);
          if (scored.matchesLocalAlbum) albumTagHit = true;
        }
        candidates.sort((a, b) => b.relScore.compareTo(a.relScore));
        if (candidates.isNotEmpty) {
          bestAlbum = candidates.first.releaseTitle;
          bestYear = candidates.first.year;
        }
      }

      final combined = mbScore +
          titleSim * 30 +
          (artistMatched ? 25 : 0) +
          (secDiff == null ? 0 : (secDiff <= 5 ? 10 : 5)) +
          (albumTagHit ? 20 : 0);

      accepted.add(_ScoredRec(
        score: combined,
        recordingId: recId,
        artist: joinedCredit.isNotEmpty
            ? joinedCredit
            : (creditNames.isNotEmpty ? creditNames.join(', ') : null),
        album: bestAlbum,
        year: bestYear,
        candidates: candidates,
      ));
    }

    accepted.sort((a, b) => b.score.compareTo(a.score));
    if (accepted.isNotEmpty) {
      _log('accept "${task.title}" → "${accepted.first.album}" by '
          '"${accepted.first.artist}" '
          '(score ${accepted.first.score.toStringAsFixed(0)}, '
          '${accepted.length} candidate(s))');
    }
    return accepted;
  }

  /// Scores one release from a recording's `releases` list. Prefers
  /// Official Album/Single releases whose title matches the local album
  /// tag; penalizes bootlegs, compilations, live and remix releases.
  static _ArtCandidate? _scoreRelease(
      Map<String, dynamic> rel, String? localAlbum) {
    final relId = rel['id'];
    final group = rel['release-group'];
    final groupId = (group is Map<String, dynamic>) ? group['id'] : null;
    if (relId is! String && groupId is! String) return null;

    var s = 0;
    final status = (rel['status'] as String?)?.toLowerCase();
    if (status == 'official') {
      s += 30;
    } else if (status == 'bootleg') {
      s -= 40;
    }

    if (group is Map<String, dynamic>) {
      final primary = (group['primary-type'] as String?)?.toLowerCase();
      s += switch (primary) {
        'album' => 25,
        'single' => 20,
        'ep' => 15,
        _ => 0,
      };
      final secondary = group['secondary-types'];
      if (secondary is List &&
          secondary.whereType<String>().any((t) => const {
                'compilation',
                'live',
                'remix',
                'dj-mix',
                'mixtape/street',
              }.contains(t.toLowerCase()))) {
        s -= 25;
      }
    }

    final relTitle = rel['title'] as String?;
    var matchesLocal = false;
    if (localAlbum != null &&
        relTitle != null &&
        _titleSimilarity(relTitle, localAlbum) >= .6) {
      s += 60; // right album by the user's own tag — strongest signal
      matchesLocal = true;
    }

    final date = rel['date'] as String?;
    int? year;
    if (date != null && date.length >= 4) {
      year = int.tryParse(date.substring(0, 4));
      if (year != null) s += 5;
    }

    return _ArtCandidate(
      releaseGroupId: groupId is String ? groupId : null,
      releaseId: relId is String ? relId : null,
      relScore: s,
      releaseTitle: relTitle,
      date: date,
      year: year,
      matchesLocalAlbum: matchesLocal,
    );
  }

  /// Fallback path: search release-groups directly by the local album tag.
  /// Returns candidate ids best-first, empty for "no match", null when MB
  /// couldn't be reached.
  static Future<List<String>?> _searchAlbumGroups(_Task task) async {
    String esc(String s) => s.replaceAll(r'\', ' ').replaceAll('"', ' ');
    final album = task.album!;
    final query = task.artist == null
        ? 'releasegroup:"${esc(album)}"'
        : 'releasegroup:"${esc(album)}" AND artist:"${esc(task.artist!)}"';
    final uri = Uri.parse(_mbReleaseGroupSearch).replace(queryParameters: {
      'query': query,
      'fmt': 'json',
      'limit': '8',
    });

    final decoded = await _mbGet(uri);
    if (decoded == null) return null;
    final groups = decoded['release-groups'];
    if (groups is! List) return const [];

    final scored = <(double, String)>[];
    for (final g in groups.whereType<Map<String, dynamic>>()) {
      final id = g['id'];
      if (id is! String || id.isEmpty) continue;
      final title = (g['title'] as String?) ?? '';
      if (_titleSimilarity(title, album) < .6) continue;

      // Without an artist tag the album title alone must be a top,
      // near-exact hit — same "no guessing" philosophy as recordings.
      final mbScore = (g['score'] as num?)?.toDouble() ?? 0;
      if (task.artist == null &&
          (mbScore < 95 || _norm(title) != _norm(album))) {
        continue;
      }
      scored.add((mbScore, id));
    }
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    return [for (final s in scored) s.$2];
  }

  /// One art candidate: release-group front first (canonical), then the
  /// specific release's front — lots of releases have art even when their
  /// group doesn't (and vice versa).
  static Future<Uint8List?> _artFor(_ArtCandidate cand) async {
    if (cand.releaseGroupId != null) {
      final art = await _fetchCover('release-group', cand.releaseGroupId!);
      if (art != null) return art;
    }
    if (cand.releaseId != null) {
      final art = await _fetchCover('release', cand.releaseId!);
      if (art != null) return art;
    }
    return null;
  }

  /// Cover Art Archive: front image at 500px. 404 = no art; the http client
  /// follows the 307 redirect to the Internet Archive automatically.
  static Future<Uint8List?> _fetchCover(String kind, String id) async {
    final uri = Uri.parse('$_caa/$kind/$id/front-500');
    final sw = Stopwatch()..start();
    try {
      final res = await http.get(uri, headers: {
        'User-Agent': _headers['User-Agent']!,
      }).timeout(_caaTimeout);
      _log('CAA $kind/$id → ${res.statusCode} in ${sw.elapsedMilliseconds}ms');
      if (res.statusCode != 200) return null;
      final bytes = res.bodyBytes;
      // Sanity check: JPEG (FF D8) or PNG (89 50) magic bytes.
      if (bytes.length < 4) return null;
      final jpeg = bytes[0] == 0xFF && bytes[1] == 0xD8;
      final png = bytes[0] == 0x89 && bytes[1] == 0x50;
      if (!jpeg && !png) return null;
      return bytes;
    } catch (e) {
      _log('CAA $kind/$id → FAILED (${e.runtimeType}) '
          'in ${sw.elapsedMilliseconds}ms');
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

  /// Persists the best match's detected tags plus its MusicBrainz ids
  /// (spec §12/§14 — cached so identical lookups never repeat, and future
  /// features like "refetch at higher resolution" get the ids for free),
  /// and pings the UI bridge.
  static Future<void> _storeMeta(int songId, _ScoredRec best) async {
    if (best.artist == null && best.album == null && best.year == null) {
      return;
    }
    final top = best.candidates.isNotEmpty ? best.candidates.first : null;
    final db = await AppDatabase.instance.database;
    await db.insert(
      'online_meta',
      {
        'song_id': songId,
        'artist': best.artist,
        'album': best.album,
        'year': best.year,
        'date': top?.date,
        'recording_id': best.recordingId,
        'release_id': top?.releaseId,
        'release_group_id': top?.releaseGroupId,
        'fetched_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    metaRevision.value++;
  }

  // --- Metadata cleaning (compact cousin of the lyrics matcher, FIX #28) ---

  static final _junkWords = RegExp(
    r'official|video|audio|lyric|lyrical|visuali[sz]er|full\s*song|'
    r'full\s*hd|[48]k|hd|hq|\d{2,3}\s*kbps|mp3|m4a|flac|rip|download|'
    r'from\s+the\s+movie|soundtrack|promo|teaser|trailer|out\s*now|'
    r'whatsapp|status',
    caseSensitive: false,
  );

  /// Version descriptors stripped from TITLES only (bracketed or after a
  /// dash): "Believer (Remastered 2020)" → "Believer", "Tum Hi Ho (From
  /// Aashiqui 2)" → "Tum Hi Ho". Deliberately NOT applied to album tags —
  /// "Live at Wembley" is a real album name — and safe for search because
  /// the duration gate still keeps the right VERSION from matching wrong.
  static final _versionWords = RegExp(
    r'remaster|re-?recorded|radio\s*edit|single\s*version|album\s*version|'
    r'extended(?:\s*(?:mix|version))?|deluxe|anniversary|expanded|'
    r'bonus\s*track|karaoke|tribute|instrumental|acoustic|unplugged|'
    r'\blive\b|explicit|clean\s*version|\bmono\b|\bstereo\b|'
    r'\bfrom\b\s+\S|original\s*motion\s*picture',
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
      return _junkWords.hasMatch(inner) ||
              _versionWords.hasMatch(inner) ||
              RegExp(r'^\s*$').hasMatch(inner)
          ? ' '
          : m[0]!;
    });
    s = s.replaceAll(
        RegExp(r'\b(?:feat|ft)\.?\s+[^\-\|\(\[]+', caseSensitive: false), ' ');
    s = s.replaceFirst(RegExp(r'^\s*\d{1,3}\s*[\.\-]\s*'), '');
    final parts = s.split(RegExp(r'\s*[\|\u2022]\s*|\s+[-\u2013\u2014]\s+'));
    if (parts.length > 1) {
      final kept = [
        for (final p in parts)
          if (!_junkWords.hasMatch(p) &&
              !_versionWords.hasMatch(p) &&
              p.trim().isNotEmpty)
            p.trim(),
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

  /// Album tags are junk-prone too ("Unknown album", site names, folder
  /// dumps). null = don't use the album path at all.
  static String? _cleanAlbum(String raw) {
    var s = raw.trim();
    final lower = s.toLowerCase();
    if (s.isEmpty ||
        lower == '<unknown>' ||
        lower == 'unknown' ||
        lower == 'unknown album' ||
        lower == 'music' ||
        lower == 'download' ||
        lower == 'downloads' ||
        lower == 'audio') {
      return null;
    }
    s = _collapse(s.replaceAll(_siteTag, ' '));
    if (s.isEmpty || _junkWords.hasMatch(s)) return null;
    return s;
  }

  static String _collapse(String s) => s
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .replaceAll(RegExp(r'^[\s\-\|,\.]+|[\s\-\|,\.]+$'), '')
      .trim();

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\u0900-\u097F]+'), ' ')
      .trim();

  /// Spec §15: debug-build-only trace of why candidates were rejected /
  /// accepted, for tuning the matcher against real libraries. Stripped
  /// from release builds automatically (kDebugMode is a compile constant).
  static void _log(String message) {
    if (kDebugMode) debugPrint('[OnlineArtwork] $message');
  }

  /// 0..1 title similarity. Stricter than the old matcher: token overlap is
  /// measured against the LONGER title (the old min-based ratio let
  /// "Song X (DJ Remix Compilation)" match "Song X" at 100%), and short
  /// titles must overlap almost completely — "Tum Hi Ho" sharing 2 of 3
  /// words with "Tum Se Hi" is still a different song.
  static double _titleSimilarity(String a, String b) {
    final na = _norm(a), nb = _norm(b);
    if (na.isEmpty || nb.isEmpty) return 0;
    if (na == nb) return 1;
    if (na.replaceAll(' ', '') == nb.replaceAll(' ', '')) return 1;
    if (na.contains(nb) || nb.contains(na)) return .85;
    final ta = na.split(' ').toSet(), tb = nb.split(' ').toSet();
    final overlap = ta.intersection(tb).length;
    final larger = ta.length > tb.length ? ta.length : tb.length;
    final ratio = overlap / larger;
    if (larger <= 3 && overlap < larger) return ratio * .7;
    return ratio;
  }

  /// Artist names get a softer bar than titles: MB credits are often
  /// "A feat. B" while the tag says just "A" (or vice versa). Compact-form
  /// equality handles punctuation variants: "A.R. Rahman" ≡ "AR Rahman".
  static bool _artistSimilar(String a, String b) {
    final na = _norm(a), nb = _norm(b);
    if (na.isEmpty || nb.isEmpty) return false;
    if (na == nb || na.contains(nb) || nb.contains(na)) return true;
    if (na.replaceAll(' ', '') == nb.replaceAll(' ', '')) return true;
    final ta = na.split(' ').toSet(), tb = nb.split(' ').toSet();
    final overlap = ta.intersection(tb).length;
    final smaller = ta.length < tb.length ? ta.length : tb.length;
    return overlap / smaller >= .5;
  }
}

/// One recording accepted by the matcher, with everything needed for both
/// artwork (candidates) and metadata (artist / album / year).
class _ScoredRec {
  _ScoredRec({
    required this.score,
    required this.recordingId,
    required this.artist,
    required this.album,
    required this.year,
    required this.candidates,
  });

  final double score;
  final String? recordingId;
  final String? artist;
  final String? album;
  final int? year;
  final List<_ArtCandidate> candidates;
}

class _ArtCandidate {
  _ArtCandidate({
    required this.releaseGroupId,
    required this.releaseId,
    required this.relScore,
    required this.releaseTitle,
    required this.date,
    required this.year,
    required this.matchesLocalAlbum,
  });

  final String? releaseGroupId;
  final String? releaseId;
  final int relScore;
  final String? releaseTitle;
  final String? date;
  final int? year;
  final bool matchesLocalAlbum;

  String get key => releaseGroupId ?? releaseId ?? '';
}

class _Task {
  _Task({
    required this.songId,
    required this.title,
    required this.artist,
    required this.album,
    required this.durationMs,
  });

  final int songId;
  final String title;
  final String? artist;
  final String? album;
  final int durationMs;
  final Completer<Uint8List?> completer = Completer();
}

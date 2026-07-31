import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';
import '../../core/i18n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/bg_theme_provider.dart';
import '../../core/theme/skin_provider.dart';
import '../../core/theme/theme_provider.dart';
import '../favorites/favorites_provider.dart';
import '../library/domain/entities.dart';
import '../library/providers/exclusions_provider.dart';
import '../library/providers/library_providers.dart';
import '../lyrics/lyrics_provider.dart';
import '../player/providers/audio_settings.dart';
import '../playlists/providers/playlist_providers.dart';
import '../stats/play_stats.dart';

// ---------------------------------------------------------------------------
// FEATURE (backup): backup & restore of everything Orvo knows that isn't the
// audio files themselves — playlists, favorites, play statistics, excluded
// folders, and settings — as a single JSON document the user saves via the
// system picker (Google Drive shows up as a destination when installed).
//
// DESIGN — durable song references. Media-store ids are NOT stable across
// reinstalls or factory resets, so every song is stored as
// { id, path, title, artist, durationMs } and resolved on restore in this
// order: exact path → exact id (same device, library unchanged) → metadata
// match (title + artist + duration, ±1s). Songs that can't be resolved are
// counted and reported, never guessed.
//
// DESIGN — restore is a MERGE, never a wipe. Favorites and excluded folders
// are unioned, play counts take the maximum of local vs backup, and
// playlists are recreated unless an identical one (same name, same length)
// already exists. Restoring twice is therefore harmless.
// ---------------------------------------------------------------------------

const int kBackupFormatVersion = 1;

/// What a restore actually did, for the summary dialog.
class RestoreSummary {
  const RestoreSummary({
    required this.playlistsAdded,
    required this.playlistsSkipped,
    required this.favoritesAdded,
    required this.statsMerged,
    required this.foldersExcluded,
    required this.settingsApplied,
    required this.unresolvedSongs,
  });

  final int playlistsAdded;
  final int playlistsSkipped;
  final int favoritesAdded;
  final int statsMerged;
  final int foldersExcluded;
  final bool settingsApplied;

  /// Referenced songs that don't exist in this device's library.
  final int unresolvedSongs;
}

/// Thrown when the picked file isn't an Orvo backup.
class InvalidBackupException implements Exception {
  const InvalidBackupException();
}

final backupServiceProvider = Provider<BackupService>((ref) {
  return BackupService(ref);
});

class BackupService {
  BackupService(this._ref);

  final Ref _ref;

  /// Suggested file name — "orvo-backup-2026-08-01.json".
  static String suggestedFileName() {
    final now = DateTime.now().toIso8601String().substring(0, 10);
    return 'orvo-backup-$now.json';
  }

  // -------------------------------------------------------------------------
  // Export
  // -------------------------------------------------------------------------

  Future<String> buildBackupJson() async {
    // RAW list on purpose: favorites / stats for songs inside excluded
    // folders must survive the round trip too.
    final songs = await _ref.read(rawSongsProvider.future);
    final byId = {for (final s in songs) s.id: s};

    Map<String, dynamic> refOf(int songId) {
      final s = byId[songId];
      if (s == null) return {'id': songId};
      return {
        'id': s.id,
        'path': s.path,
        'title': s.title,
        'artist': s.artist,
        'durationMs': s.duration.inMilliseconds,
      };
    }

    // Playlists with their ordered songs.
    final repo = _ref.read(playlistRepositoryProvider);
    final playlists = <Map<String, dynamic>>[];
    for (final p in await repo.playlists()) {
      final ids = await repo.songIds(p.id);
      playlists.add({
        'name': p.name,
        'createdAt': p.createdAt,
        'songs': [for (final id in ids) refOf(id)],
      });
    }

    // Play statistics.
    final db = await AppDatabase.instance.database;
    final statRows = await db.query('play_stats');
    final stats = [
      for (final r in statRows)
        {
          'song': refOf(r['song_id'] as int),
          'playCount': r['play_count'] as int,
          'lastPlayedAt': r['last_played_at'] as int,
        },
    ];

    final payload = <String, dynamic>{
      'app': 'orvo',
      'backupVersion': kBackupFormatVersion,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'settings': {
        'theme': _ref.read(themeProvider).name,
        'skin': _ref.read(skinProvider).name,
        'bgTheme': _ref.read(bgThemeProvider)?.id,
        'language': _ref.read(languageProvider).name,
        'dynamicColor': _ref.read(dynamicColorProvider),
        'smoothTransitions': _ref.read(smoothTransitionsProvider),
        'crossfadeSec': _ref.read(crossfadeProvider),
        'btAutoResume': _ref.read(btAutoResumeProvider),
        'onlineLyrics': _ref.read(onlineLyricsProvider),
      },
      'favorites': [
        for (final id in _ref.read(favoritesProvider)) refOf(id),
      ],
      'excludedFolders': _ref.read(excludedFoldersProvider).toList(),
      'playlists': playlists,
      'playStats': stats,
    };

    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  // -------------------------------------------------------------------------
  // Inspect (pre-restore preview)
  // -------------------------------------------------------------------------

  /// Parses and validates a backup, returning (playlists, favorites, stats,
  /// createdAt millis) counts for the confirmation dialog. Throws
  /// [InvalidBackupException] when the file isn't an Orvo backup.
  (int, int, int, int?) inspect(String jsonText) {
    final map = _decode(jsonText);
    final playlists = (map['playlists'] as List?)?.length ?? 0;
    final favorites = (map['favorites'] as List?)?.length ?? 0;
    final stats = (map['playStats'] as List?)?.length ?? 0;
    final createdAt = map['createdAt'] as int?;
    return (playlists, favorites, stats, createdAt);
  }

  Map<String, dynamic> _decode(String jsonText) {
    Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } catch (_) {
      throw const InvalidBackupException();
    }
    if (decoded is! Map<String, dynamic> || decoded['app'] != 'orvo') {
      throw const InvalidBackupException();
    }
    final version = decoded['backupVersion'];
    if (version is! int || version < 1 || version > kBackupFormatVersion) {
      throw const InvalidBackupException();
    }
    return decoded;
  }

  // -------------------------------------------------------------------------
  // Restore
  // -------------------------------------------------------------------------

  Future<RestoreSummary> restore(String jsonText) async {
    final map = _decode(jsonText);
    final songs = await _ref.read(rawSongsProvider.future);
    final resolver = _SongResolver(songs);

    var unresolved = 0;
    int? resolveRef(Object? rawRef) {
      if (rawRef is! Map) return null;
      final id = resolver.resolve(rawRef.cast<String, dynamic>());
      if (id == null) unresolved++;
      return id;
    }

    // 1. Settings — each one individually best-effort so a single bad value
    //    can never abort the whole restore.
    var settingsApplied = false;
    final settings = map['settings'];
    if (settings is Map) {
      settingsApplied = true;
      _apply(() {
        final name = settings['theme'];
        if (name is String) {
          final theme = OrvoTheme.values.where((t) => t.name == name);
          if (theme.isNotEmpty) {
            _ref.read(themeProvider.notifier).set(theme.first);
          }
        }
      });
      _apply(() {
        final name = settings['skin'];
        if (name is String) {
          final skin = OrvoSkin.values.where((s) => s.name == name);
          if (skin.isNotEmpty) _ref.read(skinProvider.notifier).set(skin.first);
        }
      });
      _apply(() {
        final id = settings['bgTheme'];
        if (id == null) {
          _ref.read(bgThemeProvider.notifier).set(null);
        } else if (id is String) {
          final bg = kBgThemes.where((b) => b.id == id);
          if (bg.isNotEmpty) _ref.read(bgThemeProvider.notifier).set(bg.first);
        }
      });
      _apply(() {
        final name = settings['language'];
        if (name is String) {
          final lang = AppLanguage.values.where((l) => l.name == name);
          if (lang.isNotEmpty) {
            _ref.read(languageProvider.notifier).set(lang.first);
          }
        }
      });
      _apply(() {
        final v = settings['dynamicColor'];
        if (v is bool) _ref.read(dynamicColorProvider.notifier).set(v);
      });
      _apply(() {
        final v = settings['smoothTransitions'];
        if (v is bool) _ref.read(smoothTransitionsProvider.notifier).set(v);
      });
      _apply(() {
        final v = settings['crossfadeSec'];
        if (v is int && v >= 0 && v <= 30) {
          _ref.read(crossfadeProvider.notifier).set(v);
        }
      });
      _apply(() {
        final v = settings['btAutoResume'];
        if (v is bool) _ref.read(btAutoResumeProvider.notifier).set(v);
      });
      _apply(() {
        final v = settings['onlineLyrics'];
        if (v is bool) _ref.read(onlineLyricsProvider.notifier).set(v);
      });
    }

    // 2. Favorites — union.
    var favoritesAdded = 0;
    final favNotifier = _ref.read(favoritesProvider.notifier);
    final favList = map['favorites'];
    if (favList is List) {
      for (final rawRef in favList) {
        final id = resolveRef(rawRef);
        if (id == null) continue;
        if (!_ref.read(favoritesProvider).contains(id)) {
          favNotifier.toggle(id);
          favoritesAdded++;
        }
      }
    }

    // 3. Excluded folders — union (only paths that exist on this device, so
    //    a backup from another phone can't litter the exclusions screen).
    var foldersExcluded = 0;
    final exclList = map['excludedFolders'];
    if (exclList is List) {
      final devicePaths = <String>{
        for (final s in songs)
          if (s.path.contains('/'))
            s.path.substring(0, s.path.lastIndexOf('/')),
      };
      final exclNotifier = _ref.read(excludedFoldersProvider.notifier);
      for (final raw in exclList) {
        if (raw is! String) continue;
        final known = devicePaths
            .any((p) => p == raw || p.startsWith('$raw/'));
        if (!known) continue;
        if (!_ref.read(excludedFoldersProvider).contains(raw)) {
          exclNotifier.toggle(raw);
          foldersExcluded++;
        }
      }
    }

    // 4. Playlists — recreate unless an identical one already exists.
    var playlistsAdded = 0;
    var playlistsSkipped = 0;
    final plList = map['playlists'];
    if (plList is List) {
      final repo = _ref.read(playlistRepositoryProvider);
      final existing = await repo.playlists();
      for (final rawPl in plList) {
        if (rawPl is! Map) continue;
        final name = (rawPl['name'] as String?)?.trim() ?? '';
        if (name.isEmpty) continue;
        final refs = rawPl['songs'];
        final ids = <int>[
          if (refs is List)
            for (final r in refs)
              if (resolveRef(r) case final int id) id,
        ];
        final duplicate = existing.any(
            (p) => p.name == name && p.songCount == ids.length);
        if (duplicate) {
          playlistsSkipped++;
          continue;
        }
        final newId = await repo.create(name);
        if (ids.isNotEmpty) await repo.addSongs(newId, ids);
        playlistsAdded++;
      }
    }

    // 5. Play stats — keep whichever count is higher, and the most recent
    //    last-played time (restoring can only preserve history, not shrink
    //    or inflate it).
    var statsMerged = 0;
    final statList = map['playStats'];
    if (statList is List) {
      final db = await AppDatabase.instance.database;
      final batch = db.batch();
      for (final rawStat in statList) {
        if (rawStat is! Map) continue;
        final id = resolveRef(rawStat['song']);
        final count = rawStat['playCount'];
        final lastAt = rawStat['lastPlayedAt'];
        if (id == null || count is! int || lastAt is! int || count <= 0) {
          continue;
        }
        batch.rawInsert('''
          INSERT INTO play_stats(song_id, play_count, last_played_at)
          VALUES(?, ?, ?)
          ON CONFLICT(song_id) DO UPDATE SET
            play_count = MAX(play_count, excluded.play_count),
            last_played_at = MAX(last_played_at, excluded.last_played_at)
        ''', [id, count, lastAt]);
        statsMerged++;
      }
      await batch.commit(noResult: true);
    }

    // Refresh everything that read the merged data.
    _ref.invalidate(playlistsProvider);
    _ref.invalidate(recentlyPlayedProvider);
    _ref.invalidate(mostPlayedProvider);

    return RestoreSummary(
      playlistsAdded: playlistsAdded,
      playlistsSkipped: playlistsSkipped,
      favoritesAdded: favoritesAdded,
      statsMerged: statsMerged,
      foldersExcluded: foldersExcluded,
      settingsApplied: settingsApplied,
      unresolvedSongs: unresolved,
    );
  }

  static void _apply(void Function() fn) {
    try {
      fn();
    } catch (_) {
      // A single bad setting must never abort the restore.
    }
  }
}

// ---------------------------------------------------------------------------
// Song reference resolution
// ---------------------------------------------------------------------------

class _SongResolver {
  _SongResolver(List<Song> songs)
      : _byPath = {for (final s in songs) s.path: s},
        _byId = {for (final s in songs) s.id: s} {
    for (final s in songs) {
      // First writer wins so resolution is deterministic.
      _byMeta.putIfAbsent(_metaKey(s.title, s.artist, s.duration.inMilliseconds), () => s);
    }
  }

  final Map<String, Song> _byPath;
  final Map<int, Song> _byId;
  final Map<String, Song> _byMeta = {};

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _metaKey(String title, String artist, int durationMs) =>
      '${_norm(title)}|${_norm(artist)}|${(durationMs / 1000).round()}';

  int? resolve(Map<String, dynamic> ref) {
    // 1. Exact path — same device, file untouched.
    final path = ref['path'];
    if (path is String && path.isNotEmpty) {
      final byPath = _byPath[path];
      if (byPath != null) return byPath.id;
    }

    final title = ref['title'];
    final artist = ref['artist'];
    final durationMs = ref['durationMs'];

    // 2. Exact media-store id — only trusted when the title still matches
    //    (ids get recycled after factory resets), or when the backup carried
    //    an id-only reference (orphan rows from the source device).
    final id = ref['id'];
    if (id is int) {
      final byId = _byId[id];
      if (byId != null) {
        if (title is! String || _norm(byId.title) == _norm(title)) {
          return byId.id;
        }
      }
    }

    // 3. Metadata match: title + artist + duration (±1 second).
    if (title is String && artist is String && durationMs is int) {
      final bucket = (durationMs / 1000).round();
      for (final b in [bucket, bucket - 1, bucket + 1]) {
        final hit = _byMeta['${_norm(title)}|${_norm(artist)}|$b'];
        if (hit != null) return hit.id;
      }
    }
    return null;
  }
}

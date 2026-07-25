import 'package:sqflite/sqflite.dart';

import '../../../core/db/app_database.dart';

class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.songCount,
  });

  final int id;
  final String name;
  final int createdAt;
  final int songCount;
}

/// FIX (#15): the schema now uses a surrogate key, so the same song can be
/// added to a playlist more than once, [addSongs] reports how many rows were
/// added (no more silent drops), and reorder/remove operate on row ids so
/// duplicates behave correctly.
class PlaylistRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  Future<List<Playlist>> playlists() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT p.id, p.name, p.created_at,
             COUNT(ps.song_id) AS song_count
      FROM playlists p
      LEFT JOIN playlist_songs ps ON ps.playlist_id = p.id
      GROUP BY p.id
      ORDER BY p.created_at DESC
    ''');
    return rows
        .map((r) => Playlist(
              id: r['id'] as int,
              name: r['name'] as String,
              createdAt: r['created_at'] as int,
              songCount: r['song_count'] as int,
            ))
        .toList(growable: false);
  }

  Future<int> create(String name) async {
    final db = await _db;
    return db.insert('playlists', {
      'name': name.trim(),
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> rename(int id, String name) async {
    final db = await _db;
    await db.update('playlists', {'name': name.trim()},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> delete(int id) async {
    final db = await _db;
    await db.delete('playlists', where: 'id = ?', whereArgs: [id]);
  }

  /// Ordered song ids for a playlist (duplicates preserved).
  Future<List<int>> songIds(int playlistId) async {
    final db = await _db;
    final rows = await db.query(
      'playlist_songs',
      columns: ['song_id'],
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
      orderBy: 'position ASC',
    );
    return rows.map((r) => r['song_id'] as int).toList(growable: false);
  }

  /// Appends [songIds] to the playlist. Returns how many were added so the
  /// UI can confirm ("Added 3 songs").
  Future<int> addSongs(int playlistId, List<int> songIds) async {
    if (songIds.isEmpty) return 0;
    final db = await _db;
    final maxRow = await db.rawQuery(
      'SELECT COALESCE(MAX(position), -1) AS max_pos FROM playlist_songs WHERE playlist_id = ?',
      [playlistId],
    );
    var position = (maxRow.first['max_pos'] as int) + 1;
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (final songId in songIds) {
      batch.insert('playlist_songs', {
        'playlist_id': playlistId,
        'song_id': songId,
        'position': position++,
        'added_at': now,
      });
    }
    await batch.commit(noResult: true);
    return songIds.length;
  }

  /// Removes ONE occurrence of [songId] (the earliest by position), so a
  /// duplicated song doesn't vanish everywhere at once.
  Future<void> removeSong(int playlistId, int songId) async {
    final db = await _db;
    await db.rawDelete('''
      DELETE FROM playlist_songs WHERE id = (
        SELECT id FROM playlist_songs
        WHERE playlist_id = ? AND song_id = ?
        ORDER BY position ASC
        LIMIT 1
      )
    ''', [playlistId, songId]);
  }

  /// Reorders by row id so duplicate songs move independently.
  Future<void> reorder(int playlistId, int oldIndex, int newIndex) async {
    final db = await _db;
    final rows = await db.query(
      'playlist_songs',
      columns: ['id'],
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
      orderBy: 'position ASC',
    );
    final rowIds = rows.map((r) => r['id'] as int).toList();
    if (oldIndex < 0 || oldIndex >= rowIds.length) return;
    final moved = rowIds.removeAt(oldIndex);
    rowIds.insert(newIndex.clamp(0, rowIds.length), moved);
    final batch = db.batch();
    for (var i = 0; i < rowIds.length; i++) {
      batch.update('playlist_songs', {'position': i},
          where: 'id = ?', whereArgs: [rowIds[i]]);
    }
    await batch.commit(noResult: true);
  }
}

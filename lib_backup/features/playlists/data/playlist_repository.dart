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

  /// Ordered song ids for a playlist.
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

  Future<void> addSongs(int playlistId, List<int> songIds) async {
    if (songIds.isEmpty) return;
    final db = await _db;
    final maxRow = await db.rawQuery(
      'SELECT COALESCE(MAX(position), -1) AS max_pos FROM playlist_songs WHERE playlist_id = ?',
      [playlistId],
    );
    var position = (maxRow.first['max_pos'] as int) + 1;
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (final songId in songIds) {
      batch.insert(
        'playlist_songs',
        {
          'playlist_id': playlistId,
          'song_id': songId,
          'position': position++,
          'added_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> removeSong(int playlistId, int songId) async {
    final db = await _db;
    await db.delete('playlist_songs',
        where: 'playlist_id = ? AND song_id = ?',
        whereArgs: [playlistId, songId]);
  }

  Future<void> reorder(int playlistId, int oldIndex, int newIndex) async {
    final ids = List<int>.from(await songIds(playlistId));
    if (oldIndex < 0 || oldIndex >= ids.length) return;
    final moved = ids.removeAt(oldIndex);
    ids.insert(newIndex.clamp(0, ids.length), moved);
    final db = await _db;
    final batch = db.batch();
    for (var i = 0; i < ids.length; i++) {
      batch.update('playlist_songs', {'position': i},
          where: 'playlist_id = ? AND song_id = ?',
          whereArgs: [playlistId, ids[i]]);
    }
    await batch.commit(noResult: true);
  }
}

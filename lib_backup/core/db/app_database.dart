import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Single sqflite database for user data that can't live in the media store:
/// playlists and play statistics. Song rows are referenced by media-store id
/// only — the library itself stays in memory from on_audio_query.
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  Database? _db;

  Future<Database> get database async => _db ??= await _open();

  Future<Database> _open() async {
    final path = p.join(await getDatabasesPath(), 'orvo.db');
    return openDatabase(
      path,
      version: 1,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE playlists(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            created_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE playlist_songs(
            playlist_id INTEGER NOT NULL
              REFERENCES playlists(id) ON DELETE CASCADE,
            song_id INTEGER NOT NULL,
            position INTEGER NOT NULL,
            added_at INTEGER NOT NULL,
            PRIMARY KEY(playlist_id, song_id)
          )
        ''');
        await db.execute('''
          CREATE TABLE play_stats(
            song_id INTEGER PRIMARY KEY,
            play_count INTEGER NOT NULL DEFAULT 0,
            last_played_at INTEGER NOT NULL
          )
        ''');
        await db.execute(
            'CREATE INDEX idx_playlist_songs ON playlist_songs(playlist_id, position)');
        await db.execute(
            'CREATE INDEX idx_last_played ON play_stats(last_played_at DESC)');
      },
    );
  }
}

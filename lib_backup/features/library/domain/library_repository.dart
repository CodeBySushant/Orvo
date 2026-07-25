import 'entities.dart';

abstract interface class LibraryRepository {
  Future<List<Song>> songs();
  Future<List<Album>> albums();
  Future<List<Artist>> artists();
  Future<List<Song>> albumSongs(int albumId);
  Future<List<Song>> artistSongs(int artistId);
}

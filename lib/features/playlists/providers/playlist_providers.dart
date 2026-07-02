import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/domain/entities.dart';
import '../../library/providers/library_providers.dart';
import '../data/playlist_repository.dart';

final playlistRepositoryProvider =
    Provider<PlaylistRepository>((ref) => PlaylistRepository());

final playlistsProvider = FutureProvider<List<Playlist>>(
  (ref) => ref.watch(playlistRepositoryProvider).playlists(),
);

final playlistSongIdsProvider = FutureProvider.family<List<int>, int>(
  (ref, playlistId) =>
      ref.watch(playlistRepositoryProvider).songIds(playlistId),
);

/// Ordered playlist songs, resolved against the in-memory library. Songs
/// deleted from the device simply drop out.
final playlistSongsProvider =
    Provider.family<AsyncValue<List<Song>>, int>((ref, playlistId) {
  final idsAsync = ref.watch(playlistSongIdsProvider(playlistId));
  final songsAsync = ref.watch(songsProvider);
  if (idsAsync.isLoading || songsAsync.isLoading) {
    return const AsyncValue.loading();
  }
  final ids = idsAsync.valueOrNull;
  final songs = songsAsync.valueOrNull;
  if (ids == null || songs == null) {
    return const AsyncValue.data(<Song>[]);
  }
  final byId = {for (final s in songs) s.id: s};
  return AsyncValue.data([
    for (final id in ids)
      if (byId[id] != null) byId[id]!,
  ]);
});

/// All mutations go through here so provider invalidation stays in one place.
final playlistActionsProvider =
    Provider<PlaylistActions>((ref) => PlaylistActions(ref));

class PlaylistActions {
  PlaylistActions(this._ref);
  final Ref _ref;

  PlaylistRepository get _repo => _ref.read(playlistRepositoryProvider);

  Future<int> create(String name) async {
    final id = await _repo.create(name);
    _ref.invalidate(playlistsProvider);
    return id;
  }

  Future<void> rename(int id, String name) async {
    await _repo.rename(id, name);
    _ref.invalidate(playlistsProvider);
  }

  Future<void> delete(int id) async {
    await _repo.delete(id);
    _ref.invalidate(playlistsProvider);
    _ref.invalidate(playlistSongIdsProvider(id));
  }

  Future<void> addSongs(int playlistId, List<int> songIds) async {
    await _repo.addSongs(playlistId, songIds);
    _ref.invalidate(playlistsProvider);
    _ref.invalidate(playlistSongIdsProvider(playlistId));
  }

  Future<void> removeSong(int playlistId, int songId) async {
    await _repo.removeSong(playlistId, songId);
    _ref.invalidate(playlistsProvider);
    _ref.invalidate(playlistSongIdsProvider(playlistId));
  }

  Future<void> reorder(int playlistId, int oldIndex, int newIndex) async {
    await _repo.reorder(playlistId, oldIndex, newIndex);
    _ref.invalidate(playlistSongIdsProvider(playlistId));
  }
}

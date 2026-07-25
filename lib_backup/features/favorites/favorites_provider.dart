import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme_provider.dart' show sharedPreferencesProvider;
import '../library/domain/entities.dart';
import '../library/providers/library_providers.dart';

const _kFavoritesKey = 'orvo.favorites';

/// Set of favorited song ids, persisted across launches.
class FavoritesNotifier extends Notifier<Set<int>> {
  @override
  Set<int> build() {
    final stored =
        ref.read(sharedPreferencesProvider).getStringList(_kFavoritesKey);
    return stored?.map(int.parse).toSet() ?? <int>{};
  }

  void toggle(int songId) {
    final next = Set<int>.from(state);
    next.contains(songId) ? next.remove(songId) : next.add(songId);
    state = next;
    ref.read(sharedPreferencesProvider).setStringList(
          _kFavoritesKey,
          next.map((id) => id.toString()).toList(growable: false),
        );
  }

  bool isFavorite(int songId) => state.contains(songId);
}

final favoritesProvider =
    NotifierProvider<FavoritesNotifier, Set<int>>(FavoritesNotifier.new);

/// Favorite songs in library order (newest first).
final favoriteSongsProvider = Provider<List<Song>>((ref) {
  final ids = ref.watch(favoritesProvider);
  final songs = ref.watch(songsProvider).valueOrNull ?? const [];
  return songs.where((s) => ids.contains(s.id)).toList(growable: false);
});

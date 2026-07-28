import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/home/home_screen.dart';
import '../../features/home/song_collection_screen.dart';
import '../../features/library/screens/album_detail_screen.dart';
import '../../features/library/screens/artist_detail_screen.dart';
import '../../features/equalizer/equalizer_screen.dart';
import '../../features/library/screens/folder_detail_screen.dart';
import '../../features/library/screens/genre_screens.dart';
import '../../features/library/screens/library_screen.dart';
import '../../features/library/screens/excluded_folders_screen.dart';
import '../../features/player/screens/now_playing_screen.dart';
import '../../features/playlists/screens/playlist_detail_screen.dart';
import '../../features/search/search_screen.dart';
import '../../features/settings/app_icon/app_icon.dart';
import '../../features/settings/help/faq_screen.dart';
import '../../features/settings/help/legal_screens.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/settings/skin_themes_screen.dart';
import '../../shell/app_shell.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/home',
    routes: [
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: '/home',
            pageBuilder: (context, state) =>
                _fade(state, const HomeScreen()),
          ),
          GoRoute(
            path: '/library',
            pageBuilder: (context, state) =>
                _fade(state, const LibraryScreen()),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) =>
                _fade(state, const SettingsScreen()),
          ),
          GoRoute(
            path: '/album/:id',
            builder: (context, state) => AlbumDetailScreen(
              albumId: int.parse(state.pathParameters['id']!),
            ),
          ),
          GoRoute(
            path: '/artist/:id',
            builder: (context, state) => ArtistDetailScreen(
              artistId: int.parse(state.pathParameters['id']!),
            ),
          ),
          GoRoute(
            path: '/playlist/:id',
            builder: (context, state) => PlaylistDetailScreen(
              playlistId: int.parse(state.pathParameters['id']!),
            ),
          ),
          GoRoute(
            path: '/folder',
            builder: (context, state) => FolderDetailScreen(
              folderPath: state.uri.queryParameters['path'] ?? '',
            ),
          ),
          GoRoute(
            path: '/search',
            pageBuilder: (context, state) =>
                _fade(state, const SearchScreen()),
          ),
          // REDESIGN: Home "See All" targets + genre browsing.
          GoRoute(
            path: '/collection/:kind',
            builder: (context, state) => SongCollectionScreen(
              kind: state.pathParameters['kind'] ?? 'added',
            ),
          ),
          GoRoute(
            path: '/genres',
            builder: (context, state) => const GenresScreen(),
          ),
          GoRoute(
            path: '/genre/:id',
            builder: (context, state) => GenreDetailScreen(
              genreId: int.parse(state.pathParameters['id']!),
              genreName: state.uri.queryParameters['name'] ?? 'Genre',
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/equalizer',
        builder: (context, state) => const EqualizerScreen(),
      ),
      // FEATURE (#27): skin themes hub.
      GoRoute(
        path: '/themes',
        builder: (context, state) => const SkinThemesScreen(),
      ),
      // FEATURE (#25): folder exclusions manager.
      GoRoute(
        path: '/excluded-folders',
        builder: (context, state) => const ExcludedFoldersScreen(),
      ),
      // FEATURE (app icon): launcher icon picker.
      GoRoute(
        path: '/app-icon',
        builder: (context, state) => const AppIconScreen(),
      ),
      // FEATURE (help): Settings → Help section screens.
      GoRoute(
        path: '/faq',
        builder: (context, state) => const FaqScreen(),
      ),
      GoRoute(
        path: '/privacy-policy',
        builder: (context, state) => const PrivacyPolicyScreen(),
      ),
      GoRoute(
        path: '/terms',
        builder: (context, state) => const TermsOfUseScreen(),
      ),
      // Full-screen player slides up over everything, including the shell.
      GoRoute(
        path: '/player',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const NowPlayingScreen(),
          transitionDuration: const Duration(milliseconds: 420),
          reverseTransitionDuration: const Duration(milliseconds: 320),
          transitionsBuilder: (context, animation, secondary, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            return SlideTransition(
              position: Tween(begin: const Offset(0, 1), end: Offset.zero)
                  .animate(curved),
              child: FadeTransition(opacity: curved, child: child),
            );
          },
        ),
      ),
    ],
  );
});

CustomTransitionPage<void> _fade(GoRouterState state, Widget child) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 220),
    transitionsBuilder: (context, animation, secondary, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}

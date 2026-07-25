import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'lyrics_parser.dart';

/// Lyrics for a given audio file path. Keyed by path so results are shared
/// between the sheet and any future full-screen lyrics view.
final lyricsProvider = FutureProvider.autoDispose.family<Lyrics, String>(
  (ref, path) => LyricsLoader.load(path),
);

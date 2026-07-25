import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';

import '../theme/app_colors.dart';
import '../utils/formatters.dart';

/// In-memory LRU artwork cache with in-flight de-duplication so scrolling a
/// 100k-song list never re-queries the media store for the same id.
class ArtworkCache {
  ArtworkCache._();
  static final ArtworkCache instance = ArtworkCache._();

  final OnAudioQuery _query = OnAudioQuery();
  final LinkedHashMap<String, Uint8List?> _cache = LinkedHashMap();
  final Map<String, Future<Uint8List?>> _inflight = {};
  static const _maxEntries = 400;

  Future<Uint8List?> load(int id, ArtworkType type, {int size = 400}) {
    final key = '${type.name}-$id-$size';
    if (_cache.containsKey(key)) {
      // Refresh LRU position.
      final v = _cache.remove(key);
      _cache[key] = v;
      return SynchronousFuture(v);
    }
    return _inflight[key] ??= _query
        .queryArtwork(id, type, size: size, quality: 100)
        .catchError((_) => null as Uint8List?)
        .then((bytes) {
      _inflight.remove(key);
      _cache[key] = bytes;
      if (_cache.length > _maxEntries) _cache.remove(_cache.keys.first);
      return bytes;
    });
  }

  void clear() => _cache.clear();
}

/// Displays artwork for a song/album/artist with a generated gradient +
/// initials placeholder when no art is embedded.
class Artwork extends StatelessWidget {
  const Artwork({
    super.key,
    required this.id,
    required this.type,
    required this.fallbackText,
    this.size,
    this.radius = 12,
    this.queryScale = 400,
  });

  final int id;
  final ArtworkType type;
  final String fallbackText;
  final double? size;
  final double radius;
  final int queryScale;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: FutureBuilder<Uint8List?>(
          future: ArtworkCache.instance.load(id, type, size: queryScale),
          builder: (context, snap) {
            final bytes = snap.data;
            if (bytes != null && bytes.isNotEmpty) {
              return Image.memory(
                bytes,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
              );
            }
            return _Placeholder(text: fallbackText);
          },
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.gradientFor(text);
    return LayoutBuilder(builder: (context, constraints) {
      final side = constraints.biggest.shortestSide;
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          Formatters.initials(text),
          style: TextStyle(
            color: Colors.white.withOpacity(.85),
            fontSize: (side * .32).clamp(10, 96),
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
      );
    });
  }
}

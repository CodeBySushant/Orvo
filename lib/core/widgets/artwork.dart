import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';

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

/// Displays artwork for a song/album/artist. Tracks without embedded art get
/// one standard vinyl-record cover (see _Placeholder below).
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

// ---------------------------------------------------------------------------
// REDESIGN v3.3 — standard placeholder cover.
//
// Previously art-less tracks showed per-name gradient tiles with initials
// ("A", "AA", "AM"…), which made lists look messy. Every track without
// embedded art now gets the SAME premium cover: a vinyl record on the brand
// violet gradient — matching the reference design's album card. Drawn with
// a CustomPainter so it's crisp at every size, from the 42px mini player to
// full-screen Now Playing, with no image assets.
//
// `fallbackText` is kept in the API (callers still pass it; it may be used
// for accessibility later) but no longer affects the visuals.
// ---------------------------------------------------------------------------

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.text});
  final String text; // ignored visually — see note above

  static const _bgGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF6C3EF0), Color(0xFF3B2AA8)],
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: _bgGradient),
      child: const CustomPaint(
        painter: _VinylPainter(),
        size: Size.infinite,
      ),
    );
  }
}

class _VinylPainter extends CustomPainter {
  const _VinylPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = Offset(size.width / 2, size.height / 2);

    // Soft highlight in the top-left corner for depth.
    canvas.drawCircle(
      Offset(size.width * .18, size.height * .16),
      s * .5,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.white.withOpacity(.14), Colors.transparent],
        ).createShader(
          Rect.fromCircle(
              center: Offset(size.width * .18, size.height * .16),
              radius: s * .5),
        ),
    );

    // The record.
    final discR = s * .34;
    canvas.drawCircle(c, discR, Paint()..color = const Color(0xFF161326));

    // Rim highlight.
    canvas.drawCircle(
      c,
      discR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (s * .012).clamp(.8, 3.0)
        ..color = Colors.white.withOpacity(.14),
    );

    // Grooves — three subtle rings between rim and label.
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = (s * .006).clamp(.5, 1.6)
      ..color = Colors.white.withOpacity(.07);
    for (final f in const [.82, .66, .50]) {
      canvas.drawCircle(c, discR * f, groove);
    }

    // Center label — small gradient circle.
    final labelR = discR * .36;
    canvas.drawCircle(
      c,
      labelR,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF9F6BFF), Color(0xFF5B3DF5)],
        ).createShader(Rect.fromCircle(center: c, radius: labelR)),
    );

    // Music note on the label (MaterialIcons glyph, so no asset needed).
    final icon = Icons.music_note_rounded;
    final notePainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          fontSize: labelR * 1.15,
          color: Colors.white.withOpacity(.95),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    notePainter.paint(
      canvas,
      c - Offset(notePainter.width / 2, notePainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _VinylPainter oldDelegate) => false;
}

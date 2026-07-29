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
    this.showPlaceholderIcon = true,
  });

  final int id;
  final ArtworkType type;
  final String fallbackText;
  final double? size;
  final double radius;
  final int queryScale;

  /// FIX (now-playing tiles): when the equalizer bars overlay this artwork
  /// for the current song, an art-less track's placeholder music-note glyph
  /// showed THROUGH the bars — two icons stacked on top of each other.
  /// Passing false renders the placeholder as a clean blank tile instead.
  /// Tracks with real artwork are unaffected.
  final bool showPlaceholderIcon;

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
            return _Placeholder(
              text: fallbackText,
              type: type,
              showIcon: showPlaceholderIcon,
            );
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
  const _Placeholder({
    required this.text,
    required this.type,
    this.showIcon = true,
  });
  final String text; // ignored visually — see note above
  final ArtworkType type;

  /// FIX (now-playing tiles): false = blank tile, no music-note glyph —
  /// used while the equalizer bars are drawn on top of this placeholder.
  final bool showIcon;

  @override
  Widget build(BuildContext context) {
    // REDESIGN v3.6: two standard covers.
    //  - Albums keep the vinyl record (Recommend Albums / album grid).
    //  - Songs & artists get the clean minimal tile from the reference:
    //    a soft translucent square with a muted music-note glyph.
    if (type == ArtworkType.ALBUM) {
      // FIX (themes): the cover gradient was a hardcoded brand violet, which
      // clashed once skins / Material You changed the accent. It now derives
      // from colorScheme.primary, so art-less album cards always match the
      // active theme color.
      final accent = Theme.of(context).colorScheme.primary;
      final top = Color.lerp(accent, Colors.white, .08)!;
      final bottom = Color.lerp(accent, Colors.black, .48)!;
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [top, bottom],
          ),
        ),
        child: CustomPaint(
          painter: _VinylPainter(accent),
          size: Size.infinite,
        ),
      );
    }

    final onSurface = Theme.of(context).colorScheme.onSurface;
    // FIX (now-playing tiles): no glyph under the equalizer-bars overlay.
    if (!showIcon) {
      return Container(color: onSurface.withOpacity(.07));
    }
    return LayoutBuilder(builder: (context, constraints) {
      final side = constraints.biggest.shortestSide;
      return Container(
        color: onSurface.withOpacity(.07),
        alignment: Alignment.center,
        child: Icon(
          Icons.music_note_rounded,
          size: side * .46,
          color: onSurface.withOpacity(.40),
        ),
      );
    });
  }
}

class _VinylPainter extends CustomPainter {
  const _VinylPainter(this.accent);

  /// FIX (themes): the disc and center label are tinted from the active
  /// theme accent instead of the hardcoded brand violet.
  final Color accent;

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

    // The record — near-black with a whisper of the accent in it.
    final discR = s * .34;
    canvas.drawCircle(
        c, discR, Paint()..color = Color.lerp(accent, Colors.black, .82)!);

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

    // Center label — small gradient circle in the accent.
    final labelR = discR * .36;
    canvas.drawCircle(
      c,
      labelR,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(accent, Colors.white, .35)!,
            accent,
          ],
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
  bool shouldRepaint(covariant _VinylPainter oldDelegate) =>
      oldDelegate.accent != accent;
}

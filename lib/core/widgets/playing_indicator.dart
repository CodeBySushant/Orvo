import 'dart:math' as math;

import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// REDESIGN v3.6: animated "now playing" equalizer bars (reference mockup —
// the orange bars replacing the thumbnail of the current song).
//
// Four rounded bars bob at different integer frequencies (so the loop wraps
// seamlessly). When [animating] is false (track paused) the bars freeze in
// place — still marking the current song, without implying playback.
// Painted with a single repainting CustomPainter driven directly by the
// AnimationController: no per-frame widget rebuilds.
// ---------------------------------------------------------------------------

class PlayingIndicator extends StatefulWidget {
  const PlayingIndicator({
    super.key,
    required this.color,
    this.size = 22,
    this.animating = true,
  });

  final Color color;
  final double size;
  final bool animating;

  @override
  State<PlayingIndicator> createState() => _PlayingIndicatorState();
}

class _PlayingIndicatorState extends State<PlayingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animating) _controller.repeat();
  }

  @override
  void didUpdateWidget(PlayingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animating && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.animating && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: CustomPaint(
        painter: _BarsPainter(animation: _controller, color: widget.color),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({required this.animation, required this.color})
      : super(repaint: animation);

  final Animation<double> animation;
  final Color color;

  // Integer cycles per loop → seamless wrap; phases break the symmetry.
  static const _cycles = [2.0, 3.0, 2.0, 4.0];
  static const _phases = [0.0, .28, .57, .82];

  @override
  void paint(Canvas canvas, Size size, ) {
    final paint = Paint()..color = color;
    const bars = 4;
    final barWidth = size.width / (bars * 2 - 1);
    final t = animation.value;

    for (var i = 0; i < bars; i++) {
      final wave =
          .5 + .5 * math.sin(2 * math.pi * (_cycles[i] * t + _phases[i]));
      final h = size.height * (.30 + .70 * wave);
      final x = i * barWidth * 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, size.height - h, barWidth, h),
          Radius.circular(barWidth / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarsPainter oldDelegate) =>
      oldDelegate.color != color;
}

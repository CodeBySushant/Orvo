import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../providers/player_providers.dart';

/// Seek bar with local drag state so the thumb never snaps back mid-drag,
/// plus elapsed / total labels. Colors are injected so Now Playing can tint
/// it with the palette accent.
class SeekBar extends ConsumerStatefulWidget {
  const SeekBar({super.key, required this.accent, required this.onSurface});

  final Color accent;
  final Color onSurface;

  @override
  ConsumerState<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends ConsumerState<SeekBar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final position =
        ref.watch(positionProvider).valueOrNull ?? Duration.zero;
    final duration =
        ref.watch(currentMediaItemProvider).valueOrNull?.duration ??
            Duration.zero;
    final maxMs = duration.inMilliseconds.toDouble().clamp(1, double.infinity);
    final value =
        (_dragValue ?? position.inMilliseconds.toDouble()).clamp(0.0, maxMs);

    final labelStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: widget.onSurface.withOpacity(.6),
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 3.5,
            activeTrackColor: widget.accent,
            inactiveTrackColor: widget.onSurface.withOpacity(.18),
            thumbColor: widget.accent,
            overlayColor: widget.accent.withOpacity(.14),
            thumbShape:
                const RoundSliderThumbShape(enabledThumbRadius: 6.5),
            overlayShape:
                const RoundSliderOverlayShape(overlayRadius: 16),
          ),
          child: Slider(
            min: 0,
            max: maxMs.toDouble(),
            value: value.toDouble(),
            onChanged: (v) => setState(() => _dragValue = v),
            onChangeEnd: (v) {
              ref
                  .read(audioHandlerProvider)
                  .seek(Duration(milliseconds: v.round()));
              setState(() => _dragValue = null);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                Formatters.duration(
                    Duration(milliseconds: value.round())),
                style: labelStyle,
              ),
              Text(Formatters.duration(duration), style: labelStyle),
            ],
          ),
        ),
      ],
    );
  }
}

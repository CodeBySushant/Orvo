import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A–Z fast-scroll rail. Drag or tap to jump; shows a floating bubble with
/// the active letter while scrubbing.
class AlphabetRail extends StatefulWidget {
  const AlphabetRail({super.key, required this.onLetter});

  /// Called with 'A'..'Z' or '#'.
  final ValueChanged<String> onLetter;

  static const letters = [
    '#', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
    'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
  ];

  @override
  State<AlphabetRail> createState() => _AlphabetRailState();
}

class _AlphabetRailState extends State<AlphabetRail> {
  String? _active;

  void _handle(Offset localPosition, double height) {
    final letters = AlphabetRail.letters;
    final index = ((localPosition.dy / height) * letters.length)
        .floor()
        .clamp(0, letters.length - 1);
    final letter = letters[index];
    if (letter != _active) {
      setState(() => _active = letter);
      HapticFeedback.selectionClick();
      widget.onLetter(letter);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(builder: (context, constraints) {
      final height = constraints.maxHeight;
      return Stack(
        alignment: Alignment.centerRight,
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: (d) => _handle(d.localPosition, height),
            onVerticalDragUpdate: (d) => _handle(d.localPosition, height),
            onVerticalDragEnd: (_) => setState(() => _active = null),
            onTapDown: (d) => _handle(d.localPosition, height),
            onTapUp: (_) => setState(() => _active = null),
            child: SizedBox(
              width: 26,
              height: height,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final letter in AlphabetRail.letters)
                    Text(
                      letter,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: letter == _active
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface.withOpacity(.45),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_active != null)
            Positioned(
              right: 40,
              child: Container(
                width: 54,
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(.3),
                      blurRadius: 16,
                    ),
                  ],
                ),
                child: Text(
                  _active!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      );
    });
  }
}

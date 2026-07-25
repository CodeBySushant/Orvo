import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../player/providers/player_providers.dart';
import 'lyrics_parser.dart';
import 'lyrics_provider.dart';

/// Bottom sheet showing lyrics for the current track. Synced lyrics
/// auto-scroll with playback and the active line is highlighted; tapping a
/// line seeks to it. Unsynced lyrics show as scrollable text.
class LyricsSheet extends ConsumerWidget {
  const LyricsSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => const FractionallySizedBox(
        heightFactor: .85,
        child: LyricsSheet(),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final item = ref.watch(currentMediaItemProvider).valueOrNull;
    final path = item?.extras?['path'] as String?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Lyrics', style: theme.textTheme.titleLarge),
              if (item != null)
                Text(item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium),
            ],
          ),
        ),
        Expanded(
          child: path == null
              ? const _LyricsMessage('Nothing playing')
              : _LyricsBody(path: path),
        ),
      ],
    );
  }
}

class _LyricsBody extends ConsumerWidget {
  const _LyricsBody({required this.path});
  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lyricsAsync = ref.watch(lyricsProvider(path));
    return lyricsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => const _LyricsMessage('Could not read lyrics'),
      data: (lyrics) {
        if (lyrics.isEmpty) {
          return const _LyricsMessage(
              'No lyrics found for this track.\n'
              'Orvo reads embedded tags and .lrc files.');
        }
        if (lyrics.isSynced) return _SyncedLyrics(lines: lyrics.synced);
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Text(
            lyrics.unsynced!,
            style: Theme.of(context)
                .textTheme
                .bodyLarge!
                .copyWith(height: 1.8, fontSize: 17),
          ),
        );
      },
    );
  }
}

class _SyncedLyrics extends ConsumerStatefulWidget {
  const _SyncedLyrics({required this.lines});
  final List<LyricLine> lines;

  @override
  ConsumerState<_SyncedLyrics> createState() => _SyncedLyricsState();
}

class _SyncedLyricsState extends ConsumerState<_SyncedLyrics> {
  static const _lineExtent = 52.0;
  final _controller = ScrollController();
  int _lastIndex = -1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int _indexFor(Duration position) {
    var index = 0;
    for (var i = 0; i < widget.lines.length; i++) {
      if (widget.lines[i].time <= position) {
        index = i;
      } else {
        break;
      }
    }
    return index;
  }

  void _autoScroll(int index, double viewport) {
    if (!_controller.hasClients || index == _lastIndex) return;
    _lastIndex = index;
    final target = (index * _lineExtent) - viewport / 2 + _lineExtent / 2;
    _controller.animateTo(
      target.clamp(0.0, _controller.position.maxScrollExtent),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final position =
        ref.watch(positionProvider).valueOrNull ?? Duration.zero;
    final current = _indexFor(position);

    return LayoutBuilder(builder: (context, constraints) {
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => _autoScroll(current, constraints.maxHeight));
      return ListView.builder(
        controller: _controller,
        physics: const BouncingScrollPhysics(),
        itemExtent: _lineExtent,
        padding: EdgeInsets.symmetric(
          vertical: constraints.maxHeight / 2 - _lineExtent / 2,
          horizontal: 24,
        ),
        itemCount: widget.lines.length,
        itemBuilder: (context, i) {
          final active = i == current;
          final line = widget.lines[i];
          return InkWell(
            onTap: () =>
                ref.read(audioHandlerProvider).seek(line.time),
            borderRadius: BorderRadius.circular(10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 220),
                style: theme.textTheme.titleMedium!.copyWith(
                  fontSize: active ? 19 : 16,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                  color: active
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface.withOpacity(.45),
                ),
                child: Text(
                  line.text.isEmpty ? '· · ·' : line.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          );
        },
      );
    });
  }
}

class _LyricsMessage extends StatelessWidget {
  const _LyricsMessage(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }
}

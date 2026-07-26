import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../player/providers/player_providers.dart';
import 'lyrics_parser.dart';
import 'lyrics_online.dart';
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
          child: path == null || item == null
              ? const _LyricsMessage('Nothing playing')
              : _LyricsBody(
                  request: LyricsRequest(
                    songId: item.extras?['songId'] as int? ?? 0,
                    path: path,
                    title: item.title,
                    artist: item.artist,
                    album: item.album,
                    durationSec: item.duration?.inSeconds,
                  ),
                ),
        ),
      ],
    );
  }
}

class _LyricsBody extends ConsumerWidget {
  const _LyricsBody({required this.request});
  final LyricsRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lyricsAsync = ref.watch(lyricsProvider(request));
    final onlineEnabled = ref.watch(onlineLyricsProvider);

    return lyricsAsync.when(
      // FEATURE (#21): animated searching state while the local chain and
      // (if enabled) the online lookup run.
      loading: () => const _LyricsLoading(),
      error: (e, _) => _LyricsEmpty(
        message: 'Could not read lyrics for this track.',
        actionLabel: 'Retry',
        onAction: () => ref.invalidate(lyricsProvider(request)),
      ),
      data: (result) {
        final lyrics = result.lyrics;
        if (lyrics.isEmpty) {
          // FEATURE (#21): three honest empty states instead of one.
          if (!onlineEnabled) {
            return _LyricsEmpty(
              message: 'No lyrics in this file.\n'
                  'Turn on Online lyrics to search the internet — '
                  'found lyrics are saved for offline use.',
              actionLabel: 'Turn on Online lyrics',
              onAction: () =>
                  ref.read(onlineLyricsProvider.notifier).set(true),
            );
          }
          if (result.lookupFailed) {
            return _LyricsEmpty(
              message: "Couldn't reach the lyrics service.\n"
                  'Check your internet connection and try again.',
              actionLabel: 'Retry',
              onAction: () => ref.invalidate(lyricsProvider(request)),
            );
          }
          return _LyricsEmpty(
            message: 'No lyrics found for this track —\n'
                'it may be an instrumental or the tags may not match.',
            actionLabel: 'Search again',
            onAction: () async {
              await OnlineLyrics.forget(request.songId);
              ref.invalidate(lyricsProvider(request));
            },
          );
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

/// FEATURE (#21): pulsing search animation shown while lyrics load. Always
/// resolves into a real state — it never spins forever (lookups time out
/// after 8 seconds and land in the "couldn't reach" state instead).
class _LyricsLoading extends StatelessWidget {
  const _LyricsLoading();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.graphic_eq_rounded,
                  size: 46, color: theme.colorScheme.primary)
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .scale(
                  begin: const Offset(1, 1),
                  end: const Offset(1.18, 1.18),
                  duration: 650.ms,
                  curve: Curves.easeInOut)
              .fade(begin: .55, end: 1),
          const SizedBox(height: 18),
          Text('Searching for lyrics', style: theme.textTheme.titleSmall),
          const SizedBox(height: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 3; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.colorScheme.primary,
                    ),
                  )
                      .animate(onPlay: (c) => c.repeat())
                      .fadeIn(delay: (i * 180).ms, duration: 350.ms)
                      .then(delay: 200.ms)
                      .fadeOut(duration: 350.ms),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Empty state with a single clear action.
class _LyricsEmpty extends StatelessWidget {
  const _LyricsEmpty({
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lyrics_outlined,
                size: 40,
                color: theme.colorScheme.onSurface.withOpacity(.35)),
            const SizedBox(height: 14),
            Text(message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
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

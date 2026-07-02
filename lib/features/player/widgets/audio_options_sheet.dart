import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/formatters.dart';
import '../providers/audio_settings.dart';
import '../providers/player_providers.dart';
import '../providers/sleep_timer.dart';

/// Bottom sheet with the Phase 3 audio controls: sleep timer, playback
/// speed, smooth transitions, and the equalizer entry point.
class AudioOptionsSheet extends ConsumerWidget {
  const AudioOptionsSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      builder: (context) => const AudioOptionsSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final timer = ref.watch(sleepTimerProvider);
    final speed = ref.watch(playbackSpeedProvider);
    final smooth = ref.watch(smoothTransitionsProvider);

    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ---------------- Sleep timer ----------------
              Row(
                children: [
                  Text('Sleep timer', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  if (timer.active)
                    Text(
                      timer.endOfTrack
                          ? 'After this track'
                          : Formatters.duration(timer.remaining!),
                      style: theme.textTheme.labelMedium!
                          .copyWith(color: theme.colorScheme.primary),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final minutes in const [15, 30, 45, 60])
                    ActionChip(
                      label: Text('${minutes}m'),
                      onPressed: () {
                        ref
                            .read(sleepTimerProvider.notifier)
                            .start(Duration(minutes: minutes));
                      },
                    ),
                  ActionChip(
                    label: const Text('End of track'),
                    onPressed: () =>
                        ref.read(sleepTimerProvider.notifier).stopAfterTrack(),
                  ),
                  if (timer.active)
                    ActionChip(
                      avatar: Icon(Icons.close_rounded,
                          size: 16, color: theme.colorScheme.primary),
                      label: const Text('Cancel'),
                      onPressed: () =>
                          ref.read(sleepTimerProvider.notifier).cancel(),
                    ),
                ],
              ),
              const SizedBox(height: 22),
              // ---------------- Playback speed ----------------
              Row(
                children: [
                  Text('Speed', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  Text('${speed.toStringAsFixed(2)}×',
                      style: theme.textTheme.labelMedium),
                ],
              ),
              Slider(
                min: 0.5,
                max: 2.0,
                divisions: 30,
                value: speed.clamp(0.5, 2.0),
                onChanged: (v) =>
                    ref.read(audioHandlerProvider).setSpeed(v),
              ),
              Wrap(
                spacing: 8,
                children: [
                  for (final preset in const [0.75, 1.0, 1.25, 1.5, 2.0])
                    ActionChip(
                      label: Text('${preset}×'),
                      onPressed: () =>
                          ref.read(audioHandlerProvider).setSpeed(preset),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              // ---------------- Smooth transitions ----------------
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Smooth transitions'),
                subtitle: Text(
                  'Gentle fade on play, pause and skip',
                  style: theme.textTheme.bodySmall,
                ),
                value: smooth,
                onChanged: (v) =>
                    ref.read(smoothTransitionsProvider.notifier).set(v),
              ),
              // ---------------- Equalizer ----------------
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.equalizer_rounded,
                    color: theme.colorScheme.primary),
                title: const Text('Equalizer'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.pop(context);
                  context.push('/equalizer');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

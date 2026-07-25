import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'equalizer_provider.dart';

class EqualizerScreen extends ConsumerStatefulWidget {
  const EqualizerScreen({super.key});

  @override
  ConsumerState<EqualizerScreen> createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends ConsumerState<EqualizerScreen> {
  int? _selectedPreset;

  @override
  void initState() {
    super.initState();
    // Attach (or re-attach) to the live audio session on open.
    Future.microtask(() => ref.read(equalizerProvider.notifier).attach());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final eq = ref.watch(equalizerProvider);
    final notifier = ref.read(equalizerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Equalizer'),
        actions: [
          if (eq.ready)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Switch(
                value: eq.enabled,
                onChanged: notifier.setEnabled,
              ),
            ),
        ],
      ),
      body: !eq.ready
          ? _Unavailable(
              reason: eq.unavailableReason ?? 'Connecting…',
              onRetry: notifier.attach,
            )
          : ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                // Presets
                if (eq.info!.presets.isNotEmpty) ...[
                  Text('Presets', style: theme.textTheme.labelMedium),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < eq.info!.presets.length; i++)
                        ChoiceChip(
                          label: Text(eq.info!.presets[i]),
                          selected: _selectedPreset == i,
                          onSelected: eq.enabled
                              ? (_) {
                                  setState(() => _selectedPreset = i);
                                  notifier.usePreset(i);
                                }
                              : null,
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
                // Bands
                Text('Bands', style: theme.textTheme.labelMedium),
                const SizedBox(height: 6),
                Opacity(
                  opacity: eq.enabled ? 1 : .4,
                  child: SizedBox(
                    height: 300,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        for (var i = 0; i < eq.info!.bands.length; i++)
                          _BandSlider(
                            label: '${eq.info!.bands[i].freqLabel}Hz',
                            min: eq.info!.minLevelMb.toDouble(),
                            max: eq.info!.maxLevelMb.toDouble(),
                            value: eq.levels[i]
                                .toDouble()
                                .clamp(eq.info!.minLevelMb.toDouble(),
                                    eq.info!.maxLevelMb.toDouble()),
                            enabled: eq.enabled,
                            onChanged: (v) {
                              setState(() => _selectedPreset = null);
                              notifier.setBandLevel(i, v.round());
                            },
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // Bass boost
                Text('Bass boost', style: theme.textTheme.labelMedium),
                Opacity(
                  opacity: eq.enabled ? 1 : .4,
                  child: Row(
                    children: [
                      const Icon(Icons.speaker_rounded, size: 20),
                      Expanded(
                        child: Slider(
                          min: 0,
                          max: 1000,
                          value: eq.bassStrength.toDouble(),
                          onChanged: eq.enabled
                              ? (v) => notifier.setBassBoost(v.round())
                              : null,
                        ),
                      ),
                      SizedBox(
                        width: 44,
                        child: Text(
                          '${(eq.bassStrength / 10).round()}%',
                          style: theme.textTheme.labelMedium,
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Adjustments apply live to the current audio session and are '
                  'remembered across sessions.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
    );
  }
}

class _BandSlider extends StatelessWidget {
  const _BandSlider({
    required this.label,
    required this.min,
    required this.max,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final double min;
  final double max;
  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final db = (value / 100).toStringAsFixed(0);
    return Column(
      children: [
        Text('${db}dB', style: theme.textTheme.labelSmall),
        Expanded(
          child: RotatedBox(
            quarterTurns: -1,
            child: Slider(
              min: min,
              max: max,
              value: value,
              onChanged: enabled ? onChanged : null,
            ),
          ),
        ),
        Text(label, style: theme.textTheme.labelSmall),
      ],
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.reason, required this.onRetry});
  final String reason;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.equalizer_rounded,
                size: 44, color: theme.colorScheme.onSurface.withOpacity(.4)),
            const SizedBox(height: 14),
            Text(reason,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium),
            const SizedBox(height: 18),
            OutlinedButton(
              onPressed: onRetry,
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

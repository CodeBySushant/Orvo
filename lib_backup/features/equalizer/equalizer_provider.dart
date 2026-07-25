import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme_provider.dart' show sharedPreferencesProvider;
import '../player/providers/player_providers.dart';
import 'equalizer_channel.dart';

const _kEnabledKey = 'orvo.eq.enabled';
const _kLevelsKey = 'orvo.eq.levels';
const _kBassKey = 'orvo.eq.bass';

class EqualizerState {
  const EqualizerState({
    this.info,
    this.enabled = false,
    this.levels = const [],
    this.bassStrength = 0,
    this.unavailableReason,
  });

  final EqInfo? info;
  final bool enabled;
  final List<int> levels; // millibels per band
  final int bassStrength; // 0–1000
  final String? unavailableReason;

  bool get ready => info != null;

  EqualizerState copyWith({
    EqInfo? info,
    bool? enabled,
    List<int>? levels,
    int? bassStrength,
    String? unavailableReason,
  }) =>
      EqualizerState(
        info: info ?? this.info,
        enabled: enabled ?? this.enabled,
        levels: levels ?? this.levels,
        bassStrength: bassStrength ?? this.bassStrength,
        unavailableReason: unavailableReason,
      );
}

class EqualizerNotifier extends Notifier<EqualizerState> {
  @override
  EqualizerState build() => const EqualizerState();

  /// Attaches to the current audio session. Requires playback to have
  /// started at least once (just_audio allocates the session lazily).
  Future<void> attach() async {
    if (!Platform.isAndroid) {
      state = state.copyWith(
          unavailableReason: 'Equalizer is Android-only for now.');
      return;
    }
    final sessionId =
        ref.read(audioHandlerProvider).androidAudioSessionId;
    if (sessionId == null || sessionId == 0) {
      state = state.copyWith(
          unavailableReason:
              'Play a song first — the equalizer attaches to the live audio session.');
      return;
    }
    try {
      final info = await EqualizerChannel.init(sessionId);
      if (info == null) {
        state = state.copyWith(unavailableReason: 'Equalizer init failed.');
        return;
      }
      final prefs = ref.read(sharedPreferencesProvider);
      final savedEnabled = prefs.getBool(_kEnabledKey) ?? false;
      final savedLevels = prefs
          .getStringList(_kLevelsKey)
          ?.map(int.parse)
          .toList(growable: false);
      final savedBass = prefs.getInt(_kBassKey) ?? 0;

      var levels = [for (final b in info.bands) b.levelMb];
      if (savedLevels != null && savedLevels.length == levels.length) {
        levels = savedLevels;
        for (var i = 0; i < levels.length; i++) {
          await EqualizerChannel.setBandLevel(i, levels[i]);
        }
      }
      await EqualizerChannel.setBassBoost(savedBass);
      await EqualizerChannel.setEnabled(savedEnabled);

      state = EqualizerState(
        info: info,
        enabled: savedEnabled,
        levels: levels,
        bassStrength: savedBass,
      );
    } catch (e) {
      state = state.copyWith(
          unavailableReason: 'Equalizer unavailable on this device.');
    }
  }

  Future<void> setEnabled(bool enabled) async {
    if (!state.ready) return;
    await EqualizerChannel.setEnabled(enabled);
    state = state.copyWith(enabled: enabled);
    ref.read(sharedPreferencesProvider).setBool(_kEnabledKey, enabled);
  }

  Future<void> setBandLevel(int band, int levelMb) async {
    if (!state.ready) return;
    await EqualizerChannel.setBandLevel(band, levelMb);
    final levels = List<int>.from(state.levels);
    levels[band] = levelMb;
    state = state.copyWith(levels: levels);
    _persistLevels(levels);
  }

  Future<void> usePreset(int preset) async {
    if (!state.ready) return;
    final levels = await EqualizerChannel.usePreset(preset);
    if (levels.isNotEmpty) {
      state = state.copyWith(levels: levels);
      _persistLevels(levels);
    }
  }

  Future<void> setBassBoost(int strength) async {
    if (!state.ready) return;
    await EqualizerChannel.setBassBoost(strength);
    state = state.copyWith(bassStrength: strength);
    ref.read(sharedPreferencesProvider).setInt(_kBassKey, strength);
  }

  void _persistLevels(List<int> levels) {
    ref.read(sharedPreferencesProvider).setStringList(
        _kLevelsKey, levels.map((l) => l.toString()).toList());
  }
}

final equalizerProvider =
    NotifierProvider<EqualizerNotifier, EqualizerState>(EqualizerNotifier.new);

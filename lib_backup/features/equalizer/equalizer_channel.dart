import 'package:flutter/services.dart';

class EqBand {
  const EqBand({
    required this.index,
    required this.centerFreqHz,
    required this.levelMb,
  });

  final int index;
  final int centerFreqHz;
  final int levelMb; // millibels

  String get freqLabel => centerFreqHz >= 1000
      ? '${(centerFreqHz / 1000).toStringAsFixed(centerFreqHz % 1000 == 0 ? 0 : 1)}k'
      : '$centerFreqHz';
}

class EqInfo {
  const EqInfo({
    required this.minLevelMb,
    required this.maxLevelMb,
    required this.bands,
    required this.presets,
  });

  final int minLevelMb;
  final int maxLevelMb;
  final List<EqBand> bands;
  final List<String> presets;
}

/// Thin wrapper over the native android.media.audiofx Equalizer/BassBoost,
/// attached to just_audio's audio session. Android only.
abstract final class EqualizerChannel {
  static const _channel = MethodChannel('orvo/equalizer');

  static Future<EqInfo?> init(int sessionId) async {
    final result = await _channel
        .invokeMapMethod<String, dynamic>('init', {'sessionId': sessionId});
    if (result == null) return null;
    final rawBands = (result['bands'] as List).cast<Map>();
    return EqInfo(
      minLevelMb: result['minLevel'] as int,
      maxLevelMb: result['maxLevel'] as int,
      bands: [
        for (final b in rawBands)
          EqBand(
            index: b['index'] as int,
            centerFreqHz: b['centerFreq'] as int,
            levelMb: b['level'] as int,
          ),
      ],
      presets: (result['presets'] as List).cast<String>(),
    );
  }

  static Future<void> setEnabled(bool enabled) =>
      _channel.invokeMethod('setEnabled', {'enabled': enabled});

  static Future<void> setBandLevel(int band, int levelMb) =>
      _channel.invokeMethod('setBandLevel', {'band': band, 'level': levelMb});

  /// Returns the band levels the preset applied, so the UI can update.
  static Future<List<int>> usePreset(int preset) async {
    final levels = await _channel
        .invokeListMethod<int>('usePreset', {'preset': preset});
    return levels ?? const [];
  }

  /// strength: 0–1000
  static Future<void> setBassBoost(int strength) =>
      _channel.invokeMethod('setBassBoost', {'strength': strength});

  static Future<void> release() => _channel.invokeMethod('release');
}

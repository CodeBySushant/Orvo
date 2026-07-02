import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/theme/theme_provider.dart';
import 'features/player/audio/audio_handler.dart';
import 'features/player/providers/player_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();

  final audioHandler = await AudioService.init(
    builder: OrvoAudioHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.orvo.playback',
      androidNotificationChannelName: 'Orvo playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      androidNotificationIcon: 'mipmap/ic_launcher',
    ),
  );

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        audioHandlerProvider.overrideWithValue(audioHandler),
      ],
      child: const OrvoApp(),
    ),
  );
}

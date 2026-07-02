# Orvo — Phase 1 (Core)

A premium offline music player for Android & iOS, built with Flutter.

**Phase 1 delivers:** background library scan (on_audio_query), gapless playback with
media notification / lock-screen / Bluetooth controls (just_audio + audio_service),
Now Playing with dynamic palette + blurred artwork + swipe-to-skip + double-tap-to-favorite,
mini player, reorderable queue, favorites, Light / Dark / AMOLED themes, Home, Library
(Songs / Albums / Artists) with sorting, Album & Artist detail, Settings.

## Setup

1. **Prerequisites:** Flutter (stable, 3.22+), Android SDK. `flutter doctor` should be clean.

2. **Generate platform folders** (this repo ships only `lib/` + config):

   ```bash
   cd orvo
   flutter create . --platforms android,ios --org com.orvo
   flutter pub get
   ```

3. **Apply the Android platform files** (required for audio_service):

   ```bash
   cp platform_setup/android/AndroidManifest.xml android/app/src/main/AndroidManifest.xml
   cp platform_setup/android/MainActivity.kt android/app/src/main/kotlin/com/orvo/orvo/MainActivity.kt
   ```

   In `android/app/build.gradle` set `minSdk = 23` (inside `defaultConfig`).

4. **iOS (optional for now):** in `ios/Runner/Info.plist` add:

   ```xml
   <key>NSAppleMusicUsageDescription</key>
   <string>Orvo needs access to your music library to play your songs.</string>
   <key>UIBackgroundModes</key>
   <array><string>audio</string></array>
   ```

5. **Run:**

   ```bash
   flutter run
   ```

## Notes

- First launch asks for the audio/media permission, then scans the device library in the background.
- Artwork is read from the media store with an in-memory LRU cache; songs without art get a
  generated gradient + initials placeholder.
- Favorites and theme choice persist via SharedPreferences (no codegen needed — `flutter run` works immediately).
- Phase 2 (INCLUDED): playlists (sqflite), global search, alphabet fast-scroll rail,
  play tracking (Recently played + On repeat on Home), and Play next / Add to queue actions.
- Phase 3: equalizer, crossfade, sleep timer, LRC lyrics. Phase 4: widgets, Android Auto.

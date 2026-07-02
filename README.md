# Orvo

A premium offline music player for Android, built with Flutter. All four development phases are complete.

Orvo plays the music already on your device — nothing ever leaves your phone. It scans the media store in the background, plays gaplessly with full system integration (notification, lock screen, Bluetooth, Android Auto), and wraps it all in a polished, palette-driven UI.

## Features

### Phase 1 — Core player
- Background library scan via the media store (`on_audio_query_pluse`), with short-clip filtering (voice notes / notification blips under 20s are excluded)
- Gapless playback engine (`just_audio` + `audio_service`) with media notification, lock-screen, and Bluetooth / headset button controls
- Pause on headphone unplug, duck / pause on interruptions (calls, navigation prompts)
- Now Playing screen: dynamic color palette extracted from artwork, blurred artwork background, swipeable artwork pager synced to the queue, double-tap to favorite, drag down to dismiss
- Mini player docked above the navigation bar with inline controls and progress strip
- Home screen: Recently added, Recently played, On repeat, Favorites, and Albums shelves + Shuffle all / Latest first quick actions
- Library with Songs / Albums / Artists tabs, sorting (Recently added, Title, Artist, Duration), and Album / Artist detail screens
- Favorites (persisted via SharedPreferences)
- Light / Dark / AMOLED themes
- Artwork LRU cache with in-flight de-duplication — smooth scrolling even on huge libraries; generated gradient + initials placeholder for songs without embedded art

### Phase 2 — Library power features
- Playlists (sqflite): create, rename, delete, add / remove songs, drag-to-reorder
- Global search across songs, albums, and artists — instant, in-memory, debounced
- Alphabet fast-scroll rail on the Songs list
- Play tracking: a play is counted after 15 seconds on a track (skipping doesn't pollute stats) — powers Recently played and On repeat on Home
- Queue management: Play next, Add to queue, reorder, and remove from a reorderable queue sheet
- Folders tab: browse music by on-device folder, derived from the library with no extra media queries
- Song info sheet, share song, set as ringtone, and delete from device (scoped-storage system dialog on Android 11+)

### Phase 3 — Audio & experience
- Equalizer: native Android `audiofx` (5-band, device presets, bass boost) attached to the live audio session, with persisted settings
- Smooth transitions: short volume ramps on play / pause / skip
- Sleep timer: countdown or stop after the current track
- Lyrics: `.lrc` sidecar files and embedded ID3v2 USLT frames, with synced (karaoke-style, auto-scrolling) and unsynced display
- Playback speed control

### Phase 4 — System integration
- Home-screen widget (4×1): live track title, artist, play state, and transport buttons that work even when the app UI is closed (media-key broadcasts to the playback foreground service)
- Android Auto: browsable media tree (Recently added / Songs / Albums) with play-in-context queues
- MediaBrowserService surface — also works with Bluetooth car stereos and wearables that browse media apps

## Tech stack

| Layer | Choice |
|---|---|
| Framework | Flutter (Dart ≥ 3.4) |
| State | Riverpod 2 |
| Navigation | go_router |
| Playback | just_audio + audio_service + audio_session |
| Media store | on_audio_query_pluse |
| Local DB | sqflite (playlists, play stats) |
| Prefs | shared_preferences (theme, favorites, EQ, toggles) |
| UI polish | palette_generator, flutter_animate |
| Native | Kotlin platform channels: `orvo/equalizer`, `orvo/system`, `orvo/widget` |

## Project structure

```
lib/
├── main.dart                  # AudioService + prefs bootstrap
├── app.dart                   # MaterialApp.router + PermissionGate
├── core/
│   ├── db/                    # sqflite database (playlists, play_stats)
│   ├── router/                # go_router routes + transitions
│   ├── theme/                 # Light / Dark / AMOLED themes
│   ├── utils/                 # formatters
│   └── widgets/               # Artwork (+ LRU cache), alphabet rail, Pressable
├── features/
│   ├── equalizer/             # audiofx channel + provider + screen
│   ├── favorites/             # persisted favorite ids
│   ├── home/                  # Home screen shelves
│   ├── library/               # repository, providers, screens, tiles
│   ├── lyrics/                # LRC / USLT parser + synced lyrics sheet
│   ├── onboarding/            # PermissionGate
│   ├── player/                # audio handler, providers, Now Playing, mini player
│   ├── playlists/             # sqflite repository + screens
│   ├── search/                # in-memory global search
│   ├── settings/              # theme, audio, about
│   ├── stats/                 # play tracker (Recently played / On repeat)
│   ├── system/                # share / ringtone / delete channel
│   └── widget/                # home-screen widget updater
└── shell/                     # bottom-nav shell + mini player dock

android/app/src/main/kotlin/com/orvo/orvo/
├── MainActivity.kt            # equalizer / system / widget channels
└── OrvoWidgetProvider.kt      # 4×1 now-playing widget
```

## Setup

1. **Prerequisites:** Flutter (stable, 3.22+), Android SDK. `flutter doctor` should be clean.

2. **Install dependencies:**

   ```bash
   flutter pub get
   ```

3. **Run:**

   ```bash
   flutter run
   ```

The `android/` folder ships fully configured — manifest permissions, the `audio_service` foreground service, media button receiver, Android Auto declaration, and the widget provider are already in place. (`platform_setup/` is kept only as a reference copy of the platform files.)

### Requirements
- `minSdk 23` (Android 6.0+), targets the latest SDK via the Flutter Gradle plugin
- Permissions used: `READ_MEDIA_AUDIO` (Android 13+) / `READ_EXTERNAL_STORAGE` (≤ Android 12), foreground media-playback service, `WRITE_SETTINGS` (optional — only for set-as-ringtone, granted via the system settings screen)

## How it works

- **First launch:** Orvo asks for the audio/media permission, then scans the device library in the background. Rescan any time with pull-to-refresh on Home.
- **Permissions:** a single-flight permission gate guarantees exactly one system request even though songs / albums / artists queries run concurrently at startup.
- **Playback queue:** lazily prepared audio sources keep even 10k+ song queues instant to load.
- **Everything offline:** no network access, no analytics, no accounts. Playlists and play stats live in a local sqflite database; the library itself stays in memory from the media store.

## Adding the home-screen widget

Long-press your launcher home screen → Widgets → Orvo → drag the 4×1 "Now playing" widget anywhere. It stays in sync while the playback service is alive and its buttons control playback directly.

## iOS status

The codebase is Flutter-first and the player core is cross-platform, but the current release is Android-focused: equalizer, home-screen widget, Android Auto, set-as-ringtone, and system delete are Android platform channels. To experiment on iOS, add to `ios/Runner/Info.plist`:

```xml
<key>NSAppleMusicUsageDescription</key>
<string>Orvo needs access to your music library to play your songs.</string>
<key>UIBackgroundModes</key>
<array><string>audio</string></array>
```

## Roadmap ideas (post-Phase 4)

- True overlapping crossfade (dual-player architecture)
- Tag editing
- Backup / restore of playlists and stats
- Folder exclusions and custom scan filters
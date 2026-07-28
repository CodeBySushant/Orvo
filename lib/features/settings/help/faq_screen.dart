import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/l10n.dart';

// ---------------------------------------------------------------------------
// FEATURE (help): FAQ screen — expandable question tiles in Orvo's own
// visual language (icon badge + chevron, like the Excluded Folders screen).
// All questions and answers are written for Orvo's actual behaviour:
// offline-only library, the 20-second short-clip filter, folder exclusions,
// the native audiofx equalizer, .lrc / embedded / LRCLIB lyrics, and
// Android audio-focus rules.
// ---------------------------------------------------------------------------

class _FaqEntry {
  const _FaqEntry(this.icon, this.question, this.answer);
  final IconData icon;
  final String question;
  final String answer;
}

const List<_FaqEntry> _faq = [
  _FaqEntry(
    Icons.cloud_off_rounded,
    'Can Orvo download or stream music?',
    'No — Orvo is a fully offline player. It plays the audio files already '
        'stored on your device and never downloads or streams music. To add '
        'new songs, copy audio files to your phone (Music, Download, or any '
        'folder), then pull down to refresh on Home or use Settings → Rescan '
        'library.',
  ),
  _FaqEntry(
    Icons.pause_circle_outline_rounded,
    'Music stops playing in the background?',
    'This is almost always the system\'s battery optimizer closing the '
        'playback service. Open your phone\'s Settings → Battery → Battery '
        'optimization (or App battery usage), find Orvo, and set it to '
        '"Unrestricted" / "Don\'t optimize". On some brands (Xiaomi, Oppo, '
        'Vivo, Realme) also enable "Autostart" and lock Orvo in the recent '
        'apps screen. Orvo runs a media foreground service, so once it is '
        'exempted from optimization, playback continues reliably with the '
        'screen off.',
  ),
  _FaqEntry(
    Icons.music_off_rounded,
    'Why are some songs not displayed?',
    'Three common reasons:\n\n'
        '1. Short clips are filtered — audio under 20 seconds (notification '
        'sounds, voice-note blips) is hidden on purpose.\n'
        '2. The folder is excluded — check Settings → Excluded folders and '
        'switch the folder back on if needed.\n'
        '3. The system hasn\'t indexed the file yet — pull down to refresh '
        'on Home, or use Settings → Rescan library. Files inside hidden '
        'folders (names starting with a dot, or containing a ".nomedia" '
        'file) are skipped by Android itself.',
  ),
  _FaqEntry(
    Icons.subtitles_off_outlined,
    'Why can\'t the lyrics scroll?',
    'Lyrics auto-scroll (karaoke style) only when they are synced — i.e. '
        'each line carries a timestamp, like in .lrc files. If a song only '
        'has plain, unsynced lyrics, Orvo shows them as static text you can '
        'scroll yourself. To get synced lyrics, place a matching .lrc file '
        'next to the song, or turn on Settings → Online lyrics to fetch '
        'synced lyrics from LRCLIB where available.',
  ),
  _FaqEntry(
    Icons.volume_off_rounded,
    'No sound, or sound is distorted, when using the equalizer?',
    'The equalizer uses your device\'s built-in audio engine, so behaviour '
        'can vary by phone. Try this order:\n\n'
        '1. Toggle the equalizer off and on again from its screen.\n'
        '2. Lower the band sliders and Bass boost — extreme boosts can '
        'clip or mute audio on some devices.\n'
        '3. Close other equalizer or "sound effects" apps (including the '
        'manufacturer\'s own), which can grab the audio session.\n'
        '4. Restart playback so the equalizer re-attaches to the new audio '
        'session.',
  ),
  _FaqEntry(
    Icons.tune_rounded,
    'The equalizer sliders don\'t seem to change anything?',
    'Start playing a song first — the equalizer attaches to the live audio '
        'session, so with nothing playing there is nothing to shape. If a '
        'device preset is selected, moving a slider switches you to a '
        'custom curve. A few phones ship without the standard equalizer '
        'component; on those devices the system simply doesn\'t expose it '
        'to apps.',
  ),
  _FaqEntry(
    Icons.headset_off_rounded,
    'Why is music paused when entering other apps?',
    'Android allows one app to hold "audio focus" at a time. When another '
        'app starts its own audio — a video, a game, a voice call — the '
        'system asks Orvo to pause or duck (lower volume) so the sounds '
        'don\'t overlap. For short interruptions like calls or navigation '
        'prompts, Orvo resumes automatically when the interruption ends. '
        'If another music or video app takes over completely, just press '
        'play again in Orvo.',
  ),
  _FaqEntry(
    Icons.lyrics_outlined,
    'How to add lyrics?',
    'Orvo reads lyrics from three places, in this order:\n\n'
        '1. Sidecar .lrc file — put a file with the same name as the song '
        'next to it (e.g. "MySong.mp3" + "MySong.lrc"). On Android 11+ you '
        'may need to connect the folder once via Settings → Lyrics folder.\n'
        '2. Embedded lyrics — lyrics saved inside the song\'s own tags by a '
        'tag editor.\n'
        '3. Online lyrics — turn on Settings → Online lyrics and Orvo will '
        'fetch missing lyrics from LRCLIB once, then keep them offline.',
  ),
  _FaqEntry(
    Icons.folder_off_outlined,
    'How do I hide WhatsApp audio, recordings, or a whole folder?',
    'Go to Settings → Excluded folders and switch off any folder you don\'t '
        'want in your library. Excluded folders disappear everywhere — '
        'library, search, shuffle and stats — but the files themselves stay '
        'untouched on your device, and you can switch a folder back on any '
        'time.',
  ),
];

class FaqScreen extends ConsumerWidget {
  const FaqScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(l10nProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t.faq)),
      body: ListView.separated(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 32),
        itemCount: _faq.length,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          indent: 68,
          endIndent: 16,
          color: theme.colorScheme.onSurface.withOpacity(.06),
        ),
        itemBuilder: (context, index) {
          final entry = _faq[index];
          return Theme(
            // Hide the ExpansionTile's default divider lines.
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              leading: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(entry.icon,
                    size: 21, color: theme.colorScheme.primary),
              ),
              title: Text(
                entry.question,
                style: theme.textTheme.titleSmall!
                    .copyWith(fontWeight: FontWeight.w600),
              ),
              childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.answer,
                  style: theme.textTheme.bodyMedium!.copyWith(
                    height: 1.5,
                    color: theme.colorScheme.onSurface.withOpacity(.75),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

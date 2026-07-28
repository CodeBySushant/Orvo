import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/l10n.dart';

// ---------------------------------------------------------------------------
// FEATURE (help): Privacy Policy + Terms of Use.
//
// Both documents are ORIGINAL text written specifically for Orvo and for how
// Orvo actually behaves (fully offline, no accounts, no analytics, opt-in
// LRCLIB lyrics lookup). They share one document scaffold so headings and
// body text stay visually consistent.
// ---------------------------------------------------------------------------

/// Single source of truth for the version shown across the app.
const String kOrvoVersion = '0.1.0';

// --- Shared document scaffold ----------------------------------------------

class _DocSection {
  const _DocSection(this.heading, this.body);
  final String? heading;
  final String body;
}

class _LegalDocScreen extends StatelessWidget {
  const _LegalDocScreen({
    required this.appBarTitle,
    required this.title,
    required this.effectiveDate,
    required this.sections,
  });

  final String appBarTitle;
  final String title;
  final String effectiveDate;
  final List<_DocSection> sections;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bodyStyle = theme.textTheme.bodyMedium!.copyWith(
      height: 1.55,
      color: theme.colorScheme.onSurface.withOpacity(.78),
    );
    final headingStyle = theme.textTheme.titleMedium!
        .copyWith(fontWeight: FontWeight.w800, height: 1.3);

    return Scaffold(
      appBar: AppBar(title: Text(appBarTitle)),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Center(
            child: Text(
              title,
              style: theme.textTheme.headlineSmall!
                  .copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 18),
          Text('Effective date: $effectiveDate',
              style: headingStyle.copyWith(fontSize: 16)),
          const SizedBox(height: 14),
          for (final section in sections) ...[
            if (section.heading != null) ...[
              const SizedBox(height: 12),
              Text(section.heading!, style: headingStyle),
              const SizedBox(height: 8),
            ],
            Text(section.body, style: bodyStyle),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

// --- Privacy Policy ---------------------------------------------------------

class PrivacyPolicyScreen extends ConsumerWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(l10nProvider);
    return _LegalDocScreen(
      appBarTitle: t.privacyPolicy,
      title: 'Privacy Policy',
      effectiveDate: 'July 29, 2026',
      sections: const [
        _DocSection(
          null,
          'Orvo is an offline music player. This Privacy Policy explains '
          'what information the app does — and, more importantly, does not — '
          'handle when you use it. The short version: your music, your '
          'listening habits and your personal data stay on your device.',
        ),
        _DocSection(
          'No accounts, no personal data',
          'Orvo does not require an account and has no sign-up or login of '
          'any kind. The app does not collect, store or transmit your name, '
          'email address, phone number, contacts, location, or any other '
          'personally identifying information. There are no ads, no '
          'analytics SDKs and no tracking of any kind inside the app.',
        ),
        _DocSection(
          'Data stored on your device',
          'To provide its features, Orvo keeps a small amount of data '
          'locally on your device only: your playlists, favorites, play '
          'statistics (used for the "Recently played" and "Most played" '
          'shelves), theme and audio preferences, folder exclusions, and '
          'the last playback session so the app can pick up where you left '
          'off. This data never leaves your device and is deleted when you '
          'uninstall the app or clear its storage.',
        ),
        _DocSection(
          'Media library access',
          'Orvo asks for the system media/audio permission for exactly one '
          'purpose: reading the music files already stored on your device '
          'so it can list and play them. The app does not upload, copy or '
          'share your files, and it does not modify them except when you '
          'explicitly choose an action such as deleting a song (which uses '
          'the standard Android confirmation dialog).',
        ),
        _DocSection(
          'Online lyrics (optional)',
          'Orvo works fully offline by default and makes no network '
          'requests. If you turn on the optional "Online lyrics" feature in '
          'Settings, the app sends only the song title, artist, album and '
          'duration of the track you are playing to LRCLIB (lrclib.net), a '
          'free open lyrics database, in order to find matching lyrics. No '
          'device identifiers or personal data are included in these '
          'requests, and the results are cached on your device so each song '
          'is looked up at most once. Turning the toggle off stops all '
          'network activity again.',
        ),
        _DocSection(
          'Other permissions',
          'The foreground-service and wake-lock permissions keep music '
          'playing reliably with the screen off. The optional "Modify '
          'system settings" permission is requested only if you use '
          '"Set as ringtone", and is granted by you on the system settings '
          'screen. None of these permissions involve any data collection.',
        ),
        _DocSection(
          'Children',
          'Orvo does not collect personal information from anyone, '
          'including children. The app contains no ads, purchases, social '
          'features or external links beyond the optional lyrics lookup '
          'described above.',
        ),
        _DocSection(
          'Changes to this policy',
          'If this policy ever changes — for example, if a new optional '
          'online feature is added — the updated version will ship inside '
          'the app with a new effective date at the top of this page.',
        ),
        _DocSection(
          'Contact',
          'If you have questions about this Privacy Policy or how Orvo '
          'handles data, you can reach the developer at '
          'support@orvo.app.',
        ),
      ],
    );
  }
}

// --- Terms of Use -----------------------------------------------------------

class TermsOfUseScreen extends ConsumerWidget {
  const TermsOfUseScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(l10nProvider);
    return _LegalDocScreen(
      appBarTitle: t.termsOfUse,
      title: 'Terms of Use',
      effectiveDate: 'July 29, 2026',
      sections: const [
        _DocSection(
          null,
          'These Terms of Use ("Terms") govern your use of the Orvo mobile '
          'application ("Orvo", "the app"). By installing or using the app '
          'you agree to these Terms. If you do not agree, please do not use '
          'the app.',
        ),
        _DocSection(
          'What Orvo does',
          'Orvo is an offline music player. It scans and plays the audio '
          'files that are already stored on your device, and provides '
          'features such as playlists, an equalizer, lyrics display and '
          'playback statistics. Orvo does not host, sell, download or '
          'stream music content of any kind.',
        ),
        _DocSection(
          'License',
          'You are granted a personal, non-exclusive, non-transferable, '
          'revocable license to install and use Orvo on devices you own or '
          'control, for personal, non-commercial purposes. You may not '
          'copy, modify, distribute, sell, sublicense or reverse engineer '
          'the app except where such a restriction is prohibited by '
          'applicable law.',
        ),
        _DocSection(
          'Your content and your responsibility',
          'All music and audio files played through Orvo belong to you or '
          'their respective rights holders — the app claims no ownership of '
          'them. You are solely responsible for ensuring that you have the '
          'legal right to possess and play the files on your device, and '
          'for complying with the copyright laws that apply to you. Orvo '
          'must not be used to play, share or manage content you are not '
          'lawfully entitled to.',
        ),
        _DocSection(
          'Intellectual property',
          'The app itself — its code, design, interface, icons and name — '
          'is the intellectual property of the Orvo developer and is '
          'protected by applicable copyright and trademark laws. These '
          'Terms do not grant you any right to use the Orvo name or '
          'branding outside of normal use of the app.',
        ),
        _DocSection(
          'Third-party services',
          'The optional "Online lyrics" feature queries LRCLIB '
          '(lrclib.net), an independent third-party service, when you '
          'enable it. Lyrics returned by that service belong to their '
          'respective rights holders, and the availability and accuracy of '
          'the service are outside of Orvo\'s control.',
        ),
        _DocSection(
          'No warranty',
          'Orvo is provided "as is" and "as available", without warranties '
          'of any kind, express or implied, including fitness for a '
          'particular purpose and non-infringement. Playback behaviour, '
          'equalizer availability and battery behaviour can vary between '
          'devices and Android versions, and uninterrupted or error-free '
          'operation is not guaranteed.',
        ),
        _DocSection(
          'Limitation of liability',
          'To the maximum extent permitted by law, the developer of Orvo '
          'shall not be liable for any indirect, incidental, special or '
          'consequential damages, or for any loss of data, arising out of '
          'or related to your use of (or inability to use) the app.',
        ),
        _DocSection(
          'Changes to these Terms',
          'These Terms may be revised from time to time — for example, when '
          'new features ship. The updated version will be included in the '
          'app with a new effective date at the top of this page, and your '
          'continued use of the app after an update means you accept the '
          'revised Terms.',
        ),
        _DocSection(
          'Termination',
          'You may stop using Orvo at any time by uninstalling it. The '
          'license granted above ends automatically if you breach these '
          'Terms.',
        ),
        _DocSection(
          'Contact',
          'Questions about these Terms can be sent to support@orvo.app.',
        ),
      ],
    );
  }
}

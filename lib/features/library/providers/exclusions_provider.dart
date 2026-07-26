import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme_provider.dart' show sharedPreferencesProvider;

/// FEATURE (#25): folder exclusions — hide voice notes, call recordings and
/// other non-music folders from the entire library.
///
/// Non-destructive by design: exclusion only filters what [songsProvider]
/// exposes. Files stay on disk, and favorites / playlist rows / play stats
/// for excluded songs are kept (cleanup runs against the RAW list), so
/// re-including a folder restores everything exactly as it was.

const _kExcludedKey = 'orvo.excludedFolders';
const _kDefaultsAppliedKey = 'orvo.exclusionDefaultsApplied';

class ExcludedFoldersNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() =>
      ref.read(sharedPreferencesProvider).getStringList(_kExcludedKey)?.toSet() ??
      <String>{};

  void toggle(String folderPath) {
    final next = Set<String>.from(state);
    next.contains(folderPath) ? next.remove(folderPath) : next.add(folderPath);
    state = next;
    _persist(next);
  }

  /// First-run smart defaults: exclude the matched folders and remember that
  /// defaults have been applied so they're never re-forced on the user.
  void applyDefaults(Iterable<String> folderPaths) {
    final prefs = ref.read(sharedPreferencesProvider);
    if (prefs.getBool(_kDefaultsAppliedKey) ?? false) return;
    prefs.setBool(_kDefaultsAppliedKey, true);
    if (folderPaths.isEmpty) return;
    final next = Set<String>.from(state)..addAll(folderPaths);
    state = next;
    _persist(next);
  }

  bool get defaultsApplied =>
      ref.read(sharedPreferencesProvider).getBool(_kDefaultsAppliedKey) ??
      false;

  void _persist(Set<String> paths) {
    ref
        .read(sharedPreferencesProvider)
        .setStringList(_kExcludedKey, paths.toList(growable: false));
  }
}

final excludedFoldersProvider =
    NotifierProvider<ExcludedFoldersNotifier, Set<String>>(
        ExcludedFoldersNotifier.new);

/// True when [songPath] lives in (or under) any excluded folder.
bool isExcludedPath(String songPath, Set<String> excluded) {
  if (excluded.isEmpty) return false;
  for (final folder in excluded) {
    if (songPath == folder ||
        songPath.startsWith('$folder/') ||
        songPath.startsWith('$folder\\')) {
      return true;
    }
  }
  return false;
}

/// Path fragments (lower-case, forward slashes) that mark typical
/// non-music folders. Conservative on purpose — a wrong auto-exclusion is
/// worse than a missed one, and everything is one tap to undo.
const defaultExclusionPatterns = <String>[
  'whatsapp audio',
  'whatsapp voice',
  '/recordings',
  'call recording',
  'callrecording',
  '/notifications',
  '/ringtones',
  '/alarms',
  'telegram audio',
  'voice recorder',
  'sound recorder',
  'voice notes',
  'voicenotes',
];

bool matchesDefaultPattern(String folderPath) {
  final p = folderPath.toLowerCase().replaceAll('\\', '/');
  return defaultExclusionPatterns.any(p.contains);
}

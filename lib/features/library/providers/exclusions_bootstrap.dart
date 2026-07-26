import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'exclusions_provider.dart';
import 'folder_providers.dart';

/// FEATURE (#25): first-run smart defaults. Once the first raw scan lands,
/// auto-exclude folders matching the usual non-music suspects (WhatsApp
/// audio, recordings, notifications…) exactly once, then never force them
/// again — the user's own choices always win afterwards. Kept alive by the
/// app shell.
final exclusionDefaultsProvider = Provider<void>((ref) {
  ref.listen(rawFoldersProvider, (previous, next) {
    final folders = next.valueOrNull;
    if (folders == null || folders.isEmpty) return;
    final notifier = ref.read(excludedFoldersProvider.notifier);
    if (notifier.defaultsApplied) return;
    notifier.applyDefaults([
      for (final folder in folders)
        if (matchesDefaultPattern(folder.path)) folder.path,
    ]);
  });
});

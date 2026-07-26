import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/l10n.dart';
import '../providers/exclusions_provider.dart';
import '../providers/folder_providers.dart';

/// FEATURE (#25): manage which folders appear in the library. Every folder
/// from the RAW scan is listed (including currently hidden ones, so nothing
/// is ever unrecoverable). Switch ON = shown in Orvo, OFF = hidden
/// everywhere. Files are never touched on disk.
class ExcludedFoldersScreen extends ConsumerWidget {
  const ExcludedFoldersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(l10nProvider);
    final excluded = ref.watch(excludedFoldersProvider);
    final foldersAsync = ref.watch(rawFoldersProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t.excludedFolders)),
      body: foldersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
            child: Text(t.scanning, style: theme.textTheme.bodySmall)),
        data: (folders) {
          // Hidden folders pinned on top so nothing "disappears" silently.
          final sorted = [...folders]..sort((a, b) {
              final ax = excluded.contains(a.path) ? 0 : 1;
              final bx = excluded.contains(b.path) ? 0 : 1;
              if (ax != bx) return ax - bx;
              return a.name.toLowerCase().compareTo(b.name.toLowerCase());
            });

          return ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Text(
                  t.excludedFoldersExplainer,
                  style: theme.textTheme.bodySmall,
                ),
              ),
              for (final folder in sorted)
                SwitchListTile(
                  value: !excluded.contains(folder.path),
                  onChanged: (_) => ref
                      .read(excludedFoldersProvider.notifier)
                      .toggle(folder.path),
                  secondary: Icon(
                    excluded.contains(folder.path)
                        ? Icons.folder_off_outlined
                        : Icons.folder_rounded,
                    color: excluded.contains(folder.path)
                        ? theme.colorScheme.onSurface.withOpacity(.4)
                        : theme.colorScheme.primary,
                  ),
                  title: Text(folder.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${t.nSongs(folder.songCount)} · ${folder.path}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

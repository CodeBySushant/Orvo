import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/folder_providers.dart';

class FoldersTab extends ConsumerWidget {
  const FoldersTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final foldersAsync = ref.watch(foldersProvider);

    return foldersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => const Center(child: Text('Could not load folders')),
      data: (folders) {
        if (folders.isEmpty) {
          return const Center(child: Text('No folders found'));
        }
        return ListView.builder(
          physics: const BouncingScrollPhysics(),
          itemCount: folders.length,
          itemBuilder: (context, i) {
            final folder = folders[i];
            return ListTile(
              onTap: () => context.go(
                  '/folder?path=${Uri.encodeComponent(folder.path)}'),
              leading: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.folder_rounded,
                    color: theme.colorScheme.primary),
              ),
              title: Text(folder.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '${folder.songCount} songs · ${folder.path}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium,
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
            );
          },
        );
      },
    );
  }
}

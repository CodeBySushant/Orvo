import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/l10n.dart';
import '../system/system_channel.dart';
import 'backup_service.dart';

/// FEATURE (backup): Backup & Restore screen.
///
/// Backup builds a single JSON snapshot (playlists, favorites, play stats,
/// excluded folders, settings) and hands it to the system "Save as…" picker —
/// Google Drive shows up there as a destination when the Drive app is
/// installed, so users can put their backup straight in the cloud. Restore
/// picks a backup file, shows what's inside, and MERGES it in (never wipes).
class BackupRestoreScreen extends ConsumerStatefulWidget {
  const BackupRestoreScreen({super.key});

  @override
  ConsumerState<BackupRestoreScreen> createState() =>
      _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends ConsumerState<BackupRestoreScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = ref.watch(l10nProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t.backupRestore)),
      body: Stack(
        children: [
          ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              // What's inside a backup.
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.add_to_drive_rounded,
                            color: theme.colorScheme.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Keep your Orvo safe',
                            style: theme.textTheme.titleMedium!
                                .copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'A backup is one small file holding your playlists, '
                      'favorites, play statistics, hidden folders and '
                      'settings — everything except the music files '
                      'themselves. Save it to Google Drive from the picker '
                      'and it survives reinstalls and new phones.',
                      style: theme.textTheme.bodySmall!.copyWith(height: 1.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              _ActionCard(
                icon: Icons.add_to_drive_rounded,
                title: 'Create backup',
                subtitle:
                    'Save to Google Drive, Downloads or anywhere you like',
                enabled: !_busy,
                onTap: _createBackup,
              ),
              const SizedBox(height: 12),
              _ActionCard(
                icon: Icons.settings_backup_restore_rounded,
                title: 'Restore from backup',
                subtitle: 'Pick a backup file — nothing gets deleted, '
                    'your current data is merged with the backup',
                enabled: !_busy,
                onTap: _restoreBackup,
              ),

              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'Restoring on a new phone matches songs by file path first, '
                  'then by title, artist and duration — so as long as the '
                  'same music is on the device, playlists and favorites '
                  'come back even if the files moved.',
                  style: theme.textTheme.labelMedium!.copyWith(height: 1.5),
                ),
              ),
            ],
          ),
          if (_busy)
            const Positioned.fill(
              child: ColoredBox(
                color: Colors.black26,
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Backup
  // ---------------------------------------------------------------------

  Future<void> _createBackup() async {
    setState(() => _busy = true);
    try {
      final json = await ref.read(backupServiceProvider).buildBackupJson();
      final ok = await SystemChannel.createDocument(
        BackupService.suggestedFileName(),
        json,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok
              ? 'Backup saved — keep it somewhere safe'
              : 'Backup cancelled'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not create the backup')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------------
  // Restore
  // ---------------------------------------------------------------------

  Future<void> _restoreBackup() async {
    setState(() => _busy = true);
    String? text;
    try {
      text = await SystemChannel.openDocument();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (text == null || !mounted) return; // cancelled

    final service = ref.read(backupServiceProvider);

    // Validate + preview before touching anything.
    int playlists, favorites, stats;
    int? createdAt;
    try {
      (playlists, favorites, stats, createdAt) = service.inspect(text);
    } on InvalidBackupException {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("That file doesn't look like an Orvo backup")),
      );
      return;
    }

    final when = createdAt == null
        ? ''
        : '\nCreated ${_formatDate(createdAt)}.';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Restore this backup?'),
        content: Text(
          'Found $playlists playlists, $favorites favorites and play '
          'history for $stats songs.$when\n\nEverything is merged into '
          'what you already have — nothing gets deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final summary = await service.restore(text);
      if (!mounted) return;
      final parts = <String>[
        if (summary.playlistsAdded > 0)
          '${summary.playlistsAdded} playlists restored',
        if (summary.playlistsSkipped > 0)
          '${summary.playlistsSkipped} already present',
        if (summary.favoritesAdded > 0)
          '${summary.favoritesAdded} favorites added',
        if (summary.statsMerged > 0) 'play history merged',
        if (summary.settingsApplied) 'settings applied',
      ];
      final headline =
          parts.isEmpty ? 'Nothing new to restore' : parts.join(' · ');
      final missing = summary.unresolvedSongs > 0
          ? '\n${summary.unresolvedSongs} songs from the backup were not '
              'found on this device and were skipped.'
          : '';
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Restore complete'),
          content: Text('$headline.$missing'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Restore failed — nothing was changed')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _formatDate(int millis) {
    final d = DateTime.fromMillisecondsSinceEpoch(millis);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }
}

// ---------------------------------------------------------------------------
// Pieces
// ---------------------------------------------------------------------------

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: theme.textTheme.titleMedium!
                            .copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: theme.textTheme.labelMedium!
                            .copyWith(height: 1.35)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

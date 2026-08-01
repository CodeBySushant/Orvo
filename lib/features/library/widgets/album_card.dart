import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart' show ArtworkType;

import '../../../core/widgets/artwork.dart';
import '../../../core/widgets/pressable.dart';
import '../domain/entities.dart';

class AlbumCard extends StatelessWidget {
  const AlbumCard({super.key, required this.album, this.width});

  final Album album;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: Artwork(
            // FIX (sync Issue 4): derived albums render their first song's
            // art (includes online covers); vinyl placeholder preserved.
            id: album.artSongId ?? album.id,
            type: album.artSongId != null
                ? ArtworkType.AUDIO
                : ArtworkType.ALBUM,
            placeholderType: ArtworkType.ALBUM,
            fallbackText: album.title,
            radius: 16,
          ),
        ),
        const SizedBox(height: 8),
        Text(album.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall),
        const SizedBox(height: 2),
        Text(album.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium),
      ],
    );

    return Pressable(
      onTap: () => context.go('/album/${album.id}'),
      child: width != null ? SizedBox(width: width, child: content) : content,
    );
  }
}

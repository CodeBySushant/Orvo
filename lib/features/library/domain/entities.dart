/// Immutable domain entities — the rest of the app never touches
/// on_audio_query models directly.
class Song {
  const Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.albumId,
    required this.artistId,
    required this.duration,
    required this.uri,
    required this.path,
    required this.dateAdded,
    this.track,
  });

  final int id;
  final String title;
  final String artist;
  final String album;
  final int albumId;
  final int artistId;
  final Duration duration;
  final String uri;

  /// Absolute file path from the media store — used for lyrics lookup
  /// (embedded ID3 tags and .lrc sidecar files).
  final String path;
  final int dateAdded; // epoch seconds
  final int? track;

  @override
  bool operator ==(Object other) => other is Song && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class Album {
  const Album({
    required this.id,
    required this.title,
    required this.artist,
    required this.songCount,
  });

  final int id;
  final String title;
  final String artist;
  final int songCount;
}

class Artist {
  const Artist({
    required this.id,
    required this.name,
    required this.trackCount,
    required this.albumCount,
  });

  final int id;
  final String name;
  final int trackCount;
  final int albumCount;
}

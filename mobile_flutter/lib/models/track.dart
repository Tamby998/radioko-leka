/// Modele hybride cote client — miroir de `api/src/sources/types.ts`.
///
/// Les capacites ne sont pas decoratives : [PlaybackController] et le
/// telechargement passent par [requireCapability], qui leve si la capacite
/// manque. Un titre du catalogue mondial ne peut donc pas finir en fichier
/// local par accident.
library;

enum Capability {
  stream,
  audioOnly,
  background,
  offline;

  static Capability? fromName(String raw) {
    for (final c in Capability.values) {
      if (c.name == raw) return c;
    }
    return null;
  }
}

class CapabilityError implements Exception {
  const CapabilityError(this.track, this.capability);

  final Track track;
  final Capability capability;

  @override
  String toString() =>
      'CapabilityError: "${track.title}" (${track.source}) ne porte pas la '
      'capacite ${capability.name}. Operation refusee.';
}

class Artist {
  const Artist({
    required this.id,
    required this.source,
    required this.name,
    this.avatarUrl,
    this.followers,
  });

  final String id;
  final String source;
  final String name;
  final String? avatarUrl;
  final int? followers;

  factory Artist.fromJson(Map<String, dynamic> json) => Artist(
        id: json['id'] as String,
        source: json['source'] as String,
        name: json['name'] as String,
        avatarUrl: json['avatarUrl'] as String?,
        followers: json['followers'] as int?,
      );
}

class Track {
  const Track({
    required this.uri,
    required this.source,
    required this.externalId,
    required this.title,
    required this.artists,
    required this.duration,
    required this.capabilities,
    required this.requiresVisiblePlayer,
    this.artworkUrl,
    this.streamUrl,
    this.viewCount,
  });

  final String uri;
  final String source;
  final String externalId;
  final String title;
  final List<Artist> artists;
  final Duration duration;
  final Set<Capability> capabilities;

  /// Vrai pour YouTube : le rendu video officiel doit rester a l'ecran.
  final bool requiresVisiblePlayer;

  final String? artworkUrl;

  /// Renseigne uniquement pour les sources sous licence.
  final String? streamUrl;

  final int? viewCount;

  String get artistNames => artists.map((a) => a.name).join(', ');
  String get primaryArtist => artists.isEmpty ? '' : artists.first.name;

  bool can(Capability c) => capabilities.contains(c);

  /// Une radio n'a ni duree ni fin : pas de barre de progression, pas
  /// d'enchainement, et le nom de la station tient lieu d'artiste.
  bool get estRadio => source == 'radio';

  /// A appeler avant toute ecriture de fichier ou lecture sans UI visible.
  void requireCapability(Capability c) {
    if (!can(c)) throw CapabilityError(this, c);
  }

  factory Track.fromJson(Map<String, dynamic> json) => Track(
        uri: json['uri'] as String,
        source: json['source'] as String,
        externalId: json['externalId'] as String,
        title: json['title'] as String,
        artists: ((json['artists'] as List<dynamic>?) ?? const [])
            .map((a) => Artist.fromJson(a as Map<String, dynamic>))
            .toList(growable: false),
        duration: Duration(milliseconds: (json['durationMs'] as num?)?.toInt() ?? 0),
        capabilities: ((json['capabilities'] as List<dynamic>?) ?? const [])
            .map((c) => Capability.fromName(c as String))
            .whereType<Capability>()
            .toSet(),
        requiresVisiblePlayer: json['requiresVisiblePlayer'] as bool? ?? false,
        artworkUrl: json['artworkUrl'] as String?,
        streamUrl: json['streamUrl'] as String?,
        viewCount: (json['viewCount'] as num?)?.toInt(),
      );
}

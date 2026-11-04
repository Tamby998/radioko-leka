/// Un rayon de la page d'accueil — miroir de `GenreSummary` cote Worker.
///
/// Seuls les genres racine en sont : un sous-genre sert a enchainer entre
/// proches, pas a decouper l'accueil en vingt etageres.
library;

class Genre {
  const Genre({
    required this.slug,
    required this.label,
    required this.tagline,
    required this.count,
    required this.pochettes,
  });

  final String slug;
  final String label;
  final String tagline;
  final int count;

  /// Jusqu'a quatre, les plus vues du rayon. La mosaique se compose ici :
  /// le Worker envoie les URLs, pas une image deja assemblee.
  final List<String> pochettes;

  factory Genre.fromJson(Map<String, dynamic> json) => Genre(
        slug: json['slug'] as String,
        label: json['label'] as String,
        tagline: json['tagline'] as String? ?? '',
        count: (json['count'] as num?)?.toInt() ?? 0,
        pochettes: ((json['pochettes'] as List<dynamic>?) ?? const [])
            .map((p) => p as String)
            .toList(growable: false),
      );
}

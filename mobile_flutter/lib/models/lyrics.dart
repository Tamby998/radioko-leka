/// Paroles synchronisees : parsing LRC et resolution de la ligne courante.
///
/// Aucune parole n'est embarquee dans l'app : tout vient de l'API a l'execution.
library;

class LyricsLine {
  const LyricsLine({required this.at, required this.text});

  final Duration at;
  final String text;

  bool get isBlank => text.trim().isEmpty;
}

class SyncedLyrics {
  SyncedLyrics({
    required this.lines,
    required this.instrumental,
    this.trackName = '',
    this.artistName = '',
  });

  final List<LyricsLine> lines;
  final bool instrumental;
  final String trackName;
  final String artistName;

  bool get isEmpty => lines.isEmpty;

  /// Index de la ligne a surligner a [position], ou -1 avant la premiere.
  ///
  /// Recherche dichotomique : appele a chaque tick du lecteur, donc tenu en
  /// O(log n) plutot qu'en balayage lineaire.
  int indexAt(Duration position) {
    var low = 0;
    var high = lines.length - 1;
    var found = -1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      if (lines[mid].at <= position) {
        found = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return found;
  }

  factory SyncedLyrics.fromJson(Map<String, dynamic> json) => SyncedLyrics(
        instrumental: json['instrumental'] as bool? ?? false,
        trackName: json['trackName'] as String? ?? '',
        artistName: json['artistName'] as String? ?? '',
        lines: ((json['lines'] as List<dynamic>?) ?? const [])
            .map(
              (l) => LyricsLine(
                at: Duration(
                  milliseconds: ((l as Map<String, dynamic>)['atMs'] as num).toInt(),
                ),
                text: l['text'] as String? ?? '',
              ),
            )
            .toList(growable: false),
      );

  /// Parse un LRC brut, pour la version corrigee que l'utilisateur garde en local.
  factory SyncedLyrics.parseLrc(String lrc) {
    final stamp = RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');
    final out = <LyricsLine>[];

    for (final raw in lrc.split(RegExp(r'\r?\n'))) {
      final stamps = <Duration>[];
      var cursor = 0;

      for (final m in stamp.allMatches(raw)) {
        // Un horodatage ne compte que s'il prefixe la ligne.
        if (m.start != cursor) break;
        cursor = m.end;
        final frac = m.group(3);
        stamps.add(
          Duration(
            minutes: int.parse(m.group(1)!),
            seconds: int.parse(m.group(2)!),
            milliseconds: frac == null ? 0 : int.parse(frac.padRight(3, '0')),
          ),
        );
      }

      if (stamps.isEmpty) continue;
      final text = raw.substring(cursor).trim();
      for (final at in stamps) {
        out.add(LyricsLine(at: at, text: text));
      }
    }

    out.sort((a, b) => a.at.compareTo(b.at));
    return SyncedLyrics(lines: out, instrumental: false);
  }
}

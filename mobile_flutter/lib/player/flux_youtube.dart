import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Trouve l'adresse du flux audio d'un titre YouTube.
///
/// Pourquoi ce detour plutot que le lecteur officiel : le lecteur IFrame doit
/// rester affiche pour jouer, et c'est ce qui coupait le son des qu'on passait
/// sur une autre app. Un flux audio est un son comme un autre — `just_audio`
/// le joue, `audio_service` le tient en arriere-plan, exactement comme une
/// radio.
///
/// Rien n'est telecharge : on recupere une adresse, on la lit en continu.
///
/// **Le client `VISIONOS`, et pourquoi lui.** Mesures du 26 novembre 2026, au
/// reseau, sur une adresse fraiche :
///
/// | Client | 0-1 Mio | 2 Mio | fin du fichier |
/// |---|---|---|---|
/// | `IOS` | 206 | 403 | 403 |
/// | `TVHTML5` | refus | — | — |
/// | `WEB` | « page needs to be reloaded » | — | — |
/// | `VISIONOS` | 206 | **206** | **206** |
///
/// Tous les autres clients sont passes a SABR, le protocole de diffusion par
/// segments de Google : leur adresse ne sert plus qu'a sonder le premier
/// mebioctet, et tout le reste repond 403 — une minute de musique, puis le
/// silence. Parler SABR demande un jeton d'attestation BotGuard renouvele a
/// chaque requete, et meme avec un jeton valide frappe dans un vrai
/// navigateur, la lecture s'arretait a 1,08 Mio sur 3,49.
///
/// `VISIONOS` n'y est pas passe. Il rend une adresse directe, lisible par
/// plages de bout en bout, **sans jeton d'aucune sorte**. Verifie : 3,49 Mio
/// recus en 3,3 s, fichier AAC 44,1 kHz de 225,77 s pour 226 s annoncees.
///
/// C'est le montage de NewPipe, pour la meme raison.
///
/// **Fragilite assumee.** Cette porte peut se fermer : rien n'oblige Google a
/// garder un client hors SABR. Le jour ou elle se ferme, la lecture des clips
/// s'arrete net, et il faudra soit un autre client, soit revenir au lecteur
/// officiel affiche.
///
/// **Resolu sur l'appareil, pas sur le Worker.** Mesure du 15 novembre 2026 :
/// quatre instances Piped publiques refusees le meme jour, « Sign in to
/// confirm that you're not a bot », parce qu'elles parlent depuis un
/// datacenter. Un telephone a une adresse residentielle, et c'est ce qui le
/// fait passer.
class FluxYoutube {
  FluxYoutube({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;

  /// La cle publique du client web de YouTube : elle est dans toutes les pages
  /// de youtube.com et n'ouvre rien a elle seule.
  static const _cle = 'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';

  static const _ua =
      'com.google.ios.youtube/19.36.4 (RealityDevice14,1; U; visionOS 1.3.21O771)';

  static const _client = {
    'clientName': 'VISIONOS',
    'clientVersion': '0.1',
    'deviceMake': 'Apple',
    'deviceModel': 'RealityDevice14,1',
    'osName': 'visionOS',
    'osVersion': '1.3.21O771',
    'hl': 'en',
    'gl': 'US',
  };

  /// Les adresses de Google expirent au bout de quelques heures. Cinq, pour
  /// garder une marge sous les six habituelles.
  static const _duree = Duration(hours: 5);

  final Map<String, _Trouvee> _cache = {};
  String? _identite;

  /// L'identite anonyme que YouTube attribue a un visiteur. Sans elle, le
  /// lecteur repond « Sign in to confirm you're not a bot » — mesure faite.
  Future<String> _visiteur() async {
    final connue = _identite;
    if (connue != null) return connue;

    final r = await _http
        .post(
          Uri.parse(
            'https://www.youtube.com/youtubei/v1/visitor_id?key=$_cle&prettyPrint=false',
          ),
          headers: const {'Content-Type': 'application/json', 'User-Agent': _ua},
          body: jsonEncode({
            'context': {
              'client': {
                'clientName': 'WEB',
                'clientVersion': '2.20250312.04.00',
                'hl': 'en',
                'gl': 'US',
              },
            },
          }),
        )
        .timeout(const Duration(seconds: 15));

    final d = jsonDecode(r.body) as Map<String, dynamic>;
    final v = (d['responseContext'] as Map<String, dynamic>?)?['visitorData'];
    if (v is! String || v.isEmpty) {
      throw StateError('identite de visiteur absente');
    }
    return _identite = v;
  }

  Future<FluxAudio> adresse(String videoId) async {
    final connue = _cache[videoId];
    if (connue != null && connue.valableJusqua.isAfter(DateTime.now())) {
      return connue.flux;
    }

    final identite = await _visiteur();
    final r = await _http
        .post(
          Uri.parse(
            'https://www.youtube.com/youtubei/v1/player?key=$_cle&prettyPrint=false',
          ),
          headers: {
            'Content-Type': 'application/json',
            'User-Agent': _ua,
            'X-Goog-Visitor-Id': identite,
            'X-YouTube-Client-Name': '101',
            'X-YouTube-Client-Version': '0.1',
          },
          body: jsonEncode({
            'videoId': videoId,
            'context': {
              'client': {..._client, 'visitorData': identite},
            },
            'contentCheckOk': true,
            'racyCheckOk': true,
          }),
        )
        .timeout(const Duration(seconds: 20));

    final d = jsonDecode(r.body) as Map<String, dynamic>;
    final statut =
        (d['playabilityStatus'] as Map<String, dynamic>?)?['status'] as String?;
    if (statut != 'OK') {
      final raison =
          (d['playabilityStatus'] as Map<String, dynamic>?)?['reason'] ?? '';
      throw StateError('lecteur refuse $videoId : $statut $raison');
    }

    final formats = ((d['streamingData'] as Map<String, dynamic>?)?['adaptiveFormats']
            as List<dynamic>? ??
        const []);

    final audio = formats
        .cast<Map<String, dynamic>>()
        .where((f) => (f['mimeType'] as String? ?? '').startsWith('audio/'))
        .where((f) => f['url'] is String)
        .toList();
    if (audio.isEmpty) throw StateError('aucun flux audio pour $videoId');

    // mp4 (AAC) et non webm (opus) : AVPlayer ne lit pas l'opus, donc aucun
    // iPhone ne lirait le meilleur flux que YouTube propose. Quelques kilobits
    // de moins, que personne n'entend, contre un silence complet sur iOS.
    final mp4 = audio
        .where((f) => (f['mimeType'] as String? ?? '').contains('mp4'))
        .toList();
    var choix = mp4.isNotEmpty ? mp4 : audio;

    // Jamais un flux sous 44,1 kHz tant qu'il en existe un : l'itag 139 est du
    // HE-AAC, dont le coeur est code a 22050 Hz et restitue a 44100. AVPlayer
    // lit le timescale du conteneur et decode au double, donc il annonce une
    // duree exactement doublee — mesure du 27 novembre 2026 : un titre fini a
    // 3:03 affichait 6:08, et trois minutes de silence passaient avant
    // l'enchainement.
    final pleinTaux = choix
        .where((f) =>
            int.tryParse('${f['audioSampleRate'] ?? ''}') != null &&
            int.parse('${f['audioSampleRate']}') >= 44100)
        .toList();
    if (pleinTaux.isNotEmpty) choix = pleinTaux;

    choix.sort(
      (a, b) => ((b['bitrate'] as num?) ?? 0).compareTo((a['bitrate'] as num?) ?? 0),
    );

    final retenu = choix.first;
    final url = retenu['url'] as String;

    // La duree que YouTube donne pour ce fichier precis, au milliseconde pres.
    // Elle vaut mieux que celle du catalogue, qui est une annonce, et mieux
    // que celle d'AVPlayer, qui est une estimation.
    final ms = int.tryParse('${retenu['approxDurationMs'] ?? ''}');
    final duree = ms == null || ms <= 0 ? null : Duration(milliseconds: ms);

    debugPrint(
      'RadiokoLeka — $videoId : itag ${retenu['itag']}, '
      '${(((retenu['bitrate'] as num?) ?? 0) / 1000).round()} kbps, '
      '${retenu['audioSampleRate']} Hz, duree ${duree?.inSeconds}s',
    );

    final flux = FluxAudio(url, duree);
    _cache[videoId] = _Trouvee(flux, DateTime.now().add(_duree));
    return flux;
  }

  /// A appeler quand une adresse a ete refusee : elle a peut-etre expire, et
  /// le prochain essai doit repartir d'une resolution fraiche.
  void oublier(String videoId) => _cache.remove(videoId);

  void dispose() {
    _cache.clear();
    _http.close();
  }
}

/// Une adresse de flux, et la duree du fichier qu'elle sert.
class FluxAudio {
  const FluxAudio(this.url, this.duree);

  final String url;

  /// `null` quand YouTube ne l'a pas donnee : on retombe alors sur ce
  /// qu'annonce le lecteur.
  final Duration? duree;
}

class _Trouvee {
  const _Trouvee(this.flux, this.valableJusqua);

  final FluxAudio flux;
  final DateTime valableJusqua;
}

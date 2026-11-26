import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/track.dart';
import 'flux_youtube.dart';
import 'lecteur_web.dart';
import 'service_arriere_plan.dart';

/// Comment jouer un clip du catalogue mondial.
///
/// `true` : on resout l'adresse du flux audio et `just_audio` le joue, comme
/// une radio — donc ecran eteint et app masquee, ce qui est la raison d'etre
/// d'un lecteur audio.
///
/// `false` : on revient au lecteur IFrame officiel, qui doit rester affiche
/// pour jouer. Conforme aux conditions de YouTube, mais le son se coupe des
/// qu'on passe sur une autre app.
///
/// Le drapeau reste ici, et les deux chemins restent compiles, parce que la
/// porte qu'emprunte le premier peut se fermer du jour au lendemain — voir
/// [FluxYoutube].
const bool fluxAudioYoutube = true;

/// Moteur retenu pour le titre courant.
enum PlaybackEngine {
  /// Lecteur IFrame officiel : la vue revient a la chaine de l'artiste.
  youtubeOfficial,

  /// Audio natif : radios et catalogue sous licence.
  licensedAudio,

  none,
}

enum Repetition { aucune, titre, liste }

/// Aiguille chaque titre vers le bon moteur, et tient la file d'attente.
///
/// Toute la frontiere legale du projet tient dans [_jouer] : un titre sans
/// [Capability.audioOnly] ne touche jamais `just_audio`, et aucun chemin ne
/// permet d'en extraire un flux.
class PlaybackController extends ChangeNotifier {
  PlaybackController({this.service}) {
    final s = service;
    if (s == null) return;
    // Les boutons de la notification, du casque et de l'ecran verrouille
    // arrivent ici : le service ne joue rien, il relaie.
    // Precises, et non `togglePlayPause` : la notification sait ce qu'elle
    // demande, et une demande de lecture ne doit jamais mettre en pause.
    s.surLecture = reprendre;
    s.surPause = mettreEnPause;
    s.surSuivant = suivant;
    s.surPrecedent = precedent;
    s.surDeplacement = seek;
    s.surArret = () async {
      await _demonter();
      notifyListeners();
    };
    addListener(_annoncerAuSysteme);
  }

  /// Absent dans les tests, et sur une plateforme sans service : tout
  /// fonctionne alors a l'identique, sans notification.
  final ServiceArrierePlan? service;

  final AudioPlayer _audio = AudioPlayer();
  final Random _de = Random();
  final FluxYoutube _flux = FluxYoutube();
  LecteurWeb? _web;

  /// Dernier etat annonce par le lecteur officiel : 1 joue, 2 pause, 0 fini.
  int _etatWeb = -1;
  Timer? _horloge;

  List<Track> _file = const [];
  int _index = -1;

  PlaybackEngine _engine = PlaybackEngine.none;
  Duration _position = Duration.zero;

  StreamSubscription<Duration>? _suiviPosition;
  StreamSubscription<void>? _suiviFin;

  bool _aleatoire = false;
  Repetition _repetition = Repetition.aucune;

  /// Faux par defaut : on vient ecouter, pas regarder. La video se montre a
  /// la demande, et le lecteur continue de tourner quand elle est cachee.
  bool _videoVisible = false;

  /// Appele quand la file arrive a sa fin : l'ecran y branche
  /// `/v1/similar`, pour que la lecture continue sans qu'on la relance.
  Future<List<Track>> Function(Track dernier)? surFileVide;

  Track? get current => _index >= 0 && _index < _file.length ? _file[_index] : null;
  List<Track> get file => List.unmodifiable(_file);
  int get index => _index;
  List<Track> get aSuivre =>
      _index < 0 ? const [] : _file.skip(_index + 1).toList(growable: false);

  PlaybackEngine get engine => _engine;
  Duration get position => _position;
  LecteurWeb? get lecteurWeb => _web;

  bool get aleatoire => _aleatoire;
  Repetition get repetition => _repetition;
  bool get videoVisible => _videoVisible;
  bool get aUneVideo => _engine == PlaybackEngine.youtubeOfficial;

  bool get enLecture => switch (_engine) {
        PlaybackEngine.licensedAudio => _audio.playing,
        PlaybackEngine.youtubeOfficial => _etatWeb == 1,
        PlaybackEngine.none => false,
      };

  void basculerVideo() {
    _videoVisible = !_videoVisible;
    notifyListeners();
  }

  void basculerAleatoire() {
    _aleatoire = !_aleatoire;
    notifyListeners();
  }

  void cyclerRepetition() {
    _repetition = switch (_repetition) {
      Repetition.aucune => Repetition.liste,
      Repetition.liste => Repetition.titre,
      Repetition.titre => Repetition.aucune,
    };
    notifyListeners();
  }

  /// Point d'entree unique : on joue toujours *dans* une liste, meme quand
  /// elle ne contient qu'un titre. Sans cela, « suivant » n'a nulle part ou
  /// aller et la lecture s'arrete a chaque fin de morceau.
  Future<void> jouerListe(List<Track> titres, int depart) async {
    if (titres.isEmpty) return;
    _file = List.of(titres);
    _index = depart.clamp(0, _file.length - 1);
    await _jouer(_file[_index]);
  }

  Future<void> jouer(Track titre) => jouerListe([titre], 0);

  /// Ajoute a la suite sans interrompre ce qui passe.
  void mettreEnFile(Iterable<Track> titres) {
    if (titres.isEmpty) return;
    _file = [..._file, ...titres];
    notifyListeners();
  }

  void viderLaSuite() {
    if (_index < 0) return;
    _file = _file.take(_index + 1).toList();
    notifyListeners();
  }

  Future<void> allerA(int i) async {
    if (i < 0 || i >= _file.length) return;
    _index = i;
    await _jouer(_file[_index]);
  }

  Future<void> suivant() async {
    if (_file.isEmpty) return;

    if (_aleatoire && _file.length > 1) {
      var tire = _index;
      while (tire == _index) {
        tire = _de.nextInt(_file.length);
      }
      return allerA(tire);
    }

    if (_index + 1 < _file.length) return allerA(_index + 1);

    if (_repetition == Repetition.liste) return allerA(0);

    // La file est finie : on demande de quoi continuer plutot que de
    // s'arreter net.
    final dernier = current;
    final remplir = surFileVide;
    if (dernier != null && remplir != null) {
      final suite = await remplir(dernier);
      if (suite.isNotEmpty) {
        mettreEnFile(suite);
        return allerA(_index + 1);
      }
    }
    notifyListeners();
  }

  /// Avant trois secondes on revient au titre precedent ; apres, on reprend
  /// celui-ci au debut. C'est le comportement de tous les lecteurs, et il
  /// evite de perdre un morceau d'un doigt maladroit.
  Future<void> precedent() async {
    if (_file.isEmpty) return;
    if (_position.inSeconds >= 3) return seek(Duration.zero);
    if (_index > 0) return allerA(_index - 1);
    return seek(Duration.zero);
  }

  Future<void> _jouer(Track titre) async {
    await _demonter();

    if (titre.can(Capability.audioOnly) || fluxAudioYoutube) {
      await _jouerAudio(titre);
    } else {
      _jouerYoutube(titre);
    }
    notifyListeners();
  }

  /// L'adresse du flux : donnee par le Worker pour une radio et pour le
  /// catalogue sous licence, resolue sur l'appareil pour un clip.
  Future<String> _adresse(Track titre) async {
    final connue = titre.streamUrl;
    if (connue != null) return connue;
    if (titre.externalId.isEmpty) {
      throw StateError('Pas d adresse, et pas d identifiant, pour ${titre.uri}');
    }
    return _flux.adresse(titre.externalId);
  }

  Future<void> _jouerAudio(Track titre) async {
    _engine = PlaybackEngine.licensedAudio;

    // `setUrl` leve pour une station morte, pour une adresse expiree, et aussi
    // pour une station que le systeme refuse. Sans ce filet, l'erreur remontait
    // jusqu'a l'ecran qui n'en faisait rien : le bouton restait sur « lecture »
    // et plus rien n'arrivait, jamais.
    final String url;
    try {
      url = await _adresse(titre);
      await _audio.setUrl(url);
    } catch (e) {
      debugPrint('RadiokoLeka — lecture refusee pour ${titre.uri} : $e');
      // Une adresse resolue a pu expirer : on l'oublie, pour que le prochain
      // essai reparte d'une resolution fraiche.
      if (titre.streamUrl == null) _flux.oublier(titre.externalId);
      _engine = PlaybackEngine.none;
      surRefusYoutube?.call(titre, -1);
      notifyListeners();
      return;
    }

    _suiviPosition = _audio.positionStream.listen((p) {
      _position = p;
      notifyListeners();
    });

    // Une radio n'a pas de fin : seul un flux fini declenche l'enchainement.
    _suiviFin = _audio.processingStateStream
        .where((e) => e == ProcessingState.completed)
        .listen((_) => _surFin());

    await _audio.play();
  }

  void _jouerYoutube(Track titre) {
    _engine = PlaybackEngine.youtubeOfficial;
    _etatWeb = -1;

    // La page est gardee d un titre a l autre : la recreer rechargerait le
    // lecteur officiel a chaque morceau, pour une seconde d attente et rien
    // de gagne.
    _web ??= LecteurWeb(
      surEtat: (etat) {
        _etatWeb = etat;
        if (etat == 0) _surFin();
        notifyListeners();
      },
      surErreur: (code) {
        // Le refus est remonte tel quel : c est a l ecran de decider s il
        // faut enchainer ou le dire, pas au moteur.
        _etatWeb = -1;
        surRefusYoutube?.call(titre, code);
        notifyListeners();
      },
    );
    _web!.jouer(titre.externalId);

    // La position se demande au lecteur, elle ne se compte pas ici : une
    // horloge locale continue d avancer quand le lecteur est bloque.
    _horloge?.cancel();
    _horloge = Timer.periodic(const Duration(milliseconds: 400), (_) async {
      if (_engine != PlaybackEngine.youtubeOfficial) return;
      _position = await _web!.position();
      notifyListeners();
    });
  }

  /// Appele quand YouTube refuse un clip, avec son code tel quel.
  void Function(Track titre, int code)? surRefusYoutube;

  void _surFin() {
    if (_repetition == Repetition.titre) {
      seek(Duration.zero);
      return;
    }
    suivant();
  }

  Future<void> reprendre() async {
    if (enLecture) return;
    await togglePlayPause();
  }

  Future<void> mettreEnPause() async {
    if (!enLecture) return;
    await togglePlayPause();
  }

  /// Dit au systeme ce qui passe, a chaque changement d'etat.
  ///
  /// Rien a publier sans titre, et rien non plus pour un titre qui exige un
  /// lecteur visible : [ServiceArrierePlan.publier] s'en retire de lui-meme.
  void _annoncerAuSysteme() {
    final s = service;
    final titre = current;
    if (s == null) return;
    if (titre == null) {
      s.retirer();
      return;
    }
    s.publier(titre: titre, enLecture: enLecture, position: _position);
  }

  Future<void> togglePlayPause() async {
    switch (_engine) {
      case PlaybackEngine.licensedAudio:
        _audio.playing ? await _audio.pause() : await _audio.play();
      case PlaybackEngine.youtubeOfficial:
        await _web?.basculer();
      case PlaybackEngine.none:
        break;
    }
    notifyListeners();
  }

  Future<void> seek(Duration to) async {
    switch (_engine) {
      case PlaybackEngine.licensedAudio:
        await _audio.seek(to);
      case PlaybackEngine.youtubeOfficial:
        await _web?.aller(to);
      case PlaybackEngine.none:
        break;
    }
    _position = to;
    notifyListeners();
  }

  Future<void> _demonter() async {
    await _suiviPosition?.cancel();
    await _suiviFin?.cancel();
    _suiviPosition = null;
    _suiviFin = null;
    _horloge?.cancel();
    _horloge = null;

    await _audio.stop();
    // La page reste en vie, seul le clip s arrete : on la garde d un titre a
    // l autre. Elle ne part qu avec `dispose`.
    await _web?.stopper();
    _etatWeb = -1;
    _engine = PlaybackEngine.none;
    _position = Duration.zero;
  }

  @override
  Future<void> dispose() async {
    if (service != null) removeListener(_annoncerAuSysteme);
    service?.retirer();
    await _demonter();
    await _audio.dispose();
    _flux.dispose();
    super.dispose();
  }
}

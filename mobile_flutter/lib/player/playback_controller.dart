import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
// `hide PlayerState` : les deux paquets definissent ce nom, et sans ce
// masque le fichier ne compile pas. Seul celui du lecteur YouTube nous sert ;
// de just_audio on ne prend que `AudioPlayer`.
import 'package:just_audio/just_audio.dart' hide PlayerState;
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../models/track.dart';

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
  PlaybackController();

  final AudioPlayer _audio = AudioPlayer();
  final Random _de = Random();
  YoutubePlayerController? _youtube;

  List<Track> _file = const [];
  int _index = -1;

  PlaybackEngine _engine = PlaybackEngine.none;
  Duration _position = Duration.zero;

  StreamSubscription<Duration>? _suiviPosition;
  StreamSubscription<void>? _suiviFin;
  StreamSubscription<YoutubeVideoState>? _suiviYoutube;
  StreamSubscription<YoutubePlayerValue>? _suiviEtatYoutube;

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
  YoutubePlayerController? get youtubeController => _youtube;

  bool get aleatoire => _aleatoire;
  Repetition get repetition => _repetition;
  bool get videoVisible => _videoVisible;
  bool get aUneVideo => _engine == PlaybackEngine.youtubeOfficial;

  bool get enLecture => switch (_engine) {
        PlaybackEngine.licensedAudio => _audio.playing,
        PlaybackEngine.youtubeOfficial =>
          _youtube?.value.playerState == PlayerState.playing,
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

    if (titre.can(Capability.audioOnly)) {
      await _jouerAudio(titre);
    } else {
      _jouerYoutube(titre);
    }
    notifyListeners();
  }

  Future<void> _jouerAudio(Track titre) async {
    final url = titre.streamUrl;
    if (url == null) {
      throw StateError(
        'Le titre ${titre.uri} porte audioOnly mais n a pas de streamUrl.',
      );
    }
    _engine = PlaybackEngine.licensedAudio;
    await _audio.setUrl(url);

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
    _youtube = YoutubePlayerController.fromVideoId(
      videoId: titre.externalId,
      autoPlay: true,
      // Le lecteur officiel garde ses controles : c'est la condition pour que
      // la lecture soit legitime et que la vue soit comptee a l'artiste.
      params: const YoutubePlayerParams(
        showControls: true,
        showFullscreenButton: true,
      ),
    );

    // La position vient d'un flux du lecteur, pas d'une horloge locale. Une
    // horloge continue d'avancer quand le lecteur, lui, est bloque.
    _suiviYoutube = _youtube!.videoStateStream.listen((etat) {
      _position = etat.position;
      notifyListeners();
    });

    _suiviEtatYoutube = _youtube!.stream.listen((v) {
      if (v.playerState == PlayerState.ended) _surFin();
      notifyListeners();
    });
  }

  void _surFin() {
    if (_repetition == Repetition.titre) {
      seek(Duration.zero);
      return;
    }
    suivant();
  }

  Future<void> togglePlayPause() async {
    switch (_engine) {
      case PlaybackEngine.licensedAudio:
        _audio.playing ? await _audio.pause() : await _audio.play();
      case PlaybackEngine.youtubeOfficial:
        _youtube?.value.playerState == PlayerState.playing
            ? _youtube?.pauseVideo()
            : _youtube?.playVideo();
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
        await _youtube?.seekTo(seconds: to.inMilliseconds / 1000);
      case PlaybackEngine.none:
        break;
    }
    _position = to;
    notifyListeners();
  }

  Future<void> _demonter() async {
    await _suiviPosition?.cancel();
    await _suiviFin?.cancel();
    await _suiviYoutube?.cancel();
    await _suiviEtatYoutube?.cancel();
    _suiviPosition = null;
    _suiviFin = null;
    _suiviYoutube = null;
    _suiviEtatYoutube = null;

    await _audio.stop();
    _youtube?.close();
    _youtube = null;
    _engine = PlaybackEngine.none;
    _position = Duration.zero;
  }

  @override
  Future<void> dispose() async {
    await _demonter();
    await _audio.dispose();
    super.dispose();
  }
}

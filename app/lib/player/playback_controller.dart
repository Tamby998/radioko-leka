import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../models/track.dart';

/// Moteur retenu pour le titre courant.
enum PlaybackEngine {
  /// Lecteur IFrame officiel : la video reste visible, la vue va a l'artiste.
  youtubeOfficial,

  /// Audio natif : arriere-plan et hors-connexion autorises.
  licensedAudio,

  none,
}

/// Aiguille chaque titre vers le bon moteur, selon ses capacites.
///
/// Toute la frontiere legale du projet tient dans [play] : un titre sans
/// [Capability.audioOnly] ne touche jamais `just_audio`, et aucun chemin ne
/// permet d'en extraire un flux.
class PlaybackController extends ChangeNotifier {
  PlaybackController();

  final AudioPlayer _audio = AudioPlayer();
  YoutubePlayerController? _youtube;

  Track? _current;
  PlaybackEngine _engine = PlaybackEngine.none;
  Duration _position = Duration.zero;
  StreamSubscription<Duration>? _audioPositionSub;
  Timer? _youtubePoll;

  Track? get current => _current;
  PlaybackEngine get engine => _engine;
  Duration get position => _position;

  /// Non nul uniquement en mode [PlaybackEngine.youtubeOfficial] : l'UI doit
  /// alors afficher le lecteur, ce n'est pas optionnel.
  YoutubePlayerController? get youtubeController => _youtube;

  bool get isPlayingInBackgroundCapableEngine =>
      _engine == PlaybackEngine.licensedAudio;

  Future<void> play(Track track) async {
    await _teardown();
    _current = track;

    if (track.can(Capability.audioOnly)) {
      await _playLicensed(track);
    } else {
      _playYoutube(track);
    }
    notifyListeners();
  }

  Future<void> _playLicensed(Track track) async {
    final url = track.streamUrl;
    if (url == null) {
      throw StateError(
        'Le titre ${track.uri} porte audioOnly mais n a pas de streamUrl.',
      );
    }
    _engine = PlaybackEngine.licensedAudio;
    await _audio.setUrl(url);
    _audioPositionSub = _audio.positionStream.listen((p) {
      _position = p;
      notifyListeners();
    });
    await _audio.play();
  }

  void _playYoutube(Track track) {
    _engine = PlaybackEngine.youtubeOfficial;
    _youtube = YoutubePlayerController.fromVideoId(
      videoId: track.externalId,
      autoPlay: true,
      // Le lecteur officiel reste visible et conserve ses controles : c'est la
      // condition pour que la lecture soit legitime et que la vue soit comptee.
      params: const YoutubePlayerParams(
        showControls: true,
        showFullscreenButton: true,
      ),
    );

    // Le lecteur IFrame n'expose pas de flux de position : on interroge.
    _youtubePoll = Timer.periodic(const Duration(milliseconds: 250), (_) async {
      final c = _youtube;
      if (c == null) return;
      _position = await c.currentTime.then(
        (s) => Duration(milliseconds: (s * 1000).round()),
      );
      notifyListeners();
    });
  }

  Future<void> togglePlayPause() async {
    switch (_engine) {
      case PlaybackEngine.licensedAudio:
        _audio.playing ? await _audio.pause() : await _audio.play();
      case PlaybackEngine.youtubeOfficial:
        final state = _youtube?.value.playerState;
        state == PlayerState.playing
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

  Future<void> _teardown() async {
    _youtubePoll?.cancel();
    _youtubePoll = null;
    await _audioPositionSub?.cancel();
    _audioPositionSub = null;
    await _audio.stop();
    _youtube?.close();
    _youtube = null;
    _engine = PlaybackEngine.none;
    _position = Duration.zero;
  }

  @override
  Future<void> dispose() async {
    await _teardown();
    await _audio.dispose();
    super.dispose();
  }
}

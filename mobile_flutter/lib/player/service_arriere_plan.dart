import 'package:audio_service/audio_service.dart';

import '../models/track.dart';

/// Le service qui tient la lecture quand l'app n'est plus a l'ecran.
///
/// Il ne joue rien lui-meme : il relaie. La lecture reste dans
/// [PlaybackController] ; ce service lui donne une existence pour Android —
/// une notification, les boutons du casque, l'ecran verrouille — et surtout
/// un service au premier plan, sans lequel le systeme coupe le son des qu'on
/// masque l'app.
///
/// Il s'allume pour tout ce qui joue. La distinction d'avant — radios en
/// arriere-plan, clips seulement a l'ecran — venait du lecteur IFrame, qui
/// devait rester affiche pour jouer. Il n'est plus sur le chemin : un clip
/// passe maintenant par son flux audio, et un flux audio s'ecoute sans etre
/// regarde. Voir `fluxAudioYoutube` dans [PlaybackController].
class ServiceArrierePlan extends BaseAudioHandler with SeekHandler {
  /// Branches par [PlaybackController] : le service ne connait pas la file,
  /// il ne fait que transmettre ce qu'on lui demande.
  Future<void> Function()? surLecture;
  Future<void> Function()? surPause;
  Future<void> Function()? surSuivant;
  Future<void> Function()? surPrecedent;
  Future<void> Function(Duration ou)? surDeplacement;
  Future<void> Function()? surArret;

  @override
  Future<void> play() async => surLecture?.call();

  @override
  Future<void> pause() async => surPause?.call();

  @override
  Future<void> skipToNext() async => surSuivant?.call();

  @override
  Future<void> skipToPrevious() async => surPrecedent?.call();

  @override
  Future<void> seek(Duration position) async => surDeplacement?.call(position);

  @override
  Future<void> stop() async {
    await surArret?.call();
    retirer();
  }

  /// Annonce au systeme ce qui passe. Sans titre, rien n'est publie.
  void publier({
    required Track titre,
    required bool enLecture,
    required Duration position,
    /// La duree du fichier, quand le lecteur la connait. Celle du catalogue
    /// n'est qu'une annonce, et elle est parfois plus courte que le morceau :
    /// la barre de la notification se remplissait alors avant la fin.
    Duration? duree,
  }) {
    final totale = duree ?? titre.duration;
    mediaItem.add(MediaItem(
      id: titre.uri,
      title: titre.title,
      artist: titre.estRadio ? 'En direct' : titre.artistNames,
      // Une radio n'a pas de duree : la donner afficherait une barre qui
      // n'avance jamais.
      duration: titre.estRadio || totale == Duration.zero ? null : totale,
      artUri: titre.artworkUrl == null ? null : Uri.parse(titre.artworkUrl!),
    ));

    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (enLecture) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: titre.estRadio ? const {} : const {MediaAction.seek},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: AudioProcessingState.ready,
      playing: enLecture,
      updatePosition: position,
    ));
  }

  /// Efface la notification et laisse tomber le service au premier plan.
  void retirer() {
    if (playbackState.value.processingState == AudioProcessingState.idle &&
        !playbackState.value.playing) {
      return;
    }
    mediaItem.add(null);
    playbackState.add(PlaybackState(
      processingState: AudioProcessingState.idle,
      playing: false,
    ));
  }
}

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radiokoleka/models/track.dart';
import 'package:radiokoleka/player/service_arriere_plan.dart';

Track _titre({
  required bool lecteurVisible,
  required Set<Capability> capacites,
  String source = 'youtube',
}) =>
    Track(
      uri: 'test:1',
      source: source,
      externalId: 'abc',
      title: 'Un titre',
      artists: const [Artist(id: 'a', source: 'test', name: 'Un artiste')],
      duration: const Duration(minutes: 3),
      capabilities: capacites,
      requiresVisiblePlayer: lecteurVisible,
    );

void main() {
  group('ServiceArrierePlan', () {
    test('publie une radio : elle a le droit de jouer sans etre regardee', () {
      final service = ServiceArrierePlan();
      service.publier(
        titre: _titre(
          lecteurVisible: false,
          capacites: {Capability.stream, Capability.audioOnly, Capability.background},
          source: 'radio',
        ),
        enLecture: true,
        position: Duration.zero,
      );

      expect(service.mediaItem.value, isNotNull);
      expect(service.playbackState.value.playing, isTrue);
      // Une radio n'a pas de duree : pas de barre qui n'avance jamais.
      expect(service.mediaItem.value!.duration, isNull);
    });

    // Ces trois tests affirmaient l'inverse jusqu'au 26 novembre 2026 : un clip
    // devait disparaitre de la notification, parce qu'il passait par le lecteur
    // IFrame et que celui-ci doit rester affiche. Il n'est plus sur le chemin —
    // un clip est resolu en flux audio et joue comme une radio — donc la regle
    // a change, et ces tests disent la nouvelle.

    test('publie un clip : il passe par son flux audio, comme une radio', () {
      final service = ServiceArrierePlan();
      service.publier(
        titre: _titre(
          lecteurVisible: true,
          capacites: {Capability.stream, Capability.background},
        ),
        enLecture: true,
        position: Duration.zero,
      );

      expect(service.mediaItem.value, isNotNull);
      expect(service.playbackState.value.playing, isTrue);
      // Un clip a une duree, lui : la barre doit avancer.
      expect(service.mediaItem.value!.duration, const Duration(minutes: 3));
    });

    test('publie aussi un titre sans la capacite background', () {
      final service = ServiceArrierePlan();
      service.publier(
        titre: _titre(
          lecteurVisible: false,
          capacites: {Capability.stream, Capability.audioOnly},
        ),
        enLecture: true,
        position: Duration.zero,
      );

      expect(service.mediaItem.value, isNotNull);
    });

    test('la notification suit le titre courant', () {
      final service = ServiceArrierePlan();
      service.publier(
        titre: _titre(
          lecteurVisible: false,
          capacites: {Capability.audioOnly, Capability.background},
          source: 'radio',
        ),
        enLecture: true,
        position: Duration.zero,
      );
      expect(service.mediaItem.value!.artist, 'En direct');

      service.publier(
        titre: _titre(
          lecteurVisible: true,
          capacites: {Capability.stream},
        ),
        enLecture: true,
        position: Duration.zero,
      );

      expect(service.mediaItem.value!.artist, 'Un artiste');
      expect(service.playbackState.value.playing, isTrue);
    });

    test('retirer efface la notification et repose l etat', () {
      final service = ServiceArrierePlan();
      service.publier(
        titre: _titre(
          lecteurVisible: false,
          capacites: {Capability.audioOnly, Capability.background},
          source: 'radio',
        ),
        enLecture: true,
        position: Duration.zero,
      );
      expect(service.mediaItem.value, isNotNull);

      service.retirer();

      expect(service.mediaItem.value, isNull);
      expect(service.playbackState.value.playing, isFalse);
      expect(service.playbackState.value.processingState,
          AudioProcessingState.idle);
    });

    test('les boutons du systeme sont relayes, pas joues ici', () async {
      final service = ServiceArrierePlan();
      final appels = <String>[];
      service.surLecture = () async => appels.add('lecture');
      service.surPause = () async => appels.add('pause');
      service.surSuivant = () async => appels.add('suivant');
      service.surPrecedent = () async => appels.add('precedent');
      service.surDeplacement = (ou) async => appels.add('aller ${ou.inSeconds}');

      await service.play();
      await service.pause();
      await service.skipToNext();
      await service.skipToPrevious();
      await service.seek(const Duration(seconds: 42));

      expect(appels,
          ['lecture', 'pause', 'suivant', 'precedent', 'aller 42']);
    });
  });
}

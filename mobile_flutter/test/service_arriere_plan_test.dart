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

    test('se retire pour un titre qui exige un lecteur visible', () {
      final service = ServiceArrierePlan();
      service.publier(
        titre: _titre(
          lecteurVisible: true,
          capacites: {Capability.stream, Capability.background},
        ),
        enLecture: true,
        position: Duration.zero,
      );

      expect(service.mediaItem.value, isNull);
      expect(service.playbackState.value.playing, isFalse);
    });

    test('se retire aussi pour un titre sans la capacite background', () {
      final service = ServiceArrierePlan();
      service.publier(
        titre: _titre(
          lecteurVisible: false,
          capacites: {Capability.stream, Capability.audioOnly},
        ),
        enLecture: true,
        position: Duration.zero,
      );

      expect(service.mediaItem.value, isNull);
    });

    test('une radio en cours puis un clip : la notification disparait', () {
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

      service.publier(
        titre: _titre(
          lecteurVisible: true,
          capacites: {Capability.stream},
        ),
        enLecture: true,
        position: Duration.zero,
      );

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

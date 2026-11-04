// Tests de ce qui se verifie sans reseau ni ecran : le decodage du JSON du
// Worker et le garde-fou des capacites.
//
// L'ancien test affirmait les textes de la maquette (« Viva Radio », stations
// ecrites en dur). Ils n'existent plus : les stations viennent du Worker.

import 'package:flutter_test/flutter_test.dart';
import 'package:radiokoleka/models/genre.dart';
import 'package:radiokoleka/models/track.dart';

void main() {
  group('Track', () {
    test('decode un clip du catalogue mondial', () {
      final t = Track.fromJson(const {
        'uri': 'youtube:abc123',
        'source': 'youtube',
        'externalId': 'abc123',
        'title': 'Hay hay',
        'artists': [
          {'id': 'c1', 'source': 'youtube', 'name': 'Mahaleo'}
        ],
        'durationMs': 254000,
        'capabilities': ['stream'],
        'requiresVisiblePlayer': true,
      });

      expect(t.title, 'Hay hay');
      expect(t.primaryArtist, 'Mahaleo');
      expect(t.duration.inSeconds, 254);
      expect(t.requiresVisiblePlayer, isTrue);
      expect(t.estRadio, isFalse);
    });

    test('une radio porte audioOnly et background, sans duree', () {
      final r = _radio();
      expect(r.estRadio, isTrue);
      expect(r.can(Capability.audioOnly), isTrue);
      expect(r.can(Capability.background), isTrue);
      expect(r.duration, Duration.zero);
      expect(r.streamUrl, isNotNull);
    });

    test('requireCapability refuse ce que le titre ne porte pas', () {
      final clip = Track.fromJson(const {
        'uri': 'youtube:abc123',
        'source': 'youtube',
        'externalId': 'abc123',
        'title': 'Un clip',
        'artists': [],
        'durationMs': 1000,
        'capabilities': ['stream'],
        'requiresVisiblePlayer': true,
      });

      // Le coeur du modele : aucun chemin ne doit transformer un clip en
      // fichier local, meme par oubli d'un appelant.
      expect(
        () => clip.requireCapability(Capability.offline),
        throwsA(isA<CapabilityError>()),
      );
      expect(() => clip.requireCapability(Capability.stream), returnsNormally);
    });

    test('une capacite inconnue du client est ignoree, pas fatale', () {
      // Le Worker peut en ajouter une avant que l'app ne soit mise a jour.
      final t = Track.fromJson(const {
        'uri': 'x:1',
        'source': 'x',
        'externalId': '1',
        'title': 'T',
        'artists': [],
        'durationMs': 0,
        'capabilities': ['stream', 'teleportation'],
      });
      expect(t.capabilities, {Capability.stream});
    });
  });

  group('Genre', () {
    test('decode un rayon et ses pochettes', () {
      final g = Genre.fromJson(const {
        'slug': 'gasy',
        'label': 'Musique malgache',
        'tagline': 'Du folk des hautes terres au salegy.',
        'count': 75,
        'pochettes': ['https://a/1.jpg', 'https://a/2.jpg'],
      });
      expect(g.slug, 'gasy');
      expect(g.count, 75);
      expect(g.pochettes, hasLength(2));
    });

    test('un rayon sans pochette ne plante pas', () {
      final g = Genre.fromJson(const {
        'slug': 'neuf',
        'label': 'Neuf',
        'count': 0,
      });
      expect(g.pochettes, isEmpty);
      expect(g.tagline, '');
    });
  });
}

Track _radio() => Track.fromJson(const {
      'uri': 'radio:uuid-1',
      'source': 'radio',
      'externalId': 'uuid-1',
      'title': 'Radio Don Bosco',
      'artists': [
        {'id': 'radio:MG', 'source': 'radio', 'name': 'Madagascar'}
      ],
      'durationMs': 0,
      'capabilities': ['stream', 'audioOnly', 'background'],
      'requiresVisiblePlayer': false,
      'streamUrl': 'http://stream.example/dbs',
    });

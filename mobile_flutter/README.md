# Radioko Leka — frontend mobile

Application mobile Flutter de Radioko Leka. Cette première interface propose
un accueil sombre et compact, pensé en priorité pour les radios malgaches.

## Interface actuelle

- recherche locale parmi les stations affichées ;
- catégories Malagasy, Actualités, Musique et Gospel ;
- grille de radios malgaches populaires ;
- ajout et retrait des favoris depuis une carte ;
- mini-lecteur avec lecture et pause ;
- navigation Accueil, Explorer, Favoris et Profil.

Les flux audio et les écrans secondaires seront connectés progressivement à
l'API de Radioko Leka.

## Lancer sur Android

Prérequis : Flutter stable, Android Studio, le SDK Android et un émulateur déjà
démarré.

```sh
cd mobile_flutter
flutter pub get
flutter devices
flutter run -d emulator-5554
```

Le premier lancement peut prendre plusieurs minutes pendant l'installation du
NDK, de CMake et des Build Tools Android. Les lancements suivants sont plus
rapides.

## Vérifier le frontend

```sh
dart format lib test
flutter analyze
flutter test
```

Le point d'entrée de l'interface est [`lib/main.dart`](lib/main.dart) et son
test principal se trouve dans [`test/widget_test.dart`](test/widget_test.dart).

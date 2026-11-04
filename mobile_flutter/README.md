# RadiokoLeka — mobile

L'app mobile, Android d'abord. Elle reunit les deux moities du projet : les
radios en direct, et le catalogue de titres avec ses paroles synchronisees.

Avant cette fusion il y avait deux applications Flutter dans le depot :
celle-ci, qui etait une maquette — six stations ecrites en dur, aucun son — et
`app/`, qui portait la logique mais n'avait aucun dossier de plateforme et
n'avait jamais ete compilee. L'une avait les dossiers `android/` et `ios/`,
l'autre le code ; elles sont maintenant une seule.

## Ce qu'elle fait

- **Radios** — stations en direct, Madagascar par defaut, le reste du monde
  au menu deroulant ;
- **Rayons** — les genres du catalogue, chacun avec une mosaique de quatre
  pochettes prises parmi ses titres les plus vus ;
- **Recherche** — titres, artistes et radios, avec autocompletion ;
- **Lecteur** — lecteur YouTube officiel pour les clips, audio natif pour les
  radios et le catalogue sous licence, paroles synchronisees quand elles
  existent.

Aucune cle d'API ne vit dans l'app : tout passe par le Worker.

## Lancer

Flutter stable et le SDK Android suffisent — **pas besoin d'Android Studio**,
les outils en ligne de commande font tout.

```sh
cd mobile_flutter
flutter pub get
flutter devices
flutter run -d <appareil>
```

L'app vise le Worker deploye. Pour pointer un Worker local, il faut une adresse
que le telephone peut joindre — `127.0.0.1` designe le telephone lui-meme :

```sh
flutter run --dart-define=RADIOKOLEKA_API_URL=http://192.168.1.12:8787
```

## Verifier

```sh
flutter analyze
flutter test
```

Les tests portent sur ce qui se verifie sans reseau ni ecran : le decodage du
JSON du Worker et le garde-fou des capacites, celui qui empeche un clip du
catalogue mondial de finir en fichier local.

## Deux pieges deja rencontres

**Le manifeste n'avait pas la permission `INTERNET`.** Elle n'etait declaree
que dans les variants debug et profile. En developpement tout marchait ; la
premiere version release aurait montre des listes vides, sans qu'aucune erreur
n'explique pourquoi.

**Android bloque le trafic en clair.** Beaucoup de radios diffusent encore en
http : 4 stations malgaches sur 18, 25 francaises sur 51. Sans
`usesCleartextTraffic`, elles sont refusees en silence — la station se
« lance » et rien ne sort. C'est la meme cause que
`NSAllowsArbitraryLoadsForMedia` cote macOS.

## Ce qui manque

**La lecture en arriere-plan.** `audio_service` est dans les dependances mais
le controleur parle a `just_audio` en direct : ecran eteint, la radio
s'arrete. C'est le prochain morceau, et sur un telephone c'est celui qui
compte.

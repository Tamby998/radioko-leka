# radioko-leka

Une radio interactive dans le terminal, écrite en Go et pensée d'abord pour
les radios malgaches.

## Fonctionnalités

- accueil chargé automatiquement avec les radios de Madagascar ;
- radios malgaches prioritaires dans les résultats de recherche ;
- favoris persistants dans la configuration utilisateur ;
- écran dédié à la station en cours de lecture ;
- recherche internationale via Radio Browser.

## Prérequis

- Go 1.19 ou plus récent
- `mpv`, `ffplay` ou `vlc` pour lire les flux audio

Sur macOS :

```sh
brew install mpv
```

## Lancer

```sh
go run ./cmd/radioko-leka
```

Tapez le nom d'une radio et appuyez sur Entrée. Sélectionnez ensuite une station
avec les flèches et appuyez de nouveau sur Entrée pour lancer la lecture.

## Raccourcis

- `↑` / `↓` : sélectionner une station
- `Entrée` : rechercher, écouter ou changer de station
- `h` : afficher les radios malgaches
- `/` ou `s` : rechercher une station
- `v` : afficher les favoris
- `n` : afficher l'écran en cours de lecture
- `f` : ajouter ou retirer la station des favoris
- `←` / `→` : diminuer ou augmenter le volume
- `Espace` : pause ou reprise
- `m` : couper ou rétablir le son
- `x` : arrêter la lecture
- `q` : quitter

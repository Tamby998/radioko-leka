# radioko-leka

Une radio interactive dans le terminal, écrite en Go.

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
- `←` / `→` : diminuer ou augmenter le volume
- `Espace` : pause ou reprise
- `m` : couper ou rétablir le son
- `/` : nouvelle recherche
- `Échap` : arrêter la lecture
- `q` : quitter

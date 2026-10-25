# Hira — architecture

## La regle fondatrice

Deux familles de sources, deux jeux de capacites. La frontiere n'est pas une
convention de code : elle est portee par le type `Track.capabilities`, et les
chemins hors-connexion / arriere-plan refusent tout `Track` qui ne porte pas la
capacite correspondante.

| Source                | stream | audioOnly | background | offline | Lecteur            |
|-----------------------|--------|-----------|------------|---------|--------------------|
| YouTube               | oui    | NON       | NON        | NON     | IFrame officiel visible |
| Audius / Jamendo      | oui    | oui       | oui        | oui     | audio natif        |
| Artistes gasy (opt-in)| oui    | oui       | oui        | oui     | audio natif        |

YouTube fournit le catalogue mondial : metadonnees via Data API v3, lecture via
le lecteur IFrame officiel. Aucun flux n'est extrait, aucun fichier n'est ecrit,
la vue revient a la chaine de l'artiste.

Le catalogue sous licence fournit tout ce qui demande un fichier local :
telechargement, ecoute hors reseau, lecture ecran verrouille.

## Couches

```
app/   Flutter  — Android, macOS, Windows, Linux (une codebase)
api/   Cloudflare Worker + D1 — catalogue cure, classements, cache paroles
```

Le client ne parle jamais directement a YouTube Data API : la cle reste dans le
Worker, qui mutualise le cache et protege le quota.

## Quota YouTube Data API (10 000 unites/jour)

- `search.list` coute 100 unites -> jamais a la volee depuis le client.
- `videos.list` coute 1 unite pour 50 IDs -> rafraichissement par lots en cron.

Le catalogue est cure en base. La recherche utilisateur tape d'abord D1, et ne
retombe sur `search.list` que pour les requetes inconnues, avec cache 24 h.

## Classements

Comptes d'ecoute maison (table `plays`), agreges en vues materialisees. Ce sont
nos propres metadonnees, independantes de toute plateforme.

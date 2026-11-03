#!/usr/bin/env python3
"""Ecrit le SQL qui retire les titres que le banc n'a pas vus jouer.

L'ordre des suppressions n'est pas libre : `track_genres` et `playlist_items`
referencent `tracks`. On retire donc les references avant les titres, sinon la
contrainte de cle etrangere refuse l'operation.

Les artistes qui perdent tous leurs titres partent aussi : un artiste sans
titre apparaitrait dans les classements sans rien a ecouter.

Le refus est aussi *memorise* dans `clips_refuses`. Supprimer le titre ne suffit
pas : `search.list` continue de le rendre, et un clip purge reviendrait dans les
resultats pour se barrer a la lecture.

**Seuls les verdicts `erreur:*` font supprimer.** Un `bloque` ne prouve rien :
il signifie que le delai a expire, ce qui arrive aussi quand l onglet dort ou
que le reseau traine. Une passe menee dans ces conditions avait declare 50
titres gasy injouables alors que 74 sur 76 jouent. Les `bloque` sont donc
listes a part, pour un second regard, et jamais supprimes automatiquement.
"""

import json
import sys
from pathlib import Path


def q(s: str) -> str:
    return "'" + s.replace("'", "''") + "'"


def main() -> None:
    candidats = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    verdicts = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
    sortie = Path(sys.argv[3])

    injouables, gardes, douteux = [], [], []
    for liste in candidats.values():
        for p in liste:
            verdict = verdicts.get(p["id"], "")
            if verdict == "ok":
                gardes.append(p)
            elif verdict.startswith("erreur:"):
                injouables.append(p)
            else:
                # `bloque`, `api-non-chargee`, verdict absent : on ne sait pas.
                douteux.append((p, verdict or "absent"))

    if douteux:
        print(f"\n  {len(douteux)} verdicts douteux, NON supprimes :", file=sys.stderr)
        for p, verdict in douteux[:12]:
            print(f"    {verdict:16} {p['artiste'][:18]:20} {p['brut'][:40]}",
                  file=sys.stderr)
        print("  Repasse-les au banc avant de conclure.\n", file=sys.stderr)

    if not injouables:
        sortie.write_text("-- Rien a retirer : aucun refus avere.\n", encoding="utf-8")
        print("aucun refus avere", file=sys.stderr)
        return

    uris = [f"youtube:{p['id']}" for p in injouables]
    liste = ",\n    ".join(q(u) for u in uris)
    refus = ",\n  ".join(
        f"({q(p['id'])}, 'youtube', {q(verdicts.get(p['id'], 'inconnu'))}, unixepoch())"
        for p in injouables
    )

    # D1 refuse CREATE TEMP TABLE (SQLITE_AUTH) : la liste est donc repetee
    # en clair dans chaque DELETE plutot que passee par une table de travail.
    sortie.write_text(f"""-- Retrait des titres que le banc n'a pas vus jouer.
-- {len(injouables)} titres sur {len(injouables) + len(gardes)} verifies.
--
-- Les references partent avant les titres : track_genres et playlist_items
-- pointent sur tracks, et la contrainte refuserait l'inverse.

DELETE FROM track_genres WHERE track_uri IN (
    {liste});

DELETE FROM playlist_items WHERE track_uri IN (
    {liste});

DELETE FROM tracks WHERE uri IN (
    {liste});

-- Un artiste sans aucun titre n'a plus rien a faire dans le catalogue.
DELETE FROM artists
 WHERE uri NOT IN (SELECT artist_uri FROM tracks WHERE artist_uri IS NOT NULL);

-- Memoire du refus : c'est elle qui empeche le clip de revenir par la recherche.
INSERT OR REPLACE INTO clips_refuses (external_id, source, verdict, checked_at) VALUES
  {refus};
""", encoding="utf-8")

    print(f"{len(injouables)} refus averes a retirer, {len(gardes)} gardes",
          file=sys.stderr)
    for p in injouables[:15]:
        print(f"   {p['artiste'][:18]:20} {p['brut'][:44]}", file=sys.stderr)


if __name__ == "__main__":
    main()

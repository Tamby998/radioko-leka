#!/usr/bin/env python3
"""Ecrit le seed a partir des candidats ET du verdict du banc. Etape 3 sur 3.

N'inscrit un titre que si le banc l'a vu jouer. Un clip refuse en base est pire
qu'un clip absent : il occupe une place dans une liste et se barre a la lecture.
"""

import json
import re
import sys
import unicodedata
from pathlib import Path

BRUIT = (r"(?:officiel|official)?\s*(?:music\s+|lyrics?\s+)?"
         r"(?:vid[eé]o|audio|clip|lyrics?|visualizer|officiel)")


def sans_accent(t: str) -> str:
    return unicodedata.normalize("NFKD", t).encode("ascii", "ignore").decode()


def slug(n: str) -> str:
    return re.sub(r"-+", "-", re.sub(r"[^a-z0-9]+", "-", sans_accent(n).lower())).strip("-")


def cle_titre(t: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", sans_accent(t).lower())


def nettoyer(titre: str, artiste: str) -> str:
    t = titre.strip()
    t = re.sub(rf"[\(\[]\s*{BRUIT}[^)\]]*[\)\]]", "", t, flags=re.I)
    t = re.sub(r"[\(\[][^)\]]*(?:prod|©|copyright|street\s+video|coulisse|nouveaute|"
               r"clip\s+gasy|mv|m/v|performance)[^)\]]*[\)\]]", "", t, flags=re.I)
    t = re.sub(rf"\b{BRUIT}\b", "", t, flags=re.I)
    t = re.sub(r"[\(\[]\s*[\d\s.,–-]*[\)\]]", "", t)

    souple = re.escape(artiste.strip()).replace(r"\ ", r"[\s-]*")
    t = re.sub(rf"^\s*{souple}\s*[-–:|]\s*", "", t, flags=re.I)
    t = re.sub(rf"\s*[-–:|]\s*{souple}\s*$", "", t, flags=re.I)
    t = re.sub(rf"^\s*{souple}\s+", "", t, flags=re.I)

    t = re.sub(r"^\s*(?:feat\.?|ft\.?|avec)\s+[^\"«»]*?[\"«»]\s*", "", t, flags=re.I)
    t = re.sub(r"^\s*(?:feat\.?|ft\.?)\s+\S+\s+", "", t, flags=re.I)
    t = re.sub(r"\s*©.*$", "", t)
    t = re.sub(r"\s*\|\s*.*$", "", t)
    t = re.sub(r"\s*[/\\]{1,2}\s*$", "", t)
    t = re.sub(r"\s+(?:19|20)\d{2}\s*$", "", t)
    return re.sub(r"\s{2,}", " ", t).strip(" -–|:/«»\"'")


def q(s: str) -> str:
    return "'" + s.replace("'", "''") + "'"


def main() -> None:
    candidats = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    verdicts = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
    sortie = Path(sys.argv[3])

    artistes: dict[str, str] = {}
    pistes: list[dict] = []
    vus: set[tuple[str, str]] = set()
    stats: dict[str, dict[str, int]] = {}

    for genre, liste in candidats.items():
        s = stats.setdefault(genre, {"candidats": 0, "refuses": 0, "rejets": 0, "gardes": 0})
        for p in sorted(liste, key=lambda x: -(x["vues"] or 0)):
            s["candidats"] += 1
            if verdicts.get(p["id"]) != "ok":
                s["refuses"] += 1
                continue

            nom = p["artiste"]
            titre = nettoyer(p["brut"], nom)
            if cle_titre(titre) in ("", cle_titre(nom)) or len(titre) < 3 \
               or not re.search(r"[A-Za-zÀ-ÿ]{2}", titre):
                s["rejets"] += 1
                continue
            k = (slug(nom), cle_titre(titre))
            if k in vus:
                s["rejets"] += 1
                continue
            vus.add(k)

            uri_a = f"youtube:artist:{slug(nom)}"
            artistes[uri_a] = nom
            pistes.append({**p, "titre": titre, "uri_a": uri_a, "genre": genre})
            s["gardes"] += 1

    out = ["-- Catalogue genere : collecte YouTube puis verification reelle de",
           "-- l'integration (web/outils/verif-embed.html). Un clip refuse par",
           "-- le lecteur n'entre pas en base.", ""]

    out.append("INSERT OR REPLACE INTO artists (uri, source, external_id, name, is_local, refreshed_at) VALUES")
    out.append(",\n".join(
        f"  ({q(u)}, 'youtube', {q(u.split(':')[-1])}, {q(n)}, "
        f"{1 if any(p['uri_a'] == u and p['genre'] == 'gasy' for p in pistes) else 0}, unixepoch())"
        for u, n in sorted(artistes.items())) + ";\n")

    out.append("INSERT OR REPLACE INTO tracks")
    out.append("  (uri, source, external_id, title, artist_uri, duration_ms, artwork_url, capabilities, view_count, refreshed_at) VALUES")
    out.append(",\n".join(
        f"  ({q('youtube:' + p['id'])}, 'youtube', {q(p['id'])}, {q(p['titre'])}, "
        f"{q(p['uri_a'])}, {p['ms']}, "
        f"{q('https://i.ytimg.com/vi/' + p['id'] + '/maxresdefault.jpg')}, 'stream', "
        f"{p['vues'] if p['vues'] else 'NULL'}, unixepoch())" for p in pistes) + ";\n")

    out.append("INSERT OR REPLACE INTO track_genres (track_uri, genre_slug) VALUES")
    out.append(",\n".join(
        f"  ({q('youtube:' + p['id'])}, {q(p['genre'])})" for p in pistes) + ";")

    sortie.write_text("\n".join(out) + "\n", encoding="utf-8")

    print(f"{len(pistes)} titres retenus, {len(artistes)} artistes\n", file=sys.stderr)
    print(f"  {'genre':10} {'cand.':>6} {'refuses':>8} {'rejets':>7} {'gardes':>7}  taux", file=sys.stderr)
    for g, s in stats.items():
        taux = f"{100 * s['gardes'] // max(s['candidats'], 1)}%"
        print(f"  {g:10} {s['candidats']:6} {s['refuses']:8} {s['rejets']:7} "
              f"{s['gardes']:7}  {taux:>5}", file=sys.stderr)


if __name__ == "__main__":
    main()

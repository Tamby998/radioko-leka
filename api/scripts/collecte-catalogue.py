#!/usr/bin/env python3
"""Collecte des candidats par genre. Etape 1 sur 3.

Deux usages :

    collecte-catalogue.py .dev.vars pop kpop         # des genres entiers
    collecte-catalogue.py .dev.vars pop:"Bruno Mars" # un artiste precis

Le second sert a remplacer un clip devenu injouable sans retoucher au reste du
catalogue. `--ordre viewCount` demande alors les titres les plus vus de
l artiste plutot que les plus pertinents : les ayants droit verrouillent surtout
les nouveautes, donc un classique a davantage de chances de passer le banc.

Couteuse en quota (100 unites par artiste), donc separee du nettoyage et de la
verification : on peut retoucher les deux etapes suivantes sans rien redemander.

La sortie n'est qu'une liste de CANDIDATS. `status.embeddable` ne prouve rien :
il vaut `true` pour des clips que le lecteur refuse ensuite. C'est
`outils/verif-embed.html` qui tranche, a l'etape 2.
"""

import json
import re
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

API = "https://www.googleapis.com/youtube/v3"

GENRES = {
    "gasy": ["Rim-Ka", "Shyn", "Denise", "Mr Sayda", "Wawa Salegy", "Vaiavy Chila",
             "Niu Raza", "Ceasar", "Lowis", "Arione Joy", "Henika",
             "Rija Rasolondraibe", "Erick Manana", "Mahaleo"],
    "pop": ["Taylor Swift", "Dua Lipa", "Billie Eilish", "Sabrina Carpenter",
            "The Weeknd", "Olivia Rodrigo"],
    "afrobeats": ["Burna Boy", "Wizkid", "Davido", "Ayra Starr", "Rema", "Asake"],
    "rap-fr": ["Ninho", "Gazo", "SDM", "Tiakola", "Damso", "Jul"],
    "hiphop": ["Kendrick Lamar", "Drake", "Travis Scott", "J. Cole", "Gunna", "21 Savage"],
    "kpop": ["BLACKPINK", "BTS", "NewJeans", "Stray Kids", "LISA", "ENHYPEN"],
    "latino": ["Bad Bunny", "KAROL G", "Shakira", "Peso Pluma", "Feid", "Rauw Alejandro"],
    "zouk": ["Kassav", "Fanny J", "Medhy Custos", "Kaysha", "Warren", "Jacob Desvarieux"],
    "gospel": ["Kirk Franklin", "Sinach", "Maverick City Music", "Tasha Cobbs Leonard",
               "Elevation Worship", "Hillsong Worship"],
}

MIN_MS, MAX_MS = 60_000, 10 * 60_000
PAR_ARTISTE = 10          # large : la verification en eliminera une partie
RESULTATS_RECHERCHE = 18


def cle(chemin: str) -> str:
    m = re.search(r'^YOUTUBE_API_KEY\s*=\s*["\']?([^"\'\s]+)',
                  Path(chemin).read_text(encoding="utf-8"), re.M)
    if not m:
        sys.exit("cle introuvable dans .dev.vars")
    return m.group(1)


def get(chemin: str, params: dict) -> dict:
    url = f"{API}/{chemin}?" + urllib.parse.urlencode(params)
    with urllib.request.urlopen(url, timeout=30) as r:
        return json.load(r)


def iso_ms(iso: str) -> int:
    m = re.match(r"^P(?:(\d+)D)?T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$", iso or "")
    if not m:
        return 0
    d, h, mi, s = (int(x or 0) for x in m.groups())
    return ((d * 24 + h) * 3600 + mi * 60 + s) * 1000


def normal(t: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", t.lower())


def main() -> None:
    k = cle(sys.argv[1])
    arguments = sys.argv[2:]

    ordre = "relevance"
    if "--ordre" in arguments:
        i = arguments.index("--ordre")
        ordre = arguments[i + 1]
        del arguments[i:i + 2]

    # `genre:Artiste` compose une carte a la volee, sans toucher a GENRES.
    cibles: dict[str, list[str]] = {}
    for argument in arguments:
        if ":" in argument:
            genre, nom = argument.split(":", 1)
            cibles.setdefault(genre, []).append(nom)
    carte = cibles or GENRES
    voulus = list(cibles) if cibles else (arguments or list(GENRES))
    sortie: dict[str, list[dict]] = {}
    vus: set[str] = set()
    cout = 0

    for genre in voulus:
        artistes = carte.get(genre)
        if not artistes:
            print(f"  ! genre inconnu : {genre}", file=sys.stderr)
            continue
        sortie[genre] = []

        for nom in artistes:
            try:
                rec = get("search", {"part": "snippet", "type": "video",
                                     "videoCategoryId": "10",
                                     "maxResults": RESULTATS_RECHERCHE,
                                     "order": ordre,
                                     "q": nom, "key": k})
                cout += 100
            except Exception as e:                       # noqa: BLE001
                print(f"  ! {genre}/{nom} : {e}", file=sys.stderr)
                continue

            ids = [i["id"]["videoId"] for i in rec.get("items", [])
                   if i.get("id", {}).get("videoId")]
            if not ids:
                continue

            det = get("videos", {"part": "snippet,contentDetails,statistics,status",
                                 "id": ",".join(ids), "key": k})
            cout += 1

            gardes = 0
            for v in det.get("items", []):
                if gardes >= PAR_ARTISTE or v["id"] in vus:
                    continue
                if v.get("status", {}).get("embeddable") is False:
                    continue
                ms = iso_ms(v["contentDetails"]["duration"])
                if not (MIN_MS <= ms <= MAX_MS):
                    continue
                brut = v["snippet"]["title"]
                if normal(nom) not in normal(f"{brut} {v['snippet']['channelTitle']}"):
                    continue

                sortie[genre].append({
                    "id": v["id"], "brut": brut, "artiste": nom,
                    "chaine": v["snippet"]["channelTitle"], "ms": ms,
                    "vues": int(v.get("statistics", {}).get("viewCount") or 0) or None,
                })
                vus.add(v["id"])
                gardes += 1

            time.sleep(0.15)

        print(f"  {genre:10} {len(sortie[genre]):3} candidats", file=sys.stderr)

    print(f"  quota consomme : ~{cout} unites", file=sys.stderr)
    print(json.dumps(sortie, ensure_ascii=False))


if __name__ == "__main__":
    main()

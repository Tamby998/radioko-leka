#!/usr/bin/env python3
"""Collecte des titres gasy integrables, et ecrit le SQL correspondant.

Ne garde qu'un clip dont `status.embeddable` est vrai ET dont la duree ressemble
a une chanson : un live de 90 minutes ou un short de 20 secondes n'ont rien a
faire dans un catalogue d'ecoute.
"""

import json
import re
import sys
import time
import unicodedata
import urllib.parse
import urllib.request
from pathlib import Path

API = "https://www.googleapis.com/youtube/v3"

# Artistes releves sur la page publique de Lyrify : la scene qui compte ici.
ARTISTES = [
    "Rim-Ka", "Shyn", "Denise", "Mr Sayda", "Wawa Salegy", "Vaiavy Chila",
    "Niu Raza", "Ceasar", "Lowis", "Arione Joy", "Henika",
    "Rija Rasolondraibe", "Erick Manana", "Mahaleo",
]

MIN_MS, MAX_MS = 60_000, 10 * 60_000
PAR_ARTISTE = 6


def cle() -> str:
    txt = Path(sys.argv[1]).read_text(encoding="utf-8")
    m = re.search(r'^YOUTUBE_API_KEY\s*=\s*["\']?([^"\'\s]+)', txt, re.M)
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


def slug(nom: str) -> str:
    base = unicodedata.normalize("NFKD", nom).encode("ascii", "ignore").decode()
    return re.sub(r"-+", "-", re.sub(r"[^a-z0-9]+", "-", base.lower())).strip("-")


def propre(titre: str) -> str:
    """Meme nettoyage que cleanTitle cote Worker, en plus court."""
    t = re.sub(r"[(\[]\s*(?:official\s+)?(?:music\s+|lyrics?\s+)?(?:video|audio)[^)\]]*[)\]]", "", titre, flags=re.I)
    t = re.sub(r"[(\[]\s*(?:clip\s+officiel|audio|lyrics?)[^)\]]*[)\]]", "", t, flags=re.I)
    t = re.sub(r"\b(?:official\s+(?:music\s+)?video|clip\s+officiel)\b", "", t, flags=re.I)
    t = re.sub(r"[(\[]\s*[\d\s.,–-]*[)\]]", "", t)
    t = re.sub(r"\s+(?:19|20)\d{2}\s*$", "", t)
    return re.sub(r"\s{2,}", " ", t).strip(" -|–")


def decoupe(titre: str) -> tuple[str, str]:
    if " - " in titre:
        a, _, b = titre.partition(" - ")
        return a.strip(), propre(b)
    return "", propre(titre)


def main() -> None:
    k = cle()
    artistes: dict[str, str] = {}
    pistes: list[dict] = []
    vus: set[str] = set()

    for nom in ARTISTES:
        try:
            rec = get("search", {
                "part": "snippet", "type": "video", "videoCategoryId": "10",
                "maxResults": 15, "q": nom, "key": k,
            })
        except Exception as e:                      # noqa: BLE001
            print(f"  ! {nom} : {e}", file=sys.stderr)
            continue

        ids = [i["id"]["videoId"] for i in rec.get("items", []) if i.get("id", {}).get("videoId")]
        if not ids:
            continue

        det = get("videos", {
            "part": "snippet,contentDetails,statistics,status",
            "id": ",".join(ids), "key": k,
        })

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
            credite, titre = decoupe(brut)
            # Le clip doit vraiment concerner l'artiste cherche.
            foin = f"{brut} {v['snippet']['channelTitle']}".lower()
            if slug(nom).replace("-", "") not in slug(foin).replace("-", ""):
                continue

            artiste = credite or v["snippet"]["channelTitle"]
            uri_a = f"youtube:artist:{slug(nom)}"
            artistes[uri_a] = nom if len(nom) >= len(artiste) else artiste

            pistes.append({
                "uri": f"youtube:{v['id']}", "id": v["id"], "titre": titre or brut,
                "artiste_uri": uri_a, "ms": ms,
                "vues": int(v.get("statistics", {}).get("viewCount") or 0) or None,
            })
            vus.add(v["id"])
            gardes += 1

        print(f"  {nom:22} {gardes} titres", file=sys.stderr)
        time.sleep(0.2)

    print(json.dumps({"artistes": artistes, "pistes": pistes}, ensure_ascii=False))


if __name__ == "__main__":
    main()

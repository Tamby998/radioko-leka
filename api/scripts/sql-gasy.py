#!/usr/bin/env python3
"""Transforme la collecte en SQL, en reparant ce que la collecte a mal nomme."""
import json, re, sys, unicodedata
from pathlib import Path

ARTISTES = ["Rim-Ka","Shyn","Denise","Mr Sayda","Wawa Salegy","Vaiavy Chila",
            "Niu Raza","Ceasar","Lowis","Arione Joy","Henika",
            "Rija Rasolondraibe","Erick Manana","Mahaleo"]

def slug(n):
    b = unicodedata.normalize("NFKD", n).encode("ascii","ignore").decode()
    return re.sub(r"-+","-",re.sub(r"[^a-z0-9]+","-",b.lower())).strip("-")

# Le nom canonique est celui qu'on a cherche, jamais celui de la chaine :
# « Mozika HO ANAO » est une chaine, pas un artiste.
CANON = {f"youtube:artist:{slug(n)}": n for n in ARTISTES}

def cle_titre(t):
    """Pour reperer deux versions du meme titre malgre l'artiste colle devant."""
    b = unicodedata.normalize("NFKD", t).encode("ascii","ignore").decode().lower()
    return re.sub(r"[^a-z0-9]+", "", b)

# « Vidéo » accentue, « Clip », « Lyrics » : les memes mentions qu'en francais.
# « Officiel » seul est courant sur les clips francophones, sans « clip ».
BRUIT = r"(?:officiel|official)?\s*(?:music\s+|lyrics?\s+)?(?:vid[eé]o|audio|clip|lyrics?|visualizer|officiel)"

def nettoyer(titre, artiste):
    """Retire le bruit de clip, puis le nom de l'artiste colle au titre."""
    t = titre.strip()
    # Groupes entiers de bruit, y compris mentions de prod, annee, copyright.
    t = re.sub(rf"[\(\[]\s*{BRUIT}[^)\]]*[\)\]]", "", t, flags=re.I)
    t = re.sub(r"[\(\[][^)\]]*(?:prod|©|copyright|street\s+video|coulisse|nouveaute|clip\s+gasy)[^)\]]*[\)\]]", "", t, flags=re.I)
    t = re.sub(rf"\b{BRUIT}\b", "", t, flags=re.I)
    t = re.sub(r"[\(\[]\s*[\d\s.,–-]*[\)\]]", "", t)

    # L'artiste colle devant ou derriere, quel que soit le separateur.
    a = re.escape(artiste.strip())
    souple = a.replace(r"\ ", r"[\s-]*")
    t = re.sub(rf"^\s*{souple}\s*[-–:|]\s*", "", t, flags=re.I)
    t = re.sub(rf"\s*[-–:|]\s*{souple}\s*$", "", t, flags=re.I)
    # « Rim-Ka VADIKO » : prefixe sans separateur.
    t = re.sub(rf"^\s*{souple}\s+", "", t, flags=re.I)

    # Mention de copyright hors parentheses : « Artiste © 2M16 ».
    t = re.sub(r"\s*©.*$", "", t)
    t = re.sub(r"\s*\|\s*.*$", "", t)              # queue apres une barre
    t = re.sub(r"\s+(?:19|20)\d{2}\s*$", "", t)
    # Retirer l'artiste peut laisser le titre commencer par son featuring :
    # « Mr SAYDA feat SUL-K "TARALILA" » devenait « feat SUL-K "TARALILA" ».
    t = re.sub(r"^\s*(?:feat\.?|ft\.?|avec)\s+[^\"«»]*?[\"«»]\s*", "", t, flags=re.I)
    t = re.sub(r"^\s*(?:feat\.?|ft\.?)\s+\S+\s+", "", t, flags=re.I)
    t = re.sub(r"\s*[/\\]{1,2}\s*$", "", t)        # « Titre // » en fin
    t = re.sub(r"\s{2,}", " ", t)
    return t.strip(" -–|:/«»\"'")

def q(s):
    return "'" + s.replace("'", "''") + "'"

def main():
    d = json.load(open(sys.argv[1], encoding="utf-8"))
    pistes, vues_cle, rejets = [], {}, []

    for p in sorted(d["pistes"], key=lambda x: -(x["vues"] or 0)):
        nom = CANON.get(p["artiste_uri"])
        if not nom:
            rejets.append((p["titre"], "artiste inconnu")); continue

        titre = nettoyer(p["titre"], nom)
        # Un titre reduit au nom de l'artiste n'est pas un titre.
        if cle_titre(titre) in ("", cle_titre(nom)):
            rejets.append((p["titre"], "titre = artiste")); continue
        if len(titre) < 3:
            rejets.append((p["titre"], "titre trop court")); continue
        # Un titre sans deux lettres consecutives n'est pas un titre.
        if not re.search(r"[A-Za-zÀ-ÿ]{2}", titre):
            rejets.append((p["titre"], "pas de mot")); continue

        # Deux uploads du meme titre : on garde le plus vu.
        k = (p["artiste_uri"], cle_titre(titre))
        if k in vues_cle:
            rejets.append((titre, "doublon")); continue
        vues_cle[k] = True
        pistes.append({**p, "titre": titre, "nom": nom})

    noms = {p["artiste_uri"]: p["nom"] for p in pistes}
    out = ["-- Catalogue gasy — clips verifies integrables via status.embeddable.",
           "-- Genere depuis l'API YouTube Data v3 ; voir scripts/.",
           ""]

    out.append("INSERT OR REPLACE INTO artists (uri, source, external_id, name, is_local, refreshed_at) VALUES")
    lignes = [f"  ({q(u)}, 'youtube', {q(u.split(':')[-1])}, {q(n)}, 1, unixepoch())"
              for u, n in sorted(noms.items())]
    out.append(",\n".join(lignes) + ";\n")

    out.append("INSERT OR REPLACE INTO tracks")
    out.append("  (uri, source, external_id, title, artist_uri, duration_ms, artwork_url, capabilities, view_count, refreshed_at) VALUES")
    lignes = []
    for p in pistes:
        art = f"https://i.ytimg.com/vi/{p['id']}/maxresdefault.jpg"
        vues = p["vues"] if p["vues"] else "NULL"
        lignes.append(f"  ({q(p['uri'])}, 'youtube', {q(p['id'])}, {q(p['titre'])}, "
                      f"{q(p['artiste_uri'])}, {p['ms']}, {q(art)}, 'stream', {vues}, unixepoch())")
    out.append(",\n".join(lignes) + ";\n")

    out.append("INSERT OR REPLACE INTO track_genres (track_uri, genre_slug) VALUES")
    out.append(",\n".join(f"  ({q(p['uri'])}, 'gasy')" for p in pistes) + ";")

    Path(sys.argv[2]).write_text("\n".join(out) + "\n", encoding="utf-8")
    print(f"{len(pistes)} pistes, {len(noms)} artistes, {len(rejets)} rejets", file=sys.stderr)
    for t, r in rejets[:10]:
        print(f"   rejet: {t[:44]:46} {r}", file=sys.stderr)

main()

#!/bin/bash
#
# Veille du catalogue en ligne.
#
# Un catalogue de clips YouTube se degrade tout seul : quatre titres sont morts
# en quatre jours pendant le developpement. Avant le deploiement, c'etait nous
# qui tombions dessus ; maintenant c'est n'importe qui ouvre l'app, et on
# l'apprend apres lui.
#
# Cette routine **rapporte, elle ne supprime pas**. La commande d'application
# est affichee a la fin, a lancer apres avoir lu le rapport. Ce n'est pas de la
# prudence de principe : le banc a deja condamne 50 titres gasy a tort, et une
# purge automatique les aurait emportes.
#
#   ./scripts/veille-catalogue.sh
#
# Sortie : un rapport lisible, et deux fichiers dans web/outils/.

set -u
cd "$(dirname "$0")/.." || exit 1

BASE="radiokoleka"
CANDIDATS="../web/outils/veille-candidats.json"
VERDICTS="../web/outils/veille-verdicts.json"
PURGE="purge-veille.sql"
NPX="${NPX:-npx}"

echo "Veille du catalogue — $(date '+%Y-%m-%d %H:%M')"
echo

# 1. Ce que la base EN LIGNE contient. C'est elle qui sert les utilisateurs,
#    donc c'est elle qu'on verifie — pas la copie locale.
echo "1. Export du catalogue en ligne"
$NPX wrangler d1 execute "$BASE" --remote --json --command \
  "SELECT t.external_id AS id, coalesce(a.name,'?') AS artiste, t.title AS brut,
          (SELECT g.genre_slug FROM track_genres g
            JOIN genres gg ON gg.slug = g.genre_slug
           WHERE g.track_uri = t.uri AND gg.parent IS NULL LIMIT 1) AS genre
     FROM tracks t LEFT JOIN artists a ON a.uri = t.artist_uri
    WHERE t.source = 'youtube'" 2>/dev/null > /tmp/veille-brut.json

python3 - "$CANDIDATS" <<'PY'
import collections, json, sys
lignes = json.load(open('/tmp/veille-brut.json'))[0]['results']
par_genre = collections.defaultdict(list)
for r in lignes:
    par_genre[r.get('genre') or 'sans-genre'].append(
        {'id': r['id'], 'artiste': r['artiste'], 'brut': r['brut']})
json.dump(par_genre, open(sys.argv[1], 'w'), ensure_ascii=False, indent=1)
print(f"   {len(lignes)} titres a verifier, {len(par_genre)} genres")
PY

# 2. Le banc natif. Il ouvre une fenetre : il lui faut une session graphique
#    ouverte, il ne tournera pas depuis un demon.
echo
echo "2. Passage au banc (compte environ 5 s par titre)"
( cd ../desktop && make banc C="$(cd ../api && pwd)/$CANDIDATS" \
                            V="$(cd ../api && pwd)/$VERDICTS" ) || {
  echo "   le banc a echoue — rien n'est modifie"; exit 1; }

# 3. Le SQL, sans l'appliquer. Seuls les `erreur:*` y entrent ; les `bloque`
#    sont listes a part par le script et demandent un second regard.
echo
echo "3. Redaction de la purge (non appliquee)"
python3 scripts/purge-injouables.py "$CANDIDATS" "$VERDICTS" "$PURGE"

echo
echo "Rien n'a ete modifie. Pour appliquer, apres avoir lu ce qui precede :"
echo
echo "  cd api"
echo "  $NPX wrangler d1 execute $BASE --remote --file=./$PURGE"
echo "  $NPX wrangler d1 execute $BASE --local  --file=./$PURGE"
echo "  $NPX wrangler d1 execute $BASE --remote --file=./cache-clear.sql"
echo

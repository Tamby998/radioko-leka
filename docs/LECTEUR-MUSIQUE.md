# Hira

Toute la musique, et les paroles qui vont avec. Android, macOS, Windows, Linux —
une seule codebase Flutter, un Worker Cloudflare, zero euro d'infrastructure.

## Le modele hybride

Deux catalogues, deux jeux de capacites, et la frontiere portee par le type
`Track.capabilities` plutot que par la discipline du developpeur.

| Catalogue | Contenu | Lecture | Hors-connexion | Ecran verrouille |
|---|---|---|---|---|
| Local | tes propres fichiers | directe | oui | oui |
| Mondial | YouTube (metadonnees Data API v3) | Lecteur IFrame officiel, visible | non | non |
| Sous licence | Audius, Jamendo, artistes partenaires | Audio natif | oui | oui |

Rien n'est extrait des flux YouTube : la lecture passe par le lecteur officiel,
donc la vue revient a la chaine de l'artiste. Le telechargement et la lecture en
arriere-plan sont reserves au catalogue dont les artistes ont publie l'audio
pour cet usage.

Ce choix est verrouille a deux endroits : `assertCapability` cote Worker
(`api/src/sources/types.ts`) et `Track.requireCapability` cote app
(`mobile_flutter/lib/models/track.dart`). Un titre du catalogue mondial ne peut pas finir
en fichier local par oubli — et l'interface ne montre meme pas le bouton.

## Structure

```
api/   Worker Cloudflare + D1 — catalogue cure, classements, cache paroles
cli/   Rust — client terminal : recherche, lecture, karaoke
mobile_flutter/  Flutter — Android d abord, iOS ensuite
docs/  ARCHITECTURE.md
```

Le modele de capacites est implemente trois fois, une par couche :
`api/src/sources/types.ts`, `cli/src/capability.rs`, `mobile_flutter/lib/models/track.dart`.

## En ligne

```
https://radiokoleka-api.radiokoleka.workers.dev
```

Le Worker est deploye sur Cloudflare, avec sa base D1 `radiokoleka` en Europe
de l'Ouest. L'app macOS tape dessus par defaut : elle n'a plus besoin qu'un
`npm run dev` tourne a cote.

| Ce qui est en ligne | |
|---|---|
| Worker | `radiokoleka-api` |
| Base D1 | `radiokoleka` — 185 titres, 36 artistes, 9 genres, 6 refus |
| Secret | `YOUTUBE_API_KEY`, pose par `wrangler secret put` |

**La base distante doit rejouer toute la sequence locale**, purges comprises.
Sans elles, elle contiendrait les six clips morts retires en local, et
`clips_refuses` partirait vide — ils reviendraient donc par la recherche.

```bash
npx wrangler d1 execute radiokoleka --remote --file=./schema.sql
# puis seed.sql, seed-gasy.sql, seed-catalogue.sql, seed-styles.sql,
# taglines.sql, purge-injouables.sql, purge-internationaux.sql
```

Un piege rencontre : renommer `database_name` dans `wrangler.toml` fait pointer
`--local` sur une base **neuve et vide**. Le Worker local tourne encore sur
l'ancienne jusqu'a son redemarrage, puis tout disparait sans message. Resemer
le local fait partie du renommage.

## La veille du catalogue

Un catalogue de clips YouTube se degrade tout seul : **quatre titres sont morts
en quatre jours** pendant le developpement. Avant le deploiement, c'est nous qui
tombions dessus ; maintenant c'est n'importe qui ouvre l'app, et on l'apprend
apres lui.

```bash
cd api && npm run veille
```

Elle exporte le catalogue **en ligne** — c'est lui qui sert les utilisateurs —
le passe au banc natif, et redige la purge sans l'appliquer. La commande
d'application est affichee a la fin.

### Elle ne supprime rien, et c'est la lecon

Le banc a deja condamne **50 titres gasy a tort**. La regle qui en sort est
desormais dans le code de la purge :

| Verdict | Ce qu'on en fait |
|---|---|
| `erreur:150`, `101`, `100` | refus avere, arrive par evenement → supprime |
| `bloque` | le delai a expire, ce qui arrive aussi quand l'onglet dort → **jamais supprime**, liste a part |
| verdict absent | idem |

`purge-injouables.py` liste les douteux a l'ecran et les laisse en base. Il
faut les repasser au banc avant de conclure.

### La planifier

`api/scripts/veille.plist` est un agent launchd mensuel, **a installer
soi-meme** :

```bash
cp api/scripts/veille.plist ~/Library/LaunchAgents/xyz.radiokoleka.veille.plist
launchctl load ~/Library/LaunchAgents/xyz.radiokoleka.veille.plist
```

C'est un *agent* et non un demon : le banc ouvre une fenetre, il lui faut une
session graphique ouverte. Et il charge le profil avec `-l`, sans quoi `npx`
est introuvable — nvm est charge avec `--no-use` et n'active aucune version.

## Demarrer l'API

```bash
cd api
npm install
npx wrangler d1 create hira          # colle l'id dans wrangler.toml
npm run db:init                      # schema en local
npm run db:seed                      # catalogue de depart, 9 titres
npm run dev                          # http://127.0.0.1:8787
```

### Remplir le catalogue

Trois etapes separees, parce qu'elles n'ont ni le meme cout ni la meme duree :

```bash
# 1. Collecte — ~100 unites de quota par artiste. A ne rejouer qu'au besoin.
python3 api/scripts/collecte-catalogue.py api/.dev.vars pop afrobeats zouk \
  > web/outils/candidats.json

# 2. Verification — ouvrir web/outils/verif-embed.html et, dans la console :
#    const c = await (await fetch('./candidats.json')).json();
#    await verifier(Object.values(c).flat().map(p => p.id));
#    Les verdicts sont gardes en localStorage : la page peut tomber sans perte.

# 3. Seed — gratuit, rejouable autant qu'on veut.
python3 api/scripts/sql-catalogue.py candidats.json verdicts.json api/seed-catalogue.sql
cd api && npm run db:seed:catalogue && npm run db:cache:clear

# 4. Purge — retire du catalogue les titres qui ne jouent plus.
python3 api/scripts/purge-injouables.py candidats.json verdicts.json \
  api/purge-injouables.sql
cd api && npm run db:purge && npm run db:cache:clear
```

D1 refuse `CREATE TEMP TABLE` (`SQLITE_AUTH`) : la purge repete donc la liste
d'uris dans chaque `DELETE`, et retire les references avant les titres.

```bash
# 5. Styles — rattache chaque artiste a son sous-genre. Gratuit, a rejouer
#    apres chaque seed, sinon les nouveaux titres n'ont pas de style.
cd api && npm run db:seed:styles && npm run db:cache:clear
```

**Pourquoi une etape de verification.** `status.embeddable` de la Data API ne
dit pas la verite : il vaut `true` pour des clips que le lecteur refuse ensuite
par l'erreur 150. Seul un chargement reel tranche.

**Le verdict ne repose que sur des evenements**, et c'est essentiel. Deux pieges
rencontres, dans cet ordre :

- se fier a l'etat du lecteur donne des faux positifs, car un clip refuse passe
  par BUFFERING *avant* que `onError` n'arrive. Le banc laisse donc un sursis a
  l'erreur avant de conclure qu'un clip joue ;
- se fier a `getCurrentTime()` donne des faux negatifs massifs : un onglet en
  arriere-plan voit ses minuteurs brides, l'horloge n'avance plus, et tout clip
  valide expire. Une passe menee ainsi a declare 50 titres gasy injouables alors
  que 74 sur 76 jouent — dont deux dont j'avais la capture d'ecran.

Un verdict `erreur:150` reste fiable dans tous les cas, puisqu'il arrive par
evenement. C'est `ok` contre `bloque` qui devient faux quand l'onglet dort.

Un clip refuse en base est pire qu'un clip absent : il occupe une place dans une
liste et se barre a la lecture.

### Le banc est natif, maintenant

Le banc en navigateur est remplace par `desktop/banc`, pour la raison meme qui
avait fausse une passe : un onglet masque fait brider les minuteries. Le banc
natif reutilise la page du lecteur de l app et son serveur interne — il mesure
donc ce que l app fera, et sa sortie est du texte.

```bash
cd desktop && make banc C=../web/outils/candidats.json V=../web/outils/verdicts.json
```

**Catalogue au 2 novembre 2026, apres passage au banc natif : 185 titres, tous
verifies jouables.**

| Genre | Titres | | Genre | Titres |
|---|---|---|---|---|
| Musique malgache | 75 | | Rap francais | 12 |
| Zouk & Kompa | 42 | | Afrobeats | 5 |
| K-pop | 29 | | Hip-Hop | 2 |
| Gospel | 19 | | Latino | 2 |

La passe sur les 114 titres internationaux a rendu **110 jouables et zero
`bloque`**. C est ce zero qui donne confiance : aucun delai d attente n a
expire, donc rien n a dormi. Les quatre refus ont ete retires
(`purge-internationaux.sql`), et le rayon **Pop a disparu** — il n avait qu un
titre.

### Le refus se decide par ayant droit, pas par clip

Les quatre refuses etaient Bruno Mars, Ayra Starr, ROSE et KAROL G. On a
cherche a les remplacer par d autres titres des memes artistes, en demandant
leurs **plus gros succes** — l idee etant que les ayants droit verrouillent
surtout les nouveautes.

**0 jouable sur 40.** *Grenade* (2010), *Just The Way You Are* (2010), *Uptown
Funk* (2014), *Tusa* (2019) : tous refuses par l erreur 150. **L age n y est
pour rien.**

Et « major = bloque » est faux aussi. Les chaines qui hebergent ce qui *joue*
chez nous :

| Chaine | Verdict |
|---|---|
| HYBE LABELS, BANGTANTV (BTS) | **ok** |
| Hillsong Worship | **ok** |
| DMW HQ (Davido), DEL Records, FANNY J | **ok** |
| les ayants droit de Bruno Mars, ROSE, Ayra Starr, KAROL G | refus sur tout |

HYBE est un des plus gros labels du monde et autorise l integration. La regle
est donc plus simple et plus bete : **c est une decision par ayant droit, prise
une fois pour tout son repertoire.** Quand elle est non, il n y a pas de
remplacant a trouver — ni plus ancien, ni plus connu, ni sur une autre chaine
officielle.

Consequence editoriale, qu aucun code ne corrigera : **un rayon Pop anglo-saxon
n est pas atteignable par cette voie.** La collecte initiale avait donne 0 sur
60 ; on sait maintenant pourquoi.

Consequence operationnelle : **un catalogue de clips YouTube se degrade**, et il
faut le repasser au banc regulierement. C est une commande.

Les taux ci-dessous sont autre chose : c est le rendement de la *collecte*,
combien de candidats trouves sur YouTube survivent a la verification avant
d entrer en base. Ils expliquent pourquoi le catalogue est profond en gasy et
mince en pop.

**Taux de clips reellement jouables, mesures sur 465 candidats :**

| Genre | Jouables | | Genre | Jouables |
|---|---|---|---|---|
| Musique malgache | **97 %** (74/76) | | Rap francais | 18 % |
| Zouk & Kompa | 77 % | | Afrobeats | 8 % |
| K-pop | 48 % | | Hip-Hop, Latino | 3 % |
| Gospel | 44 % | | **Pop** | **0 %** (0/60) |

On avait d'abord lu ce tableau comme « plus un genre est tenu par des majors,
moins il est integrable ». C'est faux, et le banc l'a montre : HYBE autorise
l'integration, et c'est de la K-pop de major. Ce que le tableau mesure
reellement, c'est la proportion d'ayants droit qui disent oui dans chaque
genre — elevee pour le gasy et le zouk, nulle pour la pop anglo-saxonne.

Un catalogue mondial complet n'est donc pas atteignable par cette voie, et
aucun code ne corrigera ca.

### Les sous-genres, et pourquoi ils existent

Le genre seul est trop grossier pour enchainer. Les 75 titres malgaches
tenaient dans un unique `gasy` : apres les quatre autres Mahaleo, « Hay hay »
enchainait sur `Rim-Ka — GLITA`, parce que le rap gasy est ce qu'il y a de plus
vu dans le genre. Du gasy, oui ; du Mahaleo, non.

Un sous-genre est un genre avec un `parent`. `/v1/similar` compte donc trois
paliers : meme artiste, **meme sous-genre**, meme genre.

| Parent | Sous-genres |
|---|---|
| `gasy` | `gasy-folk` 13 · `gasy-pop` 14 · `gasy-urbain` 36 · `gasy-cotier` 12 |
| `zouk` | `zouk-racines` 18 · `zouk-rnb` 17 · `zouk-afro` 7 |

Les autres genres n'en ont pas : ils retombent sur le palier du genre, qui
suffit tant qu'un genre reste homogene. Trois regles tiennent l'ensemble :

- **les rayons n'affichent que les genres racine** (`parent IS NULL`), sinon la
  page d'accueil se decoupe en vingt etageres pour rien ;
- **le rattachement se fait par nom d'artiste**, pas par uri de titre : un
  artiste du catalogue tient dans un seul style, et un titre seme plus tard
  herite du bon style en rejouant le seed ;
- **un titre qui porte un style porte aussi son parent**. Sans cette regle,
  « Gâter Pourri » de Rim-Ka — du rap en francais par un artiste gasy — serait
  un style sans genre racine : present dans les enchainements gasy, absent du
  rayon.

`npm run db:cache:clear` n'est pas optionnel : `cachedJson` garde les genres 24 h,
et sans purge on croit que le seed n'a pas ete pris.

`YOUTUBE_API_KEY` est **optionnelle** : sans elle, le catalogue cure et les
sources sous licence suffisent a faire tourner l'application. Posee, elle
ajoute la recherche mondiale et corrige les durees marquees placeholder.

### Obtenir et poser la cle

Gratuite, quota de 10 000 unites par jour.

1. [console.cloud.google.com](https://console.cloud.google.com) — creer un projet.
2. **APIs et services > Bibliotheque** — activer *YouTube Data API v3*.
3. **Identifiants > Creer des identifiants > Cle API**.
4. **Restreindre la cle** : dans *Restrictions relatives aux API*, choisir
   *Restreindre la cle* et ne cocher que *YouTube Data API v3*. Sans ca, une
   cle qui fuit donne acces a tous les services Google du projet.
5. Poser la cle localement :

```bash
cp api/.dev.vars.example api/.dev.vars   # puis renseigner la valeur
```

`.dev.vars` est dans le `.gitignore`. Attention : `wrangler secret put` sert au
Worker **deploye**, pas au developpement local — en local c'est `.dev.vars` que
wrangler lit au demarrage.

Redemarrer le Worker pour qu'il la prenne en compte.

La cle ne quitte jamais le serveur : le CLI et l'app ne parlent qu'au Worker,
et ne la voient donc jamais.

Routes :

| Route | Role |
|---|---|
| `GET /v1/health` | Etat du service |
| `GET /v1/search?q=` | Recherche a trois etages (voir plus bas) |
| `GET /v1/playlists/:slug` | Titres d'une playlist editoriale |
| `GET /v1/similar/:uri` | Suggestions pour enchainer la lecture |
| `GET /v1/lyrics?artist=&title=&duration=` | Paroles synchronisees (LRCLIB) |
| `GET /v1/charts/licensed-trending` | Classement du catalogue sous licence |
| `GET /v1/download/:uri` | Feu vert telechargement — 403 sur YouTube |

### La recherche, du moins cher au plus cher

1. **le catalogue cure en D1** — gratuit, editorial, et c'est la que vivent les
   titres dont on sait que les paroles existent ;
2. **les sources sous licence** — gratuites, et elles portent le hors-connexion ;
3. **`search.list` de YouTube** — 100 unites de quota, uniquement si une cle est
   posee *et* que les deux premiers etages n'ont pas rempli la demande.

Resultat : la recherche fonctionne sans aucune cle, et le quota de 10 000 unites
par jour n'est entame que pour les requetes qu'aucun titre en base ne couvre.
`videos.list` ne coute qu'1 unite pour 50 IDs : c'est lui qui rafraichit le
catalogue par lots.

Le catalogue cure passe en premier dans les resultats, ce qui compte en pratique :
la recherche d'Audius repond large, et sans cet ordre une requete comme
« niu raza » noierait le bon titre sous des correspondances approximatives.

### Deux filtres sur les resultats

**Le dedoublonnage ne compare pas les artistes.** Un meme clip remonte deux
fois : le catalogue cure connait « RIVOTRA Mahaleo Live @ Olympia » sous
l'artiste `Mahaleo`, `search.list` le rend sous la chaine `Mahaleo Officiel`.
Artiste + titre ne les rapproche pas ; la duree, si — elle est la meme a la
seconde. `src/lib/doublons.ts` fait donc deux passes : titre + duree, puis, a
duree strictement egale, un titre contenu dans l'autre (c'est ce qui rapproche
le reupload « Mahaleo- Hay hay » de « Hay hay »). Une duree inconnue desactive
les deux et on retombe sur titre + artiste. « mahaleo » passe ainsi de 16
resultats dont 6 doublons a 11 resultats distincts.

**Un clip refuse est mis en memoire, pas seulement supprime.** `search.list`
ignore la purge : sans memoire du refus, un clip retire du catalogue revient en
tete de recherche et se barre a la lecture. Deux memoires, parce qu'elles ne
mesurent pas la meme chose :

| Ou | Qui la remplit | Ce qu'elle couvre |
|---|---|---|
| `clips_refuses` en D1 | le banc, via `npm run db:purge` | les clips verifies avant le seed |
| `hira.refuses.v1` en localStorage | le lecteur, a la premiere erreur 150 | tout clip rencontre en lecture reelle |

La seconde est la plus large : elle attrape les clips que `search.list` rend
sans que le catalogue les ait jamais vus. Elle survit au rechargement, sinon le
meme clip barre serait repropose demain.

### Le catalogue de depart

`api/seed.sql` pose 9 titres — 4 internationaux, 5 de la scene gasy. Les
metadonnees viennent de l'endpoint oEmbed public de YouTube, les durees de
LRCLIB quand il connait le titre, sinon un placeholder de 3 min 30 signale par
`refreshed_at IS NULL`.

Trois de ces titres ont des paroles synchronisees (46, 53 et 46 lignes) : de quoi
voir le karaoke tourner sans poser de cle. Aucun titre gasy n'est dans LRCLIB, ce
qui explique pourquoi la correction de paroles par l'utilisateur compte autant
pour ce repertoire : aucune base publique ne le couvre.

## Client terminal

### Ta bibliotheque

Hira lit d'abord **tes** fichiers. Ils passent devant les resultats en ligne,
la recherche est instantanee et ne depend d'aucun reseau.

```bash
export HIRA_MUSIC_DIR="$HOME/Music:/Volumes/Disque/Musique"
./hira library     # verifie ce que le scan trouve
```

Formats lus : mp3, m4a, flac, wav, aac, ogg, opus, aiff. Les tags sont lus
quand ils existent ; sinon le nom de fichier sert de titre, et la convention
`Artiste - Titre.mp3` est reconnue.

**Paroles.** Un fichier `.lrc` pose a cote de l'audio — `chanson.mp3` et
`chanson.lrc` — est utilise en priorite, avant toute recherche en ligne. C'est
le format standard des lecteurs karaoke, et c'est la reponse au repertoire
qu'aucune base publique n'indexe : tu cales les paroles une fois, elles
restent.

Un titre local porte les quatre capacites par construction : le fichier est
deja la, il n'y a ni tampon ni telechargement.

### Lancer

Le lanceur demarre le Worker si besoin, puis ouvre la session :

```bash
./hira
```

C'est le mode principal : tu cherches, tu choisis un numero, et la lecture
enchaine toute seule sur des titres proches jusqu'a ce que tu fasses `q`.

```
hira rechercher > shyn

  1. > Hiara dia              Shyn          3:30
  2. v my zone!               JumpmannTR    2:47

hira [1-7] jouer · / rechercher · q quitter > 1
```

Les suggestions viennent de `/v1/similar/:uri` : meme artiste d'abord, puis
**meme sous-genre**, puis meme genre depuis le catalogue cure, complete par les
sources sous licence pour que la file ne soit jamais vide. Un `q` pendant la lecture ramene a la
recherche sans enchainer ; un morceau qui va au bout enchaine.

Sous-commandes, pour un usage ponctuel ou scripte :

```bash
./hira search "wawa salegy"
./hira trending
./hira play "rim-ka" -n 2
```

`HIRA_API_URL` pointe le Worker (defaut `http://127.0.0.1:8787`). Dans la vue
karaoke : espace met en pause, `q` quitte.

Deux chemins de lecture, selon les capacites du titre :

| Catalogue | Lecture | Paroles |
|---|---|---|
| Sous licence | `mpv` lit le flux, ou `afplay` apres copie locale | position reelle du lecteur |
| Mondial | lecteur officiel ouvert dans le navigateur | horloge calee sur une touche au demarrage |

Aucun crate audio : l'API de `rodio` bouge trop, un sous-processus suffit. La
pause passe par SIGSTOP/SIGCONT, et la position par une horloge locale — donc
pas de recherche dans la piste, `afplay` n'ayant pas d'option de depart.

## Demarrer l'app mobile

Elle vit dans `mobile_flutter/`, commune avec la radio, et vise Android
d'abord. Flutter stable et le SDK Android suffisent — pas d'Android Studio.

```bash
cd mobile_flutter
flutter pub get
flutter run -d <appareil>
```

Elle tape le Worker deploye par defaut. Pour un Worker local, il faut une
adresse que le telephone peut joindre : `127.0.0.1` designe le telephone.

```bash
flutter run --dart-define=RADIOKOLEKA_API_URL=http://192.168.1.12:8787
```

Le dossier `app/` qui existait avant portait la meme logique sans aucun
dossier de plateforme : il n'avait jamais ete compile, et une erreur de nom
ambigu entre `just_audio` et `youtube_player_iframe` l'attendait a la
premiere tentative. Son code vit maintenant dans `mobile_flutter/lib/`.

## Tests

```bash
cd api && npm test        # parsing LRC, durees ISO, garde-fous de capacites
cd cli && cargo test      # fenetre karaoke, barre, dichotomie, parsing args
cd mobile_flutter && flutter test
```

Le contrat JSON entre le CLI et le Worker est verifiable sans compilateur :
les noms de champs serde et les noms de capacites sont compares au JSON servi
en local (voir l'historique de mise en place).

## Conventions

Imports relatifs avec extension `.ts` explicite, et champs declares plutot que
parameter properties : le code tourne ainsi sous Node natif (`node --test`,
sans transpileur) comme sous esbuild via wrangler.

## Ce que le projet ne fait pas

Pas d'extraction de flux YouTube, pas de contournement de lecteur, pas de copie
locale de contenu dont les ayants droit n'ont pas autorise le telechargement.
Le hors-connexion est un argument de catalogue, pas un contournement : faire
signer les artistes locaux en direct donne une bibliotheque telechargeable que
personne ne peut proposer autrement.

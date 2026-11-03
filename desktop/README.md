# RadiokoLeka — app macOS

Le projet s appelait « hira ». Le nom s ecrit en deux couleurs : **Radioko**
dans la couleur principale, **Leka** dans la secondaire — la coupure tombe sur
« radioko », « ma radio » en malgache. Un logo viendra.

Les donnees ont suivi : `~/Library/Application Support/RadiokoLeka/`. Si
l ancien dossier `hira/` existe, il est repris au premier lancement plutot que
d etre laisse derriere.

SwiftUI. Aucun HTML ne dessine quoi que ce soit : la seule page web de l app est
celle du lecteur officiel, et elle ne sert qu a le porter.

```bash
cd desktop
make                      # construit build/hira.app, signe ad-hoc
make lancer               # session de 25 s, racontee sur la sortie d erreur
make lancer S=60          # plus longue
make universel            # Intel + arm64 fusionnes par lipo
```

Aucun Xcode. Les Command Line Tools suffisent — `swiftc` compile, `codesign
--force --sign -` signe. Le bundle complet pese 540 Ko.

## Pourquoi un serveur HTTP dans l app

Parce que le lecteur IFrame refuse toute origine qui n est pas `http://`. Ce
n est pas une precaution, c est une mesure : voir [sonde/README.md](sonde/README.md).

| Origine | Clip jouable | Clip refuse |
|---|---|---|
| `file://` | erreur 153 | erreur 153 |
| `http://127.0.0.1` | **ok** | erreur 150 |
| schema personnalise | erreur 153 | erreur 153 |

`ServeurLocal` ouvre donc un `NWListener` sur un **port ephemere**, lie a
**127.0.0.1 uniquement**, et sert une seule page. Pas de routeur, pas de
fichiers statiques, rien de joignable depuis le reseau.

**153 et 150 ne veulent pas dire la meme chose**, et l app les separe :

- **150, 101, 100** — l ayant droit refuse ce clip. On le retient et on
  enchaine, comme cote web ;
- **153** — notre origine est refusee. C est une faute de notre cote, et elle
  doit se voir au lieu d etre contournee en silence.

## Le verre, et sa contrainte

Le materiau est la **vue de contenu de la fenetre**, pas une couche dans
SwiftUI. `blendingMode = .behindWindow` melange avec ce qu il y a derriere la
fenetre ; pose a l interieur de la hierarchie SwiftUI, il se retrouvait sous le
`NSHostingView`, qui peint son propre fond — et la fenetre rendait un gris
uniforme, sans aucune translucidite.

```swift
let fond = NSVisualEffectView()
fond.material = .underWindowBackground
fond.blendingMode = .behindWindow
fond.addSubview(NSHostingView(rootView: racine))   // par-dessus, pas dessous
fenetre.contentView = fond
```

Le rayon de gauche porte son propre materiau, `.sidebar`, comme une barre
laterale native : c est ce qui le detache sans tracer de bordure.

Une fois la fenetre translucide, plus rien ne garantit le contraste du texte.
Les paroles portent donc leur propre couche sombre — sans elle, du blanc sur du
verre au-dessus d une pochette claire devient illisible.

L app dit au demarrage ce qu elle a pu poser, puisque la fenetre n est pas
observable depuis un terminal :

```
verre : materiau 21, fenetre opaque=false, transparence reduite=false
```

21 est `.underWindowBackground`. Si `transparence reduite` passe a `true`,
c est le reglage d accessibilite du systeme qui desactive la vibrancy, et
aucun code ne la ramenera.

## Le mode de verification

Une fenetre ne s observe pas depuis un terminal. `--secondes N` lance une vraie
session, la raconte sur la sortie d erreur, et se ferme seule.

```
$ make lancer S=28
  serveur local : http://127.0.0.1:54353 (boucle locale seulement)
  worker : en ligne
  genres : 9
  gasy : 50 titres
  joue : Wawa Salegy — Moto
  lecteur: en attente de la page pour Piod_S48ZUk
  lecteur: pret
  lecteur: demande differee lancee (Piod_S48ZUk)
  lecteur: etat=3        # BUFFERING
  lecteur: etat=1        # PLAYING
```

`--genre <slug>` choisit le rayon : `gasy` pour la lecture, `pop` pour le
chemin des paroles.

Ce journal a trouve son premier defaut tout seul. Au premier essai, `joue`
arrivait **avant** `lecteur: pret` : `evaluateJavaScript` sur une page encore
vide echoue sans bruit, la fonction n existe pas. La file d attente de la page
ne suffisait pas, il en fallait une cote Swift. Un clic dans la premiere
seconde se perdait de la meme facon.

## Options de lecture

| Bouton | Effet |
|---|---|
| `shuffle` | bat la file. Choisir un titre bat **tout le reste de la liste**, pas seulement ce qui suit — sinon choisir l avant-dernier titre ne melangerait rien |
| `repeat` | trois etats : aucune, ce titre, la liste |
| texte | masque ou affiche les paroles ; la liste reprend le centre |
| fleches | reduit le lecteur a 200 x 200 et le pose dans un coin |

### Les trois etats du lecteur

Le bouton cycle : **grande** (356 x 200), **reduite** (200 x 200), **masquee**.

Masquee, la vue n est pas demontee — la demonter couperait le son. Elle garde
sa taille et sort de l ecran, et son conteneur ne prend plus aucune place.
Mesure :

```
verification : video masquee a 0 s
verification : masquee, position 5 s — lecture en cours
```

**C est un choix assume, il s ecarte de ce que demande l API, et il est garde
dans la version diffusee.**

Les conditions d usage du lecteur IFrame veulent un lecteur visible d au moins
200 x 200 pixels. C est le socle du projet par ailleurs : rien n est extrait,
tout passe par le lecteur officiel. Le masquage a ete demande trois fois,
chaque fois apres que l objection a ete posee, et la derniere explicitement
pour la version a distribuer.

Ce n est donc pas un oubli, et il ne faut pas le « corriger » en croyant bien
faire. La consequence pratique, pour qui reprend ce depot : le risque porte sur
la **cle YouTube Data API** du Worker, pas sur l app — une cle peut etre
revoquee si l usage est juge non conforme. Le choix a ete fait en connaissance
de cela.

En ecrivant ces tailles on a decouvert que la surface precedente faisait
160 x 90 : **elle etait deja sous le minimum**, sans que personne l ait voulu.

Deux details que la verification a imposes :

- **la repetition de liste coupe le regarnissage.** Sinon la file ne se vide
  jamais, `.liste` ne se declenche pas, et l option ne veut rien dire. Qui
  demande « repeter la liste » veut la liste, pas des suggestions ;
- **la repetition d un titre fait un retour a zero**, elle ne recharge pas la
  video : recharger relancerait la recherche de paroles et compterait une
  seconde ecoute.

## Recherche et playlists

Le champ de recherche est dans l en-tete, et il **ne cherche qu a la validation**
— un champ qui chercherait a chaque frappe brulerait le quota, `search.list`
coutant 100 unites par appel.

Le tiroir de gauche montre trois choses, dans cet ordre : **tes listes**, les
**playlists editoriales** du Worker, puis les **genres**.

### Tes listes

Elles vivent sur ta machine, dans un seul fichier :

```
~/Library/Application Support/hira/listes.json
```

**Le titre entier y est stocke, pas seulement son uri.** C est le meme choix que
pour les favoris cote navigateur, et pour la meme raison : une liste doit rester
ecoutable meme si le catalogue ne rend plus ce titre — purge, recherche live qui
ne le ramene pas, Worker eteint.

| Geste | Ou |
|---|---|
| ajouter le titre en cours | le bouton `+` de la barre de commandes |
| creer une liste | le meme menu, « Nouvelle liste… » |
| ajouter n importe quel titre | clic droit sur sa ligne |
| retirer un titre | clic droit, quand une de tes listes est ouverte |
| supprimer une liste | clic droit sur son nom dans le tiroir |

Un fichier illisible n empeche pas l app de demarrer : elle repart d une liste
vide plutot que de refuser de s ouvrir. Et l ajout refuse les doublons — une
liste qui contient deux fois le meme titre n est jamais ce qu on voulait.

## Trois defauts que l usage a reveles

Le troisieme est le plus bete : **les lignes de « À suivre » n etaient pas
cliquables**. Chaque ligne etait un simple empilement de deux textes, sans
bouton ni geste — la file etait purement decorative. Cote navigateur elle avait
son ecouteur de clic ; en portant vers Swift il est passe a la trappe, comme la
fin de titre avant lui.

Cliquer un titre de la file y saute et **retire ce qui le precedait** : on ne
reecoute pas ce qu on vient de depasser. Clic droit pour le retirer de la file
ou l ajouter a une de tes listes.

```
joue : Jul — Bande Organisée
verification : clic sur « La Bandite », rang 2 de la file
saut dans la file : 2 titres passes
joue : Jul — La Bandite
```

## Les deux autres

Le journal d une vraie session les a sortis tous les deux, la ou aucun test ne
les avait vus.

### Les paroles mangeaient la liste

Vingt clics sur les rayons pour deux lectures : voila ce que disait le journal.
Des qu un titre avait des paroles, elles remplacaient la liste au centre et plus
rien n etait cliquable. Rouvrir un rayon rechargeait bien les titres — le
journal le prouvait — mais la vue restait sur les paroles.

La cause etait un etat **deduit** au lieu d etre explicite : « s il y a des
paroles, montre les paroles ». Le centre a maintenant un etat a lui,
`centreSurParoles`, et **ouvrir quoi que ce soit ramene la liste**. Verifie sur
la sequence exacte :

```
centre : liste          rayon ouvert
joue : Hillsong Worship — What A Beautiful Name
centre : paroles        42 lignes prennent le centre
verification : on ouvre « Zouk & Kompa » pendant la lecture
centre : liste          la liste revient
```

### Les suggestions etaient toutes injouables

`Api.similaires` encodait l uri **deux fois** : `appending(path:)` re-encode le
`%` d une chaine deja encodee. Le Worker recevait `youtube%3A...` au lieu de
`youtube:...`, ne trouvait donc aucune graine en base, et ne rendait que son
repli sous licence — dont aucun titre ne joue tant qu `AVFoundation` n est pas
branche. La file se remplissait de titres que l app saute.

```
encodage correct   Kendrick Lamar  (catalogue, video)  puis Audius
double encodage    QUE de l Audius, tout en audio direct
```

Corrige, et les suggestions ecartees sont maintenant **comptees a voix haute**
plutot que cachees :

| Rayon | Suggestions | Jouables aujourd hui |
|---|---|---|
| Musique malgache (75 titres) | 10 | **10** |
| Hip-Hop (2 titres) | 9 | **1** |

C est la mesure la plus utile de la journee : les suggestions tiennent sur les
rayons profonds, et s effondrent sur les rayons minces, ou tout repose sur le
repli sous licence. **`AVFoundation` n est donc pas un confort, c est ce qui
rend les suggestions utilisables.**

## Les radios en direct

Le rayon **Radios** joue les stations malgaches. Il vient du projet
[radioko-leka](https://radiokoleka.xyz/), dont c est le metier.

**Une station entre telle quelle dans le modele `Track`** : duree `0`, capacite
`audioOnly`, une `streamUrl`. La frontiere posee ailleurs — *les capacites du
titre decident du moteur* — les route donc vers `AVFoundation` sans une ligne de
plumbing en plus. C est ce qui a rendu l integration courte.

Ce qui a ete repris de radioko-leka n est pas le code mais la **connaissance**,
qui est la partie chere :

- `all.api.radio-browser.info`, avec un agent identifiable comme son client Go ;
- **les deux flux verifies a la main** de `internal/radio/madagascar.go` —
  Olivasoa Radio et DJ Bam — que Radio Browser ne connait pas, et qui passent
  donc en tete ;
- sa regle de dedoublonnage : meme adresse **ou** meme nom, parce que Radio
  Browser recense la meme radio sous plusieurs entrees.

Cache de six heures cote Worker : une grille de stations ne bouge pas d une
minute a l autre, et Radio Browser est un service benevole qu il serait
grossier de marteler.

### Ce qu un direct casse, et comment

| Hypothese de l app | Pour un direct |
|---|---|
| un titre a des paroles | on ne sait meme pas ce qui passe a l antenne |
| un titre a des voisins | `/v1/similar` n a rien a dire d un flux |
| un titre a une duree | une barre de progression mentirait |

Les trois sont desormais explicites dans le code. En liste, la colonne de duree
affiche « DIRECT » au lieu d un `0:00` absurde ; dans la barre, un point colore
et le temps ecoule depuis le lancement.

### Les pays, et pourquoi Madagascar reste le defaut

227 pays ont des radios chez Radio Browser. Le selecteur n apparait que dans le
rayon Radios, et **Madagascar y est epingle en tete**, au-dessus du
separateur : sans cela, ses 24 stations seraient une ligne perdue entre les
7807 americaines et les 6329 allemandes.

Le rayon ouvre **toujours** Madagascar, et le choix d un autre pays ne vaut que
pour la session. Le libelle du rayon dit « Madagascar, en direct » : si l app
rouvrait sur le dernier pays visite, ce libelle mentirait. Un defaut qui change
tout seul n en est plus un.

### Les radios dans la recherche

Une station nommee passe **devant** les clips : chercher « don bosco » et voir
huit clips avant Radio Don Bosco n est pas ce qu on voulait. Si le nom
normalise de la station contient la requete, elle prend le rang des originaux ;
sinon elle reste au rang neutre.

C est auto-limitant : Radio Browser ne cherche que sur les noms de stations,
donc « bruno mars » n en ramene aucune et une recherche musicale n est jamais
encombree.

### Les radios echappent au blocage par chaine

Trouve en ouvrant la recherche, pas avant. **Toutes les stations d un pays
partagent le meme identifiant d artiste** — `radio:MG`. Le blocage par chaine,
qui ecarte une chaine YouTube apres deux clips refuses, aurait donc banni
Madagascar en entier au deuxieme flux mort.

Le raisonnement « un ayant droit refuse tout son repertoire » vaut pour une
chaine ; il ne veut rien dire pour un pays. Les radios en sont exclues des deux
cotes : on ne compte plus, et on ne filtre plus.

### Beaucoup de radios diffusent en clair

Le defaut le plus vicieux de l integration, et le plus silencieux : `joue :`
s affichait dans le journal, et **rien ne sortait**.

```
France Info   http://direct.franceinfo.fr/live/franceinfo-midfi.mp3
Olivasoa      https://live.webradio.mg/listen/olivasoa/radio.mp3   <- jouait
```

App Transport Security bloque le texte clair, et `NSAllowsLocalNetworking` ne
l autorise que pour la boucle locale. Mesure de l ampleur :

| Pays | Stations en clair |
|---|---|
| Madagascar | 4 sur 18 |
| France | 25 sur 51 |
| Etats-Unis | 28 sur 60 |

La moitie du catalogue hors Madagascar, donc. La cle posee est
**`NSAllowsArbitraryLoadsForMedia`**, et pas `NSAllowsArbitraryLoads` : elle
n ouvre le texte clair qu aux chargements AVFoundation. La recherche, les
paroles et le Worker restent en TLS obligatoire. On ne choisit pas ces
adresses — les radios les publient ainsi.

**Lecon de methode** : `joue :` dit qu on a lance, pas qu on entend. Seul
`audio : lecture`, emis par l observateur de temps quand `timeControlStatus`
passe a `playing`, prouve une lecture. Le journal disait deja la verite ; c est
moi qui lisais la mauvaise ligne.

### Credits

Les donnees de stations viennent de [Radio Browser](https://www.radio-browser.info/),
base communautaire sous licence libre. Aucun flux n est heberge ni reencode :
l app lit l adresse publiee par la radio, exactement comme le projet d origine.

## Deux moteurs

Les capacites du titre decident du moteur, jamais sa source — la meme frontiere
que cote Worker, cote navigateur et cote terminal.

| Titre | Moteur | Ce qu on voit |
|---|---|---|
| catalogue mondial | `WKWebView`, lecteur officiel | la video, 200 x 200 au minimum |
| Audius, Jamendo | `AVPlayer` | la pochette ; rien n est ecrit sur le disque |

`LecteurAudio` expose la meme surface que le lecteur video — `jouer`,
`basculer`, `aller`, `surFin`, `surLecture` — si bien que la coordination route
sans rien savoir du moteur, et que les vues lisent celui qui joue.

Un flux illisible se comporte comme un clip refuse : il est retenu et on
enchaine, au lieu de laisser la lecture mourir dessus.

Verifie de bout en bout :

```
recherche « talking to the moon » : 24 resultats
verification : 5 resultats en audio direct
joue : S!CK!CK — Sickick - Talking to the Moon
audio : lecture
verification : saut a 105 s pour provoquer la fin
audio : termine
joue : BreathOut — Talking To The Moon - Bruno Mars
audio : lecture
```

**Les suggestions ne sont plus filtrees.** Elles l etaient tant que l audio
direct ne jouait pas : sur le rayon Hip-Hop, 8 des 9 propositions etaient
ecartees. Elles comptent toutes, maintenant.

## La recherche

Elle cherche a la validation, pas a chaque frappe : `search.list` coute 100
unites par appel. Elle demande **50 resultats** — c est tout ce qu une page
rend, et elle coute le meme quota qu une page de dix.

### Les propositions de saisie

Elles s affichent dans un **popover**, pas dans une surcouche. Une surcouche
SwiftUI declaree avant le lecteur se fait peindre dessus : `WKWebView` est une
vraie vue AppKit et rend dans sa propre couche, si bien que la liste
apparaissait **vide, derriere la video**. Un popover est une fenetre a part,
donc toujours au-dessus.

Elles viennent du **catalogue**, par `/v1/suggest`, donc de D1 : gratuit et
instantane. Les artistes passent avant les titres, puisqu en tapant trois
lettres on cherche presque toujours quelqu un. Un delai de 220 ms annule la
demande precedente, pour que trois lettres tapees vite ne fassent qu un
aller-retour.

### L ordre des resultats

| Rang | Ce que c est |
|---|---|
| 0 | le catalogue cure, et les clips officiels (`Official Video`, chaines `- Topic` et VEVO) |
| 1 | le reste |
| 2 | remix, cover, sped up, slowed, nightcore, karaoke, type beat… |

Le rang se calcule sur le titre **brut**, avant que `cleanTitle` n efface les
mentions « Official » qui servent justement de signal — il voyage donc sur le
titre jusqu a la fusion. Trier a l interieur du seul bloc YouTube ne suffisait
pas : les sources sous licence passent avant lui, et « bruno mars » rendait six
reprises avant le premier original.

**Le rang dit ce qui est original, pas ce qui jouera.** Pour les artistes dont
l ayant droit refuse l integration, ce sont precisement les clips officiels qui
echouent. D ou le filtre ci-dessous.

### Ce qui est ecarte

Deux memoires, dans `~/Library/Application Support/hira/refus.json` :

- **le clip** deja vu echouer ne revient jamais ;
- **la chaine** dont deux clips ont echoue est ecartee entierement. C est la
  lecon du banc : le refus est une decision d ayant droit, prise pour tout son
  repertoire — 0 jouable sur 40 chez Bruno Mars, classiques de 2010 compris.

## Les suggestions d un titre hors catalogue

Un titre rendu par la recherche live n a pas de graine en base, et le repli
sous licence n a presque rien de malgache : « Mr Sayda X Ortegah » rendait
**zero** suggestion alors que Mr Sayda a six titres chez nous.

Le client envoie donc l artiste **et** le titre, et le Worker cherche si un
artiste du catalogue est nomme dans l un ou l autre — le morceau creditait
ORTEGAH, et c est dans le titre que Mr Sayda apparaissait. Zero suggestion
devient six.

## La disposition

```
+----------+---------------------------+----------+
| Rayons   |  en-tete, lecteur, liste  | A suivre |
|  252     |         ou paroles        |   260    |
+----------+---------------------------+----------+
|            barre de commandes, pleine largeur    |
+--------------------------------------------------+
```

**La barre tient toute la largeur, et ce n est pas qu une question de gout.**
Elle vivait dans la colonne centrale : bouton de lecture, suivant, position,
progression a 420 px fixes, duree, volume et quatre options font pres de
970 px de largeur minimale, dans une colonne qui en avait 620. L empilement
debordait, et c est le **rayon de gauche** qui passait par-dessus bord — la
fenetre affichait « ons » au lieu de « Rayons ».

La progression prend donc `maxWidth: .infinity` et non une largeur fixe : elle
absorbe la place restante au lieu d en exiger, et la barre ne peut plus faire
deborder la fenetre a aucune taille.

## Ce qui joue, et la page de pochette

La barre du bas commence par ce qui joue : **pochette, titre, artiste**, puis un
coeur qui ajoute a une liste. Pas de notion de « favori » separee — s il n y a
aucune liste, le coeur en cree une nommee « Coups de coeur » ; sinon il ajoute a
la premiere. Deux notions de favori pour la meme chose en ferait une de trop.

**Cliquer la pochette ouvre la page de pochette** : l image en grand au centre,
le titre et l artiste dessous. On en sort en cliquant n importe ou — un retour
evident vaut mieux qu une croix a trouver.

Le centre a donc trois etats, et ils sont **explicites** :

| Etat | Quand |
|---|---|
| `liste` | par defaut, et des qu on ouvre un rayon, une liste ou une recherche |
| `paroles` | quand des paroles arrivent pour le titre en cours |
| `pochette` | quand on clique la pochette de la barre |

Les paroles ne volent pas la place a la page de pochette : si on la regarde,
c est un choix delibere, et elles attendent.

L en-tete, lui, ne porte plus le titre en cours — il faisait double emploi avec
la barre. Il garde le nom du projet, l etat courant, la recherche et les deux
tiroirs.

## Les pochettes

Chaque ligne de liste et de file porte sa pochette, et le titre en cours la
sienne a cote de son nom.

**Pas a n importe quelle taille.** Nos adresses pointent sur `maxresdefault`.
Mesure sur un clip du catalogue :

| Variante | Poids |
|---|---|
| `maxresdefault` | 106 Ko |
| `hqdefault` | 13,5 Ko |
| `mqdefault` | 9,5 Ko |

Cinquante vignettes de 36 pixels en pleine resolution, ce sont 5,3 Mo
telecharges et gardes en memoire pour rien — sur une machine de 16 Go deja a
court. Les vignettes demandent donc `mqdefault`, les grandes `hqdefault`. Et
ce n est pas qu une question de poids : **`maxresdefault` n existe pas pour
tous les clips**, il rend 404, alors que les deux petites sont toujours la.

### Les mosaiques des rayons

Le Worker sert **quatre pochettes par rayon**, prises des titres les plus vus,
par une sous-requete correlee dans la requete qui liste deja les genres : une
mosaique se compose cote client, et faire huit appels de plus pour quatre
images serait absurde.

L app en fait un carre 2 x 2 quand les quatre existent, une seule pochette
sinon, un carre neutre quand il n y en a aucune — pour que la colonne reste
alignee. Vaut pour les genres, les playlists editoriales et tes propres listes,
dont la mosaique se compose des titres qu elles contiennent.

## Les reglages

Ils vivent dans la **barre de menus**, a leur place sur macOS : menu de
l application, Commande-virgule. Un bouton dans l en-tete faisait double emploi
avec une convention que tout le monde connait.

Le menu Lecture porte aussi Lecture/Pause, Titre suivant et le volume
(Commande-Haut, Commande-Bas).


Un bouton dans l en-tete, et un fichier a cote des listes et des refus :
`~/Library/Application Support/hira/reglages.json`.

| Reglage | Effet |
|---|---|
| Theme | systeme, clair, sombre — la fenetre et son cadre suivent |
| Couleur principale | le titre en cours, la ligne de paroles atteinte, le bouton de lecture |
| Couleur secondaire | la barre de progression |
| Format du lecteur | grande, reduite, masquee |
| Volume | de 0 a 100 %, avec un curseur aussi dans la barre |
| Vitesse | 0,75x, normale, 1,25x, 1,5x |

**Volume et vitesse sont reposes a chaque titre.** Un `AVPlayer` neuf part a
plein volume, et le lecteur officiel oublie la consigne a chaque chargement :
les porter une fois au clic ne suffit pas. D ou un second crochet de lecture
sur chaque moteur, distinct de celui que les verifications se reservent.

### Pas d egaliseur, et c est definitif

On ne touche jamais au flux audio d un clip : c est le lecteur officiel qui le
joue, et il n expose ni bandes ni filtres. Un egaliseur ne vaudrait que pour
les titres en audio direct — il s allumerait et s eteindrait selon le morceau,
ce qui est pire qu un reglage absent. Le volume et la vitesse, eux, existent
des deux cotes.

## La veille, sans devinette

```
NSWorkspace.willSleepNotification   on note ce qui joue, et ou
NSWorkspace.didWakeNotification     on reprend
```

**Aucun seuil.** Cote navigateur il a fallu un battement de dix secondes, un
seuil de quatre-vingt-dix, et le pari qu un trou plus grand qu aucun bridage de
minuterie connu signifiait un sommeil. Le systeme previent une app native.
C est la justification la plus nette du choix du natif pour ce projet : la
machine s endort au bout d une minute d inactivite.

L ordre est le meme que cote web, et pour la meme raison : **le Worker
d abord**, cinq essais espaces. Tant qu il ne repond pas, relancer la lecture
ne prepare que la prochaine impasse. Et on ne relance que ce qui **jouait**.

## Now Playing et les touches media

Le README disait que ce serait a moitie possible, en croyant que la session
media de l iframe nous bloquait. **C etait faux.**
`MPNowPlayingInfoCenter` ne fait que publier des metadonnees — titre, artiste,
duree, position — et on les connait des deux cotes.
`MPRemoteCommandCenter` route les touches vers notre propre lecteur, quel qu il
soit. Lecture, pause, bascule, suivant, precedent et deplacement dans le
morceau sont branches ; la pochette est chargee en `hqdefault` et mise en cache.

C est necessaire depuis que la video peut etre masquee : la musique joue alors
sans rien a regarder.

**Reserve.** Quand un `WKWebView` joue un media, WebKit ouvre sa propre
session ; la notre peut entrer en concurrence avec elle dans le Centre de
controle. Le journal dit ce qu on publie, pas ce que le systeme affiche.

## Les tests

```bash
make tests        # 24 verifications, sans Xcode ni XCTest
```

Un binaire qui affirme et sort non nul, comme le banc. Il compile toutes les
sources sauf `main.swift`, dont le code de premier niveau entrerait en conflit.

Il couvre le **calage des paroles borne par borne** — avant le premier
horodatage, entre deux lignes, pile dessus, une milliseconde avant, apres la
derniere, et sans paroles. C est le seul vrai algorithme de l app, et une erreur
de borne y est invisible a l oeil : la ligne surlignee a juste « l air » en
retard. Plus les adresses de pochettes, les cycles d options, et le fait que
`COTE_MINIMAL` vaille toujours 200 — pour qu un refactor ne fasse pas
disparaitre en silence le minimum que l API demande.

**Ce qu ils ne couvrent pas, et il faut le savoir.** Trois des quatre defauts
trouves en une journee d usage n etaient pas testables ainsi : la fin de titre
non branchee, la file non cliquable, le double encodage d uri. C etait du
cablage entre une vue et un modele. Seule la machine a etats des paroles se
teste. Les tests reduisent la surface, ils ne la ferment pas — le journal reste
le filet pour le reste.

## Donner l app a quelqu un

Le `.app` suffit : il porte le binaire et la page du lecteur, et l API est en
ligne. **Aucune cle n y figure** — celle de YouTube vit dans le Worker.

```bash
make universel dmg   # Intel + arm64, puis l image a donner
```

L image porte l app, un lien vers Applications, et un `Lisez-moi.txt` qui
explique le refus de Gatekeeper — on le lira parce qu il est la, pas dans un
message qu on aura perdu.

**La cible `dmg` ne depend pas du bundle**, et c est volontaire : elle en
dependait, make reconstruisait alors a l architecture de la machine et
ecrasait la version universelle qu on venait de produire. `make universel dmg`
rendait un dmg x86_64 seul.

**Un seul fichier couvre les deux machines.** Il n y a pas de version Intel et
de version Apple Silicon a choisir : les deux tranches sont dans le meme
binaire, et macOS prend la bonne.

Ce qui a ete verifie sur la tranche arm64, faute de pouvoir l executer :

| | |
|---|---|
| taille | 1 897 376 octets, contre 1 893 872 pour Intel |
| cadres lies | AVFoundation, AppKit, MediaPlayer, Network, SwiftUI, WebKit |
| plateforme | macOS, `minos 14.0`, SDK 15.5 |
| symboles du projet | 4056 |

Les 4056 symboles sont ce qui compte : une tranche vide ou tronquee n en
porterait aucun. **Elle n a pourtant jamais ete executee** — compilee a
l aveugle depuis une machine Intel, seul un Mac a puce Apple le dira.

### Trois choses a dire a qui la recoit

| | |
|---|---|
| macOS 14 minimum | `LSMinimumSystemVersion` dans l Info.plist |
| Signature ad-hoc | Gatekeeper bloque au premier lancement |
| Quota partage | la cle YouTube du Worker sert tout le monde |

**Sur macOS 15, le clic droit → Ouvrir ne suffit plus** : Apple a retire ce
contournement. Il faut aller dans Reglages → Confidentialite et securite,
trouver le message qui mentionne RadiokoLeka, et cliquer « Ouvrir quand meme ».
Transmise par cle USB ou `rsync`, l app n a pas d attribut de quarantaine et
s ouvre directement.

Le quota YouTube est de 10 000 unites par jour et une recherche live en coute
100 : environ **cent recherches par jour, toutes personnes confondues**. Au-dela,
la recherche ne rend plus que le catalogue — ce n est pas une panne, c est le
fonctionnement prevu sans cle.

## A quel Worker l app parle

Trois sources, de la plus precise a la plus generale :

```bash
./RadiokoLeka                                 # le Worker deploye
./RadiokoLeka --api http://127.0.0.1:8787     # ton Worker local
```

La deuxieme source est `api` dans `reglages.json`, si tu heberges le tien.
L adresse retenue s ecrit au demarrage dans le journal, pour qu on ne se
demande jamais a qui l app parle.

Figer l adresse dans le binaire obligeait a recompiler pour basculer entre le
local et le deploye, ce qui arrive plusieurs fois par jour.

## Ce qui reste a faire

- le **mini-lecteur** en deuxieme fenetre ;
- la **bibliotheque locale surveillee** ;

## Un defaut trouve en verifiant, et corrige

Au premier lancement, le rayon `pop` ne contenait qu un titre — `1l7wbZmdtys`,
Bruno Mars, « Dance With Me » — et il rendait `erreur=150`. L app a reagi
correctement : elle a reconnu un refus d ayant droit, l a distingue du 153, et a
voulu enchainer.

Le catalogue entier est passe au banc natif ensuite : **110 jouables sur 114**,
zero `bloque`. Les quatre refuses ont ete retires, et le rayon Pop avec eux.

La recherche de remplacants a donne **0 sur 40**, y compris sur les plus gros
succes de ces artistes, vieux de quinze ans. Le refus se decide **par ayant
droit, pour tout son repertoire** — pas par clip, et sans rapport avec l age.
Detail du raisonnement et des mesures dans le README principal.

Deux consequences pour l app :

- le rayon Pop ne reviendra pas, et ce n est pas un bogue a corriger ;
- **un catalogue de clips YouTube se degrade.** Le banc doit tourner
  regulierement : `cd desktop && make banc`.

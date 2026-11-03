# Client web

Le lecteur dans le navigateur. Aucune etape de build, aucune dependance : des
modules ES servis tels quels.

```bash
cd api && npm run dev          # le Worker, sur 8787
cd web && ./serve.py           # la page, sur 5173
# puis http://127.0.0.1:5173
```

`serve.py` plutot que `python3 -m http.server` : ce dernier revalide par
`Last-Modified` et renvoie des 304, donc le navigateur rejoue l'ancien module
apres une edition. On debugge alors du code qui n'est plus sur le disque.

Pour viser un autre Worker, poser `window.HIRA_API_URL` avant le module :

```html
<script>window.HIRA_API_URL = 'https://api.exemple.test';</script>
```

## A quel Worker la page parle

Le **Worker deploye** par defaut : la page marche sans rien lancer a cote.

```
https://radiokoleka-api.radiokoleka.workers.dev
```

Pour developper contre son propre Worker, poser la variable avant les modules :

```html
<script>window.RADIOKOLEKA_API_URL = 'http://127.0.0.1:8787'</script>
```

`HIRA_API_URL` reste reconnu : le projet s appelait ainsi, et des pages posees
ailleurs peuvent encore le definir.

Le Worker renvoie `Access-Control-Allow-Origin: *`, donc une page servie depuis
`127.0.0.1:5173` l appelle sans configuration.

**Un 502 n est pas forcement une panne du Worker.** Il le rend aussi quand une
source amont echoue — Audius pour le classement sous licence, par exemple. La
page continue de se remplir : ce classement est un confort, pas une condition
de demarrage.

## Ce que la page fait

| | |
|---|---|
| Recherche | les deux catalogues, sans filtre `audio_only` — dans un navigateur le lecteur officiel existe, donc le catalogue mondial est jouable |
| Catalogue mondial | lecteur IFrame officiel, **visible**, dans la page. Rien ne s'ouvre ailleurs |
| Sous licence / local | balise `<audio>`, flux direct, rien n'est ecrit sur le disque |
| Tes fichiers | « Mes fichiers » lit l'audio sur place ; un `.lrc` depose avec lui est prioritaire sur toute recherche en ligne |
| Paroles | LRCLIB via le Worker, ligne surlignee et centree |

Pas de champ « colle un lien », pas de bouton telecharger : ce n'est pas ce que
cette app est.

## La veille, et la reprise

Verrouiller l'ecran ne coupe rien. Mesure faite sur une page masquee : l'audio
a continue de 20 s a 125 s sans une pause, `setInterval` a tenu ses battements
(ralentis a environ un par seconde), et `requestAnimationFrame` s'est gele net
— 5395 images, puis plus une seule. Ce qui s'arrete quand tu regardes
ailleurs, c'est donc le defilement des paroles, pas la musique.

Ce qui coupe, c'est la **veille systeme**. Elle arrete le son, et surtout les
deux serveurs locaux dont la page depend. Avant, la page ne le disait pas : a
la fin du titre suivant, `/v1/similar` echouait, et « À suivre » affichait
« Plus rien à enchaîner. Lance une autre recherche » — ce qui envoyait relancer
une recherche qui ne pouvait pas aboutir.

`src/reveil.js` detecte le reveil sur l'ecart entre deux battements : au-dela
de 90 s, aucun bridage de minuterie connu n'explique le trou. Le seuil est haut
exprès, parce qu'un onglet masque peut etre bride jusqu'a une fois par minute ;
et s'il se trompait quand meme, un faux reveil ne coute qu'un ping et ne montre
rien.

Au reveil, l'ordre compte : **le Worker d'abord**, cinq essais espaces sur une
quinzaine de secondes. Tant qu'il ne repond pas, relancer la lecture ne
preparerait que la prochaine impasse. Trois cas, tous les trois verifies en
simulant le saut d'horloge que produit une veille :

| Situation | Ce que la page affiche |
|---|---|
| Worker revenu | « Réveil après 3 min — reprise. » et le titre repart |
| Worker encore muet | « Réveil après 3 min — reconnexion au Worker… » |
| Worker mort | « Worker injoignable après le réveil. Relance-le : cd api && npm run dev » |

La reprise repart ou tu en etais, pas au debut : le battement note la position
a chaque passage, donc au plus dix secondes avant. Mesure : coupe a 33 s,
reprise a 35 s. Elle ne relance que ce qui **jouait vraiment** — reprendre un
titre que tu avais mis en pause serait une surprise — et elle ne recompte pas
l'ecoute, sinon les mixes construits sur l'historique se fausseraient.

La file, elle, n'a jamais bouge : elle vit en memoire et traverse la veille
intacte. 12 titres avant, 12 apres.

## La limite a connaitre

Un ayant droit peut interdire l'integration de son clip. Ce refus **n'est pas
annonce** : `status.embeddable` de la Data API vaut `true` pour des clips qui
echouent quand meme. Il n'apparait qu'a la lecture, par `onError` 101 ou 150.

La page le gere : le titre est barre dans la liste et la lecture enchaine sur le
suivant, pour que « Regarder sur YouTube » ne s'affiche jamais.

**Et elle s'en souvient.** Le refus est garde dans `hira.refuses.v1`, et les
listes construites ensuite ne le montrent plus : un clip barre une fois ne
revient pas demain. Un refus survenu *pendant* une lecture reste visible et
barre — c'est ce qui explique le saut. Le Worker a sa propre memoire,
`clips_refuses`, remplie par le banc ; celle du navigateur est plus large,
puisqu'elle attrape aussi les clips que la recherche live rend sans que le
catalogue les ait jamais vus.

Mesure faite depuis `127.0.0.1` : les artistes independants passent (le clip de
Niu Raza joue), le repertoire des majors est refuse en bloc. Ces restrictions
s'appliquent par origine ; il reste donc a verifier depuis le domaine de
production, ou le resultat peut differer.

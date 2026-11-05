# L erreur 150 : d abord soupconner le reseau

Le 5 novembre 2026, plus un seul titre ne jouait. Le lecteur renvoyait
l erreur 150 sur tout le catalogue. La cause etait un VPN actif. Ce
document existe pour que la prochaine fois prenne cinq minutes et non une
journee.

## Le diagnostic, en une commande

```
curl -s "https://www.youtube.com/watch?v=AMPdykrcho4" | grep -o '"playabilityStatus":{"status":"[A-Z_]*"'
```

- `"status":"OK"` — le reseau passe, cherchez ailleurs.
- `"status":"LOGIN_REQUIRED"` — avec pour raison « Connectez-vous pour
  confirmer que vous n etes pas un robot ». Le reseau est refuse. Coupez le
  VPN et relancez la commande.

L erreur 150 de l integration est la traduction en chiffres de cette meme
porte. Elle ne dit donc rien de l ayant droit du clip, contrairement a ce
que son nom laisse croire.

## Pourquoi un VPN

Ce controle vise les adresses de centres de donnees, et une sortie de VPN
en est une. Ce jour-la :

| sortie | YouTube |
|---|---|
| VPN | `LOGIN_REQUIRED` |
| Orange Madagascar, Antananarivo | `OK`, et la lecture repart |

## Les fausses pistes, pour ne pas les refaire

Toutes ont ete mesurees, toutes sont a ecarter :

- **l origine** : refus identique depuis `http://127.0.0.1`,
  `http://localhost` et `https://radiokoleka-api.radiokoleka.workers.dev`,
  un domaine public ;
- **l agent utilisateur** : un `WKWebView` avec l agent complet de Safari
  est refuse comme avec le sien ;
- **le moteur** : WebKit et Chromium echouent pareil ;
- **les ayants droit** : Gangnam Style est refuse, et un enregistrement
  d oiseaux a 57 vues aussi ;
- **la popularite et l ordre des essais** ;
- **notre code** : `curl` n execute ni notre app ni la moindre ligne de
  JavaScript, et recoit deja le refus.

Un navigateur connecte a un compte Google joue malgre le VPN. C est ce qui
egare : la meme machine, au meme instant, joue dans Chrome et refuse dans
l app. La difference n est pas l app, c est le compte.

`dQw4w9WgXcQ` joue meme refuse par ailleurs. C est une exception, pas un
temoin : ne jamais s en servir pour conclure que la lecture marche.

## La sonde

`/sonde-embed?ids=a,b,c` sur le Worker essaie chaque clip dans un vrai
lecteur et affiche un verdict. Deux details sans lesquels elle ment :

- **le lecteur est muet**, car un navigateur refuse l autoplay sonore sans
  geste de l utilisateur. Le premier sondage ne coupait pas le son : tout
  restait en tampon, sans erreur, et j en ai conclu une panne generale.
  Faux, et cette erreur a oriente une demi-journee ;
- **elle avance meme quand rien ne joue**, en disant l etat atteint. Un
  silence doit se lire, pas s interpreter.

## Ce que l app en a retenu

Une heure de VPN avait gravé 89 refus et banni 32 chaines — presque tous
les artistes malgaches du catalogue — parce que l app croyait chaque refus
sur parole et enchainait aussitot sur le titre suivant. Deux garde-fous :

- **un refus ne se grave qu apres une lecture reussie.** Un refus isole dit
  quelque chose d un ayant droit ; cinquante d affilee ne disent rien
  d autre que « la lecture est cassee ».
- **au-dela de cinq refus d affilee, l app se tait** quinze minutes au lieu
  d enchainer. Mais un clic reessaie toujours : qui vient de couper son VPN
  n a pas a attendre un quart d heure.

La sauvegarde des refus de ce jour-la est dans
`refus-avant-panne-2026-11-05.json.bak`, a cote de `refus.json`.

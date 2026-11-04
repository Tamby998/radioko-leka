# Prompt a donner a Claude Code pour le logo

A coller tel quel dans une session ouverte sur `~/Documents/hira`.

---

Dessine le logo de RadiokoLeka, en SVG ecrit a la main. Pas de generateur
d'image, pas de fichier binaire telecharge : du code que je peux relire et
corriger.

**Ce que le nom veut dire.** RadiokoLeka est une app macOS de musique
malgache (Swift/SwiftUI, dans `desktop/`). Le nom porte les deux couleurs du
projet : « radio » est la couleur de base, « leka » la seconde. Elles sont
deja dans le code, dans `desktop/Hira/Sources/Reglages.swift` :

    accent  #F2C94C   (Or)      — ce qui est actif, en cours, choisi
    second  #7BD88F   (Menthe)  — la progression, les accents discrets

Prends-les comme couleurs du logo, declarees une seule fois en haut du SVG
pour que je puisse en changer d'un seul endroit.

**Les trois motifs a fondre en une seule forme**, pas a poser cote a cote :

1. la radio — le poste, ou l'onde, ou les deux ;
2. le chapeau betsileo — le chapeau de paille des hautes terres. **Va
   d'abord chercher a quoi il ressemble vraiment** (forme de la calotte,
   largeur du bord, le bandeau) avant de dessiner : un chapeau generique
   raterait tout l'interet du logo, et je verrai la difference ;
3. le triangle de lecture.

Une piste, a prendre ou a laisser si tu trouves mieux : le bord du chapeau
peut faire les arcs de l'onde radio, et le triangle de lecture se loger dans
la calotte. Si cette idee ne tient pas au dessin, dis-le et propose la tienne.

**Les contraintes qui comptent :**

- il doit rester lisible a 16 px dans la barre des menus **et** tenir a
  1024 px : donc peu de traits, et aucun detail qui disparait en petit ;
- il doit marcher sur fond clair et sur fond sombre — l'app a les deux
  themes. Si une seule version n'y arrive pas, fais-en deux et dis pourquoi ;
- aucun texte dans le logo, aucune police : que des formes ;
- un seul fichier, sans dependance, sans image bitmap encastree.

**Donne-moi trois propositions** differentes, pas trois variantes de la meme,
dans `desktop/Hira/Ressources/logo/`. Pour chacune, rends une planche de
contact HTML qui la montre a 1024, 128, 32 et 16 px, sur fond clair et sur
fond sombre, cote a cote — je choisirai en regardant ca, pas en lisant une
description.

**Ensuite, quand j'aurai choisi** (attends mon choix, ne le fais pas pour les
trois) : l'app n'a aujourd'hui **aucune icone declaree** — rien dans
`desktop/Hira/Info.plist`. Donc branche-la vraiment :

- fabrique le `.iconset` et le `.icns` avec `sips` et `iconutil` (tous deux
  dans macOS, rien a installer) ;
- declare `CFBundleIconFile` dans `Info.plist` ;
- copie l'icone dans le bundle depuis le `Makefile`, dans les deux cibles
  qui l'assemblent : `$(BUNDLE)` et `universel` ;
- puis `make tout` et ouvre l'app pour verifier que l'icone apparait au Dock.
  Montre-moi une capture : une icone declaree mais mal nommee ne produit
  aucune erreur, juste l'icone grise par defaut.

Verifie avant de me dire que c'est fait.

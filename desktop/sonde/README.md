# Sonde d'integration — WKWebView et le lecteur IFrame

La question qui decidait de l'app desktop : les 189 titres du catalogue sont
des clips YouTube, et ils ne jouent que par le lecteur officiel. Si WKWebView
ne peut pas l'heberger, l'app se construit autour d'Audius, de Jamendo et des
fichiers locaux.

## Verdict

**Le lecteur joue, a une condition : une origine `http://` reelle.**

| Origine | Clip jouable | Clip refuse par l'ayant droit |
|---|---|---|
| `file://` | **erreur 153** | erreur 153 |
| `http://127.0.0.1:8099` | **ok** | **erreur 150** |
| `hira://` (WKURLSchemeHandler) | **erreur 153** | erreur 153 |

Deux codes, deux causes, et il fallait les distinguer :

- **153** — YouTube refuse l'origine. Il n'a pas de referent HTTP a verifier,
  donc il refuse tout, meme un clip parfaitement integrable. Ni `file://` ni un
  schema personnalise ne passent.
- **150** — l'ayant droit refuse ce clip-la. C'est le meme refus que celui
  mesure au banc dans le navigateur.

Le temoin le prouve : `efiS8G_V3NU`, dont le banc avait dit `erreur:150`, rend
exactement `erreur:150` sur l'origine `http://`. La sonde ne dit pas « ok » a
tout ce qu'on lui donne, et l'environnement WKWebView se comporte comme le
navigateur. **Les verdicts du banc restent donc valables sur desktop** : rien a
remesurer.

## Ce que ca impose a l'app

Un **petit serveur HTTP interne, lie a 127.0.0.1 seulement**, sur un port
ephemere, qui sert la page du lecteur. Une quarantaine de lignes avec
`NWListener`, sans dependance. L'interface reste 100 % SwiftUI : seule la page
du lecteur passe par la.

C'est aussi la confirmation du risque signale en ecartant Tauri : son
`tauri://localhost` aurait rendu 153, comme notre schema personnalise.

## Methode

Le verdict ne repose que sur des **evenements**, jamais sur une horloge. Deux
pieges deja payes au banc :

- l'etat du lecteur seul donne des faux positifs — un clip refuse passe par
  BUFFERING *avant* que `onError` arrive. D'ou le sursis de 2,5 s apres
  PLAYING, pendant lequel une erreur fait encore autorite ;
- une horloge gelee declare injouable ce qui joue.

`api=echec` est un verdict a part : sans lui, une page dont le script ne charge
pas serait confondue avec un refus d'integration.

`config.mediaTypesRequiringUserActionForPlayback = []` est indispensable. Sans
ca rien ne demarre sans clic, et tout serait declare bloque pour la mauvaise
raison.

## Rejouer

```bash
cd desktop/sonde
swiftc -framework WebKit -framework AppKit -o sonde-bin main.swift
python3 -m http.server 8099 --bind 127.0.0.1 &
./sonde-bin                 # clip jouable par defaut
./sonde-bin efiS8G_V3NU     # temoin refuse
```

Aucun Xcode : les Command Line Tools suffisent, et `codesign --force --sign -`
produit un `.app` signe ad-hoc. Verifie dans les deux formes, binaire nu et
bundle : meme resultat.

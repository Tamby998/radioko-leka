/**
 * Dedoublonnage des resultats de recherche.
 *
 * Un meme clip remonte deux fois : le catalogue cure connait « RIVOTRA Mahaleo
 * Live @ Olympia » sous l'artiste `Mahaleo`, et `search.list` le rend une
 * seconde fois sous la chaine `Mahaleo Officiel`. Comparer artiste + titre ne
 * les rapproche donc pas — c'est la duree qui est la meme, a la seconde.
 *
 * Deux passes, de la plus sure a la plus souple :
 *
 * 1. titre normalise + duree. Rapproche les reprises exactes d'un meme clip.
 * 2. a duree strictement egale, un titre contenu dans l'autre. C'est ce qui
 *    rapproche « Mahaleo- Hay hay » (reupload) de « Hay hay », que la passe 1
 *    laisse passer puisque les titres different.
 *
 * La duree inconnue (`0`, les placeholders du seed) desactive les deux : on
 * retombe sur titre + artiste, sans quoi deux titres homonymes fusionneraient
 * sur la foi de rien.
 */

import type { Track } from '../sources/types.ts';
import { normalize } from './relevance.ts';

/** Secondes pleines, ou `null` quand la duree n'est pas connue. */
function secondes(track: Track): number | null {
  const ms = track.durationMs ?? 0;
  return ms > 0 ? Math.round(ms / 1000) : null;
}

/**
 * Ce qui fait qu'on garde l'un plutot que l'autre : le nombre de capacites.
 *
 * Une source sous licence (`stream,audioOnly,background,offline`) vaut mieux
 * qu'un clip YouTube, qui exige un lecteur visible. A egalite on garde le
 * premier vu, et comme la recherche empile le catalogue cure avant les
 * resultats live, c'est l'entree verifiee qui reste.
 */
const score = (t: Track) => t.capabilities.length;

function empreinte(track: Track): string {
  const s = secondes(track);
  return s === null
    ? `t:${normalize(track.title)}|a:${normalize(track.artists[0]?.name ?? '')}`
    : `t:${normalize(track.title)}|d:${s}`;
}

/** `a` contient-il `b` en mots pleins ? « mahaleo hay hay » contient « hay hay ». */
function contient(a: string, b: string): boolean {
  if (!b) return false;
  return ` ${a} `.includes(` ${b} `);
}

export function dedupe(tracks: Track[]): Track[] {
  const gardes: Track[] = [];
  const parEmpreinte = new Map<string, number>();

  for (const piste of tracks) {
    const cle = empreinte(piste);
    const vu = parEmpreinte.get(cle);
    if (vu !== undefined) {
      if (score(piste) > score(gardes[vu])) gardes[vu] = piste;
      continue;
    }

    // Passe 2 : meme duree exacte, et un titre contenu dans l'autre.
    const s = secondes(piste);
    const titre = normalize(piste.title);
    const jumeau =
      s === null
        ? -1
        : gardes.findIndex((g) => {
            if (secondes(g) !== s) return false;
            const autre = normalize(g.title);
            return contient(autre, titre) || contient(titre, autre);
          });

    if (jumeau >= 0) {
      if (score(piste) > score(gardes[jumeau])) gardes[jumeau] = piste;
      continue;
    }

    parEmpreinte.set(cle, gardes.length);
    gardes.push(piste);
  }

  return gardes;
}

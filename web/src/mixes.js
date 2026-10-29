//! Historique d'ecoute, et les listes qu'on en tire.
//!
//! Tout vit dans le navigateur : aucune ecoute ne part sur le reseau. Les mixes
//! se deduisent de ce qui a ete joue, donc ils ne valent rien au premier
//! lancement et se precisent a chaque titre — c'est voulu.

import { tranche } from './region.js';

const CLE = 'hira.ecoutes.v1';
/** Au-dela, l'historique ne dit plus rien d'utile et pese pour rien. */
const MAX = 400;

function lire() {
  try {
    const brut = localStorage.getItem(CLE);
    return brut ? JSON.parse(brut) : [];
  } catch {
    return []; // stockage bloque : on tourne sans memoire, sans casser
  }
}

function ecrire(liste) {
  try {
    localStorage.setItem(CLE, JSON.stringify(liste.slice(0, MAX)));
  } catch {
    /* rien a faire */
  }
}

/**
 * Note une ecoute. Un titre deja connu remonte en tete et voit son compte
 * augmenter, au lieu d'etre duplique : l'historique reste une liste de titres,
 * pas un journal.
 */
export function noterEcoute(titre) {
  if (!titre?.uri) return;
  const liste = lire();
  const index = liste.findIndex((e) => e.uri === titre.uri);
  const connu = index >= 0 ? liste.splice(index, 1)[0] : null;

  liste.unshift({
    uri: titre.uri,
    source: titre.source,
    title: titre.title,
    artists: titre.artists ?? [],
    durationMs: titre.durationMs ?? 0,
    capabilities: titre.capabilities ?? [],
    requiresVisiblePlayer: Boolean(titre.requiresVisiblePlayer),
    streamUrl: titre.streamUrl ?? null,
    fois: (connu?.fois ?? 0) + 1,
    quand: Date.now(),
  });
  ecrire(liste);
}

/** Les titres joues, du plus recent au plus ancien. */
export function ecoutes() {
  return lire();
}

/**
 * Les artistes les plus ecoutes, par nombre d'ecoutes puis par recence.
 *
 * C'est la matiere des mixes : un artiste revenu souvent merite sa liste.
 */
export function artistesFrequents(limite = 8) {
  const compte = new Map();

  for (const e of lire()) {
    const nom = e.artists?.[0]?.name;
    if (!nom) continue;
    const vu = compte.get(nom) ?? { nom, fois: 0, quand: 0, graines: [] };
    vu.fois += e.fois ?? 1;
    vu.quand = Math.max(vu.quand, e.quand ?? 0);
    // Deux graines suffisent a lancer un mix, et bornent les appels reseau.
    if (vu.graines.length < 2) vu.graines.push(e);
    compte.set(nom, vu);
  }

  return [...compte.values()]
    .sort((a, b) => b.fois - a.fois || b.quand - a.quand)
    .slice(0, limite);
}

/**
 * Melange stable sur une tranche de rotation.
 *
 * La graine est le numero de tranche : le meme mix garde son ordre tant que la
 * tranche dure, et se reordonne a la suivante. Sans graine stable, la liste se
 * reordonnerait sous les yeux a chaque rendu.
 */
export function melanger(liste, graine = tranche()) {
  const out = [...liste];
  let etat = Math.floor(graine) + out.length;
  for (let i = out.length - 1; i > 0; i--) {
    etat = (etat * 1103515245 + 12345) & 0x7fffffff;
    const j = etat % (i + 1);
    [out[i], out[j]] = [out[j], out[i]];
  }
  return out;
}

/** Ecarte les doublons d'uri en gardant le premier vu. */
export function sansDoublon(titres) {
  const vus = new Set();
  return titres.filter((t) => !vus.has(t.uri) && vus.add(t.uri));
}

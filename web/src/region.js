//! D'ou ecoute la personne, et ce qu'on en deduit.
//!
//! Aucune demande de permission : l'API de geolocalisation ouvrirait une
//! fenetre de consentement pour choisir un ordre de playlist, ce qui est
//! disproportionne. Le fuseau horaire et la langue du navigateur suffisent, ils
//! sont deja la, et ils ne disent rien de plus precis qu'un pays.

/** Fuseaux qui designent Madagascar sans ambiguite. */
const FUSEAUX_MG = new Set(['Indian/Antananarivo']);

/**
 * Tranche de rotation courante.
 *
 * Les listes proposees changent toutes les cinq heures : on expose le numero
 * de tranche plutot qu'une date, pour qu'il serve a la fois de graine de
 * melange et de cle de cache.
 */
export const HEURES_ROTATION = 5;

export function tranche(maintenant = Date.now()) {
  return Math.floor(maintenant / (HEURES_ROTATION * 3600 * 1000));
}

/** Millisecondes avant la prochaine rotation, pour reprogrammer un rendu. */
export function avantRotation(maintenant = Date.now()) {
  const duree = HEURES_ROTATION * 3600 * 1000;
  return duree - (maintenant % duree);
}

function fuseau() {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone ?? '';
  } catch {
    return '';
  }
}

function langues() {
  const l = navigator.languages?.length ? navigator.languages : [navigator.language];
  return (l ?? []).filter(Boolean).map((x) => x.toLowerCase());
}

/**
 * La personne ecoute-t-elle depuis Madagascar, ou en malgache ?
 *
 * Les deux comptent : un Malgache de la diaspora n'a pas le fuseau mais a
 * souvent la langue, et c'est lui qui cherche ce repertoire.
 */
export function ecouteGasy() {
  if (FUSEAUX_MG.has(fuseau())) return true;
  return langues().some((l) => l === 'mg' || l.startsWith('mg-') || l.endsWith('-mg'));
}

/** Ce qu'on sait, pour l'afficher sans pretendre en savoir plus. */
export function contexte() {
  return { fuseau: fuseau(), langues: langues(), gasy: ecouteGasy() };
}

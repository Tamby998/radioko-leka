//! Detection d'un reveil de machine, et memoire de ce qui jouait.
//!
//! Mesure, pas supposition. Sur cette machine, une page masquee garde ses
//! `setInterval` — ils continuent, ralentis a environ un par seconde — et perd
//! `requestAnimationFrame`, qui se gele franchement. Une veille systeme, elle,
//! arrete les deux. Un battement qui constate un trou bien plus grand que sa
//! periode a donc dormi, et non pas seulement ete masque.
//!
//! Le seuil est haut pour une raison precise : un navigateur peut brider les
//! minuteries d'un onglet masque jusqu'a une fois par minute. Un trou de
//! trente secondes ne prouve donc rien. Au-dela de `SEUIL_MS`, en revanche,
//! aucun bridage connu n'explique l'ecart.
//!
//! Et si le seuil se trompait quand meme, ce n'est pas grave : la reprise
//! commence par demander au Worker s'il repond. Un faux reveil coute un ping
//! et ne montre rien.

/** Periode du battement. Assez court pour une reprise fine, assez long pour ne rien couter. */
const PERIODE_MS = 10_000;

/** Au-dela, l'ecart n'est plus un retard de minuterie mais un sommeil. */
const SEUIL_MS = 90_000;

/**
 * L'ecart constate trahit-il un sommeil ?
 *
 * Fonction pure, et c'est volontaire : c'est la seule decision du module, et
 * elle doit pouvoir etre jugee sans horloge ni navigateur.
 */
export function estUnReveil(ecouleMs, seuilMs = SEUIL_MS) {
  return ecouleMs > seuilMs;
}

/**
 * Lance le battement.
 *
 * `observer` est appele a chaque battement : c'est la qu'on note ce qui joue,
 * puisque `requestAnimationFrame` est gele des que la page passe derriere et
 * ne peut plus servir a cela. `auReveil` recoit la duree du trou.
 *
 * Rend la fonction qui arrete le battement.
 */
export function surveillerReveil(auReveil, observer = () => {}, periode = PERIODE_MS) {
  let dernier = Date.now();

  const battement = setInterval(() => {
    const maintenant = Date.now();
    const ecoule = maintenant - dernier;
    dernier = maintenant;
    if (estUnReveil(ecoule)) auReveil(ecoule);
    else observer();
  }, periode);

  // Rouvrir le capot rend la page visible sans qu'un battement soit forcement
  // tombe entre-temps. On verifie donc aussi a ce moment-la.
  const surVisibilite = () => {
    if (document.hidden) return;
    const ecoule = Date.now() - dernier;
    if (estUnReveil(ecoule)) {
      dernier = Date.now();
      auReveil(ecoule);
    }
  };
  document.addEventListener('visibilitychange', surVisibilite);

  return () => {
    clearInterval(battement);
    document.removeEventListener('visibilitychange', surVisibilite);
  };
}

/**
 * Filtre de pertinence pour les sources a recherche floue.
 *
 * Audius rapproche tres librement : sur « fy mitonia » il renvoie deux titres
 * de « zambudaximatonia », au motif que la chaine contient « matonia ». Un
 * resultat qui ne partage aucun mot avec la requete n'a rien a faire dans la
 * liste — mieux vaut zero resultat qu'un faux.
 *
 * Ne s'applique qu'aux sources floues : le catalogue D1 a deja filtre par LIKE,
 * et `search.list` de YouTube est un vrai moteur.
 */

/** Minuscules, accents retires, tout ce qui n'est pas alphanumerique en espace. */
export function normalize(text: string): string {
  return text
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

/**
 * Mots de la requete qui portent du sens.
 *
 * Les mots de moins de trois lettres sont trop permissifs pour servir de
 * critere. Si la requete n'en contient que de courts — « fy », « ro » — on
 * retombe sur la requete entiere, sinon on ne filtrerait plus rien.
 */
export function queryTokens(query: string): string[] {
  const words = normalize(query).split(' ').filter(Boolean);
  const meaningful = words.filter((w) => w.length >= 3);
  if (meaningful.length > 0) return meaningful;
  const whole = normalize(query).replace(/ /g, '');
  return whole ? [whole] : [];
}

/**
 * Vrai si au moins un mot significatif de la requete se retrouve dans le texte.
 *
 * Une requete vide ne filtre rien : on ne veut pas vider une liste par accident.
 */
export function isRelevant(query: string, haystack: string): boolean {
  const tokens = queryTokens(query);
  if (tokens.length === 0) return true;
  const hay = normalize(haystack);
  return tokens.some((token) => hay.includes(token));
}

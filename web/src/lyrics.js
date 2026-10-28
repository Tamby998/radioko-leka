//! Paroles synchronisees : lecture du format LRC et calage sur la position.

/**
 * Parse un fichier `.lrc`. Une ligne peut porter plusieurs horodatages
 * (`[00:12.00][01:30.00]refrain`), c'est courant dans les fichiers publies.
 */
export function parseLrc(texte) {
  const lignes = [];
  for (const brute of texte.split(/\r?\n/)) {
    const tags = [...brute.matchAll(/\[(\d+):(\d+)(?:[.:](\d+))?\]/g)];
    if (tags.length === 0) continue;
    const contenu = brute.replace(/\[[^\]]*\]/g, '').trim();
    if (!contenu) continue;
    for (const [, mm, ss, cs] of tags) {
      const centiemes = cs ? Number(cs.padEnd(3, '0').slice(0, 3)) : 0;
      lignes.push({ atMs: Number(mm) * 60000 + Number(ss) * 1000 + centiemes, text: contenu });
    }
  }
  lignes.sort((a, b) => a.atMs - b.atMs);
  return { instrumental: false, lines: lignes };
}

/**
 * Index de la ligne a surligner, ou -1 avant la premiere.
 * Dichotomie : appelee a chaque image, donc tenue en O(log n).
 */
export function indexA(paroles, positionMs) {
  const lignes = paroles?.lines ?? [];
  let bas = 0;
  let haut = lignes.length;
  let trouve = -1;
  while (bas < haut) {
    const milieu = bas + ((haut - bas) >> 1);
    if (lignes[milieu].atMs <= positionMs) {
      trouve = milieu;
      bas = milieu + 1;
    } else {
      haut = milieu;
    }
  }
  return trouve;
}

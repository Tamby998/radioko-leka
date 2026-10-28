//! Tes propres fichiers, ouverts depuis le navigateur.
//!
//! Rien n'est televerse : `URL.createObjectURL` lit le fichier sur place. Un
//! `.lrc` depose en meme temps que l'audio est rattache par son nom de base,
//! exactement comme la convention du client terminal.

const AUDIO = /\.(mp3|m4a|flac|wav|aac|ogg|opus|aiff)$/i;

const base = (nom) => nom.replace(/\.[^.]+$/, '');

/**
 * Transforme une selection de fichiers en titres jouables.
 *
 * La convention `Artiste - Titre.mp3` est reconnue ; sinon le nom de fichier
 * sert de titre, ce qui vaut toujours mieux que « Inconnu ».
 */
export function depuisFichiers(fichiers) {
  const liste = [...fichiers];
  const lrc = new Map();
  for (const f of liste) {
    if (/\.lrc$/i.test(f.name)) lrc.set(base(f.name).toLowerCase(), f);
  }

  const titres = [];
  for (const f of liste) {
    if (!AUDIO.test(f.name)) continue;
    const nom = base(f.name);
    const separe = nom.split(/\s+-\s+/);
    const [artiste, titre] = separe.length >= 2
      ? [separe[0], separe.slice(1).join(' - ')]
      : ['', nom];

    titres.push({
      uri: `local:${nom}`,
      source: 'local',
      title: titre,
      artists: artiste ? [{ name: artiste }] : [],
      durationMs: 0,
      capabilities: ['stream', 'audioOnly', 'background', 'offline'],
      requiresVisiblePlayer: false,
      streamUrl: URL.createObjectURL(f),
      lrcFile: lrc.get(nom.toLowerCase()) ?? null,
    });
  }
  return titres;
}

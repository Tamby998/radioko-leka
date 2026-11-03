//! Client du Worker Hira. Aucune cle d'API ne vit cote navigateur :
//! la page ne parle qu'au Worker, qui garde les secrets.

/**
 * Adresse du Worker.
 *
 * Le deploye par defaut, pour que la page marche sans rien lancer a cote.
 * `RADIOKOLEKA_API_URL` la remplace quand on developpe contre son propre
 * Worker ; `HIRA_API_URL` est garde parce que le projet s appelait ainsi et
 * que des pages posees ailleurs peuvent encore le definir.
 *
 *   <script>window.RADIOKOLEKA_API_URL = 'http://127.0.0.1:8787'</script>
 */
const DEPLOYE = 'https://radiokoleka-api.radiokoleka.workers.dev';
const BASE = (window.RADIOKOLEKA_API_URL || window.HIRA_API_URL || DEPLOYE)
  .replace(/\/+$/, '');

async function get(chemin, params = {}) {
  const url = new URL(BASE + chemin);
  for (const [cle, valeur] of Object.entries(params)) {
    if (valeur !== undefined && valeur !== null) url.searchParams.set(cle, valeur);
  }
  const reponse = await fetch(url);
  if (!reponse.ok) throw new Error(`${chemin} : ${reponse.status}`);
  return reponse.json();
}

/**
 * Recherche dans les deux catalogues.
 *
 * Contrairement au client terminal, on ne passe pas `audio_only` : dans un
 * navigateur le lecteur officiel existe, donc le catalogue mondial est jouable
 * et n'a aucune raison d'etre filtre.
 */
export async function chercher(requete, limite = 25) {
  const { tracks = [] } = await get('/v1/search', { q: requete, limit: limite });
  return tracks;
}

/** Les genres du catalogue. */
export async function genres() {
  const { genres = [] } = await get('/v1/genres');
  return genres;
}

/** Titres d'un genre. */
export async function genre(slug) {
  const { tracks = [] } = await get(`/v1/genres/${encodeURIComponent(slug)}`);
  return tracks;
}

/** Index des playlists editoriales. */
export async function playlists() {
  const { playlists = [] } = await get('/v1/playlists');
  return playlists;
}

/** Titres d'une playlist, dans l'ordre choisi par l'editeur. */
export async function playlist(slug) {
  const { tracks = [] } = await get(`/v1/playlists/${encodeURIComponent(slug)}`);
  return tracks;
}

export async function classement() {
  const { tracks = [] } = await get('/v1/charts/licensed-trending');
  return tracks;
}

/** Titres a enchainer. Une liste vide n'est pas une erreur. */
export async function similaires(titre) {
  try {
    // L'artiste est transmis : sans lui, un titre absent du catalogue cure n'a
    // pas de graine en base et le serveur repond vide.
    const { tracks = [] } = await get(`/v1/similar/${encodeURIComponent(titre.uri)}`, {
      artist: titre.artists?.[0]?.name ?? '',
    });
    return tracks;
  } catch {
    return [];
  }
}

/** Paroles synchronisees. L'absence de paroles n'est pas une erreur. */
export async function paroles(titre) {
  try {
    const { lyrics } = await get('/v1/lyrics', {
      artist: titre.artists?.[0]?.name ?? '',
      title: titre.title,
      duration: Math.round((titre.durationMs ?? 0) / 1000),
    });
    return lyrics ?? null;
  } catch {
    return null;
  }
}

export async function enLigne() {
  try {
    const { ok } = await get('/v1/health');
    return ok === true;
  } catch {
    return false;
  }
}

/**
 * Attend que le Worker reponde, en espacant les essais.
 *
 * Au reveil, un serveur local met parfois quelques secondes a reprendre, et
 * parfois ne reprend pas du tout. Un seul `enLigne()` ne distingue pas les
 * deux. Les essais cumules couvrent une quinzaine de secondes, apres quoi
 * mieux vaut le dire que laisser croire a une file vide.
 */
export async function attendreLeWorker(essais = 5, palierMs = 1000) {
  for (let i = 0; i < essais; i += 1) {
    if (await enLigne()) return true;
    await new Promise((suite) => setTimeout(suite, palierMs * (i + 1)));
  }
  return false;
}

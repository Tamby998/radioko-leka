import { AudiusSource } from './sources/audius.ts';
import { JamendoSource } from './sources/jamendo.ts';
import { parseVideoId, rangEditorial, YouTubeSource } from './sources/youtube.ts';
import { chercherRadios, paysDisponibles, radiosDuPays } from './sources/radio.ts';
import { resolveVideo } from './sources/oembed.ts';
import { assertCapability, type Track } from './sources/types.ts';
import { fetchLyrics } from './lyrics/lrclib.ts';
import { cachedJson, cacheKey } from './lib/cache.ts';
import { isRelevant } from './lib/relevance.ts';
import { dedupe } from './lib/doublons.ts';
import {
  allGenres,
  allPlaylists,
  genreTracks,
  playlistTracks,
  refusedExternalIds,
  searchCatalogue,
  similarTracks,
  suggestions,
  tracksParArtisteCite,
  trackByUri,
} from './catalogue.ts';

export interface Env {
  DB: D1Database;
  YOUTUBE_API_KEY: string;
  JAMENDO_CLIENT_ID?: string;
  AUDIUS_APP_NAME?: string;
}

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8', ...CORS },
  });

export default {
  async fetch(req: Request, env: Env): Promise<Response> {
    if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });

    const url = new URL(req.url);
    const path = url.pathname.replace(/\/+$/, '') || '/';

    try {
      switch (true) {
        case path === '/':
        case path === '/v1/health':
          return json({ ok: true, service: 'radiokoleka-api', version: '0.1.0' });

        case path === '/v1/search':
          return json(await search(env, url));

        case path === '/v1/suggest':
          return json(await suggest(env, url));

        // L'index des pays avant le prefixe, sinon il est lu comme une requete.
        case path === '/v1/radios/pays':
          return json(await paysRadio(env));

        case path === '/v1/radios':
          return json(await radios(env, url));

        case path === '/v1/lyrics':
          return json(await lyrics(env, url));

        case path === '/v1/resolve':
          return json(await resolve(env, url));

        case path === '/v1/charts/licensed-trending':
          return json(await licensedTrending(env));

        case path === '/v1/genres':
          return json(await genres(env));

        case path.startsWith('/v1/genres/'):
          return json(await genre(env, path.slice('/v1/genres/'.length)));

        // L'index doit passer avant le prefixe, sinon il est lu comme un slug vide.
        case path === '/v1/playlists':
          return json(await playlists(env));

        case path.startsWith('/v1/playlists/'):
          return json(await playlist(env, path.slice('/v1/playlists/'.length)));

        case path.startsWith('/v1/similar/'):
          return json(
            await similar(
              env,
              path.slice('/v1/similar/'.length),
              url.searchParams.get('audio_only') === '1',
              url.searchParams.get('artist') ?? undefined,
              url.searchParams.get('title') ?? undefined,
            ),
          );

        case path.startsWith('/v1/download/'):
          return await downloadManifest(env, path.slice('/v1/download/'.length));

        default:
          return json({ error: 'not_found', path }, 404);
      }
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      return json({ error: 'upstream_error', message }, 502);
    }
  },
};

/**
 * Recherche hybride, du moins cher au plus cher.
 *
 * 1. le catalogue cure en D1 : gratuit, editorial, et il contient les titres
 *    dont on sait que les paroles existent ;
 * 2. les sources sous licence : gratuites aussi, et elles portent le
 *    hors-connexion ;
 * 3. `search.list` de YouTube, 100 unites de quota, uniquement si une cle est
 *    posee et que les deux premiers n'ont pas rempli la demande.
 *
 * Sans `YOUTUBE_API_KEY`, les deux premiers etages suffisent a faire tourner
 * l'application.
 */
async function search(env: Env, url: URL) {
  const q = (url.searchParams.get('q') ?? '').trim();
  if (!q) return { tracks: [] };
  const limit = Math.min(Number(url.searchParams.get('limit') ?? 20), 50);

  // Un client qui ne sait lire que de l'audio — le terminal, par exemple — ne
  // doit jamais recevoir un titre qui exige un lecteur video visible. On evite
  // meme d'appeler search.list : c'est autant de quota economise.
  const audioOnly = url.searchParams.get('audio_only') === '1';

  const key = cacheKey('search', 'v4', audioOnly ? 'audio' : 'all', q, limit);
  return cachedJson(env, key, 60 * 60 * 24, async () => {
    const localAll = await searchCatalogue(env.DB, q, limit).catch(() => []);
    const local = audioOnly ? localAll.filter(playableAsAudio) : localAll;

    const licensed: Promise<Track[]>[] = [
      new AudiusSource(env.AUDIUS_APP_NAME ?? 'hira')
        .search(q, Math.ceil(limit / 2))
        .catch(() => []),
    ];
    if (env.JAMENDO_CLIENT_ID) {
      licensed.push(
        new JamendoSource(env.JAMENDO_CLIENT_ID)
          .search(q, Math.ceil(limit / 4))
          .catch(() => []),
      );
    }

    // Les sources floues passent par le filtre ; le catalogue D1 a deja
    // filtre par LIKE, on ne le repasse pas au tamis.
    const loose = (await Promise.all(licensed))
      .flat()
      .filter((t) =>
        isRelevant(q, `${t.title} ${t.artists.map((a) => a.name).join(' ')}`),
      );

    let results = dedupe([...local, ...loose]);

    // Les radios entrent dans la recherche. La requete ne porte que sur le nom
    // de la station, donc « bruno mars » n'en ramene aucune : c'est
    // auto-limitant, et ca n'encombre pas une recherche musicale.
    const stations = await chercherRadios(q, 12).catch(() => []);
    results = dedupe([...results, ...(audioOnly ? stations : stations)]);

    // Dernier recours seulement : c'est l'appel qui coute du quota.
    if (!audioOnly && results.length < limit && env.YOUTUBE_API_KEY) {
      const remote = await new YouTubeSource(env.YOUTUBE_API_KEY)
        .search(q, limit - results.length)
        .catch(() => []);
      // Un clip deja vu refuser l'integration ne revient pas par la recherche.
      const refuses = await refusedExternalIds(env.DB).catch(() => new Set<string>());
      results = dedupe([
        ...results,
        ...remote.filter((t) => !refuses.has(t.externalId)),
      ]);
    }

    // Classement final, sur la liste fusionnee.
    //
    // Trier a l'interieur du seul bloc YouTube ne suffisait pas : les sources
    // sous licence passent avant lui dans la fusion, si bien qu'une recherche
    // « bruno mars » rendait six reprises avant le premier titre original.
    //
    // Le catalogue cure garde la tete : il est verifie et editorial. Les
    // sources sous licence ne peuvent pas pretendre a l'original — ce sont des
    // mises en ligne d'artistes tiers — donc jamais mieux que le rang neutre.
    const cures = new Set(local.map((t) => t.uri));
    const rang = (t: Track) => {
      if (cures.has(t.uri)) return 0;
      // Une station n'est ni un original ni une reprise : elle est autre chose.
      //
      // Quand la requete **nomme** la station, elle passe devant : chercher
      // « don bosco » et voir huit clips avant Radio Don Bosco n'est pas ce
      // qu'on voulait. Sinon elle reste au rang neutre.
      if (t.source === 'radio') {
        const cherche = q.toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
        const nom = t.title.toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
        return cherche && nom.includes(cherche) ? 0 : 1;
      }
      if (t.rangEditorial !== undefined) return t.rangEditorial;
      return Math.max(1, rangEditorial(`${t.title} ${t.artists[0]?.name ?? ''}`, ''));
    };
    const ordonnes = results
      .map((t, i) => ({ t, r: rang(t), i }))
      .sort((a, b) => a.r - b.r || a.i - b.i)
      .map((x) => x.t);

    return { tracks: ordonnes.slice(0, limit) };
  });
}

/**
 * Radios en direct.
 *
 * Cache six heures : une grille de stations ne bouge pas d'une minute a
 * l'autre, et Radio Browser est un service benevole qu'il serait grossier de
 * marteler. Le code pays entre dans la cle.
 */
async function radios(env: Env, url: URL) {
  const pays = (url.searchParams.get('pays') ?? 'MG').toUpperCase().slice(0, 2);
  const q = (url.searchParams.get('q') ?? '').trim();

  if (q) {
    return cachedJson(env, cacheKey('radios', 'q', q), 60 * 60 * 6, async () => ({
      tracks: await chercherRadios(q).catch(() => []),
    }));
  }
  return cachedJson(env, cacheKey('radios', 'pays', pays), 60 * 60 * 6, async () => ({
    tracks: await radiosDuPays(pays).catch(() => []),
  }));
}

/** Les pays qui ont des radios. Cache une journee : la liste ne bouge guere. */
async function paysRadio(env: Env) {
  return cachedJson(env, cacheKey('radios', 'pays-index'), 60 * 60 * 24, async () => ({
    pays: await paysDisponibles().catch(() => []),
  }));
}

/**
 * Completion de saisie. Le catalogue seulement : gratuit et instantane.
 *
 * Deliberement sans cache : la reponse vient de D1 en une requete, et un cache
 * de 24 h rendrait des propositions perimees apres un seed.
 */
async function suggest(env: Env, url: URL) {
  const q = (url.searchParams.get('q') ?? '').trim();
  if (q.length < 2) return { suggestions: [] };
  const limit = Math.min(Number(url.searchParams.get('limit') ?? 8), 20);
  return { suggestions: await suggestions(env.DB, q, limit).catch(() => []) };
}

/**
 * Suggestions a partir d'un titre, pour enchainer la lecture.
 *
 * Le catalogue cure donne les voisins fiables (meme artiste, meme genre) ; on
 * complete avec les sources sous licence pour ne jamais rendre une file vide.
 */
/**
 * Titres a enchainer.
 *
 * `hint` est le nom d'artiste fourni par le client. Il est indispensable : un
 * titre absent du catalogue cure n'a pas de graine en base, et sans indice la
 * reponse etait vide — c'est-a-dire pour la quasi-totalite des resultats de
 * recherche live. Le client connait l'artiste ; il n'y a aucune raison de le
 * redecouvrir.
 */
async function similar(
  env: Env,
  rawUri: string,
  audioOnly: boolean,
  hintArtist?: string,
  hintTitre?: string,
) {
  const uri = decodeURIComponent(rawUri);
  const limit = 10;

  const indice = hintArtist?.trim().slice(0, 120) ?? '';
  // Le titre entre dans la recherche d'artiste cite, pas dans l'indice envoye
  // aux sources sous licence : « Mr Sayda X Ortegah » credite ORTEGAH, et
  // c'est dans le titre que Mr Sayda apparait.
  const cite = `${indice} ${hintTitre?.trim().slice(0, 160) ?? ''}`.trim();
  const key = cacheKey('similar', 'v5', audioOnly ? 'audio' : 'all', uri, cite);
  return cachedJson(env, key, 60 * 60 * 6, async () => {
    const seed = await trackByUri(env.DB, uri).catch(() => null);
    const localAll = await similarTracks(env.DB, uri, limit).catch(() => []);
    const local = audioOnly ? localAll.filter(playableAsAudio) : localAll;

    let tracks = dedupe(local);

    // Le titre joue n'est pas toujours en base : la recherche live en rend
    // beaucoup. Avant d'aller voir ailleurs, on regarde si un artiste du
    // catalogue est nomme dans l'indice — « Mr Sayda X Ortegah » ne donnait
    // rien alors que Mr Sayda a six titres chez nous.
    if (!seed && tracks.length < limit && cite) {
      const cites = await tracksParArtisteCite(env.DB, cite, limit).catch(() => []);
      const utiles = audioOnly ? cites.filter(playableAsAudio) : cites;
      tracks = dedupe([...tracks, ...utiles]).filter((t) => t.uri !== uri);
    }

    if (tracks.length < limit) {
      // Le nom de l'artiste est le meilleur indice qu'on ait pour elargir.
      const hint = seed?.artists[0]?.name ?? seed?.title ?? indice;
      if (hint) {
        const licensed = (
          await new AudiusSource(env.AUDIUS_APP_NAME ?? 'hira')
            .search(hint, limit - tracks.length)
            .catch(() => [])
        ).filter((t) =>
          isRelevant(hint, `${t.title} ${t.artists.map((a) => a.name).join(' ')}`),
        );
        tracks = dedupe([...tracks, ...licensed]).filter((t) => t.uri !== uri);
      }
    }

    return { uri, tracks: tracks.slice(0, limit) };
  });
}

/** Lisible par un client sans video : capacite `audioOnly` et pas de lecteur impose. */
function playableAsAudio(track: Track): boolean {
  return track.capabilities.includes('audioOnly') && !track.requiresVisiblePlayer;
}

async function genres(env: Env) {
  return cachedJson(env, cacheKey('genres', 'v1'), 60 * 60 * 24, async () => ({
    genres: await allGenres(env.DB),
  }));
}

/**
 * Titres d'un genre.
 *
 * `rotation` est un simple numero de tranche horaire fourni par le client : il
 * entre dans la cle de cache, donc la reponse change a chaque nouvelle tranche
 * sans qu'aucune horloge serveur n'ait a etre accordee avec le client.
 */
async function genre(env: Env, rawSlug: string) {
  const clean = decodeURIComponent(rawSlug).replace(/[^a-z0-9-]/gi, '');
  if (!clean) return { error: 'bad_slug' };
  return cachedJson(env, cacheKey('genre', 'v1', clean), 60 * 60, async () => ({
    slug: clean,
    tracks: await genreTracks(env.DB, clean, 50),
  }));
}

async function playlists(env: Env) {
  return cachedJson(env, cacheKey('playlists', 'v1'), 60 * 60, async () => ({
    playlists: await allPlaylists(env.DB),
  }));
}

async function playlist(env: Env, slug: string) {
  const clean = decodeURIComponent(slug).replace(/[^a-z0-9-]/gi, '');
  if (!clean) return { error: 'bad_slug' };
  return cachedJson(env, cacheKey('playlist', clean), 60 * 60, async () => ({
    slug: clean,
    tracks: await playlistTracks(env.DB, clean),
  }));
}

async function lyrics(env: Env, url: URL) {
  const artistName = url.searchParams.get('artist')?.trim();
  const trackName = url.searchParams.get('title')?.trim();
  if (!artistName || !trackName) {
    return { error: 'missing_params', required: ['artist', 'title'] };
  }
  const durationSec = url.searchParams.get('duration')
    ? Number(url.searchParams.get('duration'))
    : undefined;

  return cachedJson(
    env,
    cacheKey('lyrics', artistName, trackName, durationSec),
    60 * 60 * 24 * 30,
    async () => ({ lyrics: await fetchLyrics({ artistName, trackName, durationSec }) }),
  );
}

/**
 * Resout un lien YouTube colle en titre jouable.
 *
 * La duree n'etant pas fournie par oEmbed, on interroge LRCLIB : s'il connait
 * le morceau, sa duree est fiable et sert aussi a caler les paroles.
 */
async function resolve(env: Env, url: URL) {
  const input = (url.searchParams.get('url') ?? '').trim();
  if (!input) return { error: 'missing_params', required: ['url'] };

  const videoId = parseVideoId(input);
  if (!videoId) return { error: 'not_a_youtube_link', input };

  return cachedJson(env, cacheKey('resolve', videoId), 60 * 60 * 24 * 7, async () => {
    const track = await resolveVideo(videoId);
    if (!track) return { error: 'video_unavailable', videoId };

    const found = await fetchLyrics({
      artistName: track.artists[0]?.name ?? '',
      trackName: track.title,
    }).catch(() => null);

    return {
      track: found?.durationMs ? { ...track, durationMs: found.durationMs } : track,
      lyricLines: found?.lines.length ?? 0,
    };
  });
}

async function licensedTrending(env: Env) {
  return cachedJson(env, 'charts|licensed-trending', 60 * 60 * 6, async () => {
    const tracks = await new AudiusSource(env.AUDIUS_APP_NAME ?? 'hira').trending(50);
    return { slug: 'licensed-trending', tracks };
  });
}

/**
 * Le client demande ici le feu vert avant d'ecrire un fichier. Un titre
 * YouTube ne porte pas la capacite `offline` : la requete est refusee ici, et
 * une seconde fois cote client. Deux verrous, aucun oubli possible.
 */
async function downloadManifest(env: Env, uri: string): Promise<Response> {
  const decoded = decodeURIComponent(uri);
  const [source, externalId] = decoded.split(':');
  if (!source || !externalId) return json({ error: 'bad_uri', uri: decoded }, 400);

  if (source === 'youtube') {
    return json(
      {
        error: 'not_downloadable',
        reason:
          'Le catalogue YouTube se lit dans le lecteur officiel. ' +
          'Le hors-connexion est reserve au catalogue sous licence.',
      },
      403,
    );
  }

  const audius = new AudiusSource(env.AUDIUS_APP_NAME ?? 'hira');
  const [track] = await audius.tracksByIds([externalId]);
  if (!track) return json({ error: 'not_found', uri: decoded }, 404);

  assertCapability(track, 'offline');
  return json({
    uri: track.uri,
    streamUrl: track.streamUrl,
    durationMs: track.durationMs,
  });
}


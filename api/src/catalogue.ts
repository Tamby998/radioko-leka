/**
 * Catalogue cure en base.
 *
 * C'est ce qui protege le quota YouTube Data API : la recherche tape D1
 * d'abord, et `search.list` (100 unites) ne sert qu'en dernier recours, pour
 * les requetes qu'aucun titre en base ne couvre.
 *
 * Aucune parole n'est stockee ici : elles sont recuperees a la lecture.
 */

import type { Capability, SourceId, Track } from './sources/types.ts';

interface CatalogueRow {
  uri: string;
  source: string;
  external_id: string;
  title: string;
  duration_ms: number;
  artwork_url: string | null;
  capabilities: string;
  view_count: number | null;
  artist_uri: string | null;
  artist_name: string | null;
  artist_avatar: string | null;
}

const COLONNES = `
  t.uri, t.source, t.external_id, t.title, t.duration_ms, t.artwork_url,
  t.capabilities, t.view_count,
  a.uri AS artist_uri, a.name AS artist_name, a.avatar_url AS artist_avatar
`;

const SELECT = `
  SELECT ${COLONNES}
  FROM tracks t
  LEFT JOIN artists a ON a.uri = t.artist_uri
`;

/** Recherche sur le titre et sur le nom d'artiste, insensible a la casse. */
export interface GenreSummary {
  slug: string;
  label: string;
  tagline: string;
  count: number;
  /** Jusqu'a quatre pochettes, pour composer une mosaique cote client. */
  pochettes: string[];
}

interface GenreRow {
  slug: string;
  label: string;
  tagline: string | null;
  count: number;
  pochettes: string | null;
}

export interface PlaylistSummary {
  slug: string;
  title: string;
  kind: string;
  description: string;
  count: number;
  pochettes: string[];
}

interface PlaylistRow {
  slug: string;
  title: string;
  kind: string;
  description: string | null;
  count: number;
  pochettes: string | null;
}

export async function searchCatalogue(
  db: D1Database,
  query: string,
  limit: number,
): Promise<Track[]> {
  const like = `%${query.toLowerCase()}%`;
  const { results } = await db
    .prepare(
      `${SELECT}
       WHERE lower(t.title) LIKE ?1 OR lower(coalesce(a.name, '')) LIKE ?1
       -- Les titres sans compteur passent apres, sans dependre de NULLS LAST.
       ORDER BY t.view_count IS NULL, t.view_count DESC, t.title
       LIMIT ?2`,
    )
    .bind(like, limit)
    .all<CatalogueRow>();

  return (results ?? []).map(toTrack);
}

/** Titres d'une playlist editoriale, dans l'ordre choisi. */
export async function playlistTracks(db: D1Database, slug: string): Promise<Track[]> {
  const { results } = await db
    .prepare(
      `${SELECT}
       JOIN playlist_items pi ON pi.track_uri = t.uri
       WHERE pi.playlist_slug = ?1
       ORDER BY pi.position`,
    )
    .bind(slug)
    .all<CatalogueRow>();

  return (results ?? []).map(toTrack);
}

/** Un titre precis du catalogue, ou `null` s'il n'y est pas. */
/**
 * Index des playlists editoriales, la plus recemment mise a jour en tete.
 *
 * Le compte de titres vient du meme appel : une playlist vide ne doit pas
 * apparaitre comme un rayon ouvrable sur du rien.
 */
export async function allPlaylists(db: D1Database): Promise<PlaylistSummary[]> {
  const { results } = await db
    .prepare(
      `SELECT p.slug, p.title, p.kind, p.description, COUNT(pi.track_uri) AS count,
              (SELECT group_concat(a.url, '|') FROM (
                 SELECT t.artwork_url AS url
                 FROM playlist_items x
                 JOIN tracks t ON t.uri = x.track_uri
                 WHERE x.playlist_slug = p.slug AND t.artwork_url IS NOT NULL
                 ORDER BY x.position
                 LIMIT 4
               ) a) AS pochettes
       FROM playlists p
       LEFT JOIN playlist_items pi ON pi.playlist_slug = p.slug
       GROUP BY p.slug
       HAVING count > 0
       ORDER BY p.updated_at DESC`,
    )
    .all<PlaylistRow>();

  return (results ?? []).map((row) => ({
    slug: row.slug,
    title: row.title,
    kind: row.kind,
    description: row.description ?? '',
    count: Number(row.count ?? 0),
    pochettes: row.pochettes?.split('|').filter(Boolean) ?? [],
  }));
}

/** Les genres du catalogue, dans l'ordre editorial, les vides exclus. */
export async function allGenres(db: D1Database): Promise<GenreSummary[]> {
  const { results } = await db
    .prepare(
      // Seuls les genres racine sont des rayons : un sous-genre sert a enchainer
      // entre proches, pas a decouper la page d'accueil en vingt etageres.
      // Les quatre pochettes viennent des titres les plus vus du rayon, par une
      // sous-requete correlee : une mosaique se compose cote client, et faire
      // huit appels de plus pour quatre images serait absurde.
      `SELECT g.slug, g.label, g.tagline, COUNT(tg.track_uri) AS count,
              (SELECT group_concat(a.url, '|') FROM (
                 SELECT t.artwork_url AS url
                 FROM track_genres x
                 JOIN tracks t ON t.uri = x.track_uri
                 WHERE x.genre_slug = g.slug AND t.artwork_url IS NOT NULL
                 ORDER BY t.view_count IS NULL, t.view_count DESC
                 LIMIT 4
               ) a) AS pochettes
       FROM genres g
       LEFT JOIN track_genres tg ON tg.genre_slug = g.slug
       WHERE g.parent IS NULL
       GROUP BY g.slug
       HAVING count > 0
       ORDER BY g.position, g.label`,
    )
    .all<GenreRow>();

  return (results ?? []).map((row) => ({
    slug: row.slug,
    label: row.label,
    tagline: row.tagline ?? '',
    count: Number(row.count ?? 0),
    pochettes: row.pochettes?.split('|').filter(Boolean) ?? [],
  }));
}

/** Titres d'un genre, les plus vus d'abord. */
export async function genreTracks(
  db: D1Database,
  slug: string,
  limit: number,
): Promise<Track[]> {
  const { results } = await db
    .prepare(
      `${SELECT}
       JOIN track_genres tg ON tg.track_uri = t.uri
       WHERE tg.genre_slug = ?1
       ORDER BY t.view_count IS NULL, t.view_count DESC, t.title
       LIMIT ?2`,
    )
    .bind(slug, limit)
    .all<CatalogueRow>();

  return (results ?? []).map(toTrack);
}

export async function trackByUri(db: D1Database, uri: string): Promise<Track | null> {
  const row = await db
    .prepare(`${SELECT} WHERE t.uri = ?1`)
    .bind(uri)
    .first<CatalogueRow>();
  return row ? toTrack(row) : null;
}

/**
 * Titres proches, du plus proche au plus large.
 *
 * Trois paliers, dans cet ordre : meme artiste, puis meme sous-genre, puis
 * meme genre. Le palier intermediaire est ce qui empeche « Hay hay » de
 * Mahaleo d'enchainer sur du rap gasy : les deux partagent le genre `gasy`,
 * mais pas le style, et les treize titres de `gasy-folk` passent avant.
 *
 * Le `CASE` est calcule dans une sous-requete parce que SQLite ne sait pas
 * relire un alias de resultat depuis le `WHERE` : `rang IS NULL` elimine les
 * titres qui ne partagent rien, sans repeter la condition.
 */
export async function similarTracks(
  db: D1Database,
  uri: string,
  limit: number,
): Promise<Track[]> {
  const { results } = await db
    .prepare(
      `SELECT * FROM (
         SELECT ${COLONNES},
           CASE
             WHEN t.artist_uri = (SELECT artist_uri FROM tracks WHERE uri = ?1)
               THEN 0
             WHEN EXISTS (
               SELECT 1 FROM track_genres cur
               JOIN genres g ON g.slug = cur.genre_slug
               WHERE cur.track_uri = t.uri
                 AND g.parent IS NOT NULL
                 AND cur.genre_slug IN (
                   SELECT src.genre_slug FROM track_genres src
                   JOIN genres gs ON gs.slug = src.genre_slug
                   WHERE src.track_uri = ?1 AND gs.parent IS NOT NULL
                 )
             ) THEN 1
             WHEN EXISTS (
               SELECT 1 FROM track_genres cur
               WHERE cur.track_uri = t.uri
                 AND cur.genre_slug IN (
                   SELECT src.genre_slug FROM track_genres src
                   JOIN genres gs ON gs.slug = src.genre_slug
                   WHERE src.track_uri = ?1 AND gs.parent IS NULL
                 )
             ) THEN 2
           END AS rang
         FROM tracks t
         LEFT JOIN artists a ON a.uri = t.artist_uri
         WHERE t.uri != ?1
       )
       WHERE rang IS NOT NULL
       ORDER BY rang, view_count IS NULL, view_count DESC, title
       LIMIT ?2`,
    )
    .bind(uri, limit)
    .all<CatalogueRow>();

  return (results ?? []).map(toTrack);
}

/**
 * Titres du catalogue dont l'artiste est nomme dans un texte libre.
 *
 * Sert aux titres qui ne sont pas en base — ceux que la recherche live rend.
 * Leur voisinage passait par les sources sous licence, qui n'ont presque rien
 * de malgache : « Mr Sayda X Ortegah » rendait zero suggestion alors que Mr
 * Sayda a six titres chez nous. On cherche donc d'abord si un artiste du
 * catalogue est cite dans l'artiste ou le titre du morceau joue.
 *
 * La comparaison se fait sur le texte normalise, sans quoi « Mr SAYDA » et
 * « Mr Sayda » ne se reconnaissent pas.
 */
export async function tracksParArtisteCite(
  db: D1Database,
  texte: string,
  limit: number,
): Promise<Track[]> {
  const plat = texte.toLowerCase().replace(/[^a-z0-9]+/g, ' ');
  const { results: noms } = await db
    .prepare(`SELECT uri, name FROM artists`)
    .all<{ uri: string; name: string }>();

  const cites = (noms ?? []).filter((a) => {
    const nom = a.name.toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
    // Les noms d'une lettre ou deux provoqueraient des rapprochements absurdes.
    return nom.length >= 3 && plat.includes(nom);
  });
  if (!cites.length) return [];

  const marques = cites.map(() => '?').join(',');
  const { results } = await db
    .prepare(
      `${SELECT}
       WHERE t.artist_uri IN (${marques})
       ORDER BY t.view_count IS NULL, t.view_count DESC, t.title
       LIMIT ?${cites.length + 1}`,
    )
    .bind(...cites.map((a) => a.uri), limit)
    .all<CatalogueRow>();

  return (results ?? []).map(toTrack);
}

/**
 * Propositions de saisie, tirees du catalogue.
 *
 * Gratuit et instantane : c'est D1 qui repond, pas YouTube. Une completion qui
 * interrogerait `search.list` a chaque frappe couterait 100 unites par lettre
 * et viderait le quota du jour en une phrase.
 *
 * Les artistes passent avant les titres : en tapant trois lettres on cherche
 * presque toujours quelqu'un.
 */
export async function suggestions(
  db: D1Database,
  requete: string,
  limit: number,
): Promise<string[]> {
  const like = `${requete.toLowerCase()}%`;
  const dedans = `%${requete.toLowerCase()}%`;
  const { results } = await db
    .prepare(
      `SELECT texte, rang FROM (
         SELECT DISTINCT a.name AS texte,
                CASE WHEN lower(a.name) LIKE ?1 THEN 0 ELSE 1 END AS rang
         FROM artists a
         WHERE lower(a.name) LIKE ?2
         UNION
         SELECT DISTINCT t.title,
                CASE WHEN lower(t.title) LIKE ?1 THEN 2 ELSE 3 END
         FROM tracks t
         WHERE lower(t.title) LIKE ?2
       )
       ORDER BY rang, length(texte), texte
       LIMIT ?3`,
    )
    .bind(like, dedans, limit)
    .all<{ texte: string }>();

  return (results ?? []).map((r) => r.texte);
}

/**
 * Identifiants des clips que le banc a vus refuser l'integration.
 *
 * Les retirer de `tracks` ne suffit pas : `search.list` ignore la purge et les
 * rend encore. Sans cette memoire, un clip purge revient en tete de recherche
 * et se barre a la lecture — ce qui est pire qu'un clip absent, puisqu'il
 * occupe une place.
 */
export async function refusedExternalIds(db: D1Database): Promise<Set<string>> {
  const { results } = await db
    .prepare(`SELECT external_id FROM clips_refuses`)
    .all<{ external_id: string }>();
  return new Set((results ?? []).map((r) => r.external_id));
}

const KNOWN: readonly Capability[] = ['stream', 'audioOnly', 'background', 'offline'];

/** Capacites serialisees en base -> capacites typees, les inconnues ecartees. */
export function parseCapabilities(raw: string): Capability[] {
  return raw
    .split(',')
    .map((c) => c.trim())
    .filter((c): c is Capability => (KNOWN as readonly string[]).includes(c));
}

function toTrack(row: CatalogueRow): Track {
  const source = row.source as SourceId;
  return {
    uri: row.uri,
    source,
    externalId: row.external_id,
    title: row.title,
    artists: row.artist_name
      ? [
          {
            id: row.artist_uri ?? row.artist_name,
            source,
            name: row.artist_name,
            avatarUrl: row.artist_avatar ?? undefined,
          },
        ]
      : [],
    durationMs: row.duration_ms,
    artworkUrl: row.artwork_url ?? undefined,
    capabilities: parseCapabilities(row.capabilities),
    // Le catalogue mondial impose le lecteur officiel ; les sources sous
    // licence n'ont pas de video a montrer.
    requiresVisiblePlayer: source === 'youtube',
    // Jamais de flux direct pour YouTube : la lecture passe par le lecteur.
    streamUrl: undefined,
    viewCount: row.view_count ?? undefined,
  };
}

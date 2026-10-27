/**
 * Paroles synchronisees via LRCLIB (lrclib.net) : gratuit, sans cle, sans quota.
 *
 * Le Worker ne stocke que le resultat en cache technique, indexe sur
 * (artiste, titre, duree), pour epargner l'API publique.
 */

export interface LyricsLine {
  /** Position de la ligne depuis le debut du titre. */
  atMs: number;
  text: string;
}

export interface SyncedLyrics {
  source: 'lrclib';
  trackName: string;
  artistName: string;
  durationMs: number;
  instrumental: boolean;
  lines: LyricsLine[];
  /** LRC brut, utile au client pour une correction locale par l'utilisateur. */
  raw?: string;
}

const ENDPOINT = 'https://lrclib.net/api';
const USER_AGENT = 'Hira/0.1.0 (https://github.com/hira-app)';

export interface LyricsQuery {
  artistName: string;
  trackName: string;
  albumName?: string;
  durationSec?: number;
}

/**
 * Artiste principal d'un credit multiple.
 *
 * LRCLIB indexe « KAROL G », pas « KAROL G, Bruno Mars ». Quand le credit
 * complet ne donne rien, on retente avec le premier nom seul.
 */
export function primaryArtist(credited: string): string {
  return credited.split(/\s*(?:,|&|\bfeat\.?\b|\bft\.?\b|\bx\b)\s*/i)[0].trim();
}

/**
 * Cherche des paroles synchronisees, du plus precis au plus large.
 *
 * 1. correspondance exacte, duree comprise ;
 * 2. la meme sans la duree — un clip porte souvent quelques secondes d'intro
 *    que l'enregistrement audio n'a pas, et LRCLIB est strict la-dessus ;
 * 3. recherche approchee, credit complet puis artiste principal seul.
 */
export async function fetchLyrics(q: LyricsQuery): Promise<SyncedLyrics | null> {
  const exact = await getLyrics(q, q.durationSec);
  if (exact) return exact;

  if (q.durationSec !== undefined) {
    const withoutDuration = await getLyrics(q, undefined);
    if (withoutDuration) return withoutDuration;
  }

  for (const artist of candidateArtists(q.artistName)) {
    const found = await searchLyrics(artist, q.trackName, q.durationSec);
    if (found) return found;
  }

  return null;
}

function candidateArtists(credited: string): string[] {
  const main = primaryArtist(credited);
  return main && main !== credited ? [credited, main] : [credited];
}

async function getLyrics(
  q: LyricsQuery,
  durationSec: number | undefined,
): Promise<SyncedLyrics | null> {
  const url = new URL(`${ENDPOINT}/get`);
  url.searchParams.set('artist_name', q.artistName);
  url.searchParams.set('track_name', q.trackName);
  if (q.albumName) url.searchParams.set('album_name', q.albumName);
  if (durationSec) url.searchParams.set('duration', String(Math.round(durationSec)));

  const res = await fetch(url, { headers: { 'User-Agent': USER_AGENT } });
  if (!res.ok) return null;

  const record = (await res.json()) as LrclibRecord;
  return record.syncedLyrics ? toSynced(record) : null;
}

async function searchLyrics(
  artistName: string,
  trackName: string,
  durationSec?: number,
): Promise<SyncedLyrics | null> {
  const url = new URL(`${ENDPOINT}/search`);
  url.searchParams.set('artist_name', artistName);
  url.searchParams.set('track_name', trackName);

  const res = await fetch(url, { headers: { 'User-Agent': USER_AGENT } });
  if (!res.ok) return null;

  const list = (await res.json()) as LrclibRecord[];
  const best = pickBest(list, durationSec);
  return best ? toSynced(best) : null;
}

/** Prefere la version dont la duree colle le mieux : meilleure synchro. */
function pickBest(list: LrclibRecord[], durationSec?: number): LrclibRecord | null {
  const synced = list.filter((r) => r.syncedLyrics);
  const pool = synced.length ? synced : list;
  if (!pool.length) return null;
  if (!durationSec) return pool[0];
  return pool.reduce((best, cur) =>
    Math.abs((cur.duration ?? 0) - durationSec) <
    Math.abs((best.duration ?? 0) - durationSec)
      ? cur
      : best,
  );
}

function toSynced(r: LrclibRecord): SyncedLyrics {
  return {
    source: 'lrclib',
    trackName: r.trackName,
    artistName: r.artistName,
    durationMs: Math.round((r.duration ?? 0) * 1000),
    instrumental: Boolean(r.instrumental),
    lines: parseLrc(r.syncedLyrics ?? ''),
    raw: r.syncedLyrics ?? undefined,
  };
}

interface LrclibRecord {
  id?: number;
  trackName: string;
  artistName: string;
  duration?: number;
  instrumental?: boolean;
  syncedLyrics?: string | null;
  plainLyrics?: string | null;
}

const TIMESTAMP = /\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]/g;

/**
 * Parse un LRC en lignes horodatees.
 *
 * Gere les horodatages multiples sur une meme ligne (`[00:12.00][01:44.00] ...`),
 * ignore les balises de metadonnees (`[ar:]`, `[length:]`), et tolere des
 * centiemes sur 1 a 3 chiffres.
 */
export function parseLrc(lrc: string): LyricsLine[] {
  const lines: LyricsLine[] = [];

  for (const rawLine of lrc.split(/\r?\n/)) {
    TIMESTAMP.lastIndex = 0;
    const stamps: number[] = [];
    let lastEnd = 0;
    let m: RegExpExecArray | null;

    while ((m = TIMESTAMP.exec(rawLine)) !== null) {
      // Un horodatage ne compte que s'il prefixe la ligne, sans texte avant.
      if (m.index !== lastEnd) break;
      lastEnd = m.index + m[0].length;
      const [, mm, ss, frac] = m;
      const fraction = frac ? Number(frac.padEnd(3, '0')) : 0;
      stamps.push(Number(mm) * 60_000 + Number(ss) * 1000 + fraction);
    }

    if (!stamps.length) continue;
    const text = rawLine.slice(lastEnd).trim();
    for (const atMs of stamps) lines.push({ atMs, text });
  }

  return lines.sort((a, b) => a.atMs - b.atMs);
}

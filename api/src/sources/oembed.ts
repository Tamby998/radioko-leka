/**
 * Resolution d'un lien YouTube colle, sans clé d'API.
 *
 * oEmbed est l'endpoint officiel d'integration : il donne le titre et la
 * chaine d'une vidéo publique, ce qui suffit a construire un titre jouable et
 * a chercher ses paroles. Pas de quota, pas de clé, pas de scraping.
 *
 * Ce qu'il ne donne pas : la duree. Elle vient de LRCLIB quand il connait le
 * morceau, sinon elle reste inconnue et le lecteur attend que l'utilisateur
 * rende la main.
 */

import { type Artist, type Track, YOUTUBE_CAPABILITIES } from './types.ts';
import { splitCreditedTitle } from './youtube.ts';

interface OEmbed {
  title?: string;
  author_name?: string;
  thumbnail_url?: string;
}

export async function resolveVideo(videoId: string): Promise<Track | null> {
  const endpoint = new URL('https://www.youtube.com/oembed');
  endpoint.searchParams.set('url', `https://www.youtube.com/watch?v=${videoId}`);
  endpoint.searchParams.set('format', 'json');

  const res = await fetch(endpoint, { headers: { 'User-Agent': 'Hira/0.1.0' } });
  // 401/404 : vidéo privee, supprimee, ou identifiant invente.
  if (!res.ok) return null;

  const body = (await res.json()) as OEmbed;
  const credited = body.title ?? '';
  const channel = (body.author_name ?? '').replace(/VEVO$/i, '').trim();
  const { artist, title } = splitCreditedTitle(credited);

  const named: Artist = {
    id: `youtube:channel:${channel || videoId}`,
    source: 'youtube',
    name: artist || channel || 'Artiste inconnu',
  };

  return {
    uri: `youtube:${videoId}`,
    source: 'youtube',
    externalId: videoId,
    title: title || credited || videoId,
    artists: [named],
    // Inconnue a ce stade : l'appelant la complete si LRCLIB la donne.
    durationMs: 0,
    artworkUrl: body.thumbnail_url ?? `https://i.ytimg.com/vi/${videoId}/hqdefault.jpg`,
    capabilities: YOUTUBE_CAPABILITIES,
    requiresVisiblePlayer: true,
    // Jamais de flux direct : la lecture passe par le lecteur officiel.
    streamUrl: undefined,
  };
}

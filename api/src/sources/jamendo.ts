import {
  type Capability,
  LICENSED_CAPABILITIES,
  type MusicSource,
  type Track,
} from './types.ts';

/**
 * Catalogue sous licence Creative Commons. Meme jeu de capacites qu'Audius.
 * Necessite un client_id Jamendo (gratuit, inscription developpeur).
 */
export class JamendoSource implements MusicSource {
  readonly id = 'jamendo' as const;
  readonly capabilities: readonly Capability[] = LICENSED_CAPABILITIES;

  private readonly clientId: string;

  constructor(clientId: string) {
    this.clientId = clientId;
  }

  async search(query: string, limit = 20): Promise<Track[]> {
    const url = this.#endpoint('tracks', { search: query, limit: String(limit) });
    return this.#fetchTracks(url);
  }

  async tracksByIds(ids: string[]): Promise<Track[]> {
    const url = this.#endpoint('tracks', {
      id: ids.join('+'),
      limit: String(ids.length),
    });
    return this.#fetchTracks(url);
  }

  #endpoint(path: string, params: Record<string, string>): URL {
    const url = new URL(`https://api.jamendo.com/v3.0/${path}`);
    url.searchParams.set('client_id', this.clientId);
    url.searchParams.set('format', 'json');
    url.searchParams.set('audioformat', 'mp32');
    for (const [k, v] of Object.entries(params)) url.searchParams.set(k, v);
    return url;
  }

  async #fetchTracks(url: URL): Promise<Track[]> {
    const res = await fetch(url);
    if (!res.ok) throw new Error(`Jamendo ${res.status}: ${await res.text()}`);
    const body = (await res.json()) as { results?: JamendoTrack[] };
    return (body.results ?? []).map((t) => ({
      uri: `jamendo:${t.id}`,
      source: this.id,
      externalId: t.id,
      title: t.name,
      artists: [{ id: t.artist_id, source: this.id, name: t.artist_name }],
      durationMs: (t.duration ?? 0) * 1000,
      artworkUrl: t.image,
      capabilities: this.capabilities,
      requiresVisiblePlayer: false,
      streamUrl: t.audio,
    }));
  }
}

interface JamendoTrack {
  id: string;
  name: string;
  duration?: number;
  artist_id: string;
  artist_name: string;
  image?: string;
  audio?: string;
}

import {
  type Capability,
  LICENSED_CAPABILITIES,
  type MusicSource,
  type Track,
} from './types.ts';

/**
 * Catalogue sous licence — audio publie par les artistes eux-memes.
 *
 * Porte toutes les capacites : telechargement, hors-connexion et lecture
 * ecran verrouille passent par ici.
 */
export class AudiusSource implements MusicSource {
  readonly id = 'audius' as const;
  readonly capabilities: readonly Capability[] = LICENSED_CAPABILITIES;

  #host?: string;

  private readonly appName: string;

  constructor(appName: string) {
    this.appName = appName;
  }

  /** Audius est federe : on resout un noeud, puis on le garde. */
  async #resolveHost(): Promise<string> {
    if (this.#host) return this.#host;
    const res = await fetch('https://api.audius.co');
    if (!res.ok) throw new Error(`Audius discovery ${res.status}`);
    const body = (await res.json()) as { data?: string[] };
    const host = body.data?.[0];
    if (!host) throw new Error('Aucun noeud Audius disponible');
    this.#host = host;
    return host;
  }

  async search(query: string, limit = 20): Promise<Track[]> {
    const host = await this.#resolveHost();
    const url = new URL(`${host}/v1/tracks/search`);
    url.searchParams.set('query', query);
    url.searchParams.set('limit', String(Math.min(limit, 100)));
    url.searchParams.set('app_name', this.appName);
    return this.#fetchTracks(url);
  }

  async trending(limit = 50): Promise<Track[]> {
    const host = await this.#resolveHost();
    const url = new URL(`${host}/v1/tracks/trending`);
    url.searchParams.set('limit', String(Math.min(limit, 100)));
    url.searchParams.set('app_name', this.appName);
    return this.#fetchTracks(url);
  }

  async tracksByIds(ids: string[]): Promise<Track[]> {
    const host = await this.#resolveHost();
    const results = await Promise.all(
      ids.map(async (id) => {
        const url = new URL(`${host}/v1/tracks/${encodeURIComponent(id)}`);
        url.searchParams.set('app_name', this.appName);
        const tracks = await this.#fetchTracks(url);
        return tracks[0];
      }),
    );
    return results.filter((t): t is Track => Boolean(t));
  }

  async #fetchTracks(url: URL): Promise<Track[]> {
    const res = await fetch(url);
    if (!res.ok) throw new Error(`Audius ${res.status}: ${await res.text()}`);
    const body = (await res.json()) as { data?: AudiusTrack[] | AudiusTrack };
    const raw = Array.isArray(body.data) ? body.data : body.data ? [body.data] : [];
    const host = await this.#resolveHost();
    return raw.map((t) => this.#toTrack(t, host));
  }

  #toTrack(t: AudiusTrack, host: string): Track {
    const stream = new URL(`${host}/v1/tracks/${t.id}/stream`);
    stream.searchParams.set('app_name', this.appName);
    return {
      uri: `audius:${t.id}`,
      source: this.id,
      externalId: t.id,
      title: t.title,
      artists: [
        {
          id: t.user.id,
          source: this.id,
          name: t.user.name,
          avatarUrl: t.user.profile_picture?.['480x480'],
          followers: t.user.follower_count,
        },
      ],
      durationMs: (t.duration ?? 0) * 1000,
      artworkUrl: t.artwork?.['1000x1000'] ?? t.artwork?.['480x480'],
      capabilities: this.capabilities,
      requiresVisiblePlayer: false,
      streamUrl: stream.toString(),
      viewCount: t.play_count,
    };
  }
}

interface AudiusTrack {
  id: string;
  title: string;
  duration?: number;
  play_count?: number;
  artwork?: Record<string, string>;
  user: {
    id: string;
    name: string;
    follower_count?: number;
    profile_picture?: Record<string, string>;
  };
}

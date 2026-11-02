import {
  type Artist,
  type Capability,
  type MusicSource,
  type Track,
  YOUTUBE_CAPABILITIES,
} from './types.ts';

/**
 * Catalogue mondial — metadonnees uniquement.
 *
 * Cette source ne renvoie jamais de `streamUrl` : la lecture se fait par le
 * lecteur IFrame officiel cote client, ce qui garde la vue sur la chaine de
 * l'artiste. Aucun flux n'est extrait ni stocke.
 */
export class YouTubeSource implements MusicSource {
  readonly id = 'youtube' as const;
  readonly capabilities: readonly Capability[] = YOUTUBE_CAPABILITIES;

  private readonly apiKey: string;

  constructor(apiKey: string) {
    this.apiKey = apiKey;
  }

  /** 100 unites de quota. Reserve aux requetes absentes du catalogue cure. */
  async search(query: string, limit = 20): Promise<Track[]> {
    const url = new URL('https://www.googleapis.com/youtube/v3/search');
    url.searchParams.set('part', 'snippet');
    url.searchParams.set('type', 'video');
    url.searchParams.set('videoCategoryId', '10'); // Musique
    url.searchParams.set('maxResults', String(Math.min(limit, 50)));
    url.searchParams.set('q', query);
    url.searchParams.set('key', this.apiKey);

    const ids = await this.#ids(url);
    if (!ids.length) return [];
    const trouves = await this.tracksByIds(ids, true);
    return trouves;
  }

  /** 1 unite pour 50 IDs. C'est le chemin a privilegier. */
  async tracksByIds(ids: string[], classer = false): Promise<Track[]> {
    const out: Track[] = [];
    for (let i = 0; i < ids.length; i += 50) {
      const batch = ids.slice(i, i + 50);
      const url = new URL('https://www.googleapis.com/youtube/v3/videos');
      // `status` porte `embeddable`. Il ne coute rien de plus : videos.list
      // facture 1 unite par appel, pas par partie demandee.
      url.searchParams.set('part', 'snippet,contentDetails,statistics,status');
      url.searchParams.set('id', batch.join(','));
      url.searchParams.set('key', this.apiKey);

      const res = await fetch(url);
      if (!res.ok) {
        throw new Error(`YouTube videos.list ${res.status}: ${await res.text()}`);
      }
      const body = (await res.json()) as { items?: YouTubeVideo[] };
      for (const item of body.items ?? []) {
        const rang = classer
          ? rangEditorial(item.snippet.title, item.snippet.channelTitle)
          : undefined;
        // Un clip dont l'ayant droit interdit l'integration ne peut pas jouer
        // dans la page : le lecteur affiche « video non disponible » et renvoie
        // l'utilisateur sur youtube.com. Mieux vaut ne jamais le proposer.
        if (item.status?.embeddable === false) continue;
        out.push({ ...this.#toTrack(item), rangEditorial: rang });
      }
    }
    // Tri stable : a rang egal, l'ordre de pertinence de YouTube est garde.
    if (classer) {
      out.sort((a, b) => (a.rangEditorial ?? 1) - (b.rangEditorial ?? 1));
    }
    return out;
  }

  async #ids(url: URL): Promise<string[]> {
    const res = await fetch(url);
    if (!res.ok) {
      throw new Error(`YouTube search.list ${res.status}: ${await res.text()}`);
    }
    const body = (await res.json()) as { items?: { id?: { videoId?: string } }[] };
    return (body.items ?? [])
      .map((i) => i.id?.videoId)
      .filter((v): v is string => Boolean(v));
  }

  #toTrack(v: YouTubeVideo): Track {
    // Le titre d'un clip credite presque toujours l'artiste avant un tiret.
    // L'ignorer laisse « Bruno Mars - Talking To The Moon » comme titre, ce
    // qu'aucune base de paroles ne reconnait — et met le nom de la chaine
    // (« 7clouds », « Vibe Music ») a la place de l'artiste. C'est le meme
    // decoupage que celui applique au catalogue cure par `oembed.ts`.
    const credited = splitCreditedTitle(v.snippet.title);
    const artist: Artist = {
      id: v.snippet.channelId,
      source: this.id,
      name: credited.artist || v.snippet.channelTitle,
    };
    return {
      uri: `youtube:${v.id}`,
      source: this.id,
      externalId: v.id,
      title: credited.title,
      artists: [artist],
      durationMs: parseIsoDuration(v.contentDetails.duration),
      artworkUrl: `https://i.ytimg.com/vi/${v.id}/maxresdefault.jpg`,
      capabilities: this.capabilities,
      requiresVisiblePlayer: true,
      // streamUrl volontairement absent.
      viewCount: v.statistics?.viewCount ? Number(v.statistics.viewCount) : undefined,
    };
  }
}

interface YouTubeVideo {
  id: string;
  snippet: { title: string; channelId: string; channelTitle: string };
  contentDetails: { duration: string };
  statistics?: { viewCount?: string };
  status?: { embeddable?: boolean; privacyStatus?: string };
}

/** `PT4M13S` -> 253000 */
export function parseIsoDuration(iso: string): number {
  const m = /^P(?:(\d+)D)?T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$/.exec(iso);
  if (!m) return 0;
  const [, d, h, min, s] = m;
  return (
    ((Number(d ?? 0) * 24 + Number(h ?? 0)) * 3600 +
      Number(min ?? 0) * 60 +
      Number(s ?? 0)) *
    1000
  );
}

/**
 * Extrait l'identifiant d'une vidéo depuis ce que l'utilisateur colle.
 *
 * Accepte les formes `watch?v=`, `youtu.be/`, `/shorts/`, `/embed/`, et
 * l'identifiant nu. Renvoie `null` si rien ne ressemble a un id : 11
 * caracteres de l'alphabet base64url.
 */
export function parseVideoId(input: string): string | null {
  const raw = input.trim();
  if (/^[A-Za-z0-9_-]{11}$/.test(raw)) return raw;

  const patterns = [
    /[?&]v=([A-Za-z0-9_-]{11})/,
    /youtu\.be\/([A-Za-z0-9_-]{11})/,
    /\/shorts\/([A-Za-z0-9_-]{11})/,
    /\/embed\/([A-Za-z0-9_-]{11})/,
    /\/live\/([A-Za-z0-9_-]{11})/,
  ];
  for (const pattern of patterns) {
    const match = pattern.exec(raw);
    if (match?.[1]) return match[1];
  }
  return null;
}

/**
 * Separe « Artiste - Titre (Official Video) » en ses deux moities.
 *
 * Les clips nomment presque toujours l'artiste avant un tiret ; quand il n'y
 * en a pas, l'appelant retombe sur le nom de la chaine.
 */
export function splitCreditedTitle(raw: string): { artist: string; title: string } {
  const separator = raw.indexOf(' - ');
  if (separator === -1) {
    return { artist: '', title: cleanTitle(raw) };
  }
  return {
    artist: raw.slice(0, separator).trim(),
    title: cleanTitle(raw.slice(separator + 3)),
  };
}

/**
 * Rang editorial d'un resultat de recherche.
 *
 * Ce qu'on cherche en tapant « bruno mars », c'est le titre original, pas le
 * remix accelere de quelqu'un d'autre. Le classement se fait sur le titre
 * **brut** et le nom de la chaine, avant que `cleanTitle` n'efface justement
 * les mentions « Official » qui servent ici de signal.
 *
 * Trois rangs, et le tri est stable : a rang egal, la pertinence de YouTube
 * est conservee.
 *
 * Attention a ne pas y voir une promesse de lecture : pour les artistes dont
 * l'ayant droit refuse l'integration, ce sont precisement les clips officiels
 * qui echouent. Le rang dit ce qui est original, pas ce qui jouera.
 */
const DERIVE =
  /\b(?:remix|rmx|cover|reprise|sped\s*up|speed\s*up|slowed|reverb|nightcore|8d|karaoke|karaoké|instrumental|mashup|flip|bootleg|type\s*beat|ringtone|sonnerie|tutorial|reaction|mix\s*by|dj\s+\w+)\b/i;

const OFFICIEL =
  /\b(?:official\s+(?:music\s+)?video|official\s+audio|official\s+visuali[sz]er|clip\s+officiel|audio\s+officiel)\b/i;

export function rangEditorial(titreBrut: string, chaine: string): number {
  if (DERIVE.test(titreBrut) || DERIVE.test(chaine)) return 2;
  if (OFFICIEL.test(titreBrut)) return 0;
  // Les chaines que YouTube genere pour les ayants droit, et les chaines VEVO,
  // ne portent pas la mention dans le titre mais sont officielles.
  if (/\s-\sTopic$/.test(chaine) || /VEVO$/i.test(chaine)) return 0;
  return 1;
}

/**
 * Retire le bruit des titres de clips pour matcher les paroles.
 *
 * L'ordre compte : on enleve d'abord les groupes entre parentheses ou crochets
 * entiers, puis les mentions nues, et seulement ensuite les parentheses que ces
 * retraits auraient laissees vides. Sans ce dernier filet, « Hiara dia (Clip
 * officiel) » devient « Hiara dia () » — ce qui casse la recherche de paroles.
 */
export function cleanTitle(raw: string): string {
  return (
    raw
      // Groupes dont le contenu entier est du bruit.
      // `lyrics?` doit figurer ici : « (Official Lyric Video) » sinon perd
      // « Lyric Video » par la regle des mentions nues plus bas et laisse
      // « (Official ) », que LRCLIB ne reconnait pas.
      .replace(
        /[([]\s*(?:official\s+)?(?:music\s+|lyrics?\s+)?(?:video|audio)[^)\]]*[)\]]/gi,
        '',
      )
      .replace(/[([]\s*clip\s+officiel[^)\]]*[)\]]/gi, '')
      .replace(/[([]\s*prod\.?\s+by[^)\]]*[)\]]/gi, '')
      .replace(/[([]\s*(?:lyrics?|paroles)(?:\s+video)?\s*[)\]]/gi, '')
      // Les memes mentions, sans parentheses.
      .replace(
        /\b(?:official\s+(?:music\s+)?video|official\s+audio|lyrics?\s+video|clip\s+officiel)\b/gi,
        '',
      )
      // Filet : groupes vides, ou ne contenant plus qu'une annee, apres les
      // retraits ci-dessus — « (Official Video 2026) » laisse « ( 2026) ».
      .replace(/[([]\s*[\d\s.,\-–]*[)\]]/g, '')
      // Annee d'upload collee en fin de titre, qui fait echouer LRCLIB.
      .replace(/\s+(?:19|20)\d{2}\s*$/, '')
      .replace(/\s*[|\-\u2013]\s*$/, '')
      .replace(/\s{2,}/g, ' ')
      .trim()
  );
}

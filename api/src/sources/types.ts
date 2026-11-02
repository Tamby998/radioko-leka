/**
 * Le coeur du modele hybride.
 *
 * Une capacite n'est pas une suggestion : les chemins telechargement et
 * arriere-plan appellent `assertCapability` et refusent tout titre qui ne la
 * porte pas. La frontiere legale est donc impossible a franchir par oubli.
 */

export type SourceId = 'youtube' | 'audius' | 'jamendo' | 'partner' | 'radio';

export type Capability =
  /** Le titre peut etre lu dans l'app. */
  | 'stream'
  /** Le flux audio peut etre consomme sans la video (lecteur audio natif). */
  | 'audioOnly'
  /** La lecture peut continuer ecran verrouille ou app en arriere-plan. */
  | 'background'
  /** Un fichier peut etre ecrit sur l'appareil pour une ecoute hors reseau. */
  | 'offline';

/** Catalogue mondial : metadonnees libres, lecture par le lecteur officiel. */
export const YOUTUBE_CAPABILITIES: readonly Capability[] = ['stream'];

/** Catalogue sous licence : l'artiste a publie son audio pour ces usages. */
export const LICENSED_CAPABILITIES: readonly Capability[] = [
  'stream',
  'audioOnly',
  'background',
  'offline',
];

export interface Artist {
  id: string;
  source: SourceId;
  name: string;
  avatarUrl?: string;
  followers?: number;
  totalViews?: number;
}

export interface Track {
  /** Identifiant stable `source:idExterne`, ex. `youtube:1l7wbZmdtys`. */
  uri: string;
  source: SourceId;
  externalId: string;
  title: string;
  artists: Artist[];
  durationMs: number;
  artworkUrl?: string;
  /** Ce que l'app a le droit de faire de ce titre. */
  capabilities: readonly Capability[];
  /**
   * Vrai quand le rendu video officiel doit rester visible pendant la lecture
   * (exigence du lecteur IFrame YouTube).
   */
  requiresVisiblePlayer: boolean;
  /**
   * URL de flux direct. Renseignee uniquement pour les sources sous licence :
   * toujours absente pour YouTube, ou la lecture passe par le lecteur officiel.
   */
  streamUrl?: string;
  /** Vues rapportees par la plateforme d'origine, a titre indicatif. */
  viewCount?: number;
  /**
   * Rang editorial, pose par la recherche YouTube : 0 original, 1 neutre,
   * 2 reprise ou remix.
   *
   * Il vit sur le titre, et non a cote, parce qu'il se calcule sur le titre
   * **brut** — avant que `cleanTitle` n'efface les mentions « Official » qui
   * servent de signal — et doit survivre jusqu'a la fusion des sources, qui a
   * lieu dans un autre module.
   */
  rangEditorial?: number;
}

export class CapabilityError extends Error {
  readonly track: Pick<Track, 'uri' | 'source'>;
  readonly capability: Capability;

  constructor(track: Pick<Track, 'uri' | 'source'>, capability: Capability) {
    super(
      `Le titre ${track.uri} (source ${track.source}) ne porte pas la capacite ` +
        `"${capability}". Cette operation est refusee.`,
    );
    this.name = 'CapabilityError';
    this.track = track;
    this.capability = capability;
  }
}

export function can(track: Track, capability: Capability): boolean {
  return track.capabilities.includes(capability);
}

/** A appeler avant toute ecriture de fichier ou toute lecture sans UI. */
export function assertCapability(track: Track, capability: Capability): void {
  if (!can(track, capability)) {
    throw new CapabilityError(track, capability);
  }
}

/** Contrat commun a toutes les sources de catalogue. */
export interface MusicSource {
  readonly id: SourceId;
  readonly capabilities: readonly Capability[];
  search(query: string, limit: number): Promise<Track[]>;
  tracksByIds(ids: string[]): Promise<Track[]>;
}

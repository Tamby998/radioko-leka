/**
 * Radios en direct.
 *
 * Reprend ce que radioko-leka avait deja etabli : Radio Browser pour le
 * catalogue mondial, complete par une poignee de flux malgaches verifies a la
 * main — Radio Browser connait mal Madagascar, et ces deux-la sont les plus
 * ecoutes.
 *
 * Le point qui rend l'integration facile : **une station entre telle quelle
 * dans le modele `Track`**. Duree inconnue (`0`), capacite `audioOnly`, une
 * `streamUrl`. Le lecteur audio de l'app la joue sans rien de nouveau, et la
 * frontiere « capacites du titre -> moteur » decide toute seule.
 *
 * Aucun flux n'est heberge ni reencode : on lit l'adresse publiee par la radio,
 * exactement comme le projet d'origine.
 */

import type { Track } from './types.ts';

const ENDPOINT = 'https://all.api.radio-browser.info';

/** Radio Browser demande un agent identifiable. On le lui donne. */
const AGENT = 'radiokoleka/0.1';

interface StationBrowser {
  stationuuid: string;
  name: string;
  url_resolved: string;
  country: string;
  countrycode: string;
  language: string;
  codec: string;
  bitrate: number;
  favicon?: string;
}

/**
 * Flux malgaches verifies, repris de `internal/radio/madagascar.go`.
 *
 * Ils ne viennent pas de Radio Browser : ce sont les adresses officielles,
 * verifiees a la main par le projet radio.
 */
const MALGACHES: StationBrowser[] = [
  {
    stationuuid: 'mg-olivasoa',
    name: 'Olivasoa Radio',
    url_resolved: 'https://live.webradio.mg/listen/olivasoa/radio.mp3',
    country: 'Madagascar',
    countrycode: 'MG',
    language: 'Malagasy',
    codec: 'MP3',
    bitrate: 0,
  },
  {
    stationuuid: 'mg-dj-bam',
    name: 'DJ Bam',
    url_resolved: 'https://live.webradio.mg/listen/djbam/radio.mp3',
    country: 'Madagascar',
    countrycode: 'MG',
    language: 'Malagasy',
    codec: 'MP3',
    bitrate: 0,
  },
];

/**
 * Deux stations identiques par l'adresse ou par le nom n'en font qu'une.
 *
 * Meme regle que le projet d'origine : Radio Browser recense des doublons, la
 * meme radio y figurant sous plusieurs entrees.
 */
function fusionner(primaires: StationBrowser[], ajouts: StationBrowser[]): StationBrowser[] {
  const vues = new Set<string>();
  const sortie: StationBrowser[] = [];
  for (const station of [...primaires, ...ajouts]) {
    const url = station.url_resolved?.trim().toLowerCase();
    const nom = station.name?.trim().toLowerCase();
    if (!url || !nom) continue;
    if (vues.has(url) || vues.has(nom)) continue;
    vues.add(url);
    vues.add(nom);
    sortie.push(station);
  }
  return sortie;
}

function toTrack(station: StationBrowser): Track {
  const genre = [station.language, station.codec].filter(Boolean).join(' · ');
  return {
    uri: `radio:${station.stationuuid}`,
    source: 'radio',
    externalId: station.stationuuid,
    title: station.name.trim(),
    artists: [
      {
        id: `radio:${station.countrycode || 'xx'}`,
        source: 'radio',
        name: station.country || genre || 'Radio',
      },
    ],
    // Un direct n'a pas de duree. Zero veut dire inconnue partout dans l'app,
    // et c'est ce qui fera afficher « DIRECT » au lieu d'un compteur.
    durationMs: 0,
    artworkUrl: station.favicon || undefined,
    capabilities: ['stream', 'audioOnly', 'background'],
    requiresVisiblePlayer: false,
    streamUrl: station.url_resolved,
  };
}

async function interroger(chemin: string): Promise<StationBrowser[]> {
  const res = await fetch(`${ENDPOINT}${chemin}`, {
    headers: { 'User-Agent': AGENT, Accept: 'application/json' },
  });
  if (!res.ok) throw new Error(`Radio Browser ${res.status}`);
  return (await res.json()) as StationBrowser[];
}

/** Les radios d'un pays, les plus ecoutees d'abord. */
export async function radiosDuPays(code: string, limite = 60): Promise<Track[]> {
  const pays = code.toUpperCase().replace(/[^A-Z]/g, '').slice(0, 2) || 'MG';
  const params = new URLSearchParams({
    hidebroken: 'true',
    order: 'clickcount',
    reverse: 'true',
    limit: String(Math.min(limite, 200)),
  });

  const trouvees = await interroger(
    `/json/stations/bycountrycodeexact/${pays}?${params}`,
  ).catch(() => [] as StationBrowser[]);

  // Les verifiees passent devant pour Madagascar : ce sont celles dont on sait
  // qu'elles repondent.
  const ajouts = pays === 'MG' ? MALGACHES : [];
  return fusionner(ajouts, trouvees).map(toTrack);
}

export interface PaysRadio {
  code: string;
  nom: string;
  stations: number;
}

/**
 * Les pays qui ont des radios, les mieux pourvus d'abord.
 *
 * Radio Browser en recense plus de deux cents. On ecarte ceux dont le code est
 * vide ou le compte nul : un pays sans station n'est pas un choix.
 */
export async function paysDisponibles(): Promise<PaysRadio[]> {
  interface Ligne {
    name: string;
    iso_3166_1: string;
    stationcount: number;
  }
  const res = await fetch(`${ENDPOINT}/json/countries`, {
    headers: { 'User-Agent': AGENT, Accept: 'application/json' },
  });
  if (!res.ok) throw new Error(`Radio Browser ${res.status}`);
  const lignes = (await res.json()) as Ligne[];

  return lignes
    .filter((l) => l.iso_3166_1?.trim() && Number(l.stationcount) > 0)
    .map((l) => ({
      code: l.iso_3166_1.trim().toUpperCase(),
      nom: l.name?.trim() || l.iso_3166_1,
      stations: Number(l.stationcount),
    }))
    .sort((a, b) => a.nom.localeCompare(b.nom, 'fr'));
}

/** Recherche par nom, tous pays. */
export async function chercherRadios(requete: string, limite = 40): Promise<Track[]> {
  const propre = requete.trim();
  if (!propre) return [];
  const params = new URLSearchParams({
    name: propre,
    hidebroken: 'true',
    order: 'clickcount',
    reverse: 'true',
    limit: String(Math.min(limite, 100)),
  });
  const trouvees = await interroger(`/json/stations/search?${params}`).catch(
    () => [] as StationBrowser[],
  );
  const locales = MALGACHES.filter((s) =>
    s.name.toLowerCase().includes(propre.toLowerCase()),
  );
  return fusionner(locales, trouvees).map(toTrack);
}

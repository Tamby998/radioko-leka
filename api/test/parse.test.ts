import assert from 'node:assert/strict';
import { test } from 'node:test';

import { parseCapabilities } from '../src/catalogue.ts';
import { dedupe } from '../src/lib/doublons.ts';
import { isRelevant, normalize, queryTokens } from '../src/lib/relevance.ts';
import { parseLrc, primaryArtist } from '../src/lyrics/lrclib.ts';
import {
  cleanTitle,
  parseIsoDuration,
  parseVideoId,
  rangEditorial,
  splitCreditedTitle,
} from '../src/sources/youtube.ts';
import {
  assertCapability,
  CapabilityError,
  LICENSED_CAPABILITIES,
  type Track,
  YOUTUBE_CAPABILITIES,
} from '../src/sources/types.ts';

// Texte neutre : aucune parole reelle dans les fixtures.
const LRC = [
  '[ar:Artiste de test]',
  '[length:03:00]',
  '[00:12.50]premiere ligne',
  '[00:18.00]deuxieme ligne',
  '[01:04.25][02:10.00]refrain repete',
  'ligne sans horodatage ignoree',
  '[00:30.1]tolerance un chiffre',
].join('\n');

test('parseLrc lit les horodatages et ignore les metadonnees', () => {
  const lines = parseLrc(LRC);
  assert.equal(lines.length, 5);
  assert.equal(lines[0].atMs, 12_500);
  assert.equal(lines[0].text, 'premiere ligne');
});

test('parseLrc dedouble les horodatages multiples et trie', () => {
  const lines = parseLrc(LRC);
  const refrains = lines.filter((l) => l.text === 'refrain repete');
  assert.equal(refrains.length, 2);
  assert.deepEqual(
    refrains.map((l) => l.atMs),
    [64_250, 130_000],
  );
  for (let i = 1; i < lines.length; i += 1) {
    assert.ok(lines[i].atMs >= lines[i - 1].atMs, 'les lignes doivent etre triees');
  }
});

test('parseLrc tolere des centiemes sur un chiffre', () => {
  const line = parseLrc(LRC).find((l) => l.text === 'tolerance un chiffre');
  assert.equal(line?.atMs, 30_100);
});

test('parseIsoDuration convertit la duree YouTube', () => {
  assert.equal(parseIsoDuration('PT4M13S'), 253_000);
  assert.equal(parseIsoDuration('PT1H2M3S'), 3_723_000);
  assert.equal(parseIsoDuration('PT45S'), 45_000);
  assert.equal(parseIsoDuration('nawak'), 0);
});

test('cleanTitle retire le bruit des titres de clips', () => {
  assert.equal(cleanTitle('Un Titre (Official Video)'), 'Un Titre');
  assert.equal(cleanTitle('Un Titre [Official Music Video]'), 'Un Titre');
  assert.equal(cleanTitle('Un Titre | Clip Officiel'), 'Un Titre');
});

const base = {
  uri: 'x',
  source: 'youtube' as const,
  externalId: 'x',
  title: 'T',
  artists: [],
  durationMs: 1000,
  requiresVisiblePlayer: true,
};

test('un titre YouTube refuse le hors-connexion', () => {
  const track: Track = { ...base, capabilities: YOUTUBE_CAPABILITIES };
  assert.throws(() => assertCapability(track, 'offline'), CapabilityError);
  assert.throws(() => assertCapability(track, 'background'), CapabilityError);
  assert.doesNotThrow(() => assertCapability(track, 'stream'));
});

test('un titre sous licence accepte le hors-connexion', () => {
  const track: Track = {
    ...base,
    source: 'audius',
    capabilities: LICENSED_CAPABILITIES,
    requiresVisiblePlayer: false,
  };
  for (const c of ['stream', 'audioOnly', 'background', 'offline'] as const) {
    assert.doesNotThrow(() => assertCapability(track, c));
  }
});

test('parseCapabilities lit la colonne serialisee', () => {
  assert.deepEqual(parseCapabilities('stream'), ['stream']);
  assert.deepEqual(parseCapabilities('stream,audioOnly,background,offline'), [
    'stream',
    'audioOnly',
    'background',
    'offline',
  ]);
  assert.deepEqual(parseCapabilities(' stream , offline '), ['stream', 'offline']);
});

test('parseCapabilities ecarte les valeurs inconnues', () => {
  // Une colonne corrompue ne doit jamais accorder une capacite par accident.
  assert.deepEqual(parseCapabilities('stream,telechargement,OFFLINE'), ['stream']);
  assert.deepEqual(parseCapabilities(''), []);
  assert.deepEqual(parseCapabilities('offlin'), []);
});

test('normalize retire accents et ponctuation', () => {
  assert.equal(normalize('Gâter Pourri'), 'gater pourri');
  assert.equal(normalize('ROSÉ - new trick!'), 'rose new trick');
  assert.equal(normalize('  Fy   Mitonia  '), 'fy mitonia');
});

test('queryTokens garde les mots porteurs', () => {
  assert.deepEqual(queryTokens('fy mitonia'), ['mitonia']);
  assert.deepEqual(queryTokens('wawa salegy'), ['wawa', 'salegy']);
  // Que des mots courts : on retombe sur la requete entiere.
  assert.deepEqual(queryTokens('fy'), ['fy']);
  assert.deepEqual(queryTokens('ro da'), ['roda']);
  assert.deepEqual(queryTokens('   '), []);
});

test('isRelevant ecarte le bruit d Audius', () => {
  // Le cas reel : « mitonia » n'est pas dans « zambudaximatonia ».
  assert.equal(isRelevant('fy mitonia', 'sandbreaker-379630 zambudaximatonia'), false);
  assert.equal(isRelevant('fy mitonia', 'tell-me-what-379638 zambudaximatonia'), false);
});

test('isRelevant garde les vraies correspondances', () => {
  assert.equal(isRelevant('shyn', 'Hiara dia Shyn'), true);
  assert.equal(isRelevant('bruno mars', 'Talking To The Moon - Bruno Mars BreathOut'), true);
  assert.equal(isRelevant('ROSÉ', 'new trick Rose'), true);
  // Une requete vide ne doit jamais vider la liste.
  assert.equal(isRelevant('', 'nimporte quoi'), true);
});

test('parseVideoId accepte les formes de lien usuelles', () => {
  const id = 'fCmnTQyb0Cg';
  assert.equal(parseVideoId(id), id);
  assert.equal(parseVideoId(`https://www.youtube.com/watch?v=${id}`), id);
  assert.equal(parseVideoId(`https://youtu.be/${id}`), id);
  assert.equal(parseVideoId(`https://www.youtube.com/shorts/${id}`), id);
  assert.equal(parseVideoId(`https://www.youtube.com/embed/${id}`), id);
  assert.equal(parseVideoId(`https://m.youtube.com/watch?v=${id}&t=42s`), id);
  assert.equal(parseVideoId(`  https://youtu.be/${id}?si=xyz  `), id);
});

test('parseVideoId refuse ce qui n est pas un identifiant', () => {
  assert.equal(parseVideoId('fy mitonia'), null);
  assert.equal(parseVideoId(''), null);
  assert.equal(parseVideoId('https://example.test/video'), null);
  // Dix caracteres : un id en fait onze.
  assert.equal(parseVideoId('abcdefghij'), null);
});

test('splitCreditedTitle separe artiste et titre', () => {
  assert.deepEqual(splitCreditedTitle('Shyn - Hiara dia (Clip officiel) 2025'), {
    artist: 'Shyn',
    title: 'Hiara dia',
  });
  assert.deepEqual(splitCreditedTitle('Bruno Mars - Dance With Me [Official Music Video]'), {
    artist: 'Bruno Mars',
    title: 'Dance With Me',
  });
  // Sans tiret : l'appelant retombe sur le nom de la chaine.
  assert.deepEqual(splitCreditedTitle('IKALAJEJO'), { artist: '', title: 'IKALAJEJO' });
});

test('cleanTitle retire un groupe « Official Lyric Video » entier', () => {
  // Le bug : « Lyric Video » partait par la regle des mentions nues, laissant
  // « (Official ) » — que LRCLIB ne reconnait pas, donc plus de karaoke.
  assert.equal(
    cleanTitle('Talking To The Moon (Official Lyric Video)'),
    'Talking To The Moon',
  );
  assert.equal(cleanTitle('Un titre (Official Audio)'), 'Un titre');
  assert.equal(cleanTitle('Un titre [Official Music Video]'), 'Un titre');
  // Une parenthese porteuse de sens n'est pas du bruit.
  assert.equal(cleanTitle('Un titre (Live at Berklee)'), 'Un titre (Live at Berklee)');
});

test('cleanTitle ne laisse pas de parentheses vides', () => {
  // Le bug attrape par le test : la mention etait retiree, pas ses parentheses.
  assert.equal(cleanTitle('Hiara dia (Clip officiel) 2025'), 'Hiara dia');
  assert.equal(cleanTitle('IKALAJEJO (prod. by Teints Record) (Official Video)'), 'IKALAJEJO');
  assert.equal(cleanTitle('Tsy Mazava (Clip Officiel)'), 'Tsy Mazava');
  assert.equal(cleanTitle('new trick (OFFICIAL MUSIC VIDEO)'), 'new trick');
  assert.equal(cleanTitle('HISAOTRA ANAO (Official Video 2026)'), 'HISAOTRA ANAO');
});

test('cleanTitle ne mange pas un titre legitime', () => {
  assert.equal(cleanTitle('Still'), 'Still');
  assert.equal(cleanTitle('Heaven Baby ft. ZAYN'), 'Heaven Baby ft. ZAYN');
  // Un titre qui n'est qu'une annee doit survivre.
  assert.equal(cleanTitle('1999'), '1999');
  assert.equal(cleanTitle('Gâter Pourri'), 'Gâter Pourri');
});

test('primaryArtist isole le premier credit', () => {
  assert.equal(primaryArtist('KAROL G, Bruno Mars'), 'KAROL G');
  assert.equal(primaryArtist('Ayra Starr ft. ZAYN'), 'Ayra Starr');
  assert.equal(primaryArtist('Wawa Salegy feat. Diamond Platnumz'), 'Wawa Salegy');
  assert.equal(primaryArtist('Ceasar & Denise'), 'Ceasar');
  assert.equal(primaryArtist('onumi x SAWTOWNE'), 'onumi');
});

test('primaryArtist laisse un artiste seul intact', () => {
  assert.equal(primaryArtist('Bruno Mars'), 'Bruno Mars');
  assert.equal(primaryArtist('NIU RAZA'), 'NIU RAZA');
  assert.equal(primaryArtist('Mr SAYDA'), 'Mr SAYDA');
});

// --- Dedoublonnage ------------------------------------------------------

/** Un clip YouTube : la duree et le titre font l'empreinte, pas la chaine. */
const clip = (
  externalId: string,
  title: string,
  artiste: string,
  durationMs: number,
): Track => ({
  uri: `youtube:${externalId}`,
  source: 'youtube',
  externalId,
  title,
  artists: [{ id: artiste, source: 'youtube', name: artiste }],
  durationMs,
  capabilities: YOUTUBE_CAPABILITIES,
  requiresVisiblePlayer: true,
});

test('dedupe rapproche un meme clip remonte sous deux chaines', () => {
  const gardes = dedupe([
    clip('a', 'RIVOTRA Mahaleo Live @ Olympia', 'Mahaleo', 259_000),
    clip('b', 'RIVOTRA Mahaleo Live @ Olympia', 'Mahaleo Officiel', 259_000),
  ]);
  assert.equal(gardes.length, 1);
  // Le catalogue cure passe en premier dans la recherche : c'est lui qui reste.
  assert.equal(gardes[0].externalId, 'a');
});

test('dedupe rapproche un reupload dont le titre porte l artiste', () => {
  const gardes = dedupe([
    clip('a', 'Hay hay', 'Mahaleo', 248_000),
    clip('b', 'Mahaleo- Hay hay', 'Rino minato', 248_000),
  ]);
  assert.equal(gardes.length, 1);
  assert.equal(gardes[0].externalId, 'a');
});

test('dedupe garde deux titres homonymes de durees differentes', () => {
  const gardes = dedupe([
    clip('a', 'Ou la', 'Kassav', 240_000),
    clip('b', 'Ou la', 'Kassav', 318_000),
  ]);
  assert.equal(gardes.length, 2);
});

test('dedupe ne fusionne pas sur la seule duree', () => {
  const gardes = dedupe([
    clip('a', 'Medley', 'Mahaleo', 206_000),
    clip('b', 'Vololona', 'Mahaleo', 206_000),
  ]);
  assert.equal(gardes.length, 2);
});

test('dedupe sans duree connue retombe sur titre et artiste', () => {
  const gardes = dedupe([
    clip('a', 'Inconnu', 'Artiste A', 0),
    clip('b', 'Inconnu', 'Artiste B', 0),
    clip('c', 'Inconnu', 'Artiste A', 0),
  ]);
  assert.equal(gardes.length, 2);
});

test('dedupe garde la version la plus capable', () => {
  const youtube = clip('a', 'Meme titre', 'Artiste', 200_000);
  const licencie: Track = {
    ...clip('b', 'Meme titre', 'Artiste', 200_000),
    source: 'audius',
    uri: 'audius:b',
    capabilities: LICENSED_CAPABILITIES,
    requiresVisiblePlayer: false,
  };
  const gardes = dedupe([youtube, licencie]);
  assert.equal(gardes.length, 1);
  assert.equal(gardes[0].uri, 'audius:b');
});

test('dedupe preserve l ordre des resultats gardes', () => {
  const gardes = dedupe([
    clip('a', 'Premier', 'X', 100_000),
    clip('b', 'Second', 'X', 110_000),
    clip('c', 'Premier', 'Y', 100_000),
    clip('d', 'Troisieme', 'X', 120_000),
  ]);
  assert.deepEqual(
    gardes.map((t) => t.externalId),
    ['a', 'b', 'd'],
  );
});

// --- Rang editorial -----------------------------------------------------

test('rangEditorial met l officiel devant', () => {
  assert.equal(rangEditorial('Bruno Mars - Grenade (Official Music Video)', 'BrunoMarsVEVO'), 0);
  assert.equal(rangEditorial('Hiara dia (Clip Officiel)', 'Shyn'), 0);
  assert.equal(rangEditorial('Ny Lasantsika', 'Mahaleo - Topic'), 0);
});

test('rangEditorial relegue reprises et remixes', () => {
  assert.equal(rangEditorial('Talking to the Moon (sped up)', 'Nightcore World'), 2);
  assert.equal(rangEditorial('Grenade - Piano Cover', 'Piano Guy'), 2);
  assert.equal(rangEditorial('Moto (DJ Mix)', 'DJ Tunez'), 2);
});

test('rangEditorial laisse le reste au milieu', () => {
  assert.equal(rangEditorial('Veloma Ry Fahazazana', 'Mahaleo'), 1);
});

test('rangEditorial ne confond pas un titre contenant un mot proche', () => {
  // « Discover » contient « cover », mais pas en mot plein.
  assert.equal(rangEditorial('Discover the night', 'Un Artiste'), 1);
});

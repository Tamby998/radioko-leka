/**
 * Corrige les durees du catalogue cure depuis l'API YouTube.
 *
 * `videos.list` coute 1 unite pour 50 identifiants, contre 100 pour une seule
 * recherche : rafraichir tout le catalogue tient dans une poignee d'unites.
 * C'est ce script qu'un cron appellera.
 *
 *   node scripts/refresh-durations.mjs [--remote]
 *
 * Les lignes a corriger sont celles dont `refreshed_at` est NULL : elles
 * portent une duree de depart approximative, posee par le seed.
 */

import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';

const REMOTE = process.argv.includes('--remote');
const SCOPE = REMOTE ? '--remote' : '--local';
const BATCH = 50;

function apiKey() {
  // En local la cle vit dans .dev.vars ; en remote elle est deja un secret du
  // Worker, mais ce script tourne ici, donc il la lit au meme endroit.
  const fromEnv = process.env.YOUTUBE_API_KEY;
  if (fromEnv) return fromEnv;
  try {
    const line = readFileSync(new URL('../.dev.vars', import.meta.url), 'utf8')
      .split('\n')
      .find((l) => l.startsWith('YOUTUBE_API_KEY='));
    const value = line?.slice('YOUTUBE_API_KEY='.length).trim();
    if (value) return value;
  } catch {
    /* fichier absent : on tombe dans l'erreur ci-dessous */
  }
  throw new Error('YOUTUBE_API_KEY introuvable (.dev.vars ou variable d environnement)');
}

function d1(sql) {
  const out = execFileSync(
    'npx',
    ['wrangler', 'd1', 'execute', 'hira', SCOPE, '--json', '--command', sql],
    { encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 },
  );
  // wrangler prefixe parfois le JSON de lignes decoratives.
  const start = out.indexOf('[');
  if (start === -1) throw new Error(`reponse D1 inattendue : ${out.slice(0, 200)}`);
  return JSON.parse(out.slice(start));
}

/** `PT4M13S` -> 253000 */
function parseIsoDuration(iso) {
  const m = /^P(?:(\d+)D)?T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$/.exec(iso ?? '');
  if (!m) return 0;
  const [, d, h, min, s] = m;
  return (
    ((Number(d ?? 0) * 24 + Number(h ?? 0)) * 3600 + Number(min ?? 0) * 60 + Number(s ?? 0)) *
    1000
  );
}

const key = apiKey();

const rows = d1(
  "SELECT external_id, title FROM tracks WHERE source = 'youtube' AND refreshed_at IS NULL",
)[0].results;

if (rows.length === 0) {
  console.log('Rien a corriger : toutes les durees sont a jour.');
  process.exit(0);
}

console.log(`${rows.length} titres a corriger.`);
let units = 0;
let fixed = 0;

for (let i = 0; i < rows.length; i += BATCH) {
  const slice = rows.slice(i, i + BATCH);
  const url = new URL('https://www.googleapis.com/youtube/v3/videos');
  url.searchParams.set('part', 'contentDetails');
  url.searchParams.set('id', slice.map((r) => r.external_id).join(','));
  url.searchParams.set('key', key);

  const res = await fetch(url);
  units += 1;
  if (!res.ok) {
    throw new Error(`videos.list ${res.status} : ${(await res.text()).slice(0, 300)}`);
  }
  const body = await res.json();

  const updates = [];
  for (const item of body.items ?? []) {
    const ms = parseIsoDuration(item.contentDetails?.duration);
    if (!ms) continue;
    const before = slice.find((r) => r.external_id === item.id);
    updates.push(
      `UPDATE tracks SET duration_ms = ${ms}, refreshed_at = unixepoch() ` +
        `WHERE external_id = '${item.id.replace(/'/g, "''")}';`,
    );
    console.log(`  ${(before?.title ?? item.id).slice(0, 38).padEnd(38)} ${Math.round(ms / 1000)}s`);
    fixed += 1;
  }

  if (updates.length) d1(updates.join(' '));
}

console.log(`\n${fixed} durees corrigees, ${units} unite(s) de quota consommee(s).`);

/**
 * Cache a deux etages : le cache d'edge du Worker, puis D1 pour les entrees
 * qui doivent survivre a une purge (paroles, resultats de recherche).
 */

export interface CacheEnv {
  DB: D1Database;
}

export async function cachedJson<T>(
  env: CacheEnv,
  key: string,
  ttlSeconds: number,
  produce: () => Promise<T>,
): Promise<T> {
  const row = await env.DB.prepare(
    'SELECT payload FROM kv_cache WHERE key = ?1 AND expires_at > unixepoch()',
  )
    .bind(key)
    .first<{ payload: string }>();

  if (row) return JSON.parse(row.payload) as T;

  const value = await produce();
  await env.DB.prepare(
    `INSERT INTO kv_cache (key, payload, expires_at)
     VALUES (?1, ?2, unixepoch() + ?3)
     ON CONFLICT(key) DO UPDATE SET payload = excluded.payload,
                                    expires_at = excluded.expires_at`,
  )
    .bind(key, JSON.stringify(value), ttlSeconds)
    .run();

  return value;
}

export function cacheKey(...parts: (string | number | undefined)[]): string {
  return parts
    .filter((p) => p !== undefined)
    .map((p) => String(p).toLowerCase().trim())
    .join('|');
}

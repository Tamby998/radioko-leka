-- Retrait des titres que le banc n'a pas vus jouer.
-- 4 titres sur 114 verifies.
--
-- Les references partent avant les titres : track_genres et playlist_items
-- pointent sur tracks, et la contrainte refuserait l'inverse.

DELETE FROM track_genres WHERE track_uri IN (
    'youtube:2ZTcvsdMR1c',
    'youtube:Lufa9QAFFeY',
    'youtube:1l7wbZmdtys',
    'youtube:aQXq3ndLkHs');

DELETE FROM playlist_items WHERE track_uri IN (
    'youtube:2ZTcvsdMR1c',
    'youtube:Lufa9QAFFeY',
    'youtube:1l7wbZmdtys',
    'youtube:aQXq3ndLkHs');

DELETE FROM tracks WHERE uri IN (
    'youtube:2ZTcvsdMR1c',
    'youtube:Lufa9QAFFeY',
    'youtube:1l7wbZmdtys',
    'youtube:aQXq3ndLkHs');

-- Un artiste sans aucun titre n'a plus rien a faire dans le catalogue.
DELETE FROM artists
 WHERE uri NOT IN (SELECT artist_uri FROM tracks WHERE artist_uri IS NOT NULL);

-- Memoire du refus : c'est elle qui empeche le clip de revenir par la recherche.
INSERT OR REPLACE INTO clips_refuses (external_id, source, verdict, checked_at) VALUES
  ('2ZTcvsdMR1c', 'youtube', 'erreur:150', unixepoch()),
  ('Lufa9QAFFeY', 'youtube', 'erreur:150', unixepoch()),
  ('1l7wbZmdtys', 'youtube', 'erreur:150', unixepoch()),
  ('aQXq3ndLkHs', 'youtube', 'erreur:150', unixepoch());

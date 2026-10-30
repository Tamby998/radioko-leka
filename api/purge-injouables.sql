-- Retrait des titres que le banc n'a pas vus jouer.
-- 2 titres sur 76 verifies.
--
-- Les references partent avant les titres : track_genres et playlist_items
-- pointent sur tracks, et la contrainte refuserait l'inverse.

DELETE FROM track_genres WHERE track_uri IN (
    'youtube:hWNRoePtEhs',
    'youtube:efiS8G_V3NU');

DELETE FROM playlist_items WHERE track_uri IN (
    'youtube:hWNRoePtEhs',
    'youtube:efiS8G_V3NU');

DELETE FROM tracks WHERE uri IN (
    'youtube:hWNRoePtEhs',
    'youtube:efiS8G_V3NU');

-- Un artiste sans aucun titre n'a plus rien a faire dans le catalogue.
DELETE FROM artists
 WHERE uri NOT IN (SELECT artist_uri FROM tracks WHERE artist_uri IS NOT NULL);

-- Memoire du refus : c'est elle qui empeche le clip de revenir par la recherche.
INSERT OR REPLACE INTO clips_refuses (external_id, source, verdict, checked_at) VALUES
  ('hWNRoePtEhs', 'youtube', 'erreur:150', unixepoch()),
  ('efiS8G_V3NU', 'youtube', 'erreur:150', unixepoch());

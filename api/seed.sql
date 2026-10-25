-- Hira — catalogue de depart.
--
-- Permet a la recherche de fonctionner sans cle YouTube Data API : les
-- metadonnees viennent de l endpoint oEmbed public, les durees de LRCLIB.
-- Les durees marquees placeholder seront corrigees par videos.list (1 unite
-- de quota pour 50 titres) des que YOUTUBE_API_KEY sera pose : ce sont les
-- lignes dont refreshed_at est NULL.
--
-- Aucune parole n est stockee ici : elles sont recuperees a la lecture.

INSERT OR REPLACE INTO artists (uri, source, external_id, name, is_local, refreshed_at) VALUES
  ('youtube:artist:bruno-mars', 'youtube', 'bruno-mars', 'Bruno Mars', 0, NULL),
  ('youtube:artist:rim-ka', 'youtube', 'rim-ka', 'Rim-Ka', 1, NULL),
  ('youtube:artist:karol-g-bruno-mars', 'youtube', 'karol-g-bruno-mars', 'KAROL G, Bruno Mars', 0, NULL),
  ('youtube:artist:shyn', 'youtube', 'shyn', 'Shyn', 1, NULL),
  ('youtube:artist:ayra-starr', 'youtube', 'ayra-starr', 'Ayra Starr', 0, NULL),
  ('youtube:artist:denise', 'youtube', 'denise', 'Denise', 1, NULL),
  ('youtube:artist:rose', 'youtube', 'rose', 'ROSÉ', 0, NULL),
  ('youtube:artist:mr-sayda', 'youtube', 'mr-sayda', 'Mr SAYDA', 1, NULL),
  ('youtube:artist:niu-raza', 'youtube', 'niu-raza', 'NIU RAZA', 1, NULL);

-- capabilities = 'stream' seul : lecture par le lecteur officiel, jamais de
-- copie locale ni de lecture en arriere-plan.
INSERT OR REPLACE INTO tracks
  (uri, source, external_id, title, artist_uri, duration_ms, artwork_url, capabilities, view_count, refreshed_at) VALUES
  ('youtube:1l7wbZmdtys', 'youtube', '1l7wbZmdtys', 'Dance With Me', 'youtube:artist:bruno-mars', 219000, 'https://i.ytimg.com/vi/1l7wbZmdtys/maxresdefault.jpg', 'stream', NULL, NULL),
  ('youtube:bn5A_rlCMVU', 'youtube', 'bn5A_rlCMVU', 'Gâter Pourri', 'youtube:artist:rim-ka', 210000, 'https://i.ytimg.com/vi/bn5A_rlCMVU/maxresdefault.jpg', 'stream', NULL, NULL),
  ('youtube:aQXq3ndLkHs', 'youtube', 'aQXq3ndLkHs', 'Still', 'youtube:artist:karol-g-bruno-mars', 220000, 'https://i.ytimg.com/vi/aQXq3ndLkHs/maxresdefault.jpg', 'stream', NULL, NULL),
  ('youtube:fCmnTQyb0Cg', 'youtube', 'fCmnTQyb0Cg', 'Hiara dia', 'youtube:artist:shyn', 210000, 'https://i.ytimg.com/vi/fCmnTQyb0Cg/maxresdefault.jpg', 'stream', NULL, NULL),
  ('youtube:2ZTcvsdMR1c', 'youtube', '2ZTcvsdMR1c', 'Heaven Baby ft. ZAYN', 'youtube:artist:ayra-starr', 210000, 'https://i.ytimg.com/vi/2ZTcvsdMR1c/maxresdefault.jpg', 'stream', NULL, NULL),
  ('youtube:IxTEr-c8eD0', 'youtube', 'IxTEr-c8eD0', 'Tsy Mazava', 'youtube:artist:denise', 210000, 'https://i.ytimg.com/vi/IxTEr-c8eD0/maxresdefault.jpg', 'stream', NULL, NULL),
  ('youtube:Lufa9QAFFeY', 'youtube', 'Lufa9QAFFeY', 'new trick', 'youtube:artist:rose', 183000, 'https://i.ytimg.com/vi/Lufa9QAFFeY/maxresdefault.jpg', 'stream', NULL, NULL),
  ('youtube:kclMyi2UaCE', 'youtube', 'kclMyi2UaCE', 'HISAOTRA ANAO', 'youtube:artist:mr-sayda', 210000, 'https://i.ytimg.com/vi/kclMyi2UaCE/maxresdefault.jpg', 'stream', NULL, NULL),
  ('youtube:xjv8n8Agnwo', 'youtube', 'xjv8n8Agnwo', 'IKALAJEJO', 'youtube:artist:niu-raza', 210000, 'https://i.ytimg.com/vi/xjv8n8Agnwo/maxresdefault.jpg', 'stream', NULL, NULL);

-- Genres utilises par ce seed. OR IGNORE laisse intacts ceux que schema.sql a
-- deja poses ; seuls les manquants sont ajoutes. Necessaire parce qu une
-- violation de cle etrangere n est PAS ignoree par OR IGNORE : elle annule tout.
INSERT OR IGNORE INTO genres (slug, label, tagline, position) VALUES
  ('pop', 'Pop', 'Les refrains que tout le monde connait.', 1),
  ('afrobeats', 'Afrobeats', 'De Lagos a Londres, le groove qui a pris le monde.', 2),
  ('rap-fr', 'Rap francais', 'Des classiques aux sorties du vendredi.', 3),
  ('kpop', 'K-pop', 'Seoul, en voix et en choregraphies.', 5),
  ('latino', 'Latino', 'Reggaeton et hits latinos, toute l annee.', 6),
  ('gasy', 'Musique malgache', 'Salegy, tsapiky, rap gasy, classiques.', 7);

INSERT OR IGNORE INTO track_genres (track_uri, genre_slug) VALUES
  ('youtube:1l7wbZmdtys', 'pop'),
  ('youtube:bn5A_rlCMVU', 'rap-fr'),
  ('youtube:aQXq3ndLkHs', 'latino'),
  ('youtube:fCmnTQyb0Cg', 'gasy'),
  ('youtube:2ZTcvsdMR1c', 'afrobeats'),
  ('youtube:IxTEr-c8eD0', 'gasy'),
  ('youtube:Lufa9QAFFeY', 'kpop'),
  ('youtube:kclMyi2UaCE', 'gasy'),
  ('youtube:xjv8n8Agnwo', 'gasy');

INSERT OR REPLACE INTO playlists (slug, title, kind, description, updated_at) VALUES
  ('decouverte', 'Decouverte Hira', 'selection',
   'Catalogue de depart : du mainstream et la scene gasy.', unixepoch());

INSERT OR REPLACE INTO playlist_items (playlist_slug, track_uri, position) VALUES
  ('decouverte', 'youtube:1l7wbZmdtys', 1),
  ('decouverte', 'youtube:bn5A_rlCMVU', 2),
  ('decouverte', 'youtube:aQXq3ndLkHs', 3),
  ('decouverte', 'youtube:fCmnTQyb0Cg', 4),
  ('decouverte', 'youtube:2ZTcvsdMR1c', 5),
  ('decouverte', 'youtube:IxTEr-c8eD0', 6),
  ('decouverte', 'youtube:Lufa9QAFFeY', 7),
  ('decouverte', 'youtube:kclMyi2UaCE', 8),
  ('decouverte', 'youtube:xjv8n8Agnwo', 9);

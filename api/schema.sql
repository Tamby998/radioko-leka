-- Hira — schema D1
-- Catalogue cure : c'est lui qui protege le quota YouTube Data API.

CREATE TABLE IF NOT EXISTS artists (
  uri          TEXT PRIMARY KEY,          -- 'youtube:UC...' | 'audius:xyz'
  source       TEXT NOT NULL,
  external_id  TEXT NOT NULL,
  name         TEXT NOT NULL,
  avatar_url   TEXT,
  followers    INTEGER,
  is_local     INTEGER NOT NULL DEFAULT 0, -- scene gasy mise en avant
  refreshed_at INTEGER
);

CREATE TABLE IF NOT EXISTS tracks (
  uri            TEXT PRIMARY KEY,
  source         TEXT NOT NULL,
  external_id    TEXT NOT NULL,
  title          TEXT NOT NULL,
  artist_uri     TEXT REFERENCES artists(uri),
  duration_ms    INTEGER NOT NULL DEFAULT 0,
  artwork_url    TEXT,
  -- Capacites serialisees, p.ex. 'stream' ou 'stream,audioOnly,background,offline'
  capabilities   TEXT NOT NULL,
  view_count     INTEGER,
  refreshed_at   INTEGER
);
CREATE INDEX IF NOT EXISTS idx_tracks_artist ON tracks(artist_uri);
CREATE INDEX IF NOT EXISTS idx_tracks_source ON tracks(source);

-- `parent` porte les sous-genres : un style precis (folk gasy, zouk racines)
-- pointe vers le genre qui le contient. Les rayons n'affichent que les genres
-- racine ; le parent sert a enchainer entre proches avant d'elargir.
CREATE TABLE IF NOT EXISTS genres (
  slug   TEXT PRIMARY KEY,
  label  TEXT NOT NULL,
  tagline TEXT,
  position INTEGER NOT NULL DEFAULT 0,
  parent TEXT REFERENCES genres(slug)
);

CREATE TABLE IF NOT EXISTS track_genres (
  track_uri  TEXT NOT NULL REFERENCES tracks(uri),
  genre_slug TEXT NOT NULL REFERENCES genres(slug),
  PRIMARY KEY (track_uri, genre_slug)
);

CREATE TABLE IF NOT EXISTS playlists (
  slug        TEXT PRIMARY KEY,
  title       TEXT NOT NULL,
  kind        TEXT NOT NULL,  -- 'classement' | 'scene' | 'selection'
  description TEXT,
  updated_at  INTEGER
);

CREATE TABLE IF NOT EXISTS playlist_items (
  playlist_slug TEXT NOT NULL REFERENCES playlists(slug),
  track_uri     TEXT NOT NULL REFERENCES tracks(uri),
  position      INTEGER NOT NULL,
  PRIMARY KEY (playlist_slug, track_uri)
);

-- Nos propres compteurs : les classements sont a nous, pas a la plateforme.
CREATE TABLE IF NOT EXISTS plays (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  track_uri  TEXT NOT NULL,
  played_at  INTEGER NOT NULL DEFAULT (unixepoch()),
  ms_played  INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_plays_track_date ON plays(track_uri, played_at);

-- Clips que le banc a vus refuser l'integration. Ils sont retires de `tracks`,
-- mais `search.list` continue de les rendre : sans memoire du refus, un clip
-- purge revient dans les resultats et se barre a la lecture.
CREATE TABLE IF NOT EXISTS clips_refuses (
  external_id TEXT PRIMARY KEY,
  source      TEXT NOT NULL DEFAULT 'youtube',
  verdict     TEXT NOT NULL,          -- 'erreur:150', 'erreur:101', ...
  checked_at  INTEGER
);

CREATE TABLE IF NOT EXISTS kv_cache (
  key        TEXT PRIMARY KEY,
  payload    TEXT NOT NULL,
  expires_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_kv_expiry ON kv_cache(expires_at);

INSERT OR IGNORE INTO genres (slug, label, tagline, position) VALUES
  ('pop',       'Pop',               'Grands refrains et production au cordeau.', 1),
  ('afrobeats', 'Afrobeats',         'Basses rondes et percussions d Afrique de l Ouest.', 2),
  ('rap-fr',    'Rap francais',      'La scene francaise, du texte brut a l autotune.', 3),
  ('hiphop',    'Hip-Hop',           'Le rap americain, de la cote est a Atlanta.', 4),
  ('kpop',      'K-pop',             'La pop coreenne, travaillee jusqu au dernier temps.', 5),
  ('gasy',      'Musique malgache',  'De Mahaleo au rap de Tana : notre etagere la plus profonde.', 6),
  ('zouk',      'Zouk & Kompa',      'Zouk, kompa et kuduro, des racines a la generation love.', 7),
  ('gospel',    'Gospel',            'Choeurs, orgue et louange.', 8);

-- Sous-genres : le style precis sous le genre large.
--
-- Pourquoi. Le genre seul est trop grossier pour enchainer. Les 74 titres
-- malgaches vivaient dans un unique `gasy` : apres les titres du meme artiste,
-- « Hay hay » de Mahaleo enchainait sur du rap gasy, parce que ce sont les
-- plus vus du genre. Un sous-genre donne un palier intermediaire : meme
-- artiste, puis meme style, puis seulement le genre.
--
-- Les titres gardent leur genre racine : rien ne change pour les rayons ni
-- pour /v1/genres, qui n'affichent que les genres sans parent.
--
-- Le rattachement se fait par nom d'artiste, pas par URI de titre : chaque
-- artiste du catalogue tient dans un seul style, et un nouveau titre seme plus
-- tard herite du bon style en rejouant ce fichier.

INSERT OR REPLACE INTO genres (slug, label, tagline, position, parent) VALUES
  ('gasy-folk',    'Folk gasy',           'Guitare, voix, ba-gasy : les classiques.',       61, 'gasy'),
  ('gasy-pop',     'Pop gasy',            'Variete et R&B d''Antananarivo.',                62, 'gasy'),
  ('gasy-urbain',  'Rap & trap gasy',     'La scene urbaine, du kawitry au drill.',         63, 'gasy'),
  ('gasy-cotier',  'Salegy & tsapiky',    'Le nord et le sud, pour danser.',                64, 'gasy'),
  ('zouk-racines', 'Zouk racines',        'Kassav'' et les fondateurs.',                    71, 'zouk'),
  ('zouk-rnb',     'Zouk R&B',            'La generation love et R&B.',                     72, 'zouk'),
  ('zouk-afro',    'Afro-zouk & kuduro',  'Kompa, kuduro, afro-house.',                     73, 'zouk');

-- gasy
INSERT OR IGNORE INTO track_genres (track_uri, genre_slug)
SELECT t.uri, 'gasy-folk' FROM tracks t JOIN artists a ON a.uri = t.artist_uri
WHERE a.name IN ('Mahaleo', 'Erick Manana', 'Rija Rasolondraibe');

INSERT OR IGNORE INTO track_genres (track_uri, genre_slug)
SELECT t.uri, 'gasy-pop' FROM tracks t JOIN artists a ON a.uri = t.artist_uri
WHERE a.name IN ('Niu Raza', 'Henika', 'Shyn');

INSERT OR IGNORE INTO track_genres (track_uri, genre_slug)
SELECT t.uri, 'gasy-urbain' FROM tracks t JOIN artists a ON a.uri = t.artist_uri
WHERE a.name IN ('Rim-Ka', 'Ceasar', 'Arione Joy', 'Mr Sayda', 'Lowis', 'Denise');

INSERT OR IGNORE INTO track_genres (track_uri, genre_slug)
SELECT t.uri, 'gasy-cotier' FROM tracks t JOIN artists a ON a.uri = t.artist_uri
WHERE a.name IN ('Wawa Salegy', 'Vaiavy Chila');

-- zouk
INSERT OR IGNORE INTO track_genres (track_uri, genre_slug)
SELECT t.uri, 'zouk-racines' FROM tracks t JOIN artists a ON a.uri = t.artist_uri
WHERE a.name IN ('Kassav', 'Jacob Desvarieux');

INSERT OR IGNORE INTO track_genres (track_uri, genre_slug)
SELECT t.uri, 'zouk-rnb' FROM tracks t JOIN artists a ON a.uri = t.artist_uri
WHERE a.name IN ('Medhy Custos', 'Warren', 'Fanny J');

INSERT OR IGNORE INTO track_genres (track_uri, genre_slug)
SELECT t.uri, 'zouk-afro' FROM tracks t JOIN artists a ON a.uri = t.artist_uri
WHERE a.name IN ('Kaysha');

-- Invariant : un titre qui porte un style porte aussi le genre qui le contient.
-- Sans cela, « Gâter Pourri » de Rim-Ka — du rap en francais par un artiste
-- gasy — serait un style sans genre racine, et il sortirait des enchainements
-- gasy sans jamais apparaitre dans le rayon.
INSERT OR IGNORE INTO track_genres (track_uri, genre_slug)
SELECT tg.track_uri, g.parent FROM track_genres tg
JOIN genres g ON g.slug = tg.genre_slug
WHERE g.parent IS NOT NULL;

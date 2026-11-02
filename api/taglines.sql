-- Taglines de genres, ecrites pour hira.
--
-- Les precedentes etaient celles de lyrify, mot pour mot : reprises telles
-- quelles le jour ou on a examine leur page. Ce ne sont pas nos textes, et
-- lyrify n est pas a nous. INSERT OR IGNORE dans schema.sql ne touche pas une
-- ligne existante, d ou ces UPDATE pour les bases deja semees.

UPDATE genres SET tagline = 'Grands refrains et production au cordeau.' WHERE slug = 'pop';
UPDATE genres SET tagline = 'Basses rondes et percussions d Afrique de l Ouest.' WHERE slug = 'afrobeats';
UPDATE genres SET tagline = 'La scene francaise, du texte brut a l autotune.' WHERE slug = 'rap-fr';
UPDATE genres SET tagline = 'Le rap americain, de la cote est a Atlanta.' WHERE slug = 'hiphop';
UPDATE genres SET tagline = 'La pop coreenne, travaillee jusqu au dernier temps.' WHERE slug = 'kpop';
UPDATE genres SET tagline = 'De Mahaleo au rap de Tana : notre etagere la plus profonde.' WHERE slug = 'gasy';
UPDATE genres SET tagline = 'Reggaeton, corridos et guitares du continent.' WHERE slug = 'latino';
UPDATE genres SET tagline = 'Zouk, kompa et kuduro, des racines a la generation love.' WHERE slug = 'zouk';
UPDATE genres SET tagline = 'Choeurs, orgue et louange.' WHERE slug = 'gospel';

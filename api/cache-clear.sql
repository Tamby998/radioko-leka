-- Vide le cache applicatif. A lancer apres toute modification du catalogue :
-- `cachedJson` sert sinon l'ancienne reponse jusqu'a expiration (24 h pour les
-- genres), et on croit a tort que le seed n'a pas ete pris.
-- Ne touche que `kv_cache`, dont le contenu est par definition regenerable.
DELETE FROM kv_cache;

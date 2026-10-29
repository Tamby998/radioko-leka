//! Lecteur IFrame officiel.
//!
//! Il reste visible pendant toute la lecture : c'est la condition d'usage de
//! l'API, et ce qui fait que la vue revient a la chaine de l'artiste. Rien
//! n'est extrait, rien n'est copie — le lecteur joue dans la page, et c'est
//! tout ce qu'on lui demande.

let pret = null;

/** Charge l'API une seule fois, et resout quand elle est utilisable. */
function chargerApi() {
  if (pret) return pret;
  pret = new Promise((resoudre) => {
    if (window.YT?.Player) return resoudre(window.YT);
    const precedent = window.onYouTubeIframeAPIReady;
    window.onYouTubeIframeAPIReady = () => {
      precedent?.();
      resoudre(window.YT);
    };
    const script = document.createElement('script');
    script.src = 'https://www.youtube.com/iframe_api';
    document.head.appendChild(script);
  });
  return pret;
}

/**
 * Codes d'erreur de l'API qui signifient « ce clip ne jouera jamais ici ».
 *
 * 101 et 150 sont le meme refus : l'ayant droit interdit l'integration. Ils
 * n'apparaissent qu'a la lecture — `status.embeddable` de la Data API vaut
 * `true` pour des clips qui echouent quand meme, donc ce signal-ci est le seul
 * qui dise la verite. 100 : clip supprime ou prive entre-temps.
 */
const REFUS = new Set([100, 101, 150]);

export class LecteurYouTube {
  #player = null;
  #conteneur;
  #surFin;
  #surRefus;

  constructor(idElement, surFin, surRefus) {
    this.#conteneur = idElement;
    this.#surFin = surFin;
    this.#surRefus = surRefus;
  }

  async jouer(videoId) {
    const YT = await chargerApi();
    if (this.#player) {
      this.#player.loadVideoById(videoId);
      return;
    }
    this.#player = new YT.Player(this.#conteneur, {
      videoId,
      playerVars: {
        // Lecture dans la page sur mobile : sans ca iOS passe en plein ecran.
        playsinline: 1,
        rel: 0,
        modestbranding: 1,
      },
      events: {
        onReady: (e) => e.target.playVideo(),
        onStateChange: (e) => {
          if (e.data === YT.PlayerState.ENDED) this.#surFin?.();
        },
        // Sans ca, le lecteur affiche « Regarder sur YouTube » et la seule
        // issue pour l'utilisateur est de quitter la page. On enchaine.
        onError: (e) => {
          if (REFUS.has(e.data)) this.#surRefus?.(e.data);
        },
      },
    });
  }

  /** Position en millisecondes, pour caler les paroles. */
  position() {
    const secondes = this.#player?.getCurrentTime?.() ?? 0;
    return Math.max(0, secondes * 1000);
  }

  /** Saut dans la piste, declenche en tapant une ligne de paroles. */
  chercher(ms) {
    this.#player?.seekTo?.(ms / 1000, true);
  }

  /** Bascule lecture/pause. Renvoie l'etat obtenu, ou null si pas de lecteur. */
  basculerPause() {
    const p = this.#player;
    if (!p?.getPlayerState) return null;
    const enPause = p.getPlayerState() !== window.YT?.PlayerState?.PLAYING;
    if (enPause) p.playVideo?.();
    else p.pauseVideo?.();
    return enPause; // vrai si on vient de relancer
  }

  enLecture() {
    return this.#player?.getPlayerState?.() === window.YT?.PlayerState?.PLAYING;
  }

  arreter() {
    this.#player?.stopVideo?.();
  }

  visible(oui) {
    const noeud = document.getElementById(this.#conteneur);
    if (noeud) noeud.style.display = oui ? '' : 'none';
  }
}

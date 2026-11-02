//! Assemblage : recherche, choix d'un titre, lecture, paroles.
//!
//! Deux moteurs, choisis par les capacites du titre — la meme frontiere que
//! cote Worker et cote terminal :
//!
//! - catalogue mondial  -> lecteur IFrame officiel, visible dans la page ;
//! - sous licence/local -> balise `<audio>`, flux direct, rien n'est ecrit.

import * as api from './api.js';
import { depuisFichiers } from './local.js';
import { indexA, parseLrc } from './lyrics.js';
import {
  artistesFrequents,
  ecoutes,
  melanger,
  noterEcoute,
  sansDoublon,
} from './mixes.js';
import { avantRotation, ecouteGasy, tranche } from './region.js';
import { surveillerReveil } from './reveil.js';
import { LecteurYouTube } from './youtube.js';

const $ = (id) => document.getElementById(id);
const elements = {
  form: $('recherche'),
  q: $('q'),
  locaux: $('locaux'),
  etat: $('etat'),
  liste: $('liste'),
  audio: $('audio'),
  encours: $('encours'),
  paroles: $('paroles'),
  rayons: $('rayons'),
  suite: $('suite'),
  file: $('file'),
  compteSuite: $('compteSuite'),
  precedent: $('precedent'),
  pause: $('pause'),
  suivant: $('suivant'),
  favori: $('favori'),
};

let resultats = [];
let courant = null;
let parolesCourantes = null;
let ligneAffichee = -1;
/**
 * Clips dont le lecteur a refuse l'integration : on ne les repropose pas.
 *
 * Garde entre deux visites. Le serveur ne connait que les refus mesures au
 * banc ; ceux-la sont mesures par toi, en lecture reelle, et sur des clips que
 * la recherche live rend sans que le catalogue les ait jamais vus. Oublier le
 * refus a chaque rechargement, c'est reproposer le meme clip barre demain.
 */
const REFUSES_CLE = 'hira.refuses.v1';

function lireRefuses() {
  try {
    const brut = localStorage.getItem(REFUSES_CLE);
    return new Set(brut ? JSON.parse(brut) : []);
  } catch {
    return new Set(); // navigation privee, stockage bloque : on continue sans
  }
}

const refuses = lireRefuses();

function retenirRefus(uri) {
  refuses.add(uri);
  try {
    localStorage.setItem(REFUSES_CLE, JSON.stringify([...refuses]));
  } catch {
    /* le refus tient pour la session, c'est deja l'essentiel */
  }
}
/** Les `<p>` des paroles, construits une fois par titre. */
let lignesDom = [];
/**
 * Ce qui jouera apres le titre courant.
 *
 * Choisir un titre dans une liste met la suite de cette liste dans la file :
 * c'est ce qui fait qu'une playlist s'ecoute d'un bout a l'autre sans cliquer.
 * Quand elle se vide, on retombe sur les suggestions du serveur.
 */
let file = [];
/** Ce qui a deja ete joue, pour le bouton precedent. */
const historique = [];

/**
 * Favoris, gardes entre deux visites.
 *
 * Le titre entier est stocke, pas seulement l'uri : un favori doit rester
 * ouvrable meme si le catalogue ne le renvoie plus dans une recherche.
 */
const FAVORIS_CLE = 'hira.favoris.v1';

function lireFavoris() {
  try {
    const brut = localStorage.getItem(FAVORIS_CLE);
    return brut ? new Map(JSON.parse(brut)) : new Map();
  } catch {
    return new Map(); // navigation privee, stockage bloque : on continue sans
  }
}

function ecrireFavoris(map) {
  try {
    localStorage.setItem(FAVORIS_CLE, JSON.stringify([...map]));
  } catch {
    /* rien a faire : les favoris restent le temps de la session */
  }
}

let favoris = lireFavoris();

const youtube = new LecteurYouTube('yt', () => void enchainer(), () => void contourner());

const minutes = (ms) => {
  if (!ms) return '';
  const total = Math.round(ms / 1000);
  return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, '0')}`;
};

const artistes = (titre) =>
  titre.artists?.map((a) => a.name).join(', ') || 'Artiste inconnu';

/** Le titre a-t-il besoin du lecteur video officiel ? */
const videoObligatoire = (titre) =>
  titre.requiresVisiblePlayer || !titre.capabilities?.includes('audioOnly');

/**
 * Ce qu'on accepte de montrer.
 *
 * Un clip deja vu refuser l'integration n'a rien a faire dans une liste : il
 * occuperait une place et se barrerait a la lecture. Le filtre est pose ici
 * plutot qu'a chaque appel, pour qu'il couvre aussi les genres, les playlists
 * et les mixes. Un refus survenu *pendant* cette lecture reste visible et
 * barre : la liste etait deja construite, et le barre est ce qui explique le
 * saut.
 */
const jouables = (titres) => titres.filter((t) => !refuses.has(t.uri));

function afficherListe(titresBruts, message) {
  const titres = jouables(titresBruts);
  resultats = titres;
  elements.etat.textContent = message;
  elements.liste.innerHTML = '';

  titres.forEach((titre, i) => {
    const li = document.createElement('li');
    li.className = 'piste';
    li.tabIndex = 0;
    li.innerHTML = `
      <span class="rang">${i + 1}</span>
      <span class="marque" title="${
        titre.source === 'local' ? 'ton fichier' : videoObligatoire(titre) ? 'lecteur officiel' : 'audio direct'
      }">${titre.source === 'local' ? '★' : videoObligatoire(titre) ? '▶' : '♪'}</span>
      <span class="titre">${titre.title}</span>
      <span class="artiste">${artistes(titre)}</span>
      <span class="duree">${minutes(titre.durationMs)}</span>`;
    // La suite de la liste devient la file : une playlist s'ecoute en entier.
    const lancer = () => {
      file = titres.slice(i + 1);
      void jouer(titre);
    };
    li.addEventListener('click', lancer);
    li.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault();
        lancer();
      }
    });
    elements.liste.appendChild(li);
  });
}

async function jouer(titre, options = {}) {
  // Le retour en arriere ne doit pas empiler ce qu'il depile.
  if (courant && !options.retour && courant.uri !== titre.uri) {
    historique.push(courant);
  }
  courant = titre;
  ligneAffichee = -1;
  parolesCourantes = null;

  [...elements.liste.children].forEach((li, i) =>
    li.classList.toggle('actif', resultats[i]?.uri === titre.uri),
  );

  elements.encours.innerHTML =
    `<strong>${titre.title}</strong><span>${artistes(titre)}</span>`;
  // Une reprise apres un reveil n'est pas une nouvelle ecoute : la compter
  // deux fois biaiserait les mixes construits dessus.
  if (!options.reprise) noterEcoute(titre);
  rendreRayonsPersonnels();
  rendreFile();
  // « À suivre » ne doit jamais etre vide : jouer le dernier titre d'une liste
  // laissait la file a zero jusqu'a la fin du morceau. On garnit en fond.
  if (file.length < 4) void regarnir(titre);
  rendreCommandes();
  lignesDom = [];
  elements.paroles.innerHTML = '<p class="message">Recherche des paroles…</p>';

  if (videoObligatoire(titre)) {
    // Catalogue mondial : le lecteur officiel, visible, dans la page.
    elements.audio.pause();
    elements.audio.removeAttribute('src');
    elements.audio.hidden = true;
    youtube.visible(true);
    await youtube.jouer(titre.uri.split(':')[1]);
  } else {
    // Audio direct : rien a afficher, rien a ecrire sur le disque.
    youtube.arreter();
    youtube.visible(false);
    elements.audio.hidden = false;
    elements.audio.src = titre.streamUrl;
    await elements.audio.play().catch(() => {});
  }

  parolesCourantes = await chargerParoles(titre);
  rendreParoles(parolesCourantes);
}

/** Le `.lrc` pose a cote du fichier gagne sur toute recherche en ligne. */
async function chargerParoles(titre) {
  if (titre.lrcFile) {
    const texte = await titre.lrcFile.text();
    const parse = parseLrc(texte);
    if (parse.lines.length) return parse;
  }
  return api.paroles(titre);
}

/**
 * Un clip dont l'integration est refusee : on passe au suivant de la liste.
 *
 * C'est le seul moment ou le refus se manifeste, et sans ca l'utilisateur se
 * retrouve devant « Regarder sur YouTube » — exactement ce que cette app
 * existe pour eviter. Les reprises d'un meme titre sont nombreuses, donc le
 * suivant joue presque toujours.
 */
async function contourner() {
  if (!courant) return;
  retenirRefus(courant.uri);
  marquerRefuse(courant.uri);
  // Meme chemin que la fin normale d'un titre : la file d'abord, les
  // suggestions ensuite. Passer par les resultats laisserait le titre refuse
  // dans la file, et il serait repropose au titre suivant.
  await enchainer();
}

/** Barre le titre refuse dans la liste, pour que le choix reste lisible. */
function marquerRefuse(uri) {
  const index = resultats.findIndex((t) => t.uri === uri);
  elements.liste.children[index]?.classList.add('refuse');
}

/**
 * Complete la file a partir du titre courant.
 *
 * Appelee des que la file descend bas, pas seulement quand elle est vide : on
 * veut que « À suivre » montre toujours quelque chose, et que l'enchainement
 * n'ait jamais a attendre un aller-retour reseau.
 */
async function regarnir(graine) {
  if (!graine) return 0;
  let suite = [];
  try {
    suite = await api.similaires(graine);
  } catch {
    return 0;
  }

  const connus = new Set([
    graine.uri,
    courant?.uri,
    ...file.map((t) => t.uri),
    ...refuses,
  ]);
  const neufs = sansDoublon(suite).filter((t) => !connus.has(t.uri));
  file.push(...neufs);
  rendreFile();
  return neufs.length;
}

/**
 * Construit un mix autour d'un artiste deja ecoute.
 *
 * Ses propres titres servent d'ossature, les suggestions du serveur elargissent
 * autour. Melange a la journee : le meme mix ne ressort pas dans le meme ordre
 * demain.
 */
async function construireMix(artiste) {
  const siens = artiste.graines;
  const autour = [];
  for (const graine of siens) {
    try {
      autour.push(...(await api.similaires(graine)));
    } catch {
      /* une graine muette n'empeche pas le mix */
    }
  }
  return melanger(sansDoublon([...siens, ...autour])).slice(0, 40);
}

/**
 * Lecture automatique : la file d'abord, les suggestions ensuite.
 *
 * L'ordre compte. Si on interrogeait le serveur en premier, choisir le 3e titre
 * d'une playlist enchainerait sur un titre « proche » au lieu du 4e — et la
 * playlist ne voudrait plus rien dire.
 */
async function enchainer() {
  if (!courant) return;

  while (file.length) {
    const suivant = file.shift();
    if (!refuses.has(suivant.uri)) {
      await jouer(suivant);
      // Recharge en fond : la lecture a deja repris, personne n'attend.
      if (file.length < 4) void regarnir(suivant);
      return;
    }
  }

  // La file est vide : on la regarnit depuis le titre courant, puis depuis ce
  // qui a ete ecoute avant. C'est ce qui rend la lecture reellement sans fin,
  // au lieu de retomber sur la liste de depart.
  if (await regarnir(courant)) return enchainer();

  for (const e of ecoutes().slice(0, 6)) {
    if (e.uri === courant.uri) continue;
    if (await regarnir(e)) return enchainer();
  }

  // Une file vide et un Worker muet ne sont pas la meme chose. Apres une
  // veille c'est presque toujours le second, et annoncer le premier envoyait
  // relancer une recherche qui ne pouvait pas aboutir.
  if (!(await api.enLigne())) {
    elements.file.innerHTML =
      '<li class="vide">Worker injoignable. La file reprend dès qu’il répond.</li>';
    return;
  }

  elements.file.innerHTML =
    '<li class="vide">Plus rien à enchaîner. Lance une autre recherche.</li>';
}

/**
 * Ce qui jouait au dernier battement.
 *
 * `requestAnimationFrame` est gele des que la page passe derriere — mesure sur
 * cette machine : 5395 images, puis plus une seule. Il ne peut donc pas tenir
 * cette memoire. C'est le battement de `reveil.js` qui la tient, a sa periode
 * pres : une reprise recule donc d'au plus dix secondes, ce qui vaut mieux que
 * de reprendre au debut.
 */
let avantSommeil = null;

function noterPosition() {
  if (!courant) {
    avantSommeil = null;
    return;
  }
  avantSommeil = { titre: courant, ms: positionMs(), jouait: enLecture() };
}

/** Le moteur en cours joue-t-il vraiment ? */
function enLecture() {
  return videoObligatoire(courant) ? youtube.enLecture() : !elements.audio.paused;
}

/**
 * Reprise apres un reveil de machine.
 *
 * L'ordre compte. On interroge le Worker d'abord : la veille a suspendu les
 * deux serveurs locaux, et tant qu'ils ne repondent pas, ni les suggestions ni
 * les paroles n'aboutiront, donc relancer la lecture ne ferait que preparer la
 * prochaine impasse. S'il ne revient pas, on le dit — c'est ce que l'ancienne
 * fin de file cachait derriere « Plus rien à enchaîner ».
 */
async function auReveil(dormiMs) {
  const minutes = Math.round(dormiMs / 60_000);
  const repere = avantSommeil;

  elements.etat.textContent = `Réveil après ${minutes} min — reconnexion au Worker…`;

  if (!(await api.attendreLeWorker())) {
    elements.etat.textContent =
      'Worker injoignable après le réveil. Relance-le : cd api && npm run dev';
    return;
  }

  elements.etat.textContent = `Réveil après ${minutes} min — reprise.`;

  // La file est en memoire, elle a traverse la veille intacte ; c'est la
  // lecture qui s'est arretee. On ne relance que ce qui jouait vraiment :
  // reprendre un titre que tu avais mis en pause serait une surprise.
  if (repere?.jouait) {
    await jouer(repere.titre, { reprise: true });
    if (repere.ms > 3000) positionner(repere.ms);
  }

  // Et on regarnit : les suggestions demandees pendant la veille ont echoue.
  if (courant && file.length < 4) void regarnir(courant);
  rendreFile();
}

/** Etat des boutons : favori rempli, precedent grise quand rien derriere. */
function rendreCommandes() {
  const actif = Boolean(courant);
  elements.precedent.disabled = historique.length === 0;
  elements.pause.disabled = !actif;
  elements.suivant.disabled = !actif;
  elements.favori.disabled = !actif;

  const aime = actif && favoris.has(courant.uri);
  elements.favori.textContent = aime ? '★' : '☆';
  elements.favori.classList.toggle('aime', Boolean(aime));
  elements.favori.title = aime ? 'Retirer des favoris' : 'Ajouter aux favoris';
}

/** Revenir au titre precedent. Le courant repasse en tete de file. */
async function precedent() {
  const avant = historique.pop();
  if (!avant) return;
  if (courant) file.unshift(courant);
  await jouer(avant, { retour: true });
}

function basculerPause() {
  if (!courant) return;
  if (videoObligatoire(courant)) {
    const relance = youtube.basculerPause();
    elements.pause.textContent = relance === false ? '▶' : '⏸';
  } else if (elements.audio.paused) {
    void elements.audio.play().catch(() => {});
    elements.pause.textContent = '⏸';
  } else {
    elements.audio.pause();
    elements.pause.textContent = '▶';
  }
}

function basculerFavori() {
  if (!courant) return;
  if (favoris.has(courant.uri)) favoris.delete(courant.uri);
  else favoris.set(courant.uri, courant);
  ecrireFavoris(favoris);
  rendreCommandes();
  rendreRayonFavoris();
}

/** Le panneau « À suivre », replie par defaut pour ne pas voler la vue. */
function rendreFile() {
  elements.compteSuite.textContent = file.length ? `· ${file.length}` : '';
  elements.file.innerHTML = '';

  if (!file.length) {
    elements.file.innerHTML =
      '<li class="vide">La suite viendra des suggestions.</li>';
    return;
  }

  file.slice(0, 12).forEach((titre, i) => {
    const li = document.createElement('li');
    li.className = 'aSuivre';
    li.innerHTML =
      `<span class="titre">${titre.title}</span>` +
      `<span class="artiste">${artistes(titre)}</span>`;
    // Sauter directement a ce titre : ce qui le precede quitte la file.
    li.addEventListener('click', () => {
      file = file.slice(i + 1);
      void jouer(titre);
    });
    elements.file.appendChild(li);
  });
}

/**
 * Rayon « Favoris », toujours en tete et toujours present.
 *
 * Il se redessine a chaque ajout : le compte doit suivre sans recharger.
 */
function rendreRayonFavoris() {
  let bouton = document.getElementById('rayonFavoris');
  if (!bouton) {
    bouton = document.createElement('button');
    bouton.id = 'rayonFavoris';
    bouton.className = 'rayon favoris';
    bouton.type = 'button';
    bouton.addEventListener('click', () => {
      const titres = [...favoris.values()];
      afficherListe(
        titres,
        titres.length
          ? `Tes favoris — ${titres.length} titres`
          : 'Aucun favori. Ajoute-en avec l’étoile sous le lecteur.',
      );
    });
    elements.rayons.prepend(bouton);
  }
  bouton.innerHTML = `★ Favoris<span class="compte">${favoris.size}</span>`;
}

/**
 * La liste proposee, renouvelee a chaque tranche de cinq heures.
 *
 * Son assise depend d'ou l'on ecoute : depuis Madagascar, ou en malgache, elle
 * part du genre gasy du catalogue plutot que du classement general. Ailleurs,
 * elle part du classement. Dans les deux cas l'ordre est fige pour la tranche
 * en cours, puis rebattu.
 */
async function listeProposee() {
  const graine = tranche();
  const tete = ecouteGasy() ? await api.genre('gasy').catch(() => []) : [];
  const reste = await api.classement().catch(() => []);

  // Les deux groupes sont melanges separement, puis concatenes. Melanger
  // l'ensemble d'un bloc noierait les quatre titres gasy au milieu de
  // cinquante autres — c'est exactement ce qu'on veut eviter.
  return sansDoublon([
    ...melanger(tete, graine),
    ...melanger(reste, graine),
  ]).slice(0, 50);
}

function rendreRayonPropose() {
  const gasy = ecouteGasy();
  let bouton = document.getElementById('rayonPropose');
  if (!bouton) {
    bouton = document.createElement('button');
    bouton.id = 'rayonPropose';
    bouton.className = 'rayon propose';
    bouton.type = 'button';
    bouton.addEventListener('click', async () => {
      afficherListe([], 'Préparation de ta sélection…');
      const titres = await listeProposee();
      afficherListe(titres, `${bouton.dataset.libelle} — ${titres.length} titres`);
    });
    elements.rayons.prepend(bouton);
  }
  bouton.dataset.libelle = gasy ? 'Gasy pour toi' : 'Pour toi';
  bouton.innerHTML = `◆ ${bouton.dataset.libelle}`;
  bouton.title = gasy
    ? 'Priorité à la musique malgache, renouvelée toutes les 5 heures'
    : 'Renouvelée toutes les 5 heures';
}

/** Rayon « Historique » : ce qui a ete joue, du plus recent au plus ancien. */
function rendreRayonHistorique() {
  const liste = ecoutes();
  let bouton = document.getElementById('rayonHistorique');

  if (!liste.length) {
    bouton?.remove();
    return;
  }
  if (!bouton) {
    bouton = document.createElement('button');
    bouton.id = 'rayonHistorique';
    bouton.className = 'rayon';
    bouton.type = 'button';
    bouton.addEventListener('click', () => {
      const titres = ecoutes();
      afficherListe(titres, `Historique — ${titres.length} titres`);
    });
    document.getElementById('rayonFavoris')?.after(bouton);
  }
  bouton.innerHTML = `⏱ Historique<span class="compte">${liste.length}</span>`;
}

/**
 * Un rayon par artiste frequemment ecoute.
 *
 * Les mixes ne sont pas construits ici : seulement les boutons. Batir huit
 * mixes au chargement ferait huit series d'appels pour des listes que personne
 * n'ouvrira peut-etre. Le mix se construit au clic.
 */
function rendreMixes() {
  const artistes = artistesFrequents(8);
  const existants = new Map(
    [...document.querySelectorAll('.rayon.mix')].map((b) => [b.dataset.artiste, b]),
  );

  artistes.forEach((artiste, rang) => {
    let bouton = existants.get(artiste.nom);
    existants.delete(artiste.nom);

    if (!bouton) {
      bouton = document.createElement('button');
      bouton.className = 'rayon mix';
      bouton.type = 'button';
      bouton.dataset.artiste = artiste.nom;
      bouton.addEventListener('click', async () => {
        afficherListe([], `Construction du mix ${artiste.nom}…`);
        const titres = await construireMix(artiste);
        afficherListe(
          titres,
          titres.length
            ? `Mix ${artiste.nom} — ${titres.length} titres`
            : `Rien à mettre dans un mix ${artiste.nom} pour l'instant.`,
        );
      });
      elements.rayons.appendChild(bouton);
    }
    bouton.innerHTML =
      `Mix ${artiste.nom}<span class="compte">${artiste.fois}</span>`;
    bouton.title = `Construit autour de ${artiste.nom}, d'après tes écoutes`;
    bouton.style.order = String(rang);
  });

  // Un artiste sorti du classement perd son rayon.
  for (const orphelin of existants.values()) orphelin.remove();
}

/** Redessine tout ce qui depend des ecoutes. */
function rendreRayonsPersonnels() {
  rendreRayonPropose();
  rendreRayonFavoris();
  rendreRayonHistorique();
  rendreMixes();
}

/** Un rayon par genre du catalogue, apres les rayons personnels. */
async function rendreGenres() {
  let listes = [];
  try {
    listes = await api.genres();
  } catch {
    return;
  }
  listes.forEach((g, rang) => {
    const bouton = document.createElement('button');
    bouton.className = 'rayon genre';
    bouton.type = 'button';
    bouton.innerHTML = `${g.label}<span class="compte">${g.count}</span>`;
    bouton.title = g.tagline || g.label;
    bouton.style.order = String(20 + rang);
    bouton.addEventListener('click', async () => {
      afficherListe([], `Ouverture de « ${g.label} »…`);
      const titres = await api.genre(g.slug);
      afficherListe(titres, `${g.label} — ${titres.length} titres`);
    });
    elements.rayons.appendChild(bouton);
  });
}

/** Les rayons editoriaux, charges une fois au demarrage. */
async function rendreRayons() {
  let listes = [];
  try {
    listes = await api.playlists();
  } catch {
    return; // les rayons sont un confort, pas une condition de demarrage
  }
  if (!listes.length) return;

  for (const liste of listes) {
    const bouton = document.createElement('button');
    bouton.className = 'rayon';
    bouton.type = 'button';
    bouton.innerHTML =
      `${liste.title}<span class="compte">${liste.count}</span>`;
    bouton.title = liste.description || liste.title;
    // Apres les rayons personnels, qui comptent plus au quotidien.
    bouton.style.order = '50';
    bouton.addEventListener('click', async () => {
      afficherListe([], `Ouverture de « ${liste.title} »…`);
      const titres = await api.playlist(liste.slug);
      afficherListe(titres, `${liste.title} — ${titres.length} titres`);
    });
    elements.rayons.appendChild(bouton);
  }
}

function positionMs() {
  if (!courant) return 0;
  return videoObligatoire(courant)
    ? youtube.position()
    : (elements.audio.currentTime || 0) * 1000;
}

/**
 * Construit les lignes une fois par titre.
 *
 * Les reconstruire a chaque changement de ligne effacerait la position de
 * defilement — donc tout geste de l'utilisateur — et ferait clignoter le
 * panneau. Ensuite seules les classes changent.
 */
function rendreParoles(paroles) {
  lignesDom = [];
  elements.paroles.scrollTop = 0;

  if (paroles?.instrumental) {
    elements.paroles.innerHTML = '<p class="message">Instrumental</p>';
    return;
  }
  const lignes = paroles?.lines ?? [];
  if (!lignes.length) {
    elements.paroles.innerHTML =
      '<p class="message">Paroles indisponibles pour ce titre</p>';
    return;
  }

  const fragment = document.createDocumentFragment();
  lignes.forEach((ligne, i) => {
    const p = document.createElement('p');
    p.className = 'ligne';
    p.textContent = ligne.text;
    // Taper une ligne saute a cet instant du morceau.
    p.addEventListener('click', () => positionner(ligne.atMs));
    fragment.appendChild(p);
    lignesDom.push(p);
  });
  elements.paroles.replaceChildren(fragment);
}

/** Saut dans la piste, quel que soit le moteur en cours. */
function positionner(ms) {
  if (!courant) return;
  if (videoObligatoire(courant)) youtube.chercher(ms);
  else elements.audio.currentTime = ms / 1000;
}

/**
 * Centre la ligne active dans le panneau.
 *
 * Appele au changement de ligne seulement, pas a chaque image : sinon on lutte
 * contre l'utilisateur des qu'il fait defiler lui-meme.
 */
function centrerSur(index) {
  const ligne = lignesDom[index];
  if (!ligne) return;
  const panneau = elements.paroles;
  panneau.scrollTo({
    top: ligne.offsetTop - panneau.clientHeight / 2 + ligne.offsetHeight / 2,
    behavior: 'smooth',
  });
}

/** Boucle d'affichage : surligne la ligne atteinte, et la garde centree. */
function rafraichir() {
  if (lignesDom.length) {
    const index = indexA(parolesCourantes, positionMs());
    if (index !== ligneAffichee) {
      // Trois etats, comme dans l'app : la ligne atteinte, celles deja passees
      // en retrait, celles a venir un peu plus lisibles.
      lignesDom.forEach((p, i) => {
        p.classList.toggle('actif', i === index);
        p.classList.toggle('passe', i < index);
      });
      ligneAffichee = index;
      centrerSur(index);
    }
  }
  requestAnimationFrame(rafraichir);
}

elements.form.addEventListener('submit', async (e) => {
  e.preventDefault();
  const requete = elements.q.value.trim();
  if (!requete) return;
  afficherListe([], `Recherche de « ${requete} »…`);
  try {
    const titres = jouables(await api.chercher(requete));
    afficherListe(
      titres,
      titres.length
        ? `${titres.length} résultats pour « ${requete} »`
        : `Aucun résultat pour « ${requete} ».`,
    );
  } catch (err) {
    afficherListe([], `Le Worker ne répond pas (${err.message}).`);
  }
});

elements.precedent.addEventListener('click', () => void precedent());
elements.suivant.addEventListener('click', () => void enchainer());
elements.pause.addEventListener('click', basculerPause);
elements.favori.addEventListener('click', basculerFavori);

// Le lecteur audio peut etre mis en pause par ses propres commandes natives :
// le bouton doit alors suivre, sinon il ment.
elements.audio.addEventListener('play', () => (elements.pause.textContent = '⏸'));
elements.audio.addEventListener('pause', () => (elements.pause.textContent = '▶'));

elements.locaux.addEventListener('change', (e) => {
  const titres = depuisFichiers(e.target.files);
  afficherListe(
    titres,
    titres.length ? `${titres.length} titres chez toi` : 'Aucun fichier audio reconnu.',
  );
});

// Au demarrage : le classement sous licence, pour ne pas ouvrir sur du vide.
(async () => {
  elements.audio.hidden = true;
  youtube.visible(false);
  requestAnimationFrame(rafraichir);

  rendreFile();
  rendreCommandes();
  rendreRayonsPersonnels();
  void rendreRayons();
  void rendreGenres();
  surveillerReveil((dormi) => void auReveil(dormi), noterPosition);

  if (!(await api.enLigne())) {
    elements.etat.textContent =
      'Worker injoignable. Lance-le : cd api && npm run dev';
    return;
  }
  try {
    const titres = await listeProposee();
    if (titres.length) {
      const libelle = document.getElementById('rayonPropose')?.dataset.libelle;
      afficherListe(titres, `${libelle} — ${titres.length} titres`);
    }
  } catch {
    /* la selection est un confort, pas une condition de demarrage */
  }

  programmerRotation();
})();

/**
 * Rebat la selection a la tranche suivante, sans recharger la page.
 *
 * Une session laissee ouverte toute la journee doit voir sa liste changer
 * comme celle de quelqu'un qui revient : sinon « toutes les cinq heures » ne
 * veut rien dire pour qui ne ferme jamais l'onglet.
 */
function programmerRotation() {
  setTimeout(() => {
    rendreRayonsPersonnels();
    void (async () => {
      const bouton = document.getElementById('rayonPropose');
      // On ne remplace la liste affichee que si c'est bien celle-la qu'on
      // regarde : sinon on ecraserait une recherche en cours.
      if (elements.etat.textContent.startsWith(bouton?.dataset.libelle ?? ' ')) {
        const titres = await listeProposee();
        afficherListe(titres, `${bouton.dataset.libelle} — ${titres.length} titres`);
      }
      programmerRotation();
    })();
  }, avantRotation());
}

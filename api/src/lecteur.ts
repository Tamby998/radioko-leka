/// La page du lecteur, servie en https depuis une vraie origine.
///
/// Elle existe parce que le 5 novembre 2026 Android refusait tout clip :
/// « This video is unavailable, error 152 - 4 ». Ce n etait ni le reseau — le
/// telephone et le Mac sortaient par la meme adresse — ni l agent de la
/// WebView, ni la video cachee : la meme sonde, servie par ce Worker et
/// ouverte dans une WebView ordinaire du telephone, a joue du premier coup.
///
/// C etait la page. `youtube_player_iframe` fabrique son HTML et le charge en
/// lui donnant pour base `https://www.youtube.com`, une origine qu elle n a
/// pas. Servie depuis cette URL-ci, l integration passe, avec l agent de
/// WebView d origine et sans rien masquer.
///
/// C est le montage du bureau, qui n a jamais eu ce probleme : une vraie
/// page, chargee par une vraie URL.
export function pageLecteur(): Response {
  return new Response(
    `<!doctype html>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>lecteur</title>
<style>
  html, body { margin: 0; background: #000; overflow: hidden; }
  #p { width: 100vw; height: 100vh; }
</style>
<body>
<div id="p"></div>
<script>
// Cette page ne dessine rien d autre : elle heberge le lecteur officiel, que
// les conditions d usage imposent de montrer. L interface est native, de
// l autre cote du pont.
//
// Deux ponts, car deux hotes : un canal JavaScript sur Android, les
// gestionnaires de messages de WebKit sur macOS. La page ne sait pas lequel
// l heberge, et n a pas a le savoir.
function dire(message) {
  var t = JSON.stringify(message);
  try { if (window.RadiokoLeka) { window.RadiokoLeka.postMessage(t); return; } } catch (e) {}
  try { window.webkit.messageHandlers.hira.postMessage(t); } catch (e) {}
}

let lecteur = null;
let attente = null;

window.onYouTubeIframeAPIReady = function () {
  lecteur = new YT.Player('p', {
    width: '100%',
    height: '100%',
    playerVars: { playsinline: 1, rel: 0, modestbranding: 1 },
    events: {
      onReady: () => { dire({ quoi: 'pret' }); if (attente) { jouer(attente); attente = null; } },
      onStateChange: (e) => dire({ quoi: 'etat', valeur: e.data }),
      onError: (e) => dire({ quoi: 'erreur', valeur: e.data }),
    },
  });
};

function jouer(id) {
  if (!lecteur) { attente = id; return; }
  lecteur.loadVideoById(id);
  lecteur.playVideo();
}
function basculer() {
  if (!lecteur) return false;
  const enLecture = lecteur.getPlayerState() === 1;
  if (enLecture) lecteur.pauseVideo(); else lecteur.playVideo();
  return !enLecture;
}
function position() { return lecteur ? Math.round(lecteur.getCurrentTime() * 1000) : 0; }
function duree() { return lecteur ? Math.round(lecteur.getDuration() * 1000) : 0; }
function volume(n) { if (lecteur) { lecteur.unMute(); lecteur.setVolume(n); } }
function vitesse(f) { if (lecteur) lecteur.setPlaybackRate(f); }
function aller(ms) { if (lecteur) lecteur.seekTo(ms / 1000, true); }
function stopper() { if (lecteur) lecteur.stopVideo(); }

// Le script de l API ne charge pas toujours du premier coup : vu echouer une
// fois, et l app restait alors muette pour de bon. Trois reessais espaces
// avant de declarer forfait.
let essais = 0;
function chargerApi() {
  const s = document.createElement('script');
  s.src = 'https://www.youtube.com/iframe_api';
  s.onerror = () => {
    essais += 1;
    if (essais < 4) {
      dire({ quoi: 'api', valeur: 'reessai ' + essais });
      setTimeout(chargerApi, 800 * essais);
    } else {
      dire({ quoi: 'api', valeur: 'echec' });
    }
  };
  document.head.appendChild(s);
}
chargerApi();
</script>`,
    { headers: { 'content-type': 'text/html; charset=utf-8' } },
  );
}

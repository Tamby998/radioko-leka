/// Page de diagnostic de l'integration YouTube, servie en https.
///
/// Elle existe parce qu'une panne generale a frappe le 5 novembre 2026 :
/// tous les clips renvoyaient l'erreur 150, y compris ceux verifies jouables
/// la veille. Servie depuis ce Worker, donc depuis une origine https
/// publique, elle a d'abord montre que l'origine n'y etait pour rien.
///
/// Elle sert maintenant a departager les navigateurs : le meme code, la meme
/// machine, le meme reseau, et d'un cote Chrome, de l'autre les navigateurs
/// embarques dont nos deux lecteurs se servent.
///
/// Deux details comptent, et le premier nous a deja trompes :
///   - le lecteur est muet, car un navigateur refuse l'autoplay sonore sans
///     geste de l'utilisateur. Sans cela on reste en tampon, sans erreur, et
///     un sondage qui n'avance qu'en cas de lecture ou d'erreur se bloque la.
///   - on passe au clip suivant meme quand rien ne joue, en disant l'etat
///     atteint. Un silence doit se lire, pas s'interpreter.
export function sondeEmbed(url: URL): Response {
  // Les identifiants viennent de l'URL : la sonde doit pouvoir mesurer un
  // echantillon du catalogue, pas seulement les trois clips du premier jour.
  const demandes = (url.searchParams.get('ids') || '')
    .split(',')
    .map((s) => s.trim())
    .filter((s) => /^[A-Za-z0-9_-]{11}$/.test(s));
  const ids = demandes.length > 0
    ? demandes
    : ['dQw4w9WgXcQ', 'SIvQJHBfQl4', '87YqPAzwmJU', 'jkxCp9HuBp8'];
  return new Response(
    `<!doctype html><meta charset="utf-8"><title>sonde embed</title>
<body style="background:#111;color:#eee;font:14px system-ui">
<div id="p"></div><pre id="log"></pre>
<script>
const IDS = ${JSON.stringify(ids)};
const NOMS = {'-1':'non demarre','0':'fini','1':'JOUE','2':'pause','3':'tampon','5':'en attente'};
let i = 0, lecteur, minuteur, dernierEtat = -1, verdict = [];
const log = m => { document.getElementById('log').textContent += m + '\\n'; };
function suivant() {
  clearTimeout(minuteur);
  if (i >= IDS.length) {
    log('');
    log('VERDICT  ' + verdict.join('  '));
    log('agent    ' + navigator.userAgent);
    return;
  }
  const id = IDS[i++];
  dernierEtat = -1;
  log('essai ' + id);
  lecteur.loadVideoById(id);
  minuteur = setTimeout(() => {
    const e = lecteur.getPlayerState();
    log('  rien apres 8 s, etat=' + (NOMS[e] || e));
    verdict.push(id + '=' + (e === 1 ? 'joue' : 'muet(' + e + ')'));
    suivant();
  }, 6000);
}
function onYouTubeIframeAPIReady() {
  lecteur = new YT.Player('p', {
    height: 240, width: 400,
    // mute : sans lui l'autoplay est refuse et le sondage ne conclut rien.
    playerVars: { playsinline: 1, rel: 0, modestbranding: 1, mute: 1 },
    events: {
      onReady: () => { log('api prete, origine=' + location.origin); suivant(); },
      onError: e => { log('  ERREUR ' + e.data); verdict.push(IDS[i - 1] + '=err' + e.data); suivant(); },
      onStateChange: e => {
        if (e.data === dernierEtat) return;
        dernierEtat = e.data;
        log('  etat=' + (NOMS[String(e.data)] || e.data));
        if (e.data === 1) { verdict.push(IDS[i - 1] + '=joue'); suivant(); }
      },
    },
  });
}
const s = document.createElement('script');
s.src = 'https://www.youtube.com/iframe_api';
document.head.appendChild(s);
</script>`,
    { headers: { 'content-type': 'text/html; charset=utf-8' } },
  );
}

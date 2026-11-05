/// Page de diagnostic de l'integration YouTube, servie en https.
///
/// Elle existe parce qu'une panne generale a frappe le 5 novembre 2026 :
/// tous les clips renvoyaient l'erreur 150, y compris ceux verifies jouables
/// la veille. Reproduite hors de l'app, sur `http://127.0.0.1` comme sur
/// `http://localhost`, donc ni l'app ni le navigateur n'etaient en cause.
/// Restait l'origine elle-meme : les deux essais etaient en clair.
///
/// Cette page sert le meme code depuis une origine https, et tranche.
export function sondeEmbed(): Response {
  return new Response(
    `<!doctype html><meta charset="utf-8"><title>sonde embed</title>
<body style="background:#111;color:#eee;font:14px system-ui">
<div id="p"></div><pre id="log"></pre>
<script>
const IDS = ['SIvQJHBfQl4','87YqPAzwmJU','jkxCp9HuBp8'];
let i = 0, lecteur;
const log = m => { document.getElementById('log').textContent += m + '\\n'; };
function suivant() {
  if (i >= IDS.length) { log('fini'); return; }
  const id = IDS[i++];
  log('essai ' + id + '  origine=' + location.origin);
  lecteur.loadVideoById(id);
  setTimeout(() => { if (lecteur.getPlayerState() === 1) { log('  JOUE ' + id); suivant(); } }, 6000);
}
function onYouTubeIframeAPIReady() {
  lecteur = new YT.Player('p', {
    height: 240, width: 400,
    playerVars: { playsinline: 1, rel: 0, modestbranding: 1 },
    events: {
      onReady: () => { log('api prete'); suivant(); },
      onError: e => { log('  ERREUR ' + e.data); suivant(); },
      onStateChange: e => log('  etat=' + e.data),
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

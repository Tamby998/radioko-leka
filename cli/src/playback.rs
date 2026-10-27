//! Routage de la lecture, partage par la commande one-shot et le mode interactif.
//!
//! C'est ici que la frontiere du projet se traduit en comportement :
//! un titre qui peut donner son audio seul se joue dans le terminal, les autres
//! passent par le lecteur officiel dans le navigateur.
//!
//! Cache et telechargement sont deux choses distinctes :
//!
//! - le **cache** est un tampon technique. `afplay` ne sait lire qu'un fichier
//!   local, donc le flux atterrit sur le disque le temps de la lecture, dans un
//!   dossier temporaire efface en quittant. L'utilisateur n'a rien demande.
//! - le **telechargement** est un geste de l'utilisateur. Le fichier va dans sa
//!   musique, il reste, et il n'est possible que pour les titres qui portent la
//!   capacite `offline`.

use std::io::{self, Write};
use std::path::PathBuf;
use std::time::Duration;

use crate::api::{HiraApi, SyncedLyrics, Track};
use crate::capability::Capability;
use crate::karaoke::{self, Outcome};
use crate::library;
use crate::player::{Backend, Player};

type Res<T> = Result<T, Box<dyn std::error::Error>>;

/// Joue un titre, paroles comprises. Les paroles manquantes ne sont pas une erreur.
pub fn play(api: &HiraApi, track: &Track, up_next: Option<&str>) -> Res<Outcome> {
    let lyrics = resolve_lyrics(api, track);

    // Un fichier de l'utilisateur : rien a chercher, rien a mettre en tampon.
    if let Some(path) = track.local_path.clone() {
        return play_local(track, &path, lyrics.as_ref(), up_next);
    }

    // Deux conditions, pas une : il faut pouvoir consommer l'audio seul, et que
    // le titre n'exige pas un lecteur video visible.
    if track.can(Capability::AudioOnly) && !track.requires_visible_player {
        play_licensed(api, track, lyrics.as_ref(), up_next)
    } else {
        // Ce client est un terminal : il n'ouvre pas de navigateur. Un titre qui
        // exige un lecteur video n'a rien a faire dans ses resultats, et s'il y
        // arrive quand meme, on le dit au lieu d'ouvrir une fenetre.
        Err(format!(
            "« {} » demande un lecteur video : illisible dans un terminal.",
            track.title
        )
        .into())
    }
}

/// Paroles : le fichier `.lrc` pose a cote de l'audio gagne sur tout le reste.
///
/// C'est ce qui rend le repertoire qu'aucune base publique n'indexe enfin
/// synchronisable : l'utilisateur cale ses paroles une fois, elles restent.
fn resolve_lyrics(api: &HiraApi, track: &Track) -> Option<SyncedLyrics> {
    if let Some(path) = &track.local_path {
        if let Some(lrc) = library::sidecar_lyrics(path) {
            if let Ok(text) = std::fs::read_to_string(&lrc) {
                let parsed = library::parse_lrc(&text);
                if !parsed.lines.is_empty() {
                    return Some(parsed);
                }
            }
        }
    }
    api.lyrics_for(track).unwrap_or(None)
}

/// Bibliotheque locale : lecture directe du fichier.
fn play_local(
    track: &Track,
    path: &std::path::Path,
    lyrics: Option<&SyncedLyrics>,
    up_next: Option<&str>,
) -> Res<Outcome> {
    let backend = Backend::detect()
        .ok_or("aucun lecteur audio trouve. Installe mpv, ou lance ceci sur macOS (afplay)")?;
    let mut player = Player::new(backend);
    player.play_file(path)?;
    Ok(karaoke::run(track, lyrics, &mut player, Duration::ZERO, up_next)?)
}

/// Catalogue sous licence : audio dans le terminal.
fn play_licensed(
    api: &HiraApi,
    track: &Track,
    lyrics: Option<&SyncedLyrics>,
    up_next: Option<&str>,
) -> Res<Outcome> {
    let backend = Backend::detect().ok_or(
        "aucun lecteur audio trouve. Installe mpv, ou lance ceci sur macOS (afplay)",
    )?;
    let mut player = Player::new(backend);

    if backend.streams_remote_urls() {
        // mpv lit l'URL directement : rien ne touche le disque.
        let url = track
            .stream_url
            .as_deref()
            .ok_or("ce titre porte audioOnly mais n'expose pas de flux")?;
        player.play_url(url)?;
    } else {
        // afplay exige un fichier : on met en tampon, on n'archive pas.
        let path = stream_cache_path(track)?;
        if !path.exists() {
            print!("  mise en memoire tampon…");
            io::stdout().flush()?;
            api.download_to(track, &path)?;
            println!("\r                        \r");
        }
        player.play_file(&path)?;
    }

    Ok(karaoke::run(track, lyrics, &mut player, Duration::ZERO, up_next)?)
}

/// Telechargement demande par l'utilisateur : le fichier reste, et il est visible.
///
/// Refuse tout titre sans la capacite `offline` — c'est le meme garde-fou que
/// cote serveur, et l'interface ne propose meme pas l'action dans ce cas.
pub fn download_for_offline(api: &HiraApi, track: &Track) -> Res<PathBuf> {
    track.require(Capability::Offline)?;

    let dir = downloads_dir()?;
    std::fs::create_dir_all(&dir)?;
    let path = dir.join(format!("{}.audio", safe_name(track)));

    if path.exists() {
        return Ok(path);
    }
    api.download_to(track, &path)?;
    Ok(path)
}

/// `~/Music/Hira` : un endroit que l'utilisateur peut ouvrir et vider lui-meme.
pub fn downloads_dir() -> Res<PathBuf> {
    let home = std::env::var("HOME")?;
    Ok(PathBuf::from(home).join("Music").join("Hira"))
}

pub fn is_downloaded(track: &Track) -> bool {
    downloads_dir()
        .map(|d| d.join(format!("{}.audio", safe_name(track))).exists())
        .unwrap_or(false)
}

fn stream_cache_dir() -> PathBuf {
    std::env::temp_dir().join("hira-stream")
}

fn stream_cache_path(track: &Track) -> Res<PathBuf> {
    let dir = stream_cache_dir();
    std::fs::create_dir_all(&dir)?;
    Ok(dir.join(format!("{}.audio", safe_name(track))))
}

/// Vide le tampon. Appele en quittant : rien ne doit survivre a la session.
pub fn clear_stream_cache() {
    let _ = std::fs::remove_dir_all(stream_cache_dir());
}

fn safe_name(track: &Track) -> String {
    track
        .uri
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() { c } else { '_' })
        .collect()
}

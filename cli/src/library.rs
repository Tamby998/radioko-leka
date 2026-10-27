//! Bibliotheque locale : les fichiers audio de l'utilisateur.
//!
//! Un titre local porte toutes les capacites — il est deja sur le disque, rien
//! a telecharger, rien a mettre en tampon, et la lecture ne depend d'aucun
//! reseau. C'est le seul catalogue dont on soit certain qu'il contienne la
//! musique que l'utilisateur ecoute vraiment.
//!
//! Les paroles suivent la convention `.lrc` : un fichier portant le meme nom
//! que l'audio, a cote de lui. C'est le format standard des lecteurs karaoke,
//! et il rend le repertoire que personne n'indexe enfin synchronisable.

use std::path::{Path, PathBuf};
use std::time::Duration;

use lofty::file::{AudioFile, TaggedFileExt};
use lofty::prelude::ItemKey;

use crate::api::{Artist, LyricsLine, SyncedLyrics, Track};
use crate::capability::Capability;

/// Extensions reconnues au scan.
const AUDIO: &[&str] = &["mp3", "m4a", "flac", "wav", "aac", "ogg", "opus", "aiff"];

/// Profondeur maximale : au-dela on scanne des arborescences sans rapport.
const MAX_DEPTH: usize = 6;

/// Dossiers qu'on ne traverse jamais : ils sont lourds et ne contiennent pas
/// de musique. Sans ca, scanner ~/Documents part dans les artefacts de build.
const SKIP: &[&str] = &[
    "node_modules",
    "target",
    "build",
    "dist",
    "Library",
    "Applications",
    ".git",
    "vendor",
    "Pods",
];

pub struct Library {
    tracks: Vec<Track>,
}

impl Library {
    pub fn len(&self) -> usize {
        self.tracks.len()
    }

    pub fn is_empty(&self) -> bool {
        self.tracks.is_empty()
    }

    /// Recherche insensible a la casse et aux accents, sur titre et artiste.
    pub fn search(&self, query: &str, limit: usize) -> Vec<Track> {
        let needle = normalize(query);
        if needle.is_empty() {
            return Vec::new();
        }
        self.tracks
            .iter()
            .filter(|t| {
                let hay = normalize(&format!("{} {}", t.title, t.artist_names()));
                needle.split(' ').filter(|w| !w.is_empty()).any(|w| hay.contains(w))
            })
            .take(limit)
            .cloned()
            .collect()
    }

    pub fn all(&self, limit: usize) -> Vec<Track> {
        self.tracks.iter().take(limit).cloned().collect()
    }
}

/// Dossiers a scanner : `HIRA_MUSIC_DIR` (separes par `:`), sinon `~/Music`.
pub fn configured_roots() -> Vec<PathBuf> {
    if let Ok(raw) = std::env::var("HIRA_MUSIC_DIR") {
        let roots: Vec<PathBuf> = raw
            .split(':')
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .map(PathBuf::from)
            .collect();
        if !roots.is_empty() {
            return roots;
        }
    }
    match std::env::var("HOME") {
        Ok(home) => vec![PathBuf::from(home).join("Music")],
        Err(_) => Vec::new(),
    }
}

pub fn scan(roots: &[PathBuf]) -> Library {
    let mut tracks = Vec::new();
    for root in roots {
        walk(root, 0, &mut tracks);
    }
    // Par artiste puis titre : l'ordre d'un disque, pas celui du systeme de fichiers.
    tracks.sort_by(|a, b| {
        normalize(&a.artist_names())
            .cmp(&normalize(&b.artist_names()))
            .then_with(|| normalize(&a.title).cmp(&normalize(&b.title)))
    });
    Library { tracks }
}

fn walk(dir: &Path, depth: usize, out: &mut Vec<Track>) {
    if depth > MAX_DEPTH {
        return;
    }
    let Ok(entries) = std::fs::read_dir(dir) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        let name = entry.file_name();
        // Dossiers caches et bibliotheques systeme : rien d'ecoutable dedans.
        if name.to_string_lossy().starts_with('.') {
            continue;
        }
        if path.is_dir() {
            if SKIP.contains(&name.to_string_lossy().as_ref()) {
                continue;
            }
            walk(&path, depth + 1, out);
        } else if is_audio(&path) {
            if let Some(track) = read_track(&path) {
                out.push(track);
            }
        }
    }
}

fn is_audio(path: &Path) -> bool {
    path.extension()
        .and_then(|e| e.to_str())
        .map(|e| AUDIO.contains(&e.to_ascii_lowercase().as_str()))
        .unwrap_or(false)
}

/// Lit les tags ; a defaut, retombe sur le nom de fichier.
fn read_track(path: &Path) -> Option<Track> {
    let stem = path.file_stem()?.to_string_lossy().to_string();

    let (title, artist, duration) = match lofty::read_from_path(path) {
        Ok(file) => {
            let seconds = file.properties().duration();
            let tag = file.primary_tag().or_else(|| file.first_tag());
            let title = tag
                .and_then(|t| t.get_string(&ItemKey::TrackTitle))
                .map(str::to_string);
            let artist = tag
                .and_then(|t| t.get_string(&ItemKey::TrackArtist))
                .map(str::to_string);
            (title, artist, seconds)
        }
        // Fichier illisible ou sans tag : on garde quand meme le fichier.
        Err(_) => (None, None, Duration::ZERO),
    };

    let (from_name_artist, from_name_title) = split_stem(&stem);
    let title = title.filter(|s| !s.trim().is_empty()).unwrap_or(from_name_title);
    let artist = artist
        .filter(|s| !s.trim().is_empty())
        .or(from_name_artist)
        .unwrap_or_else(|| "Artiste inconnu".to_string());

    Some(Track {
        uri: format!("local:{}", path.to_string_lossy()),
        source: "local".to_string(),
        title,
        artists: vec![Artist { name: artist }],
        duration_ms: duration.as_millis() as u64,
        // Le fichier est deja la : toutes les capacites, par construction.
        capabilities: vec![
            Capability::Stream,
            Capability::AudioOnly,
            Capability::Background,
            Capability::Offline,
        ],
        requires_visible_player: false,
        stream_url: None,
        view_count: None,
        local_path: Some(path.to_path_buf()),
    })
}

/// `Artiste - Titre` -> les deux moities ; sinon tout le nom fait le titre.
fn split_stem(stem: &str) -> (Option<String>, String) {
    match stem.split_once(" - ") {
        Some((artist, title)) if !artist.trim().is_empty() && !title.trim().is_empty() => {
            (Some(artist.trim().to_string()), title.trim().to_string())
        }
        _ => (None, stem.to_string()),
    }
}

/// Paroles posees a cote du fichier : `chanson.mp3` -> `chanson.lrc`.
pub fn sidecar_lyrics(path: &Path) -> Option<PathBuf> {
    let candidate = path.with_extension("lrc");
    candidate.exists().then_some(candidate)
}

/// Parse un fichier `.lrc` pose a cote de l'audio.
///
/// Les lignes sans horodatage et les balises de metadonnees (`[ar:]`, `[ti:]`)
/// sont ignorees ; un meme texte peut porter plusieurs horodatages, auquel cas
/// il apparait a chaque position.
pub fn parse_lrc(text: &str) -> SyncedLyrics {
    let mut lines: Vec<LyricsLine> = Vec::new();

    for raw in text.lines() {
        let mut stamps: Vec<u64> = Vec::new();
        let mut cursor = 0usize;

        // Seuls les horodatages qui prefixent la ligne comptent.
        while raw[cursor..].starts_with('[') {
            let rest = &raw[cursor..];
            let Some(close) = rest.find(']') else { break };
            match parse_timestamp(&rest[1..close]) {
                Some(ms) => {
                    stamps.push(ms);
                    cursor += close + 1;
                }
                None => break,
            }
        }

        if stamps.is_empty() {
            continue;
        }
        let body = raw[cursor..].trim().to_string();
        for at_ms in stamps {
            lines.push(LyricsLine { at_ms, text: body.clone() });
        }
    }

    lines.sort_by_key(|l| l.at_ms);
    SyncedLyrics { instrumental: false, lines }
}

/// `01:23.45` -> 83450 ms. Tolere 1 a 3 chiffres de fraction.
fn parse_timestamp(inside: &str) -> Option<u64> {
    let (minutes, rest) = inside.split_once(':')?;
    let minutes: u64 = minutes.trim().parse().ok()?;
    let (seconds, frac) = match rest.split_once(['.', ':']) {
        Some((s, f)) => (s, Some(f)),
        None => (rest, None),
    };
    let seconds: u64 = seconds.trim().parse().ok()?;
    let millis: u64 = match frac {
        Some(f) => format!("{:0<3}", f.trim()).get(..3)?.parse().ok()?,
        None => 0,
    };
    Some(minutes * 60_000 + seconds * 1000 + millis)
}

fn normalize(text: &str) -> String {
    text.to_lowercase()
        .chars()
        .map(|c| match c {
            'á' | 'à' | 'â' | 'ä' | 'ã' => 'a',
            'é' | 'è' | 'ê' | 'ë' => 'e',
            'í' | 'ì' | 'î' | 'ï' => 'i',
            'ó' | 'ò' | 'ô' | 'ö' | 'õ' => 'o',
            'ú' | 'ù' | 'û' | 'ü' => 'u',
            'ç' => 'c',
            'ñ' => 'n',
            c if c.is_alphanumeric() => c,
            _ => ' ',
        })
        .collect::<String>()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn split_stem_separe_artiste_et_titre() {
        assert_eq!(
            split_stem("Mahaleo - Mitonia"),
            (Some("Mahaleo".to_string()), "Mitonia".to_string())
        );
        assert_eq!(split_stem("Mitonia"), (None, "Mitonia".to_string()));
        // Un tiret sans espaces n'est pas un separateur d'artiste.
        assert_eq!(split_stem("Rock-n-Roll"), (None, "Rock-n-Roll".to_string()));
    }

    #[test]
    fn normalize_ignore_casse_et_accents() {
        assert_eq!(normalize("Gâter  Pourri"), "gater pourri");
        assert_eq!(normalize("ROSÉ"), "rose");
        assert_eq!(normalize("  NIU   RAZA  "), "niu raza");
    }

    #[test]
    fn is_audio_reconnait_les_extensions() {
        assert!(is_audio(Path::new("/a/b.mp3")));
        assert!(is_audio(Path::new("/a/b.FLAC")));
        assert!(is_audio(Path::new("/a/b.m4a")));
        assert!(!is_audio(Path::new("/a/b.txt")));
        assert!(!is_audio(Path::new("/a/b")));
    }
}

#[cfg(test)]
mod lrc_tests {
    use super::*;

    // Texte neutre : aucune parole reelle dans les fixtures.
    const SAMPLE: &str = "[ar:Artiste de test]\n[00:12.50]premiere ligne\n[00:18.0]deuxieme\n[01:04.25][02:10.00]refrain\nligne sans horodatage\n";

    #[test]
    fn parse_lrc_lit_les_horodatages() {
        let parsed = parse_lrc(SAMPLE);
        // 4 et non 5 : la balise [ar:] et la ligne sans horodatage sont ignorees.
        assert_eq!(parsed.lines.len(), 4);
        assert_eq!(parsed.lines[0].at_ms, 12_500);
        assert_eq!(parsed.lines[0].text, "premiere ligne");
        assert_eq!(parsed.lines[1].at_ms, 18_000);
    }

    #[test]
    fn parse_lrc_dedouble_et_trie() {
        let parsed = parse_lrc(SAMPLE);
        let refrains: Vec<u64> = parsed
            .lines
            .iter()
            .filter(|l| l.text == "refrain")
            .map(|l| l.at_ms)
            .collect();
        assert_eq!(refrains, vec![64_250, 130_000]);
        for pair in parsed.lines.windows(2) {
            assert!(pair[0].at_ms <= pair[1].at_ms);
        }
    }

    #[test]
    fn parse_timestamp_tolere_les_fractions() {
        assert_eq!(parse_timestamp("00:12.5"), Some(12_500));
        assert_eq!(parse_timestamp("00:12.50"), Some(12_500));
        assert_eq!(parse_timestamp("00:12.500"), Some(12_500));
        assert_eq!(parse_timestamp("01:00"), Some(60_000));
        // Une balise de metadonnees n'est pas un horodatage.
        assert_eq!(parse_timestamp("ar:Artiste"), None);
        assert_eq!(parse_timestamp("length:03:00"), None);
    }
}

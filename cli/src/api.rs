//! Client du Worker Hira. Aucune cle d'API ne vit dans le binaire.

use std::time::Duration;

use serde::Deserialize;

use crate::capability::{Capability, CapabilityError};

#[derive(Debug, Clone, Deserialize)]
pub struct Artist {
    pub name: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Track {
    pub uri: String,
    pub source: String,
    pub title: String,
    #[serde(default)]
    pub artists: Vec<Artist>,
    #[serde(default)]
    pub duration_ms: u64,
    #[serde(default)]
    pub capabilities: Vec<Capability>,
    #[serde(default)]
    pub requires_visible_player: bool,
    #[serde(default)]
    pub stream_url: Option<String>,
    #[serde(default)]
    pub view_count: Option<u64>,
    /// Chemin sur le disque, pour un titre de la bibliotheque locale.
    /// Jamais present dans une reponse du Worker.
    #[serde(skip)]
    pub local_path: Option<std::path::PathBuf>,
}

impl Track {
    pub fn artist_names(&self) -> String {
        if self.artists.is_empty() {
            return "Artiste inconnu".to_string();
        }
        self.artists
            .iter()
            .map(|a| a.name.as_str())
            .collect::<Vec<_>>()
            .join(", ")
    }

    pub fn primary_artist(&self) -> &str {
        self.artists.first().map(|a| a.name.as_str()).unwrap_or("")
    }

    pub fn can(&self, capability: Capability) -> bool {
        self.capabilities.contains(&capability)
    }

    /// A appeler avant toute ecriture de fichier ou lecture hors interface.
    pub fn require(&self, capability: Capability) -> Result<(), CapabilityError> {
        if self.can(capability) {
            Ok(())
        } else {
            Err(CapabilityError {
                title: self.title.clone(),
                source: self.source.clone(),
                capability,
            })
        }
    }

    pub fn duration(&self) -> Duration {
        Duration::from_millis(self.duration_ms)
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LyricsLine {
    pub at_ms: u64,
    pub text: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncedLyrics {
    #[serde(default)]
    pub instrumental: bool,
    #[serde(default)]
    pub lines: Vec<LyricsLine>,
}

impl SyncedLyrics {
    /// Index de la ligne a surligner, ou `None` avant la premiere.
    ///
    /// Dichotomie : appelee a chaque image, donc tenue en O(log n).
    pub fn index_at(&self, position: Duration) -> Option<usize> {
        let pos = position.as_millis() as u64;
        let mut low = 0usize;
        let mut high = self.lines.len();
        let mut found = None;
        while low < high {
            let mid = low + (high - low) / 2;
            if self.lines[mid].at_ms <= pos {
                found = Some(mid);
                low = mid + 1;
            } else {
                high = mid;
            }
        }
        found
    }
}

#[derive(Debug, Deserialize)]
struct TracksResponse {
    #[serde(default)]
    tracks: Vec<Track>,
}

#[derive(Debug, Deserialize)]
struct LyricsResponse {
    lyrics: Option<SyncedLyrics>,
}

#[derive(Debug, Deserialize)]
struct DownloadResponse {
    #[serde(rename = "streamUrl")]
    stream_url: String,
}

pub struct HiraApi {
    base_url: String,
    http: reqwest::blocking::Client,
}

type Res<T> = Result<T, Box<dyn std::error::Error>>;

impl HiraApi {
    pub fn new(base_url: &str) -> Res<Self> {
        let http = reqwest::blocking::Client::builder()
            .timeout(Duration::from_secs(30))
            .user_agent("hira-cli/0.1.0")
            .build()?;
        Ok(Self {
            base_url: base_url.trim_end_matches('/').to_string(),
            http,
        })
    }

    pub fn search(&self, query: &str, limit: usize) -> Res<Vec<Track>> {
        let url = format!("{}/v1/search", self.base_url);
        // Un tableau doit etre homogene : on lie la chaine avant de l'emprunter.
        let limit = limit.to_string();
        let body: TracksResponse = self
            .http
            .get(url)
            // Le terminal ne sait pas afficher de video : on ne demande que
            // ce qu'il peut reellement jouer.
            .query(&[("q", query), ("limit", limit.as_str()), ("audio_only", "1")])
            .send()?
            .error_for_status()?
            .json()?;
        Ok(body.tracks)
    }

    pub fn licensed_trending(&self) -> Res<Vec<Track>> {
        let url = format!("{}/v1/charts/licensed-trending", self.base_url);
        let body: TracksResponse =
            self.http.get(url).send()?.error_for_status()?.json()?;
        Ok(body.tracks)
    }

    pub fn lyrics_for(&self, track: &Track) -> Res<Option<SyncedLyrics>> {
        let url = format!("{}/v1/lyrics", self.base_url);
        let seconds = (track.duration_ms / 1000).to_string();
        let body: LyricsResponse = self
            .http
            .get(url)
            .query(&[
                ("artist", track.primary_artist()),
                ("title", track.title.as_str()),
                ("duration", seconds.as_str()),
            ])
            .send()?
            .error_for_status()?
            .json()?;
        Ok(body.lyrics)
    }

    /// Titres a enchainer apres celui-ci.
    ///
    /// Le serveur combine le catalogue cure (meme artiste, meme genre) et les
    /// sources sous licence. Une liste vide n'est pas une erreur : l'appelant
    /// retombe sur le classement.
    pub fn similar(&self, track: &Track) -> Res<Vec<Track>> {
        let url = format!("{}/v1/similar/{}", self.base_url, urlencode(&track.uri));
        let body: TracksResponse = self
            .http
            .get(url)
            .query(&[("audio_only", "1")])
            .send()?
            .error_for_status()?
            .json()?;
        Ok(body.tracks)
    }

    /// Le serveur refuse par un 403 tout titre sans la capacite `offline`.
    /// On verifie aussi localement : deux verrous valent mieux qu'un.
    pub fn resolve_download_url(&self, track: &Track) -> Res<String> {
        track.require(Capability::Offline)?;
        let url = format!("{}/v1/download/{}", self.base_url, urlencode(&track.uri));
        let body: DownloadResponse =
            self.http.get(url).send()?.error_for_status()?.json()?;
        Ok(body.stream_url)
    }

    /// Telecharge le flux dans un fichier local. Garde-fou avant la requete.
    pub fn download_to(&self, track: &Track, path: &std::path::Path) -> Res<()> {
        track.require(Capability::Offline)?;
        let stream_url = self.resolve_download_url(track)?;
        let bytes = self
            .http
            .get(stream_url)
            .send()?
            .error_for_status()?
            .bytes()?;
        std::fs::write(path, &bytes)?;
        Ok(())
    }
}

/// Encodage minimal pour un segment de chemin (`audius:xyz` -> `audius%3Axyz`).
fn urlencode(raw: &str) -> String {
    let mut out = String::with_capacity(raw.len() * 3);
    for byte in raw.bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                out.push(byte as char);
            }
            _ => out.push_str(&format!("%{:02X}", byte)),
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn lyrics() -> SyncedLyrics {
        SyncedLyrics {
            instrumental: false,
            lines: vec![
                LyricsLine {
                    at_ms: 1_000,
                    text: "une".into(),
                },
                LyricsLine {
                    at_ms: 5_000,
                    text: "deux".into(),
                },
                LyricsLine {
                    at_ms: 9_000,
                    text: "trois".into(),
                },
            ],
        }
    }

    #[test]
    fn avant_la_premiere_ligne_aucun_index() {
        assert_eq!(lyrics().index_at(Duration::from_millis(500)), None);
    }

    #[test]
    fn index_at_prend_la_derniere_ligne_atteinte() {
        let l = lyrics();
        assert_eq!(l.index_at(Duration::from_millis(1_000)), Some(0));
        assert_eq!(l.index_at(Duration::from_millis(4_999)), Some(0));
        assert_eq!(l.index_at(Duration::from_millis(5_000)), Some(1));
        assert_eq!(l.index_at(Duration::from_secs(60)), Some(2));
    }

    fn track(source: &str, capabilities: Vec<Capability>, visible: bool) -> Track {
        Track {
            uri: format!("{source}:abc"),
            source: source.to_string(),
            title: "Un titre".to_string(),
            artists: vec![Artist {
                name: "Un artiste".to_string(),
            }],
            duration_ms: 180_000,
            capabilities,
            requires_visible_player: visible,
            stream_url: None,
            view_count: None,
            local_path: None,
        }
    }

    #[test]
    fn le_catalogue_mondial_refuse_le_hors_connexion() {
        let t = track("youtube", vec![Capability::Stream], true);
        assert!(t.require(Capability::Stream).is_ok());
        assert!(t.require(Capability::Offline).is_err());
        assert!(t.require(Capability::Background).is_err());
        assert!(t.require(Capability::AudioOnly).is_err());
    }

    #[test]
    fn le_catalogue_sous_licence_accepte_tout() {
        let t = track(
            "audius",
            vec![
                Capability::Stream,
                Capability::AudioOnly,
                Capability::Background,
                Capability::Offline,
            ],
            false,
        );
        for c in [
            Capability::Stream,
            Capability::AudioOnly,
            Capability::Background,
            Capability::Offline,
        ] {
            assert!(t.require(c).is_ok(), "{c} devrait etre autorise");
        }
    }

    #[test]
    fn le_refus_nomme_le_titre_et_la_capacite() {
        let err = track("youtube", vec![Capability::Stream], true)
            .require(Capability::Offline)
            .unwrap_err();
        let message = err.to_string();
        assert!(message.contains("Un titre"), "{message}");
        assert!(message.contains("offline"), "{message}");
        assert!(message.contains("refusee"), "{message}");
    }

    #[test]
    fn les_capacites_se_deserialisent_depuis_le_json_du_worker() {
        let json = r#"{
            "uri": "audius:xyz",
            "source": "audius",
            "externalId": "xyz",
            "title": "Un titre",
            "artists": [{ "name": "Un artiste" }],
            "durationMs": 1234,
            "capabilities": ["stream", "audioOnly", "background", "offline"],
            "requiresVisiblePlayer": false,
            "streamUrl": "https://exemple.test/flux"
        }"#;
        let parsed: Track = serde_json::from_str(json).expect("desarialisation");
        assert_eq!(parsed.capabilities.len(), 4);
        assert!(parsed.can(Capability::Offline));
        assert_eq!(parsed.duration_ms, 1234);
        assert_eq!(
            parsed.stream_url.as_deref(),
            Some("https://exemple.test/flux")
        );
        assert_eq!(parsed.primary_artist(), "Un artiste");
    }

    #[test]
    fn urlencode_protege_les_deux_points() {
        assert_eq!(urlencode("audius:7eP5p"), "audius%3A7eP5p");
        assert_eq!(urlencode("youtube:1l7wbZmdtys"), "youtube%3A1l7wbZmdtys");
    }
}

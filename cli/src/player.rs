//! Lecture audio par sous-processus.
//!
//! Aucun crate audio : l'API de `rodio` bouge trop pour etre ecrite sans
//! compilateur sous la main, et un sous-processus suffit largement ici.
//!
//! Deux backends, meme mecanique : SIGSTOP/SIGCONT pour la pause, et une
//! horloge locale pour la position.
//!
//! - `mpv`   : lit l'URL directement, rien n'est ecrit sur le disque.
//! - `afplay`: ne lit que des fichiers locaux, donc le titre est telecharge
//!             d'abord — ce qui exige la capacite `offline`.
//!
//! Ni l'un ni l'autre ne sait chercher dans la piste : `afplay` n'a pas
//! d'option de depart, et on n'ajoute pas ffmpeg pour ca. `seek_supported()`
//! dit la verite a l'interface.

use std::path::Path;
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Backend {
    /// Preferé : lit un flux distant sans rien ecrire.
    Mpv,
    /// Fourni avec macOS : fichier local uniquement.
    Afplay,
}

impl Backend {
    /// Premier backend disponible, mpv d'abord.
    pub fn detect() -> Option<Backend> {
        for (backend, binary) in [(Backend::Mpv, "mpv"), (Backend::Afplay, "afplay")] {
            if which(binary) {
                return Some(backend);
            }
        }
        None
    }

    pub fn binary(self) -> &'static str {
        match self {
            Backend::Mpv => "mpv",
            Backend::Afplay => "afplay",
        }
    }

    /// Vrai si le backend lit une URL sans fichier intermediaire.
    pub fn streams_remote_urls(self) -> bool {
        matches!(self, Backend::Mpv)
    }

    pub fn label(self) -> &'static str {
        match self {
            Backend::Mpv => "mpv (flux direct)",
            Backend::Afplay => "afplay (fichier local)",
        }
    }
}

fn which(binary: &str) -> bool {
    Command::new("/usr/bin/which")
        .arg(binary)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

pub struct Player {
    backend: Backend,
    child: Option<Child>,
    /// Instant de demarrage du processus courant.
    started: Instant,
    /// Cumul des pauses deja terminees.
    paused_total: Duration,
    /// Debut de la pause en cours, si en pause.
    paused_since: Option<Instant>,
}

impl Player {
    pub fn new(backend: Backend) -> Self {
        Self {
            backend,
            child: None,
            started: Instant::now(),
            paused_total: Duration::ZERO,
            paused_since: None,
        }
    }

    pub fn backend(&self) -> Backend {
        self.backend
    }

    pub fn is_paused(&self) -> bool {
        self.paused_since.is_some()
    }

    /// Lance la lecture d'une URL distante. Reserve au backend mpv.
    pub fn play_url(&mut self, url: &str) -> std::io::Result<()> {
        debug_assert!(self.backend.streams_remote_urls());
        let child = Command::new(self.backend.binary())
            .args(["--no-video", "--really-quiet", url])
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()?;
        self.adopt(child);
        Ok(())
    }

    /// Lance la lecture d'un fichier deja present sur le disque.
    pub fn play_file(&mut self, path: &Path) -> std::io::Result<()> {
        let mut command = Command::new(self.backend.binary());
        if self.backend == Backend::Mpv {
            command.args(["--no-video", "--really-quiet"]);
        }
        let child = command
            .arg(path)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()?;
        self.adopt(child);
        Ok(())
    }

    fn adopt(&mut self, child: Child) {
        self.child = Some(child);
        self.started = Instant::now();
        self.paused_total = Duration::ZERO;
        self.paused_since = None;
    }

    /// Position estimee : temps ecoule depuis le lancement, pauses deduites.
    pub fn position(&self) -> Duration {
        let reference = self.paused_since.unwrap_or_else(Instant::now);
        reference
            .saturating_duration_since(self.started)
            .saturating_sub(self.paused_total)
    }

    /// Suspend ou reprend le processus de lecture.
    pub fn toggle_pause(&mut self) -> std::io::Result<()> {
        let pid = self.child.as_ref().map(|c| c.id());

        if let Some(since) = self.paused_since.take() {
            self.paused_total += since.elapsed();
            if let Some(pid) = pid {
                signal(pid, "-CONT")?;
            }
        } else {
            self.paused_since = Some(Instant::now());
            if let Some(pid) = pid {
                signal(pid, "-STOP")?;
            }
        }
        Ok(())
    }

    /// Vrai quand le processus de lecture s'est termine de lui-meme.
    pub fn is_finished(&mut self) -> bool {
        match self.child.as_mut() {
            None => true,
            Some(child) => matches!(child.try_wait(), Ok(Some(_))),
        }
    }

    pub fn stop(&mut self) {
        if let Some(mut child) = self.child.take() {
            // Un processus suspendu ignore SIGTERM : on le reveille d'abord.
            if self.paused_since.take().is_some() {
                let _ = signal(child.id(), "-CONT");
            }
            let _ = child.kill();
            let _ = child.wait();
        }
    }
}

impl Drop for Player {
    fn drop(&mut self) {
        self.stop();
    }
}

fn signal(pid: u32, sig: &str) -> std::io::Result<()> {
    Command::new("/bin/kill")
        .arg(sig)
        .arg(pid.to_string())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()?;
    Ok(())
}

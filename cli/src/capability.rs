//! Le modele hybride, troisieme implementation apres le Worker et l'app.
//!
//! Ici le compilateur fait plus que dans les deux autres : `Capability` est un
//! enum ferme, et `require` renvoie un `Result` que l'appelant ne peut pas
//! ignorer sans warning. Le telechargement passe obligatoirement par la.

use std::fmt;

use serde::Deserialize;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
pub enum Capability {
    /// Le titre peut etre lu dans l'app.
    #[serde(rename = "stream")]
    Stream,
    /// Le flux audio peut etre consomme sans la video.
    #[serde(rename = "audioOnly")]
    AudioOnly,
    /// La lecture peut continuer sans interface visible.
    #[serde(rename = "background")]
    Background,
    /// Un fichier peut etre ecrit sur l'appareil.
    #[serde(rename = "offline")]
    Offline,
}

impl fmt::Display for Capability {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let name = match self {
            Capability::Stream => "stream",
            Capability::AudioOnly => "audioOnly",
            Capability::Background => "background",
            Capability::Offline => "offline",
        };
        f.write_str(name)
    }
}

/// Refus explicite, remonte jusqu'a l'utilisateur sans paniquer.
#[derive(Debug)]
pub struct CapabilityError {
    pub title: String,
    pub source: String,
    pub capability: Capability,
}

impl fmt::Display for CapabilityError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "\"{}\" ({}) ne porte pas la capacite \"{}\" : operation refusee.",
            self.title, self.source, self.capability
        )
    }
}

impl std::error::Error for CapabilityError {}

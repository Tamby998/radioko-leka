//! Affichage partage : listes de titres et formatage.

use crate::api::Track;
use crate::capability::Capability;
use crate::karaoke;

/// Liste numerotee, avec un marqueur de ce que chaque titre permet.
pub fn print_tracks(tracks: &[Track]) {
    for (i, track) in tracks.iter().enumerate() {
        let marker = if track.local_path.is_some() {
            "*" // un fichier a toi
        } else if track.can(Capability::Offline) {
            "v" // telechargeable, ecoutable hors connexion
        } else {
            ">" // lecture seule, par le lecteur officiel
        };
        println!(
            "{:>3}. {} {:<40} {:<24} {:>6} {:>9}",
            i + 1,
            marker,
            clip(&track.title, 40),
            clip(&track.artist_names(), 24),
            karaoke::format_duration(track.duration()),
            track.view_count.map(format_count).unwrap_or_default(),
        );
    }
}

pub fn legend() {
    println!(
        "\n  * ta bibliotheque   v telechargeable   • telecharge   > lecteur officiel"
    );
}

/// Compte d'ecoutes abrege, virgule decimale a la francaise.
pub fn format_count(n: u64) -> String {
    if n >= 1_000_000 {
        format!("{:.1} M", n as f64 / 1_000_000.0).replace('.', ",")
    } else if n >= 1_000 {
        format!("{} k", n / 1_000)
    } else {
        n.to_string()
    }
}

/// Tronque en comptant les caracteres, pas les octets.
pub fn clip(text: &str, width: usize) -> String {
    if text.chars().count() <= width {
        return text.to_string();
    }
    let mut out: String = text.chars().take(width.saturating_sub(1)).collect();
    out.push('…');
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn format_count_abrege_les_grands_nombres() {
        assert_eq!(format_count(0), "0");
        assert_eq!(format_count(999), "999");
        assert_eq!(format_count(14_700), "14 k");
        assert_eq!(format_count(14_700_000), "14,7 M");
        assert_eq!(format_count(613_100_000), "613,1 M");
    }

    #[test]
    fn clip_tronque_sur_les_caracteres() {
        assert_eq!(clip("abc", 10), "abc");
        assert_eq!(clip("abcdefghij", 5), "abcd…");
        // 6 caracteres, 9 octets en UTF-8 : on doit compter 6.
        assert_eq!(clip("éèêëàç", 10).chars().count(), 6);
    }
}

//! Vue karaoke en terminal.
//!
//! Le calcul de la fenetre de lignes est une fonction pure, testable sans
//! terminal ; crossterm ne sert qu'a la peindre.

use std::io::{self, IsTerminal, Write};
use std::time::Duration;

use crossterm::event::{self, Event, KeyCode, KeyEventKind};
use crossterm::style::{
    Attribute, Color, Print, ResetColor, SetAttribute, SetForegroundColor,
};
use crossterm::terminal::{self, Clear, ClearType};
use crossterm::{cursor, execute, queue};

use crate::api::{SyncedLyrics, Track};
use crate::capability::Capability;
use crate::player::Player;

/// Pourquoi la vue a rendu la main. L'enchainement automatique en depend :
/// on ne passe au titre suivant que si celui-ci est alle au bout.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Outcome {
    /// Le morceau est alle jusqu'au bout.
    Finished,
    /// L'utilisateur a demande l'arret.
    Quit,
    /// Passer au titre suivant tout de suite.
    Next,
    /// Revenir au titre precedent.
    Previous,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LineState {
    Past,
    Active,
    Future,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FrameLine {
    pub text: String,
    pub state: LineState,
}

/// Fenetre de `rows` lignes centree sur la ligne active.
///
/// Avant la premiere ligne (`active` a `None`), montre le debut du texte. En
/// fin de morceau, s'arrete au bord bas plutot que de laisser du vide.
pub fn frame(
    lyrics: &SyncedLyrics,
    active: Option<usize>,
    rows: usize,
) -> Vec<FrameLine> {
    if rows == 0 || lyrics.lines.is_empty() {
        return Vec::new();
    }

    let total = lyrics.lines.len();
    let active_index = active.unwrap_or(0);
    let half = rows / 2;

    // Centre la ligne active, puis recadre dans les bornes du texte.
    let mut start = active_index.saturating_sub(half);
    if start + rows > total {
        start = total.saturating_sub(rows);
    }

    lyrics.lines[start..(start + rows).min(total)]
        .iter()
        .enumerate()
        .map(|(offset, line)| {
            let index = start + offset;
            let state = match active {
                Some(a) if index == a => LineState::Active,
                Some(a) if index < a => LineState::Past,
                _ => LineState::Future,
            };
            FrameLine {
                text: line.text.clone(),
                state,
            }
        })
        .collect()
}

/// Barre de progression en caracteres pleins.
pub fn progress_bar(position: Duration, total: Duration, width: usize) -> String {
    if width == 0 {
        return String::new();
    }
    let ratio = if total.is_zero() {
        0.0
    } else {
        (position.as_secs_f64() / total.as_secs_f64()).clamp(0.0, 1.0)
    };
    let filled = (ratio * width as f64).round() as usize;
    let filled = filled.min(width);
    format!("{}{}", "━".repeat(filled), "─".repeat(width - filled))
}

pub fn format_duration(d: Duration) -> String {
    let total = d.as_secs();
    format!("{}:{:02}", total / 60, total % 60)
}

/// Boucle interactive. Rend la main sur `q`, Echap, ou fin du morceau.
pub fn run(
    track: &Track,
    lyrics: Option<&SyncedLyrics>,
    player: &mut Player,
    clock_offset: Duration,
    up_next: Option<&str>,
) -> io::Result<Outcome> {
    if !io::stdout().is_terminal() {
        return run_headless(track, lyrics, player);
    }

    let mut out = io::stdout();
    terminal::enable_raw_mode()?;
    execute!(out, cursor::Hide)?;

    let outcome = draw_loop(&mut out, track, lyrics, player, clock_offset, up_next);

    execute!(out, cursor::Show, ResetColor)?;
    terminal::disable_raw_mode()?;
    println!();
    outcome
}

fn draw_loop(
    out: &mut io::Stdout,
    track: &Track,
    lyrics: Option<&SyncedLyrics>,
    player: &mut Player,
    clock_offset: Duration,
    up_next: Option<&str>,
) -> io::Result<Outcome> {
    loop {
        if event::poll(Duration::from_millis(120))? {
            if let Event::Key(key) = event::read()? {
                if key.kind == KeyEventKind::Press {
                    match key.code {
                        KeyCode::Char('q') | KeyCode::Esc => {
                            return Ok(Outcome::Quit);
                        }
                        KeyCode::Char(' ') => player.toggle_pause()?,
                        KeyCode::Char('n') | KeyCode::Right => {
                            return Ok(Outcome::Next);
                        }
                        KeyCode::Char('p') | KeyCode::Left => {
                            return Ok(Outcome::Previous);
                        }
                        _ => {}
                    }
                }
            }
        }

        if player.is_finished() {
            break;
        }

        let position = player.position() + clock_offset;
        paint(out, track, lyrics, player, position, up_next)?;
    }
    Ok(Outcome::Finished)
}

fn paint(
    out: &mut io::Stdout,
    track: &Track,
    lyrics: Option<&SyncedLyrics>,
    player: &Player,
    position: Duration,
    up_next: Option<&str>,
) -> io::Result<()> {
    let (columns, rows) = terminal::size()?;
    let width = columns as usize;
    // En-tete 4 lignes, pied 2 lignes.
    let lyric_rows = (rows as usize).saturating_sub(6);

    queue!(out, Clear(ClearType::All), cursor::MoveTo(0, 0))?;

    // --- en-tete ---
    queue!(
        out,
        SetAttribute(Attribute::Bold),
        Print(clip(&track.title, width)),
        SetAttribute(Attribute::Reset),
        cursor::MoveTo(0, 1),
        SetForegroundColor(Color::DarkGrey),
        Print(clip(&track.artist_names(), width)),
        ResetColor,
        cursor::MoveTo(0, 2),
    )?;

    let badge = if track.can(Capability::Offline) {
        "sous licence · hors connexion possible"
    } else {
        "catalogue mondial · lecteur officiel"
    };
    queue!(
        out,
        SetForegroundColor(Color::DarkGrey),
        Print(clip(
            &format!("{}  ·  {}", badge, player.backend().label()),
            width
        )),
        ResetColor,
    )?;

    // --- paroles ---
    match lyrics {
        None => {
            queue!(
                out,
                cursor::MoveTo(0, 4),
                SetForegroundColor(Color::DarkGrey),
                Print("Paroles indisponibles pour ce titre"),
                ResetColor,
            )?;
        }
        Some(l) if l.instrumental => {
            queue!(
                out,
                cursor::MoveTo(0, 4),
                SetForegroundColor(Color::DarkGrey),
                Print("Instrumental"),
                ResetColor,
            )?;
        }
        Some(l) => {
            let active = l.index_at(position);
            for (row, line) in frame(l, active, lyric_rows).iter().enumerate() {
                queue!(out, cursor::MoveTo(0, 4 + row as u16))?;
                match line.state {
                    LineState::Active => queue!(
                        out,
                        SetAttribute(Attribute::Bold),
                        SetForegroundColor(Color::Green),
                        Print(clip(&line.text, width)),
                        ResetColor,
                        SetAttribute(Attribute::Reset),
                    )?,
                    LineState::Past => queue!(
                        out,
                        SetForegroundColor(Color::DarkGrey),
                        Print(clip(&line.text, width)),
                        ResetColor,
                    )?,
                    LineState::Future => queue!(out, Print(clip(&line.text, width)))?,
                }
            }
        }
    }

    // --- pied ---
    let bar_width = width.saturating_sub(16).min(60);
    let transport = format!(
        "{} {} {}",
        format_duration(position),
        progress_bar(position, track.duration(), bar_width),
        format_duration(track.duration()),
    );
    let state = if player.is_paused() { "EN PAUSE  ·  " } else { "" };
    let help = match up_next {
        Some(next) => {
            format!("{state}n suivant  ·  espace pause  ·  q liste  ·  puis : {next}")
        }
        None => format!("{state}n suivant  ·  espace pause  ·  q liste"),
    };

    queue!(
        out,
        cursor::MoveTo(0, rows.saturating_sub(2)),
        Print(clip(&transport, width)),
        cursor::MoveTo(0, rows.saturating_sub(1)),
        SetForegroundColor(Color::DarkGrey),
        Print(clip(&help, width)),
        ResetColor,
    )?;

    out.flush()
}

/// Mode degrade : pas de terminal interactif (pipe, CI). On attend la fin.
fn run_headless(
    track: &Track,
    lyrics: Option<&SyncedLyrics>,
    player: &mut Player,
) -> io::Result<Outcome> {
    let count = lyrics.map(|l| l.lines.len()).unwrap_or(0);
    println!(
        "Lecture de \"{}\" — {} ({}), {} lignes de paroles.",
        track.title,
        track.artist_names(),
        format_duration(track.duration()),
        count,
    );
    println!("Sortie non interactive : pas d'affichage karaoke.");
    while !player.is_finished() {
        std::thread::sleep(Duration::from_millis(250));
    }
    Ok(Outcome::Finished)
}

/// Tronque a la largeur du terminal, en comptant les caracteres et non les octets.
fn clip(text: &str, width: usize) -> String {
    if text.chars().count() <= width {
        return text.to_string();
    }
    if width <= 1 {
        return text.chars().take(width).collect();
    }
    let mut out: String = text.chars().take(width - 1).collect();
    out.push('…');
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::LyricsLine;

    fn lyrics(n: usize) -> SyncedLyrics {
        SyncedLyrics {
            instrumental: false,
            lines: (0..n)
                .map(|i| LyricsLine {
                    at_ms: (i as u64) * 1_000,
                    text: format!("ligne {i}"),
                })
                .collect(),
        }
    }

    #[test]
    fn la_fenetre_centre_la_ligne_active() {
        let l = lyrics(20);
        let f = frame(&l, Some(10), 5);
        assert_eq!(f.len(), 5);
        assert_eq!(f[2].state, LineState::Active);
        assert_eq!(f[2].text, "ligne 10");
        assert_eq!(f[0].state, LineState::Past);
        assert_eq!(f[4].state, LineState::Future);
    }

    #[test]
    fn la_fenetre_ne_depasse_pas_le_debut() {
        let f = frame(&lyrics(20), Some(0), 5);
        assert_eq!(f.len(), 5);
        assert_eq!(f[0].state, LineState::Active);
    }

    #[test]
    fn la_fenetre_ne_depasse_pas_la_fin() {
        let l = lyrics(20);
        let f = frame(&l, Some(19), 5);
        assert_eq!(f.len(), 5);
        assert_eq!(f[4].state, LineState::Active);
        assert_eq!(f[4].text, "ligne 19");
    }

    #[test]
    fn fenetre_plus_grande_que_le_texte() {
        let f = frame(&lyrics(3), Some(1), 10);
        assert_eq!(f.len(), 3);
    }

    #[test]
    fn avant_la_premiere_ligne_tout_est_a_venir() {
        let f = frame(&lyrics(10), None, 4);
        assert!(f.iter().all(|l| l.state == LineState::Future));
    }

    #[test]
    fn paroles_vides_ou_zero_ligne() {
        assert!(frame(&lyrics(0), None, 5).is_empty());
        assert!(frame(&lyrics(10), Some(0), 0).is_empty());
    }

    #[test]
    fn la_barre_respecte_la_largeur() {
        let bar = progress_bar(Duration::from_secs(50), Duration::from_secs(100), 10);
        assert_eq!(bar.chars().count(), 10);
        assert_eq!(bar.chars().filter(|c| *c == '━').count(), 5);
    }

    #[test]
    fn la_barre_gere_les_bornes() {
        assert_eq!(
            progress_bar(Duration::ZERO, Duration::from_secs(100), 4)
                .chars()
                .filter(|c| *c == '━')
                .count(),
            0
        );
        assert_eq!(
            progress_bar(Duration::from_secs(999), Duration::from_secs(100), 4),
            "━━━━"
        );
        assert_eq!(
            progress_bar(Duration::from_secs(5), Duration::ZERO, 4),
            "────"
        );
    }

    #[test]
    fn clip_compte_les_caracteres_pas_les_octets() {
        assert_eq!(clip("eteint", 10), "eteint");
        assert_eq!(clip("abcdefghij", 5), "abcd…");
        // Accents : 6 caracteres, 9 octets en UTF-8.
        assert_eq!(clip("éèêëàç", 10).chars().count(), 6);
    }

    #[test]
    fn format_duration_affiche_minutes_secondes() {
        assert_eq!(format_duration(Duration::from_secs(0)), "0:00");
        assert_eq!(format_duration(Duration::from_secs(65)), "1:05");
        assert_eq!(format_duration(Duration::from_secs(3_600)), "60:00");
    }
}

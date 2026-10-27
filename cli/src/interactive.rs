//! Navigateur en plein ecran : chercher, selectionner aux fleches, jouer.
//!
//! Deux modes dans une seule boucle d'evenements. En `Search` on tape, en
//! `Results` on se deplace dans la liste. La lecture, elle, sort de cet ecran :
//! `playback` et la vue karaoke gerent leur propre affichage, donc on quitte
//! l'ecran alterne avant de jouer et on y revient apres.

use std::io::{self, IsTerminal, Write};
use std::time::Duration;

use crossterm::event::{self, Event, KeyCode, KeyEventKind, KeyModifiers};
use crossterm::style::{
    Attribute, Color, Print, ResetColor, SetAttribute, SetBackgroundColor, SetForegroundColor,
};
use crossterm::terminal::{
    self, Clear, ClearType, EnterAlternateScreen, LeaveAlternateScreen,
};
use crossterm::{cursor, execute, queue};

use crate::api::{HiraApi, Track};
use crate::capability::Capability;
use crate::karaoke::{format_duration, Outcome};
use crate::library::{self, Library};
use crate::playback;
use crate::ui;

type Res<T> = Result<T, Box<dyn std::error::Error>>;

const RESULTS: usize = 40;

#[derive(PartialEq, Eq)]
enum Mode {
    Search,
    Results,
}

struct App {
    /// Scannee une fois au demarrage : la recherche locale est instantanee.
    library: Library,
    mode: Mode,
    query: String,
    results: Vec<Track>,
    cursor: usize,
    /// Premiere ligne affichee, pour que la selection reste visible.
    offset: usize,
    status: Option<String>,
}

impl App {
    fn new(library: Library) -> Self {
        let status = if library.is_empty() {
            "tape une recherche".to_string()
        } else {
            format!(
                "{} titres dans ta bibliotheque · tape une recherche",
                library.len()
            )
        };
        Self {
            library,
            mode: Mode::Search,
            query: String::new(),
            results: Vec::new(),
            cursor: 0,
            offset: 0,
            status: Some(status),
        }
    }

    fn selected(&self) -> Option<&Track> {
        self.results.get(self.cursor)
    }

    fn move_cursor(&mut self, delta: isize, visible: usize) {
        if self.results.is_empty() {
            return;
        }
        let last = self.results.len() - 1;
        self.cursor = (self.cursor as isize + delta).clamp(0, last as isize) as usize;

        // Garde la selection dans la fenetre visible.
        if self.cursor < self.offset {
            self.offset = self.cursor;
        } else if visible > 0 && self.cursor >= self.offset + visible {
            self.offset = self.cursor + 1 - visible;
        }
    }
}

pub fn run(api: &HiraApi) -> Res<()> {
    // Le mode plein ecran a besoin d'un vrai terminal : dans un tube ou une
    // tache de fond, mieux vaut le dire que d'echouer sur le mode brut.
    if !io::stdout().is_terminal() || !io::stdin().is_terminal() {
        return Err("le mode interactif demande un vrai terminal. Essaie « hira search <recherche> » ou « hira play <recherche> »."
            .into());
    }

    let roots = library::configured_roots();
    if !roots.is_empty() {
        println!("lecture de ta bibliotheque…");
    }
    let library = library::scan(&roots);

    let mut app = App::new(library);
    enter_screen()?;
    let outcome = event_loop(api, &mut app);
    leave_screen()?;
    // Le tampon de lecture ne survit pas a la session : ce n'etait pas un
    // telechargement, l'utilisateur n'a rien demande a garder.
    playback::clear_stream_cache();
    outcome
}

fn enter_screen() -> Res<()> {
    terminal::enable_raw_mode()?;
    execute!(io::stdout(), EnterAlternateScreen, cursor::Hide)?;
    Ok(())
}

fn leave_screen() -> Res<()> {
    execute!(io::stdout(), cursor::Show, ResetColor, LeaveAlternateScreen)?;
    terminal::disable_raw_mode()?;
    Ok(())
}

fn event_loop(api: &HiraApi, app: &mut App) -> Res<()> {
    loop {
        draw(app)?;

        if !event::poll(Duration::from_millis(200))? {
            continue;
        }
        let Event::Key(key) = event::read()? else {
            continue;
        };
        if key.kind != KeyEventKind::Press {
            continue;
        }
        if key.modifiers.contains(KeyModifiers::CONTROL) && key.code == KeyCode::Char('c') {
            return Ok(());
        }

        let visible = visible_rows();

        match app.mode {
            Mode::Search => match key.code {
                KeyCode::Enter => submit(api, app),
                KeyCode::Esc => {
                    if !app.results.is_empty() {
                        app.mode = Mode::Results;
                    }
                }
                KeyCode::Backspace => {
                    app.query.pop();
                }
                KeyCode::Char(c) => app.query.push(c),
                _ => {}
            },
            Mode::Results => match key.code {
                KeyCode::Char('q') | KeyCode::Esc => return Ok(()),
                KeyCode::Up | KeyCode::Char('k') => app.move_cursor(-1, visible),
                KeyCode::Down | KeyCode::Char('j') => app.move_cursor(1, visible),
                KeyCode::PageUp => app.move_cursor(-(visible as isize), visible),
                KeyCode::PageDown => app.move_cursor(visible as isize, visible),
                KeyCode::Home => app.move_cursor(-(app.results.len() as isize), visible),
                KeyCode::End => app.move_cursor(app.results.len() as isize, visible),
                KeyCode::Char('/') => {
                    app.mode = Mode::Search;
                    app.query.clear();
                    app.status = Some("tape une recherche".to_string());
                }
                KeyCode::Char('t') => download_selected(api, app),
                KeyCode::Enter => {
                    if let Some(track) = app.selected().cloned() {
                        leave_screen()?;
                        let played = play_queue(api, track);
                        enter_screen()?;
                        if let Err(err) = played {
                            app.status = Some(format!("lecture interrompue : {err}"));
                        } else {
                            app.status = Some("retour a la liste".to_string());
                        }
                    }
                }
                _ => {}
            },
        }
    }
}

fn submit(api: &HiraApi, app: &mut App) {
    let query = app.query.trim().to_string();
    if query.is_empty() {
        return;
    }

    // La bibliotheque repond sans reseau : ses titres passent devant.
    let local = app.library.search(&query, RESULTS);

    app.status = Some("recherche…".to_string());
    let _ = draw(app);

    match api.search(&query, RESULTS.saturating_sub(local.len())) {
        Ok(found) if found.is_empty() && local.is_empty() => {
            app.status = Some(format!("aucun resultat pour « {query} »"));
        }
        Ok(found) => {
            let mut merged = local;
            merged.extend(found);
            let mine = merged.iter().filter(|t| t.local_path.is_some()).count();
            app.status = Some(format!(
                "{} resultats dont {mine} chez toi",
                merged.len()
            ));
            app.results = merged;
            app.cursor = 0;
            app.offset = 0;
            app.mode = Mode::Results;
        }
        // Le reseau tombe : la bibliotheque locale reste utilisable.
        Err(err) if !local.is_empty() => {
            app.status =
                Some(format!("{} titres chez toi (reseau : {err})", local.len()));
            app.results = local;
            app.cursor = 0;
            app.offset = 0;
            app.mode = Mode::Results;
        }
        Err(err) => app.status = Some(format!("erreur : {err}")),
    }
}

/// Telechargement : une action de l'utilisateur, jamais automatique.
fn download_selected(api: &HiraApi, app: &mut App) {
    let Some(track) = app.selected().cloned() else {
        return;
    };

    if !track.can(Capability::Offline) {
        app.status = Some(
            "ce titre se lit dans le lecteur officiel : pas de copie locale".to_string(),
        );
        return;
    }
    if playback::is_downloaded(&track) {
        app.status = Some(format!("« {} » est deja dans ta musique", track.title));
        return;
    }

    app.status = Some(format!("telechargement de « {} »…", track.title));
    let _ = draw(app);

    app.status = Some(match playback::download_for_offline(api, &track) {
        Ok(path) => format!("telecharge : {}", path.display()),
        Err(err) => format!("telechargement impossible : {err}"),
    });
}

/// Lit une file prechargee : suivant et precedent sont alors instantanes.
///
/// Les suggestions sont demandees une seule fois, au lancement. `n` avance,
/// `p` recule, la fin d'un morceau avance aussi, et `q` rend la main a la liste.
fn play_queue(api: &HiraApi, first: Track) -> Res<()> {
    let mut queue = vec![first.clone()];
    let mut suggestions = api.similar(&first).unwrap_or_default();
    if suggestions.is_empty() {
        suggestions = api.licensed_trending().unwrap_or_default();
    }
    queue.extend(suggestions.into_iter().filter(|t| t.uri != first.uri));

    let mut index = 0usize;
    while let Some(track) = queue.get(index).cloned() {
        let up_next = queue
            .get(index + 1)
            .map(|t| format!("{} — {}", t.title, t.artist_names()));

        println!("\n  > {} — {}", track.title, track.artist_names());

        match playback::play(api, &track, up_next.as_deref()) {
            Ok(Outcome::Quit) => return Ok(()),
            Ok(Outcome::Previous) => index = index.saturating_sub(1),
            Ok(Outcome::Next) | Ok(Outcome::Finished) => index += 1,
            Err(err) => {
                // Un titre illisible ne doit pas tuer la file : on passe.
                println!("  lecture impossible : {err}");
                index += 1;
            }
        }
    }

    println!("  fin de la file.");
    Ok(())
}

fn visible_rows() -> usize {
    let (_, rows) = terminal::size().unwrap_or((80, 24));
    // Entete 4 lignes, pied 2 lignes.
    (rows as usize).saturating_sub(6)
}

fn draw(app: &App) -> io::Result<()> {
    let mut out = io::stdout();
    let (columns, rows) = terminal::size()?;
    let width = columns as usize;
    let visible = visible_rows();

    queue!(out, Clear(ClearType::All), cursor::MoveTo(0, 0))?;

    // Entete.
    queue!(
        out,
        SetAttribute(Attribute::Bold),
        Print(ui::clip("hira", width)),
        SetAttribute(Attribute::Reset),
        cursor::MoveTo(0, 1),
    )?;

    let caret = if app.mode == Mode::Search { "▌" } else { "" };
    queue!(
        out,
        SetForegroundColor(if app.mode == Mode::Search {
            Color::Green
        } else {
            Color::DarkGrey
        }),
        Print(ui::clip(&format!("recherche : {}{caret}", app.query), width)),
        ResetColor,
    )?;

    // Liste.
    for row in 0..visible {
        let index = app.offset + row;
        let Some(track) = app.results.get(index) else {
            break;
        };
        let selected = index == app.cursor && app.mode == Mode::Results;

        let marker = if track.local_path.is_some() {
            "*" // un fichier a toi
        } else if track.can(Capability::Offline) {
            if playback::is_downloaded(track) {
                "•"
            } else {
                "v"
            }
        } else {
            ">"
        };

        let line = format!(
            " {} {:<38} {:<22} {:>6}",
            marker,
            ui::clip(&track.title, 38),
            ui::clip(&track.artist_names(), 22),
            format_duration(track.duration()),
        );

        queue!(out, cursor::MoveTo(0, 3 + row as u16))?;
        if selected {
            queue!(
                out,
                SetBackgroundColor(Color::Green),
                SetForegroundColor(Color::Black),
                Print(format!("{:<width$}", ui::clip(&line, width), width = width)),
                ResetColor,
            )?;
        } else {
            queue!(out, Print(ui::clip(&line, width)))?;
        }
    }

    // Pied.
    if let Some(status) = &app.status {
        queue!(
            out,
            cursor::MoveTo(0, rows.saturating_sub(2)),
            SetForegroundColor(Color::DarkGrey),
            Print(ui::clip(status, width)),
            ResetColor,
        )?;
    }

    let help = match app.mode {
        Mode::Search => "Entree chercher  ·  Echap liste  ·  Ctrl-C quitter",
        Mode::Results => {
            "↑↓ choisir  ·  Entree jouer  ·  t telecharger  ·  / rechercher  ·  q quitter"
        }
    };
    queue!(
        out,
        cursor::MoveTo(0, rows.saturating_sub(1)),
        SetForegroundColor(Color::DarkGrey),
        Print(ui::clip(help, width)),
        ResetColor,
    )?;

    out.flush()
}

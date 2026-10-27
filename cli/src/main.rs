//! Hira en terminal.
//!
//! Sans argument, ouvre la session interactive : on cherche, on choisit, et la
//! lecture enchaine sur des titres proches. Les sous-commandes restent la pour
//! un usage ponctuel ou scripte.
//!
//! Deux chemins de lecture, dictes par les capacites du titre (voir
//! `playback.rs`) : audio local pour le catalogue sous licence, lecteur
//! officiel dans le navigateur pour le catalogue mondial. Rien n'est extrait
//! d'un flux YouTube.

mod api;
mod capability;
mod interactive;
mod karaoke;
mod library;
mod playback;
mod player;
mod ui;

use std::env;

use api::HiraApi;

const DEFAULT_API: &str = "http://127.0.0.1:8787";

type Res<T> = Result<T, Box<dyn std::error::Error>>;

fn main() {
    if let Err(err) = run() {
        eprintln!("hira : {err}");
        std::process::exit(1);
    }
}

fn run() -> Res<()> {
    let args: Vec<String> = env::args().skip(1).collect();
    let base = env::var("HIRA_API_URL").unwrap_or_else(|_| DEFAULT_API.to_string());

    match args.first().map(String::as_str) {
        // Sans argument, le mode interactif : c'est l'usage principal.
        None => interactive::run(&HiraApi::new(&base)?),
        Some("help" | "-h" | "--help") => {
            usage();
            Ok(())
        }
        Some("library") => cmd_library(),
        Some("trending") => cmd_trending(&HiraApi::new(&base)?),
        Some("search") => cmd_search(&HiraApi::new(&base)?, &args[1..]),
        Some("play") => cmd_play(&HiraApi::new(&base)?, &args[1..]),
        Some(other) => {
            eprintln!("hira : commande inconnue \"{other}\"\n");
            usage();
            std::process::exit(2);
        }
    }
}

fn usage() {
    println!(
        "\
hira — toute la musique, et les paroles qui vont avec

  hira                           session interactive (recherche + enchainement)
  hira search <recherche>        cherche dans les deux catalogues
  hira library                   liste ta bibliotheque locale
  hira trending                  classement du catalogue sous licence
  hira play <recherche> [-n N]   lit le resultat N (1 par defaut)

Variables :
  HIRA_API_URL     adresse du Worker (defaut {DEFAULT_API})
  HIRA_MUSIC_DIR   dossiers de musique, separes par « : » (defaut ~/Music)

Dans la vue karaoke : espace met en pause, q quitte.

Le catalogue sous licence se lit dans le terminal et peut etre telecharge.
Le catalogue mondial s'ouvre dans le lecteur officiel, cote navigateur : la
vue revient a la chaine de l'artiste, et rien n'est copie en local."
    );
}

/// Montre ce que le scan a trouve : utile pour verifier HIRA_MUSIC_DIR.
fn cmd_library() -> Res<()> {
    let roots = library::configured_roots();
    if roots.is_empty() {
        return Err("aucun dossier de musique. Renseigne HIRA_MUSIC_DIR.".into());
    }
    for root in &roots {
        println!("scan : {}", root.display());
    }

    let library = library::scan(&roots);
    if library.is_empty() {
        println!("\nAucun fichier audio trouve.");
        return Ok(());
    }

    println!("\n{} titres\n", library.len());
    ui::print_tracks(&library.all(200));
    ui::legend();
    Ok(())
}

fn cmd_trending(api: &HiraApi) -> Res<()> {
    let tracks = api.licensed_trending()?;
    println!(
        "Classement du catalogue sous licence — {} titres\n",
        tracks.len()
    );
    ui::print_tracks(&tracks);
    ui::legend();
    Ok(())
}

fn cmd_search(api: &HiraApi, args: &[String]) -> Res<()> {
    let (query, _) = parse_query(args);
    if query.is_empty() {
        return Err("precise une recherche : hira search <artiste ou titre>".into());
    }
    let mut tracks = library::scan(&library::configured_roots()).search(&query, 20);
    let mine = tracks.len();
    tracks.extend(api.search(&query, 20usize.saturating_sub(mine))?);

    if tracks.is_empty() {
        println!("Aucun resultat pour \"{query}\".");
        return Ok(());
    }
    println!("{} resultats pour \"{}\" dont {mine} chez toi\n", tracks.len(), query);
    ui::print_tracks(&tracks);
    ui::legend();
    Ok(())
}

fn cmd_play(api: &HiraApi, args: &[String]) -> Res<()> {
    let (query, pick) = parse_query(args);
    if query.is_empty() {
        return Err("precise une recherche : hira play <artiste ou titre>".into());
    }

    let tracks = api.search(&query, 20)?;
    let index = pick.unwrap_or(1).saturating_sub(1);
    let track = tracks
        .get(index)
        .ok_or_else(|| format!("aucun resultat numero {} pour \"{query}\"", index + 1))?;

    playback::play(api, track, None)?;
    Ok(())
}

/// Separe la recherche de l'option `-n N`.
fn parse_query(args: &[String]) -> (String, Option<usize>) {
    let mut words: Vec<&str> = Vec::new();
    let mut pick = None;
    let mut iter = args.iter();

    while let Some(arg) = iter.next() {
        match arg.as_str() {
            "-n" | "--pick" => {
                pick = iter.next().and_then(|v| v.parse::<usize>().ok());
            }
            other => words.push(other),
        }
    }

    (words.join(" "), pick)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn words(list: &[&str]) -> Vec<String> {
        list.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn parse_query_assemble_les_mots() {
        let (q, pick) = parse_query(&words(&["wawa", "salegy"]));
        assert_eq!(q, "wawa salegy");
        assert_eq!(pick, None);
    }

    #[test]
    fn parse_query_lit_l_option_n() {
        let (q, pick) = parse_query(&words(&["rim", "ka", "-n", "3"]));
        assert_eq!(q, "rim ka");
        assert_eq!(pick, Some(3));
    }

    #[test]
    fn parse_query_ignore_un_n_invalide() {
        let (q, pick) = parse_query(&words(&["-n", "abc", "shyn"]));
        assert_eq!(q, "shyn");
        assert_eq!(pick, None);
    }
}

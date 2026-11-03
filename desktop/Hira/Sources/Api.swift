//  Client du Worker.
//
//  Aucune cle d API ne vit dans l app : elle ne parle qu au Worker, qui garde
//  les secrets. Tant que le Worker n est pas deploye, l adresse par defaut est
//  celle du `npm run dev` local.

import Foundation

struct Artiste: Codable {
  let name: String
  /// Pour un resultat YouTube, c est l identifiant de la chaine. Il sert a
  /// reconnaitre un ayant droit qui refuse tout son repertoire.
  let id: String?
}

struct Titre: Codable, Identifiable, Hashable {
  let uri: String
  let title: String
  let artists: [Artiste]
  let durationMs: Int
  let artworkUrl: String?
  let capabilities: [String]
  let requiresVisiblePlayer: Bool?
  let streamUrl: String?

  var id: String { uri }
  var artiste: String { artists.first?.name ?? "" }
  /// Une radio en direct : pas de duree, pas de paroles, pas de voisins.
  var estRadio: Bool { uri.hasPrefix("radio:") }
  /// L identifiant YouTube, quand c est de la video.
  var video: String? {
    uri.hasPrefix("youtube:") ? String(uri.dropFirst("youtube:".count)) : nil
  }
  /// Meme frontiere que cote Worker et cote web : pas d audio seul, donc lecteur visible.
  var videoObligatoire: Bool {
    (requiresVisiblePlayer ?? false) || !capabilities.contains("audioOnly")
  }
  func hash(into h: inout Hasher) { h.combine(uri) }
  static func == (a: Titre, b: Titre) -> Bool { a.uri == b.uri }
}

struct Genre: Decodable, Identifiable, Hashable {
  let slug: String
  let label: String
  let tagline: String
  let count: Int
  /// Jusqu a quatre pochettes, pour la mosaique du rayon.
  let pochettes: [String]?
  var id: String { slug }
}

struct PaysRadio: Decodable, Identifiable, Hashable {
  let code: String
  let nom: String
  let stations: Int
  var id: String { code }
}

struct Playlist: Decodable, Identifiable, Hashable {
  let slug: String
  let title: String
  let kind: String
  let description: String
  let count: Int
  let pochettes: [String]?
  var id: String { slug }
}

struct LigneParole: Decodable, Hashable {
  let atMs: Int
  let text: String
}

enum Api {
  /// Adresse du Worker.
  ///
  /// Trois sources, de la plus precise a la plus generale :
  ///
  /// 1. `--api <url>` au lancement — pour pointer le Worker local pendant le
  ///    developpement sans recompiler ;
  /// 2. `api` dans le fichier de reglages, si tu heberges le tien ;
  /// 3. le Worker deploye, par defaut.
  ///
  /// Figer l'adresse dans le binaire obligeait a recompiler pour basculer
  /// entre le local et le deploye, ce qui arrive plusieurs fois par jour.
  static let PAR_DEFAUT = "https://radiokoleka-api.radiokoleka.workers.dev"

  static var base: URL = {
    if let i = CommandLine.arguments.firstIndex(of: "--api"),
       i + 1 < CommandLine.arguments.count,
       let url = URL(string: CommandLine.arguments[i + 1]) {
      return url
    }
    return URL(string: PAR_DEFAUT)!
  }()

  /// Pose l'adresse venue des reglages, si elle y est.
  static func adopter(_ adresse: String) {
    guard !CommandLine.arguments.contains("--api"),
          !adresse.trimmingCharacters(in: .whitespaces).isEmpty,
          let url = URL(string: adresse) else { return }
    base = url
  }

  private static func lire<T: Decodable>(_ chemin: String, _ type: T.Type) async throws -> T {
    let (donnees, _) = try await URLSession.shared.data(from: base.appending(path: chemin))
    return try JSONDecoder().decode(type, from: donnees)
  }

  private struct Genres: Decodable { let genres: [Genre] }
  private struct Titres: Decodable { let tracks: [Titre] }
  private struct Playlists: Decodable { let playlists: [Playlist] }
  private struct Paroles: Decodable {
    struct Corps: Decodable { let lines: [LigneParole] }
    let lyrics: Corps?
  }

  static func enLigne() async -> Bool {
    struct Sante: Decodable { let ok: Bool }
    return (try? await lire("/v1/health", Sante.self))?.ok == true
  }

  /// Attend que le Worker reponde, en espacant les essais.
  ///
  /// Au reveil, un serveur local met parfois quelques secondes a reprendre, et
  /// parfois ne reprend pas du tout. Un seul `enLigne()` ne distingue pas les
  /// deux. Meme raisonnement que cote navigateur.
  static func attendreLeWorker(essais: Int = 5, palierMs: UInt64 = 1000) async -> Bool {
    for i in 0..<essais {
      if await enLigne() { return true }
      try? await Task.sleep(nanoseconds: palierMs * 1_000_000 * UInt64(i + 1))
    }
    return false
  }

  static func genres() async throws -> [Genre] {
    try await lire("/v1/genres", Genres.self).genres
  }

  static func genre(_ slug: String) async throws -> [Titre] {
    try await lire("/v1/genres/\(slug)", Titres.self).tracks
  }

  /// Recherche dans les deux catalogues.
  ///
  /// On ne passe pas `audio_only` : l app porte le lecteur officiel, donc le
  /// catalogue mondial est jouable et n a aucune raison d etre filtre. Meme
  /// raisonnement que cote navigateur.
  /// 50 est le maximum qu'une page de `search.list` rend, et elle coute le
  /// meme quota qu'une page de 10 : autant la demander entiere.
  static func chercher(_ requete: String, limite: Int = 50) async -> [Titre] {
    var composants = URLComponents(url: base.appending(path: "/v1/search"),
                                   resolvingAgainstBaseURL: false)!
    composants.queryItems = [
      .init(name: "q", value: requete),
      .init(name: "limit", value: String(limite)),
    ]
    guard let url = composants.url,
          let (donnees, _) = try? await URLSession.shared.data(from: url),
          let corps = try? JSONDecoder().decode(Titres.self, from: donnees)
    else { return [] }
    return corps.tracks
  }

  /// Completion de saisie. Le catalogue seulement — zero unite de quota.
  static func propositions(_ debut: String) async -> [String] {
    var composants = URLComponents(url: base.appending(path: "/v1/suggest"),
                                   resolvingAgainstBaseURL: false)!
    composants.queryItems = [.init(name: "q", value: debut)]
    struct Reponse: Decodable { let suggestions: [String] }
    guard let url = composants.url,
          let (donnees, _) = try? await URLSession.shared.data(from: url),
          let corps = try? JSONDecoder().decode(Reponse.self, from: donnees)
    else { return [] }
    return corps.suggestions
  }

  /// Radios en direct d un pays. Le Worker garde la grille six heures.
  static func radios(pays: String = "MG") async -> [Titre] {
    var composants = URLComponents(url: base.appending(path: "/v1/radios"),
                                   resolvingAgainstBaseURL: false)!
    composants.queryItems = [.init(name: "pays", value: pays)]
    guard let url = composants.url,
          let (donnees, _) = try? await URLSession.shared.data(from: url),
          let corps = try? JSONDecoder().decode(Titres.self, from: donnees)
    else { return [] }
    return corps.tracks
  }

  /// Les pays qui ont des radios. Le Worker garde la liste une journee.
  static func paysRadio() async -> [PaysRadio] {
    struct Reponse: Decodable { let pays: [PaysRadio] }
    guard let (donnees, _) = try? await URLSession.shared.data(
            from: base.appending(path: "/v1/radios/pays")),
          let corps = try? JSONDecoder().decode(Reponse.self, from: donnees)
    else { return [] }
    return corps.pays
  }

  static func playlists() async throws -> [Playlist] {
    try await lire("/v1/playlists", Playlists.self).playlists
  }

  static func playlist(_ slug: String) async throws -> [Titre] {
    try await lire("/v1/playlists/\(slug)", Titres.self).tracks
  }

  /// Titres a enchainer.
  ///
  /// L artiste est transmis, et ce n est pas un detail : un titre absent du
  /// catalogue cure n a pas de graine en base, et sans cet indice le Worker
  /// repond vide — c est-a-dire pour la quasi-totalite des resultats de
  /// recherche live.
  static func similaires(_ titre: Titre) async -> [Titre] {
    // Surtout pas `appending(path:)` ici : il re-encode le `%` de l uri deja
    // encodee, le Worker recoit `youtube%3A...` au lieu de `youtube:...`, ne
    // trouve aucune graine en base, et ne rend que le repli sous licence. La
    // file se remplissait alors de titres en audio direct, que l app saute.
    let encodee = titre.uri.addingPercentEncoding(
      withAllowedCharacters: .alphanumerics) ?? titre.uri
    var composants = URLComponents(
      string: base.absoluteString + "/v1/similar/" + encodee)!
    composants.queryItems = [
      .init(name: "artist", value: titre.artiste),
      // Le titre sert a reconnaitre un artiste du catalogue cite dedans :
      // « Mr Sayda X Ortegah » credite ORTEGAH, et Mr Sayda est dans le titre.
      .init(name: "title", value: titre.title),
    ]
    guard let url = composants.url,
          let (donnees, _) = try? await URLSession.shared.data(from: url),
          let corps = try? JSONDecoder().decode(Titres.self, from: donnees)
    else { return [] }
    return corps.tracks
  }

  /// Une liste vide n est pas une erreur : beaucoup de titres n ont pas de paroles.
  static func paroles(_ titre: Titre) async -> [LigneParole] {
    var composants = URLComponents(url: base.appending(path: "/v1/lyrics"), resolvingAgainstBaseURL: false)!
    composants.queryItems = [
      .init(name: "artist", value: titre.artiste),
      .init(name: "title", value: titre.title),
      .init(name: "duration", value: String(titre.durationMs / 1000)),
    ]
    guard let url = composants.url,
          let (donnees, _) = try? await URLSession.shared.data(from: url),
          let corps = try? JSONDecoder().decode(Paroles.self, from: donnees)
    else { return [] }
    return corps.lyrics?.lines ?? []
  }
}

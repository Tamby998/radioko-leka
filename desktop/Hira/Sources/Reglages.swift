//  Les reglages, gardes sur la machine.
//
//  Meme principe que les listes et les refus : un fichier JSON dans le dossier
//  de l application, ecrit en entier a chaque changement.
//
//  Ce qui n y est pas, et pourquoi : il n y a **pas d egaliseur**. On ne touche
//  jamais au flux audio d un clip — c est le lecteur officiel qui le joue, et
//  il n expose ni bandes ni filtres. Un egaliseur ne marcherait que sur les
//  titres en audio direct, donc s allumerait et s eteindrait selon le morceau.
//  Le volume et la vitesse, eux, existent des deux cotes.

import SwiftUI

enum Theme: String, CaseIterable, Codable {
  case systeme, clair, sombre

  var mot: String {
    switch self {
    case .systeme: return "Systeme"
    case .clair: return "Clair"
    case .sombre: return "Sombre"
    }
  }
  var schema: ColorScheme? {
    switch self {
    case .systeme: return nil
    case .clair: return .light
    case .sombre: return .dark
    }
  }
  /// L apparence AppKit, pour que le cadre de la fenetre suive le contenu.
  var apparence: NSAppearance? {
    switch self {
    case .systeme: return nil
    case .clair: return NSAppearance(named: .aqua)
    case .sombre: return NSAppearance(named: .darkAqua)
    }
  }
}

/// Les couleurs sont gardees en hexadecimal : un `Color` ne se serialise pas,
/// et six caracteres se relisent a l oeil dans le fichier.
struct Reglages: Codable, Equatable {
  var theme: Theme = .sombre
  /// Couleur principale : ce qui est actif, en cours, choisi.
  var accent: String = "F2C94C"
  /// Couleur secondaire : la ligne de progression, les accents discrets.
  var second: String = "7BD88F"
  var volume: Double = 1.0
  var vitesse: Double = 1.0
  /// Adresse du Worker. Vide = celle compilee par defaut.
  var api: String = ""
  /// Jouer des l ouverture.
  ///
  /// Vrai par defaut : l app s ouvrait sur une liste muette, et qui la
  /// decouvre se demande si elle fonctionne avant d avoir pense a cliquer.
  /// Trois secondes de son repondent mieux qu un mode d emploi.
  var demarrerEnLecture: Bool = true
  /// `grande`, `reduite` ou `masquee`.
  var tailleVideo: String = TailleVideo.grande.rawValue
}

/// Le dossier ou vivent listes, refus et reglages.
///
/// Un seul endroit qui le decide, parce que trois magasins le partagent. Le
/// projet s appelait « hira » : si l ancien dossier existe, on le reprend
/// plutot que de laisser les listes derriere.
func dossierDonnees() -> URL {
  let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
    .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
  let nouveau = base.appendingPathComponent("RadiokoLeka", isDirectory: true)
  let ancien = base.appendingPathComponent("hira", isDirectory: true)

  let f = FileManager.default
  if !f.fileExists(atPath: nouveau.path), f.fileExists(atPath: ancien.path) {
    try? f.moveItem(at: ancien, to: nouveau)
  }
  try? f.createDirectory(at: nouveau, withIntermediateDirectories: true)
  return nouveau
}

@MainActor
final class Preferences: ObservableObject {
  @Published var valeurs: Reglages {
    didSet { if valeurs != oldValue { enregistrer() } }
  }

  private let fichier: URL
  private let journal: (String) -> Void

  init(journal: @escaping (String) -> Void = { _ in }) {
    self.journal = journal
    fichier = dossierDonnees().appendingPathComponent("reglages.json")

    if let donnees = try? Data(contentsOf: fichier),
       let lues = try? JSONDecoder().decode(Reglages.self, from: donnees) {
      valeurs = lues
    } else {
      valeurs = Reglages()
    }
    journal("reglages : theme \(valeurs.theme.rawValue), accent #\(valeurs.accent)"
            + ", volume \(Int(valeurs.volume * 100)) %")
  }

  var accent: Color { Color(hex: valeurs.accent) }
  var second: Color { Color(hex: valeurs.second) }

  /// Les deux couleurs proposees, pour ne pas imposer un selecteur a l aveugle.
  static let PALETTE: [(nom: String, hex: String)] = [
    ("Or", "F2C94C"),
    ("Menthe", "7BD88F"),
    ("Corail", "FF6B6B"),
    ("Lavande", "B39DDB"),
    ("Ciel", "64B5F6"),
    ("Cuivre", "D98E5A"),
  ]

  private func enregistrer() {
    let encodeur = JSONEncoder()
    encodeur.outputFormatting = [.prettyPrinted, .sortedKeys]
    do {
      try encodeur.encode(valeurs).write(to: fichier, options: .atomic)
    } catch {
      journal("echec d ecriture des reglages : \(error)")
    }
  }
}

extension Color {
  /// `RRGGBB`, sans diese. Une valeur illisible rend un gris neutre plutot que
  /// de faire planter l interface.
  init(hex: String) {
    let propre = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    guard propre.count == 6, let valeur = UInt32(propre, radix: 16) else {
      self = .gray
      return
    }
    self = Color(
      .sRGB,
      red: Double((valeur >> 16) & 0xFF) / 255,
      green: Double((valeur >> 8) & 0xFF) / 255,
      blue: Double(valeur & 0xFF) / 255)
  }
}

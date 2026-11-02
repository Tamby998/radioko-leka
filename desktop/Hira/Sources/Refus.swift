//  Memoire des clips qui n ont pas joue.
//
//  Le Worker a la sienne, `clips_refuses`, remplie par le banc avant le seed.
//  Celle-ci est plus large : elle retient ce que *toi* as rencontre en lecture
//  reelle, y compris des clips que la recherche live rend sans que le catalogue
//  les ait jamais vus. C est elle qui fait qu un titre barre une fois ne
//  revient pas demain.
//
//  Meme choix que cote navigateur, ou elle vit dans `hira.refuses.v1`. Ici
//  c est un fichier, pour qu elle survive au redemarrage.

import Foundation

@MainActor
final class MemoireDesRefus: ObservableObject {
  @Published private(set) var uris: Set<String> = []
  /// Chaines dont plusieurs clips ont refuse.
  ///
  /// Le banc l a montre ce matin : le refus se decide **par ayant droit**, pour
  /// tout son repertoire — 0 jouable sur 40 chez Bruno Mars, classiques de 2010
  /// compris. Deux refus sur une meme chaine suffisent donc a conclure, et ses
  /// autres clips n ont plus rien a faire en tete de recherche.
  @Published private(set) var chaines: [String: Int] = [:]

  static let SEUIL_CHAINE = 2

  private let fichier: URL
  private let journal: (String) -> Void

  init(journal: @escaping (String) -> Void = { _ in }) {
    self.journal = journal
    fichier = dossierDonnees().appendingPathComponent("refus.json")

    if let donnees = try? Data(contentsOf: fichier),
       let lues = try? JSONDecoder().decode(Fichier.self, from: donnees) {
      uris = Set(lues.uris)
      chaines = lues.chaines
    }
    journal("refus connus : \(uris.count) clips, \(chainesEcartees.count) chaines ecartees")
  }

  private struct Fichier: Codable {
    var uris: [String] = []
    var chaines: [String: Int] = [:]
  }

  func contient(_ uri: String) -> Bool { uris.contains(uri) }

  var chainesEcartees: Set<String> {
    Set(chaines.filter { $0.value >= Self.SEUIL_CHAINE }.keys)
  }

  /// La chaine de ce titre est-elle condamnee ?
  ///
  /// **Jamais pour une radio.** Toutes les stations d un pays partagent le
  /// meme identifiant d artiste — `radio:MG` — si bien que deux flux morts
  /// banniraient Madagascar en entier. Le raisonnement « un ayant droit refuse
  /// tout son repertoire » vaut pour une chaine YouTube, pas pour un pays.
  func chaineEcartee(_ titre: Titre) -> Bool {
    guard !titre.estRadio, let chaine = titre.artists.first?.id else { return false }
    return (chaines[chaine] ?? 0) >= Self.SEUIL_CHAINE
  }

  func retenir(_ uri: String, chaine: String?, pourquoi: String) {
    guard !uris.contains(uri) else { return }
    uris.insert(uri)
    // Le compteur par chaine ne vaut que pour YouTube : voir `chaineEcartee`.
    if let chaine, !chaine.isEmpty, !chaine.hasPrefix("radio:") {
      let compte = (chaines[chaine] ?? 0) + 1
      chaines[chaine] = compte
      if compte == Self.SEUIL_CHAINE {
        journal("chaine ecartee apres \(compte) refus : \(chaine)")
      }
    }
    journal("refus retenu (\(pourquoi)) : \(uri) — \(uris.count) au total")
    enregistrer()
  }

  /// Pour le jour ou un ayant droit change d avis. Rien ne l appelle encore.
  func oublier(_ uri: String) {
    guard uris.remove(uri) != nil else { return }
    enregistrer()
  }

  /// Pour le jour ou on voudra redonner sa chance a une chaine.
  func rehabiliter(_ chaine: String) {
    chaines.removeValue(forKey: chaine)
    enregistrer()
  }

  private func enregistrer() {
    let encodeur = JSONEncoder()
    encodeur.outputFormatting = [.prettyPrinted, .sortedKeys]
    do {
      let contenu = Fichier(uris: uris.sorted(), chaines: chaines)
      try encodeur.encode(contenu).write(to: fichier, options: .atomic)
    } catch {
      journal("echec d ecriture des refus : \(error)")
    }
  }
}

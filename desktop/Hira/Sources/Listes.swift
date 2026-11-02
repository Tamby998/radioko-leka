//  Les listes de l utilisateur, gardees sur sa machine.
//
//  Le titre entier est stocke, pas seulement son uri. C est le meme choix que
//  pour les favoris cote navigateur, et pour la meme raison : une liste doit
//  rester ecoutable meme si le catalogue ne rend plus ce titre — purge,
//  recherche live qui ne le ramene pas, Worker eteint.
//
//  Un seul fichier JSON, ecrit en entier a chaque changement. Les listes d une
//  personne tiennent en quelques dizaines de kilo-octets ; une base de donnees
//  ici serait du zele.

import Foundation

struct ListeLocale: Codable, Identifiable, Hashable {
  var id: String
  var nom: String
  var titres: [Titre]
  var modifiee: Date

  init(nom: String, titres: [Titre] = []) {
    self.id = UUID().uuidString
    self.nom = nom
    self.titres = titres
    self.modifiee = Date()
  }
}

@MainActor
final class MesListes: ObservableObject {
  @Published private(set) var listes: [ListeLocale] = []

  private let fichier: URL
  private let journal: (String) -> Void

  init(journal: @escaping (String) -> Void = { _ in }) {
    self.journal = journal
    fichier = dossierDonnees().appendingPathComponent("listes.json")
    charger()
  }

  /// Ou le fichier vit, pour pouvoir le dire dans le journal.
  var chemin: String { fichier.path }

  private func charger() {
    guard let donnees = try? Data(contentsOf: fichier) else {
      journal("mes listes : aucune (\(fichier.path))")
      return
    }
    let decodeur = JSONDecoder()
    decodeur.dateDecodingStrategy = .iso8601
    // Un fichier illisible ne doit pas empecher l app de demarrer : on repart
    // d une liste vide plutot que de refuser de s ouvrir.
    guard let lues = try? decodeur.decode([ListeLocale].self, from: donnees) else {
      journal("mes listes : fichier illisible, ignore")
      return
    }
    listes = lues.sorted { $0.modifiee > $1.modifiee }
    let titres = listes.reduce(0) { $0 + $1.titres.count }
    journal("mes listes : \(listes.count) (\(titres) titres)")
  }

  private func enregistrer() {
    let encodeur = JSONEncoder()
    encodeur.dateEncodingStrategy = .iso8601
    encodeur.outputFormatting = [.prettyPrinted, .sortedKeys]
    do {
      try encodeur.encode(listes).write(to: fichier, options: .atomic)
    } catch {
      journal("echec d ecriture des listes : \(error)")
    }
  }

  // MARK: modifications

  @discardableResult
  func creer(_ nom: String, avec titre: Titre? = nil) -> ListeLocale? {
    let propre = nom.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !propre.isEmpty else { return nil }
    var liste = ListeLocale(nom: propre)
    if let titre { liste.titres = [titre] }
    listes.insert(liste, at: 0)
    enregistrer()
    journal("liste creee : \(propre)")
    return liste
  }

  /// Ajoute, sans doublon : une liste qui contient deux fois le meme titre
  /// n est jamais ce qu on voulait.
  func ajouter(_ titre: Titre, a identifiant: String) {
    guard let index = listes.firstIndex(where: { $0.id == identifiant }) else { return }
    guard !listes[index].titres.contains(where: { $0.uri == titre.uri }) else {
      journal("deja dans « \(listes[index].nom) » : \(titre.title)")
      return
    }
    listes[index].titres.append(titre)
    listes[index].modifiee = Date()
    enregistrer()
    journal("ajoute a « \(listes[index].nom) » : \(titre.title) (\(listes[index].titres.count))")
  }

  func retirer(_ uri: String, de identifiant: String) {
    guard let index = listes.firstIndex(where: { $0.id == identifiant }) else { return }
    listes[index].titres.removeAll { $0.uri == uri }
    listes[index].modifiee = Date()
    enregistrer()
    journal("retire de « \(listes[index].nom) » (\(listes[index].titres.count) restants)")
  }

  func renommer(_ identifiant: String, en nom: String) {
    let propre = nom.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !propre.isEmpty,
          let index = listes.firstIndex(where: { $0.id == identifiant }) else { return }
    listes[index].nom = propre
    listes[index].modifiee = Date()
    enregistrer()
  }

  func supprimer(_ identifiant: String) {
    guard let index = listes.firstIndex(where: { $0.id == identifiant }) else { return }
    let nom = listes[index].nom
    listes.remove(at: index)
    enregistrer()
    journal("liste supprimee : \(nom)")
  }

  func liste(_ identifiant: String) -> ListeLocale? {
    listes.first { $0.id == identifiant }
  }
}

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

  /// Au-dela de ce nombre de refus d affilee sans une seule lecture reussie,
  /// on cesse de croire les refus.
  ///
  /// Le 5 novembre 2026, tous les clips ont renvoye l erreur 150 pendant une
  /// panne d integration cote YouTube — y compris ceux qui jouaient la veille,
  /// et y compris la video la plus integree du web. L app a condamne 89 clips
  /// et banni 20 chaines, dont presque tous les artistes malgaches du
  /// catalogue, avant qu on ne s en apercoive. Un refus isole dit quelque
  /// chose d un ayant droit ; cinquante d affilee ne disent rien d autre que
  /// « la lecture est cassee ».
  static let SEUIL_PANNE = 5

  /// Refus observes depuis la derniere lecture reussie.
  private var enAttente: [(uri: String, chaine: String?, pourquoi: String)] = []
  private var refusDAffilee = 0
  private var panneSignalee = false

  private let fichier: URL
  private let journal: (String) -> Void

  /// `dossier` n existe que pour les tests : sans lui, la verification du
  /// garde-fou ecrirait dans la memoire reelle de l utilisateur.
  init(journal: @escaping (String) -> Void = { _ in }, dossier: URL? = nil) {
    self.journal = journal
    fichier = (dossier ?? dossierDonnees()).appendingPathComponent("refus.json")

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

  /// Note un refus **sans le graver**.
  ///
  /// Il n entre en memoire qu une fois qu une lecture a reussi derriere :
  /// c est cette reussite qui prouve que le refus disait quelque chose du clip
  /// et non de la chaine de lecture.
  func retenir(_ uri: String, chaine: String?, pourquoi: String) {
    guard !uris.contains(uri) else { return }
    refusDAffilee += 1

    if refusDAffilee >= Self.SEUIL_PANNE {
      if !panneSignalee {
        panneSignalee = true
        journal("panne generale suspectee : \(refusDAffilee) refus d affilee,"
                + " aucun n est enregistre tant qu un titre n aura pas joue")
      }
      enAttente.removeAll()
      return
    }

    enAttente.append((uri, chaine, pourquoi))
    journal("refus en attente (\(pourquoi)) : \(uri)")
  }

  /// Un titre a reellement joue : la chaine de lecture fonctionne, donc les
  /// refus observes juste avant portent bien sur leurs clips.
  func succes() {
    refusDAffilee = 0
    panneSignalee = false
    guard !enAttente.isEmpty else { return }

    for refus in enAttente where !uris.contains(refus.uri) {
      uris.insert(refus.uri)
      // Le compteur par chaine ne vaut que pour YouTube : voir `chaineEcartee`.
      if let chaine = refus.chaine, !chaine.isEmpty, !chaine.hasPrefix("radio:") {
        let compte = (chaines[chaine] ?? 0) + 1
        chaines[chaine] = compte
        if compte == Self.SEUIL_CHAINE {
          journal("chaine ecartee apres \(compte) refus : \(chaine)")
        }
      }
      journal("refus confirme (\(refus.pourquoi)) : \(refus.uri) — \(uris.count) au total")
    }
    enAttente.removeAll()
    enregistrer()
  }

  /// Tout oublier, apres une panne qui a condamne le catalogue a tort.
  func toutOublier() {
    uris.removeAll()
    chaines.removeAll()
    enAttente.removeAll()
    refusDAffilee = 0
    panneSignalee = false
    journal("memoire des refus remise a zero")
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

//  Le pont vers le lecteur officiel.
//
//  La WebView n est pas l interface : c est une surface de lecture. Elle ne
//  porte que la page du lecteur, servie par le serveur interne, et tout le
//  dialogue passe par un pont nomme `hira`.
//
//  Les codes de refus valent ce qu ils valaient dans le navigateur : 100, 101
//  et 150 veulent dire « ce clip ne jouera jamais ici ». 153 est different —
//  c est l origine qui est refusee, donc une faute de notre cote, pas celle de
//  l ayant droit. On les distingue, sinon on accuserait un clip innocent.

import Combine
import SwiftUI
import WebKit

enum Refus: Int {
  case supprime = 100, interdit = 101, interditBis = 150, origine = 153

  var estLeClip: Bool { self != .origine }
}

@MainActor
final class Lecteur: NSObject, ObservableObject, WKScriptMessageHandler {
  @Published var pret = false
  @Published var enLecture = false
  @Published var positionMs = 0
  /// Dernier refus recu, pour que l interface puisse enchainer ou se plaindre.
  @Published var refus: Refus?

  let vue: WKWebView
  private var horloge: Timer?
  private var journal: (String) -> Void
  /// Appelee quand la lecture demarre vraiment.
  var surLecture: (() -> Void)?
  /// Second crochet, reserve a l app : volume et vitesse a reposer.
  var surLectureSysteme: (() -> Void)?
  /// Appelee quand le titre va au bout.
  ///
  /// Le lecteur envoie `ENDED` (0) comme tout autre changement d etat. Sans
  /// cette sortie, l etat etait journalise et rien n enchainait : le bouton
  /// Suivant marchait, la fin d un titre ne faisait rien.
  var surFin: (() -> Void)?
  /// Demande arrivee avant que la page soit la.
  ///
  /// `evaluateJavaScript` sur une page encore vide echoue sans bruit : la
  /// fonction n existe pas. La file d attente de la page ne suffit donc pas, il
  /// faut aussi attendre de ce cote. Sinon un clic dans la premiere seconde se
  /// perd — c est exactement ce que le journal a montre.
  private var enAttente: String?

  init(port: UInt16, journal: @escaping (String) -> Void = { _ in }) {
    self.journal = journal
    let config = WKWebViewConfiguration()
    // Une app a le droit de lancer sa propre lecture. Sans cette ligne, rien
    // ne demarre sans clic — et la sonde aurait declare tout bloque a tort.
    config.mediaTypesRequiringUserActionForPlayback = []
    vue = WKWebView(frame: .zero, configuration: config)
    vue.setValue(false, forKey: "drawsBackground")
    super.init()
    config.userContentController.add(self, name: "hira")
    vue.load(URLRequest(url: URL(string: "http://127.0.0.1:\(port)/lecteur.html")!))
    // L horloge ne sert qu a suivre la position pour les paroles ; elle ne
    // decide de rien. Les verdicts arrivent par evenement.
    horloge = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.interrogerPosition() }
    }
  }

  func jouer(_ videoId: String) {
    refus = nil
    guard pret else {
      enAttente = videoId
      journal("lecteur: en attente de la page pour \(videoId)")
      return
    }
    evaluer("jouer('\(videoId)')")
  }

  func basculer() {
    vue.evaluateJavaScript("basculer()") { [weak self] resultat, _ in
      Task { @MainActor in self?.enLecture = (resultat as? Bool) ?? false }
    }
  }

  func aller(_ ms: Int) { evaluer("aller(\(ms))") }

  /// Volume de 0 a 1. Le lecteur officiel l attend de 0 a 100.
  func volume(_ niveau: Double) {
    evaluer("volume(\(Int((niveau * 100).rounded())))")
  }

  /// Vitesse de lecture. Le lecteur n accepte que certains paliers et ignore
  /// le reste en silence — on ne lui propose donc que ceux-la.
  func vitesse(_ facteur: Double) { evaluer("vitesse(\(facteur))") }
  func stopper() { evaluer("stopper()") }

  private func interrogerPosition() {
    vue.evaluateJavaScript("position()") { [weak self] resultat, _ in
      Task { @MainActor in
        if let ms = resultat as? Int { self?.positionMs = ms }
      }
    }
  }

  private func evaluer(_ code: String) {
    vue.evaluateJavaScript(code, completionHandler: nil)
  }

  func userContentController(
    _ controleur: WKUserContentController, didReceive message: WKScriptMessage
  ) {
    guard let brut = message.body as? String,
          let donnees = brut.data(using: .utf8),
          let objet = try? JSONSerialization.jsonObject(with: donnees) as? [String: Any],
          let quoi = objet["quoi"] as? String
    else { return }
    let valeur = objet["valeur"]

    switch quoi {
    case "pret":
      pret = true
      journal("lecteur: pret")
      if let attendu = enAttente {
        enAttente = nil
        evaluer("jouer('\(attendu)')")
        journal("lecteur: demande differee lancee (\(attendu))")
      }
    case "etat":
      // 1 = PLAYING, 2 = PAUSED, 3 = BUFFERING, 0 = ENDED
      let etat = valeur as? Int ?? -1
      enLecture = etat == 1
      journal("lecteur: etat=\(etat)")
      if etat == 0 { surFin?() }
      if etat == 1 { surLectureSysteme?(); surLecture?() }
    case "erreur":
      let code = valeur as? Int ?? -1
      refus = Refus(rawValue: code)
      journal("lecteur: erreur=\(code)")
    case "api":
      journal("lecteur: api=\(valeur as? String ?? "?")")
    default:
      break
    }
  }
}

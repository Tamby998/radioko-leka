//  Banc d integration natif.
//
//  Il remplace le banc en navigateur, et pour une raison precise : celui-la
//  mesurait dans un onglet, et un onglet masque fait brider les minuteries.
//  Une passe menee ainsi avait declare 50 titres gasy injouables alors que 74
//  sur 76 jouent. Ici le verdict est rendu par evenement, la sortie est du
//  texte, et rien ne dort.
//
//  Il reutilise la page du lecteur de l app et son serveur interne : on mesure
//  donc exactement ce que l app fera, pas une approximation.
//
//  Usage :
//    ./banc candidats.json verdicts.json
//
//  `candidats.json` est le format des scripts de collecte : un objet de genres,
//  chacun une liste de { id, artiste, brut }.

import AppKit
import WebKit

let SURSIS: TimeInterval = 2.5
let DELAI: TimeInterval = 14

guard CommandLine.arguments.count >= 3 else {
  FileHandle.standardError.write("usage: banc <candidats.json> <verdicts.json>\n".data(using: .utf8)!)
  exit(2)
}
let fichierEntree = CommandLine.arguments[1]
let fichierSortie = CommandLine.arguments[2]

struct Candidat {
  let id: String
  let artiste: String
  let brut: String
  let genre: String
}

func lireCandidats(_ chemin: String) -> [Candidat] {
  guard let donnees = FileManager.default.contents(atPath: chemin),
        let objet = try? JSONSerialization.jsonObject(with: donnees) as? [String: [[String: Any]]]
  else {
    FileHandle.standardError.write("candidats illisibles : \(chemin)\n".data(using: .utf8)!)
    exit(1)
  }
  var tout: [Candidat] = []
  for (genre, liste) in objet.sorted(by: { $0.key < $1.key }) {
    for element in liste {
      guard let id = element["id"] as? String else { continue }
      tout.append(Candidat(
        id: id,
        artiste: element["artiste"] as? String ?? "?",
        brut: element["brut"] as? String ?? "?",
        genre: genre))
    }
  }
  return tout
}

func page() -> String {
  let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("../Hira/Ressources/lecteur.html")
  guard let contenu = try? String(contentsOf: url, encoding: .utf8) else {
    FileHandle.standardError.write("page du lecteur introuvable\n".data(using: .utf8)!)
    exit(1)
  }
  return contenu
}

func dire(_ texte: String) {
  FileHandle.standardError.write((texte + "\n").data(using: .utf8)!)
  // Sans vidage explicite, la sortie d un run de dix minutes arrive d un bloc
  // a la fin, et on ne peut pas suivre.
  fflush(stderr)
}

@MainActor
final class Banc: NSObject, WKScriptMessageHandler {
  private let vue: WKWebView
  private let fenetre: NSWindow
  private var restants: [Candidat]
  private let total: Int
  private var verdicts: [String: String] = [:]
  private var detail: [(Candidat, String)] = []

  private var courant: Candidat?
  private var pretDuLecteur = false
  private var fini = false
  private var sursis: Timer?
  private var limite: Timer?

  init(candidats: [Candidat], port: UInt16) {
    restants = candidats
    total = candidats.count

    let config = WKWebViewConfiguration()
    // Indispensable : sans ca rien ne demarre sans clic, et tout serait
    // declare bloque pour la mauvaise raison.
    config.mediaTypesRequiringUserActionForPlayback = []
    vue = WKWebView(frame: .init(x: 0, y: 0, width: 480, height: 270), configuration: config)
    fenetre = NSWindow(
      contentRect: .init(x: 40, y: 40, width: 480, height: 270),
      styleMask: [.titled], backing: .buffered, defer: false)
    super.init()
    config.userContentController.add(self, name: "hira")
    fenetre.title = "banc hira"
    fenetre.contentView = vue
    fenetre.makeKeyAndOrderFront(nil)
    vue.load(URLRequest(url: URL(string: "http://127.0.0.1:\(port)/lecteur.html")!))
  }

  func userContentController(
    _ controleur: WKUserContentController, didReceive message: WKScriptMessage
  ) {
    guard let brut = message.body as? String,
          let donnees = brut.data(using: .utf8),
          let objet = try? JSONSerialization.jsonObject(with: donnees) as? [String: Any],
          let quoi = objet["quoi"] as? String
    else { return }

    switch quoi {
    case "pret":
      guard !pretDuLecteur else { return }
      pretDuLecteur = true
      dire("lecteur pret — \(total) titres a passer")
      suivant()
    case "erreur":
      // Le refus arrive par evenement, et il fait autorite sur tout le reste.
      terminer("erreur:\(objet["valeur"] as? Int ?? -1)")
    case "etat":
      let etat = objet["valeur"] as? Int ?? -1
      // PLAYING ou BUFFERING : on ouvre un sursis, pendant lequel une erreur
      // peut encore tomber. Conclure ici donnerait des faux positifs.
      if (etat == 1 || etat == 3), sursis == nil, !fini {
        sursis = Timer.scheduledTimer(withTimeInterval: SURSIS, repeats: false) { _ in
          Task { @MainActor in self.terminer("ok") }
        }
      }
    default:
      break
    }
  }

  private func suivant() {
    sursis?.invalidate(); sursis = nil
    limite?.invalidate()
    guard let prochain = restants.first else { rendreCompte(); return }
    restants.removeFirst()
    courant = prochain
    fini = false

    vue.evaluateJavaScript("jouer('\(prochain.id)')", completionHandler: nil)
    limite = Timer.scheduledTimer(withTimeInterval: DELAI, repeats: false) { _ in
      Task { @MainActor in self.terminer("bloque") }
    }
  }

  private func terminer(_ verdict: String) {
    guard !fini, let c = courant else { return }
    fini = true
    sursis?.invalidate(); sursis = nil
    limite?.invalidate()
    verdicts[c.id] = verdict
    detail.append((c, verdict))

    let rang = total - restants.count
    let marque = verdict == "ok" ? " " : "!"
    dire(String(format: "%@ %3d/%d  %-11s %-22s %-34s %@",
                marque, rang, total, (c.genre as NSString).utf8String!,
                (String(c.artiste.prefix(22)) as NSString).utf8String!,
                (String(c.brut.prefix(34)) as NSString).utf8String!,
                verdict))

    vue.evaluateJavaScript("stopper()", completionHandler: nil)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.suivant() }
  }

  private func rendreCompte() {
    let ok = detail.filter { $0.1 == "ok" }.count
    dire("")
    dire("\(ok) jouables sur \(total)")

    var parGenre: [String: (Int, Int)] = [:]
    for (c, v) in detail {
      var (bons, compte) = parGenre[c.genre] ?? (0, 0)
      if v == "ok" { bons += 1 }
      parGenre[c.genre] = (bons, compte + 1)
    }
    for (genre, (bons, compte)) in parGenre.sorted(by: { $0.key < $1.key }) {
      dire(String(format: "  %-11s %2d/%-2d  %3.0f %%",
                  (genre as NSString).utf8String!, bons, compte,
                  compte == 0 ? 0 : Double(bons) / Double(compte) * 100))
    }

    if let donnees = try? JSONSerialization.data(
      withJSONObject: verdicts, options: [.prettyPrinted, .sortedKeys]) {
      try? donnees.write(to: URL(fileURLWithPath: fichierSortie))
      dire("")
      dire("verdicts ecrits : \(fichierSortie)")
    }
    NSApplication.shared.terminate(nil)
  }
}

@MainActor
func lancer() -> Never {
  let candidats = lireCandidats(fichierEntree)
  guard !candidats.isEmpty else { dire("aucun candidat"); exit(1) }

  let application = NSApplication.shared
  application.setActivationPolicy(.accessory)

  guard let serveur = try? ServeurLocal(page: page()) else {
    dire("serveur local impossible"); exit(1)
  }
  let port = serveur.demarrer()
  guard port != 0 else { dire("aucun port attribue"); exit(1) }
  dire("serveur local : http://127.0.0.1:\(port)")

  let banc = Banc(candidats: candidats, port: port)
  _ = banc
  application.run()
  exit(0)
}

MainActor.assumeIsolated { lancer() }

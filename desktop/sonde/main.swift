//  Sonde d'integration : le lecteur IFrame joue-t-il dans WKWebView ?
//
//  C'est la question qui decide de l'app desktop. Les 189 titres du catalogue
//  sont des clips YouTube, et ils ne jouent que par le lecteur officiel. Si
//  WKWebView ne peut pas l'heberger, l'app se construit autour d'Audius, de
//  Jamendo et des fichiers locaux — autant le savoir avant de dessiner.
//
//  Trois origines, parce que YouTube verifie qui integre son lecteur :
//    file://        la page livree dans le bundle de l'app ;
//    http://        un petit serveur interne a l'app ;
//    hira://        un gestionnaire de schema, via WKURLSchemeHandler.
//
//  Le verdict ne repose que sur des evenements, jamais sur une horloge. Deux
//  pieges deja payes cette semaine : un clip refuse passe par BUFFERING avant
//  que `onError` arrive, donc un etat de lecture seul donne des faux positifs ;
//  et une horloge gelee declare injouable ce qui joue. Donc `erreur` tranche,
//  et PLAYING ouvre un sursis pendant lequel une erreur peut encore tomber.

import AppKit
import WebKit

let VIDEO = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AMPdykrcho4"
let PORT = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "8099"
let SURSIS: TimeInterval = 2.5
let DELAI: TimeInterval = 14

struct Cas {
  let nom: String
  let url: URL
}

final class Sonde: NSObject, WKScriptMessageHandler, WKURLSchemeHandler {
  private var vue: WKWebView!
  private let fenetre: NSWindow
  private var cas: [Cas]
  private var courant: Cas?
  private var fini = false
  private var sursis: Timer?
  private var limite: Timer?
  private var journal: [String] = []
  private var verdicts: [(String, String, String)] = []

  init(cas: [Cas]) {
    self.cas = cas
    fenetre = NSWindow(
      contentRect: .init(x: 80, y: 80, width: 660, height: 380),
      styleMask: [.titled], backing: .buffered, defer: false)
    super.init()

    let config = WKWebViewConfiguration()
    config.userContentController.add(self, name: "hira")
    // Sans ca, rien ne demarre sans clic et tout serait declare bloque pour la
    // mauvaise raison. Une app a le droit de lancer sa propre lecture.
    config.mediaTypesRequiringUserActionForPlayback = []
    config.allowsAirPlayForMediaPlayback = false
    config.setURLSchemeHandler(self, forURLScheme: "hira")

    vue = WKWebView(frame: fenetre.contentLayoutRect, configuration: config)
    fenetre.title = "sonde hira"
    fenetre.contentView = vue
    fenetre.makeKeyAndOrderFront(nil)
  }

  func demarrer() { suivant() }

  private func suivant() {
    sursis?.invalidate(); limite?.invalidate()
    guard !cas.isEmpty else { rendreCompte(); return }
    courant = cas.removeFirst()
    fini = false
    journal = []
    FileHandle.standardError.write("  … \(courant!.nom)\n".data(using: .utf8)!)

    if courant!.url.isFileURL {
      vue.loadFileURL(courant!.url, allowingReadAccessTo: courant!.url.deletingLastPathComponent())
    } else {
      vue.load(URLRequest(url: courant!.url))
    }
    limite = Timer.scheduledTimer(withTimeInterval: DELAI, repeats: false) { _ in
      self.terminer("bloque")
    }
  }

  private func terminer(_ verdict: String) {
    guard !fini, let c = courant else { return }
    fini = true
    sursis?.invalidate(); limite?.invalidate()
    verdicts.append((c.nom, verdict, journal.joined(separator: " ")))
    vue.loadHTMLString("<body style='background:#000'>", baseURL: nil)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.suivant() }
  }

  func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
    guard let texte = m.body as? String, !fini else { return }
    journal.append(texte)

    if texte.hasPrefix("erreur=") {
      terminer("erreur:" + texte.dropFirst(7))
      return
    }
    if texte == "api=echec" {
      terminer("api-non-chargee")
      return
    }
    // PLAYING ou BUFFERING : on ne conclut pas tout de suite. Une erreur peut
    // encore arriver, et c'est elle qui ferait autorite.
    if texte == "etat=1" || texte == "etat=3", sursis == nil {
      sursis = Timer.scheduledTimer(withTimeInterval: SURSIS, repeats: false) { _ in
        self.terminer("ok")
      }
    }
  }

  // Origine hira:// — la page vit en memoire, comme elle vivrait dans le bundle.
  func webView(_ v: WKWebView, start task: WKURLSchemeTask) {
    let page = (try? String(contentsOf: pageLocale, encoding: .utf8)) ?? ""
    let data = Data(page.utf8)
    let reponse = HTTPURLResponse(
      url: task.request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "text/html; charset=utf-8"])!
    task.didReceive(reponse)
    task.didReceive(data)
    task.didFinish()
  }
  func webView(_ v: WKWebView, stop task: WKURLSchemeTask) {}

  private func rendreCompte() {
    print("")
    print("clip teste : \(VIDEO)")
    print("")
    for (nom, verdict, trace) in verdicts {
      print("  \(nom.padding(toLength: 22, withPad: " ", startingAt: 0)) \(verdict)")
      print("    \(trace)")
    }
    NSApplication.shared.terminate(nil)
  }
}

let pageLocale = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
  .appendingPathComponent("sonde.html")

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let sonde = Sonde(cas: [
  Cas(nom: "file://", url: URL(string: "?id=\(VIDEO)", relativeTo: pageLocale)!),
  Cas(nom: "http://127.0.0.1", url: URL(string: "http://127.0.0.1:\(PORT)/sonde.html?id=\(VIDEO)")!),
  Cas(nom: "hira:// (schema)", url: URL(string: "hira://local/sonde.html?id=\(VIDEO)")!),
])
DispatchQueue.main.async { sonde.demarrer() }
app.run()

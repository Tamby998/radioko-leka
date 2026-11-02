//  La barre de menus.
//
//  Les reglages vivent ici, a leur place sur macOS : le menu de l application,
//  avec Commande-virgule. Un bouton dans l en-tete faisait double emploi avec
//  une convention que tout le monde connait deja.
//
//  Les actions passent par des fermetures gardees dans cet objet : une cible de
//  menu doit etre un `NSObject` avec des selecteurs, et on ne va pas repandre
//  des `@objc` dans la coordination pour autant.

import AppKit

@MainActor
final class Menus: NSObject {
  private let ouvrirReglages: () -> Void
  private let basculerLecture: () -> Void
  private let titreSuivant: () -> Void
  private let reglerVolume: (Double) -> Void

  init(
    ouvrirReglages: @escaping () -> Void,
    basculerLecture: @escaping () -> Void,
    titreSuivant: @escaping () -> Void,
    reglerVolume: @escaping (Double) -> Void
  ) {
    self.ouvrirReglages = ouvrirReglages
    self.basculerLecture = basculerLecture
    self.titreSuivant = titreSuivant
    self.reglerVolume = reglerVolume
    super.init()
  }

  @objc private func surReglages() { ouvrirReglages() }
  @objc private func surLecture() { basculerLecture() }
  @objc private func surSuivant() { titreSuivant() }
  @objc private func surPlusFort() { reglerVolume(0.1) }
  @objc private func surMoinsFort() { reglerVolume(-0.1) }

  func poser(nom: String) {
    let barre = NSMenu()

    // Menu de l application.
    let app = NSMenuItem()
    let menuApp = NSMenu()
    menuApp.addItem(withTitle: "A propos de \(nom)",
                    action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                    keyEquivalent: "")
    menuApp.addItem(.separator())
    let reglages = NSMenuItem(title: "Reglages…", action: #selector(surReglages),
                              keyEquivalent: ",")
    reglages.target = self
    menuApp.addItem(reglages)
    menuApp.addItem(.separator())
    menuApp.addItem(withTitle: "Masquer \(nom)",
                    action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
    menuApp.addItem(withTitle: "Quitter \(nom)",
                    action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    app.submenu = menuApp
    barre.addItem(app)

    // Lecture.
    let lecture = NSMenuItem()
    let menuLecture = NSMenu(title: "Lecture")
    for (titre, selecteur, touche, modificateurs) in [
      ("Lecture / Pause", #selector(surLecture), " ", NSEvent.ModifierFlags()),
      ("Titre suivant", #selector(surSuivant), "\u{2192}", NSEvent.ModifierFlags.command),
      ("Plus fort", #selector(surPlusFort), "\u{2191}", NSEvent.ModifierFlags.command),
      ("Moins fort", #selector(surMoinsFort), "\u{2193}", NSEvent.ModifierFlags.command),
    ] as [(String, Selector, String, NSEvent.ModifierFlags)] {
      let item = NSMenuItem(title: titre, action: selecteur, keyEquivalent: touche)
      item.keyEquivalentModifierMask = modificateurs
      item.target = self
      menuLecture.addItem(item)
    }
    lecture.submenu = menuLecture
    barre.addItem(lecture)

    // Fenetre, pour que Reduire et Zoom existent comme ailleurs.
    let fenetre = NSMenuItem()
    let menuFenetre = NSMenu(title: "Fenetre")
    menuFenetre.addItem(withTitle: "Reduire",
                        action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
    menuFenetre.addItem(withTitle: "Zoom",
                        action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
    fenetre.submenu = menuFenetre
    barre.addItem(fenetre)

    NSApplication.shared.mainMenu = barre
    NSApplication.shared.windowsMenu = menuFenetre
  }
}

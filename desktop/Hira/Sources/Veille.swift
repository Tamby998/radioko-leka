//  Veille et reveil.
//
//  Cote navigateur, il a fallu deviner : un battement de dix secondes, un seuil
//  de quatre-vingt-dix, et le pari qu un trou plus grand qu aucun bridage de
//  minuterie connu signifiait un sommeil. Tout ca parce qu une page web n est
//  pas prevenue.
//
//  Une app native l est. `NSWorkspace` previent avant de dormir et apres le
//  reveil, sans seuil, sans faux positif, sans horloge a surveiller. C est la
//  raison la plus nette de faire du natif pour ce projet precis — la machine
//  s endort au bout d une minute d inactivite.

import AppKit

@MainActor
final class Veille {
  private var observateurs: [NSObjectProtocol] = []
  private let journal: (String) -> Void

  init(journal: @escaping (String) -> Void = { _ in }) {
    self.journal = journal
  }

  /// `avant` est appele juste avant le sommeil, `apres` au reveil.
  func surveiller(avant: @escaping () -> Void, apres: @escaping (TimeInterval) -> Void) {
    let centre = NSWorkspace.shared.notificationCenter
    var endormiA: Date?

    observateurs.append(centre.addObserver(
      forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
    ) { [weak self] _ in
      endormiA = Date()
      MainActor.assumeIsolated {
        self?.journal("veille : la machine s endort")
        avant()
      }
    })

    observateurs.append(centre.addObserver(
      forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      let dormi = endormiA.map { Date().timeIntervalSince($0) } ?? 0
      endormiA = nil
      MainActor.assumeIsolated {
        self?.journal("veille : reveil apres \(Int(dormi)) s")
        apres(dormi)
      }
    })
  }

  deinit {
    let centre = NSWorkspace.shared.notificationCenter
    for o in observateurs { centre.removeObserver(o) }
  }
}

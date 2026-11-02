//  Serveur HTTP interne, lie a la boucle locale.
//
//  Il existe pour une seule raison, mesuree et pas supposee : le lecteur IFrame
//  refuse toute origine qui n est pas `http://`. La sonde l a montre sans
//  ambiguite — `file://` et un schema personnalise rendent tous deux
//  l erreur 153, y compris sur un clip parfaitement integrable, tandis que
//  `http://127.0.0.1` joue. Voir desktop/sonde/README.md.
//
//  Il ne sert donc que la page du lecteur, sur un port ephemere, et il
//  n ecoute que 127.0.0.1 : rien de tout ceci ne doit etre joignable depuis le
//  reseau.

import Foundation
import Network

final class ServeurLocal {
  private let ecouteur: NWListener
  private let page: Data
  private(set) var port: UInt16 = 0

  init(page: String) throws {
    self.page = Data(page.utf8)
    let parametres = NWParameters.tcp
    parametres.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
    ecouteur = try NWListener(using: parametres)
  }

  /// Demarre et rend le port attribue. Bloque le temps de l attribution.
  func demarrer() -> UInt16 {
    let attente = DispatchSemaphore(value: 0)
    ecouteur.stateUpdateHandler = { [weak self] etat in
      if case .ready = etat {
        self?.port = self?.ecouteur.port?.rawValue ?? 0
        attente.signal()
      }
      if case .failed = etat { attente.signal() }
    }
    ecouteur.newConnectionHandler = { [weak self] lien in self?.servir(lien) }
    ecouteur.start(queue: .global(qos: .userInitiated))
    _ = attente.wait(timeout: .now() + 3)
    return port
  }

  func arreter() { ecouteur.cancel() }

  /// Une seule page a servir : on lit la requete, on ne la lit meme pas en
  /// entier, et on repond. Pas de routeur, pas de fichiers statiques.
  private func servir(_ lien: NWConnection) {
    lien.start(queue: .global(qos: .userInitiated))
    lien.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] _, _, _, _ in
      guard let self else { return }
      var entetes = "HTTP/1.1 200 OK\r\n"
      entetes += "Content-Type: text/html; charset=utf-8\r\n"
      entetes += "Content-Length: \(self.page.count)\r\n"
      entetes += "Cache-Control: no-store\r\n"
      entetes += "Connection: close\r\n\r\n"
      var reponse = Data(entetes.utf8)
      reponse.append(self.page)
      lien.send(content: reponse, completion: .contentProcessed { _ in lien.cancel() })
    }
  }
}

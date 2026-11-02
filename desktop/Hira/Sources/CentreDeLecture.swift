//  Now Playing et touches media.
//
//  J avais dit que ce serait a moitie possible, en croyant que la session media
//  de l iframe nous bloquait. C est faux : `MPNowPlayingInfoCenter` ne fait que
//  **publier des metadonnees**, et on connait le titre, l artiste, la duree et
//  la position des deux cotes. `MPRemoteCommandCenter` route les touches vers
//  notre propre lecteur, quel qu il soit.
//
//  C est devenu necessaire depuis que la video peut etre masquee : la musique
//  joue alors sans rien a regarder, et sans touches media il faudrait revenir
//  cliquer dans la fenetre.
//
//  Reserve honnete : quand un `WKWebView` joue un media, WebKit ouvre sa propre
//  session. Celle de l app peut donc entrer en concurrence avec la sienne dans
//  le Centre de controle. Le journal dit ce qu on publie ; ce que le systeme
//  affiche se verifie a l oeil.

import AppKit
import MediaPlayer

@MainActor
final class CentreDeLecture {
  private let journal: (String) -> Void
  private var pochetteEnCache: (uri: String, image: NSImage)?

  init(journal: @escaping (String) -> Void = { _ in }) {
    self.journal = journal
  }

  /// Branche les touches. Les fermetures reviennent a la coordination, qui
  /// seule sait quel moteur joue.
  func brancher(
    lecture: @escaping () -> Void,
    pause: @escaping () -> Void,
    bascule: @escaping () -> Void,
    suivant: @escaping () -> Void,
    precedent: @escaping () -> Void,
    aller: @escaping (Int) -> Void
  ) {
    let centre = MPRemoteCommandCenter.shared()

    centre.playCommand.addTarget { _ in
      MainActor.assumeIsolated { lecture() }
      return .success
    }
    centre.pauseCommand.addTarget { _ in
      MainActor.assumeIsolated { pause() }
      return .success
    }
    centre.togglePlayPauseCommand.addTarget { _ in
      MainActor.assumeIsolated { bascule() }
      return .success
    }
    centre.nextTrackCommand.addTarget { _ in
      MainActor.assumeIsolated { suivant() }
      return .success
    }
    centre.previousTrackCommand.addTarget { _ in
      MainActor.assumeIsolated { precedent() }
      return .success
    }
    centre.changePlaybackPositionCommand.addTarget { evenement in
      guard let e = evenement as? MPChangePlaybackPositionCommandEvent else {
        return .commandFailed
      }
      MainActor.assumeIsolated { aller(Int(e.positionTime * 1000)) }
      return .success
    }

    journal("touches media : branchees")
  }

  /// Publie ce qui joue. A rappeler au changement de titre et quand la lecture
  /// demarre ou s arrete ; la position se met a jour toute seule a partir du
  /// couple position + vitesse.
  func publier(_ titre: Titre?, positionMs: Int, enLecture: Bool, vitesse: Double) {
    let info = MPNowPlayingInfoCenter.default()
    guard let titre else {
      info.nowPlayingInfo = nil
      info.playbackState = .stopped
      return
    }

    var champs: [String: Any] = [
      MPMediaItemPropertyTitle: titre.title,
      MPMediaItemPropertyArtist: titre.artiste,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: Double(positionMs) / 1000,
      // La vitesse doit etre 0 a l arret, sinon le systeme continue de faire
      // avancer la position tout seul.
      MPNowPlayingInfoPropertyPlaybackRate: enLecture ? vitesse : 0,
    ]
    if titre.durationMs > 0 {
      champs[MPMediaItemPropertyPlaybackDuration] = Double(titre.durationMs) / 1000
    }
    if let image = pochetteEnCache?.uri == titre.uri ? pochetteEnCache?.image : nil {
      champs[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in
        image
      }
    }

    info.nowPlayingInfo = champs
    info.playbackState = enLecture ? .playing : .paused
  }

  /// Charge la pochette en fond, puis republie.
  ///
  /// `hqdefault` suffit largement pour une vignette de Centre de controle, et
  /// `maxresdefault` n existe pas pour tous les clips.
  func chargerPochette(_ titre: Titre, puis republier: @escaping () -> Void) {
    guard pochetteEnCache?.uri != titre.uri,
          let url = adressePochette(titre, .grande) else { return }
    Task { @MainActor in
      guard let (donnees, _) = try? await URLSession.shared.data(from: url),
            let image = NSImage(data: donnees) else { return }
      pochetteEnCache = (titre.uri, image)
      republier()
    }
  }
}

//  Lecture directe, pour les titres qui n ont pas besoin d un lecteur video.
//
//  Audius et Jamendo publient leur audio ; ces titres portent la capacite
//  `audioOnly` et se lisent avec AVFoundation, sans WebView et sans rien
//  afficher. Rien n est ecrit sur le disque : `AVPlayer` lit le flux.
//
//  La meme frontiere que partout ailleurs dans le projet — Worker, navigateur,
//  terminal : les capacites du titre decident du moteur, pas sa source.

import AVFoundation
import Combine
import Foundation

@MainActor
final class LecteurAudio: NSObject, ObservableObject {
  @Published var enLecture = false
  @Published var positionMs = 0

  var surFin: (() -> Void)?
  /// Appelee quand la lecture demarre vraiment, comme cote video.
  var surLecture: (() -> Void)?
  /// Second crochet, reserve a l app : volume et vitesse a reposer. Separe de
  /// `surLecture`, que les verifications se reservent.
  var surLectureSysteme: (() -> Void)?
  /// Un flux qui ne se charge pas doit etre dit, pas subi.
  var surEchec: ((String) -> Void)?

  private var joueur: AVPlayer?
  private var observateur: Any?
  private var abonnements: Set<AnyCancellable> = []
  private let journal: (String) -> Void
  private var aDemarre = false
  /// Retenu ici pour etre applique au flux suivant : un `AVPlayer` neuf part
  /// a plein volume.
  var niveauVolume: Double = 1.0

  init(journal: @escaping (String) -> Void = { _ in }) {
    self.journal = journal
    super.init()
  }

  func jouer(_ url: URL) {
    arreter()
    aDemarre = false

    let element = AVPlayerItem(url: url)
    let joueur = AVPlayer(playerItem: element)
    joueur.automaticallyWaitsToMinimizeStalling = true
    joueur.volume = Float(niveauVolume)
    self.joueur = joueur

    // La position sert a caler les paroles ; cinq fois par seconde suffit, et
    // c est AVFoundation qui tient l horloge, pas nous.
    observateur = joueur.addPeriodicTimeObserver(
      forInterval: CMTime(seconds: 0.2, preferredTimescale: 600), queue: .main
    ) { [weak self] temps in
      Task { @MainActor in
        guard let self else { return }
        self.positionMs = Int(temps.seconds * 1000)
        let joue = joueur.timeControlStatus == .playing
        if joue != self.enLecture { self.enLecture = joue }
        if joue, !self.aDemarre {
          self.aDemarre = true
          self.journal("audio : lecture")
          self.surLectureSysteme?()
          self.surLecture?()
        }
      }
    }

    NotificationCenter.default
      .publisher(for: .AVPlayerItemDidPlayToEndTime, object: element)
      .sink { [weak self] _ in
        Task { @MainActor in
          self?.journal("audio : termine")
          self?.surFin?()
        }
      }
      .store(in: &abonnements)

    NotificationCenter.default
      .publisher(for: .AVPlayerItemFailedToPlayToEndTime, object: element)
      .sink { [weak self] note in
        Task { @MainActor in
          let erreur = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
          let texte = erreur?.localizedDescription ?? "flux illisible"
          self?.journal("audio : echec — \(texte)")
          self?.surEchec?(texte)
        }
      }
      .store(in: &abonnements)

    joueur.play()
  }

  /// Rend l etat obtenu : vrai si on vient de relancer.
  @discardableResult
  func basculer() -> Bool {
    guard let joueur else { return false }
    if joueur.timeControlStatus == .playing {
      joueur.pause()
      enLecture = false
      return false
    }
    joueur.play()
    enLecture = true
    return true
  }

  /// Volume de 0 a 1, comme le reste de l app.
  func volume(_ niveau: Double) { joueur?.volume = Float(niveau) }

  /// Vitesse. Poser `rate` relance la lecture, donc on ne touche qu en lecture.
  func vitesse(_ facteur: Double) {
    guard let joueur, joueur.timeControlStatus == .playing else { return }
    joueur.rate = Float(facteur)
  }

  func aller(_ ms: Int) {
    joueur?.seek(to: CMTime(seconds: Double(ms) / 1000, preferredTimescale: 600))
  }

  func arreter() {
    if let observateur { joueur?.removeTimeObserver(observateur) }
    observateur = nil
    abonnements.removeAll()
    joueur?.pause()
    joueur = nil
    enLecture = false
    positionMs = 0
  }
}

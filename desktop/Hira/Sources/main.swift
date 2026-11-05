//  hira — app macOS.
//
//  Ce fichier assemble, il ne decide rien : le serveur interne sert la page du
//  lecteur, le pont parle au lecteur officiel, SwiftUI dessine tout le reste.
//
//  L app raconte ce qu elle fait sur la sortie standard. Ce n est pas du
//  deboguage laisse la par negligence : la fenetre n est pas observable depuis
//  un terminal, et c est ce journal qui permet de verifier une lecture sans
//  demander a quelqu un de regarder l ecran.

import AppKit
import Combine
import SwiftUI

func journaliser(_ texte: String) {
  FileHandle.standardError.write("  \(texte)\n".data(using: .utf8)!)
}

/// La page du lecteur : dans les ressources du bundle, ou a cote de l
/// executable quand on lance depuis le dossier de travail.
func pageDuLecteur() -> String {
  let candidats = [
    Bundle.main.url(forResource: "lecteur", withExtension: "html"),
    URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appendingPathComponent("Ressources/lecteur.html"),
  ].compactMap { $0 }
  for url in candidats {
    if let contenu = try? String(contentsOf: url, encoding: .utf8) { return contenu }
  }
  journaliser("page du lecteur introuvable")
  exit(1)
}

@MainActor
final class Coordination {
  let etat = Etat()
  let mesListes = MesListes(journal: journaliser)
  let audio = LecteurAudio(journal: journaliser)
  let memoire = MemoireDesRefus(journal: journaliser)
  let prefs = Preferences(journal: journaliser)
  let veille = Veille(journal: journaliser)
  let centreDeLecture = CentreDeLecture(journal: journaliser)
  /// Ce qui jouait quand la machine s est endormie.
  private var avantSommeil: (titre: Titre, ms: Int)?
  let lecteur: Lecteur
  /// En mode verification, l app joue d elle-meme le premier titre : sans ca
  /// le journal prouverait seulement qu elle sait ouvrir un rayon.
  var autoLecture = false
  /// Verification : saute pres de la fin du premier titre pour declencher ENDED.
  var sauterVersLaFin = false
  /// Verification : rayon a ouvrir une fois la lecture lancee.
  var rayonSuivant: String?
  /// Verification : rang a « cliquer » dans la file une fois la lecture lancee.
  var rangDeLaFile: Int?
  var verifierMasquage = false
  private var masquageFait = false
  /// Verification : ce qu on fait une fois la recherche *reellement* revenue.
  /// Une attente sur horloge regardait les resultats avant qu ils arrivent.
  var apresRecherche: (() -> Void)?
  /// Nombre de sauts deja faits. Borne, pour que la verification d une
  /// repetition de liste puisse traverser plusieurs titres sans boucler.
  private var sautsFaits = 0
  private let serveur: ServeurLocal
  private var historique: [Titre] = []

  init() {
    do {
      serveur = try ServeurLocal(page: pageDuLecteur())
    } catch {
      journaliser("serveur local impossible : \(error)")
      exit(1)
    }
    Api.adopter(prefs.valeurs.api)
    journaliser("worker : \(Api.base.absoluteString)")
    etat.refuses = memoire.uris
    etat.tailleVideo = TailleVideo(rawValue: prefs.valeurs.tailleVideo) ?? .grande
    let port = serveur.demarrer()
    guard port != 0 else {
      journaliser("serveur local : aucun port attribue")
      exit(1)
    }
    journaliser("serveur local : http://127.0.0.1:\(port) (boucle locale seulement)")
    lecteur = Lecteur(port: port, journal: journaliser)
    // Un titre qui va au bout enchaine. C est l interet d une file.
    lecteur.surFin = { [weak self] in self?.surFinDeTitre() }
    audio.surFin = { [weak self] in self?.surFinDeTitre() }
    // Le lecteur officiel oublie volume et vitesse a chaque chargement.
    lecteur.surLectureSysteme = { [weak self] in
      self?.appliquerSon()
      self?.publierLecture()
      // Preuve que la lecture marche : les refus en attente deviennent
      // definitifs, et le compteur de panne repart de zero.
      self?.memoire.succes()
    }
    audio.surLectureSysteme = { [weak self] in
      self?.appliquerSon()
      self?.publierLecture()
      self?.memoire.succes()
    }
    // Un flux illisible se comporte comme un clip refuse : on le retient et on
    // enchaine, plutot que de laisser la lecture mourir dessus.
    audio.surEchec = { [weak self] texte in
      guard let self, let courant = self.etat.courant else { return }
      journaliser("audio injouable, on enchaine : \(courant.title) (\(texte))")
      self.retenirRefus(courant.uri, "flux illisible")
      self.suivant()
    }
  }

  /// Publie ce qui joue vers le Centre de controle et les touches media.
  func publierLecture() {
    let joue = etat.courant.map { _ in enVideo ? lecteur.enLecture : audio.enLecture } ?? false
    centreDeLecture.publier(etat.courant, positionMs: positionActuelle(),
                            enLecture: joue, vitesse: prefs.valeurs.vitesse)
  }

  func positionActuelle() -> Int { enVideo ? lecteur.positionMs : audio.positionMs }

  /// Branche les touches media et la veille. Appele une fois au demarrage.
  func brancherSysteme() {
    centreDeLecture.brancher(
      lecture: { [weak self] in self?.reprendre() },
      pause: { [weak self] in self?.mettreEnPause() },
      bascule: { [weak self] in self?.basculer() },
      suivant: { [weak self] in self?.suivant() },
      precedent: { [weak self] in self?.precedent() },
      aller: { [weak self] ms in self?.aller(ms) })

    veille.surveiller(
      avant: { [weak self] in
        guard let self, let courant = self.etat.courant else { return }
        self.avantSommeil = (courant, self.positionActuelle())
        journaliser("veille : \(courant.title) a \(self.positionActuelle() / 1000) s")
      },
      apres: { [weak self] dormi in
        guard let self else { return }
        Task { @MainActor in await self.auReveil(dormi) }
      })
  }

  /// Reprise apres un reveil.
  ///
  /// Le Worker d abord : la veille a suspendu les serveurs locaux, et tant
  /// qu ils ne repondent pas, ni les suggestions ni les paroles n aboutiront.
  /// Relancer la lecture ne ferait que preparer la prochaine impasse.
  func auReveil(_ dormi: TimeInterval) async {
    let repere = avantSommeil
    avantSommeil = nil
    etat.message = "Reveil apres \(Int(dormi / 60)) min — reconnexion…"

    guard await Api.attendreLeWorker() else {
      etat.message = "Worker injoignable apres le reveil. Lance-le : cd api && npm run dev"
      journaliser("reveil : worker injoignable")
      return
    }
    journaliser("reveil : worker en ligne")
    etat.message = "Reveil — reprise."

    // On ne relance que ce qui jouait : reprendre un titre mis en pause avant
    // de fermer le capot serait une surprise.
    if let repere, repere.titre.uri == etat.courant?.uri {
      lancer(repere.titre, reprise: true)
      if repere.ms > 3000 { aller(repere.ms) }
    }
    if etat.courant != nil, etat.file.count < 4, etat.repetition != .liste {
      if let courant = etat.courant { await regarnir(courant) }
    }
  }

  func reprendre() {
    guard let courant = etat.courant else { return }
    let joue = enVideo ? lecteur.enLecture : audio.enLecture
    if !joue { basculer() }
    _ = courant
  }

  func mettreEnPause() {
    let joue = enVideo ? lecteur.enLecture : audio.enLecture
    if joue { basculer() }
  }

  func precedent() {
    guard let avant = historique.popLast() else { return }
    if let courant = etat.courant { etat.file.insert(courant, at: 0) }
    lancer(avant, reprise: true)
  }

  func demarrer() {
    Task { @MainActor in
      guard await Api.enLigne() else {
        etat.message = "Worker injoignable. Lance-le : cd api && npm run dev"
        journaliser("worker : injoignable")
        return
      }
      journaliser("worker : en ligne")
      do {
        etat.genres = try await Api.genres()
        etat.playlists = (try? await Api.playlists()) ?? []
        journaliser("genres : \(etat.genres.count), playlists : \(etat.playlists.count)")
        // `--radios` verifie une lecture en direct sans clavier.
        if CommandLine.arguments.contains("--radios") {
          let voulu = CommandLine.arguments.firstIndex(of: "--pays")
            .flatMap { CommandLine.arguments.indices.contains($0 + 1)
                       ? CommandLine.arguments[$0 + 1] : nil }
          ouvrirRadios(pays: voulu)
          if autoLecture {
            Task { @MainActor in
              try? await Task.sleep(nanoseconds: 3_000_000_000)
              guard let premiere = etat.titres.first else {
                journaliser("verification : aucune station")
                return
              }
              journaliser("verification : station \(premiere.title)")
              jouer(premiere)
            }
          }
          return
        }

        // `--chercher <texte>` verifie la recherche sans clavier.
        if let i = CommandLine.arguments.firstIndex(of: "--chercher"),
           i + 1 < CommandLine.arguments.count {
          let requete = CommandLine.arguments[i + 1]
          // `--audio` joue le premier resultat en audio direct : c est la seule
          // facon de verifier AVFoundation sans clavier.
          if CommandLine.arguments.contains("--audio") {
            apresRecherche = { [weak self] in
              guard let self else { return }
              let directs = self.etat.titres.filter { !$0.videoObligatoire }
              journaliser("verification : \(directs.count) resultats en audio direct")
              guard let premier = directs.first else { return }
              journaliser("verification : on joue \(premier.artiste) / \(premier.title)")
              self.jouer(premier)
            }
          }
          chercher(requete)
          return
        }

        // `--genre <slug>` sert la verification : pop contient le titre dont on
        // sait que LRCLIB a les paroles, gasy contient les clips integrables.
        let voulu = CommandLine.arguments.firstIndex(of: "--genre")
          .flatMap { CommandLine.arguments.indices.contains($0 + 1) ? CommandLine.arguments[$0 + 1] : nil }
          ?? "gasy"
        if let premier = etat.genres.first(where: { $0.slug == voulu }) ?? etat.genres.first {
          ouvrir(premier)
        }
      } catch {
        etat.message = "Le Worker a repondu de travers : \(error)"
      }
    }
  }

  func chercher(_ requete: String) {
    let propre = requete.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !propre.isEmpty else { return }
    Task { @MainActor in
      etat.listeOuverte = nil
      etat.paysRadio = nil
      etat.centre = .liste
      etat.message = "Recherche de « \(propre) »…"
      let trouves = await Api.chercher(propre)
      // Les clips deja vus refuser l integration n ont rien a faire dans une
      // liste : ils occuperaient une place et se barreraient a la lecture.
      // Deux filtres : le clip deja refuse, et la chaine dont plusieurs clips
      // ont refuse. Le second vient de la mesure du banc — le refus est une
      // decision d ayant droit, prise pour tout son repertoire.
      etat.titres = trouves.filter { !memoire.contient($0.uri) && !memoire.chaineEcartee($0) }
      let ecartes = trouves.count - etat.titres.count
      journaliser("recherche « \(propre) » : \(etat.titres.count) resultats"
                  + (ecartes > 0 ? ", \(ecartes) ecartes comme injouables" : ""))
      etat.message = etat.titres.isEmpty
        ? "Aucun resultat pour « \(propre) »."
        : "\(etat.titres.count) resultats pour « \(propre) »"
      let suite = apresRecherche
      apresRecherche = nil
      suite?()
    }
  }

  // MARK: mes listes

  func ouvrirMaListe(_ mienne: ListeLocale) {
    etat.paysRadio = nil
    etat.centre = .liste
    etat.titres = mienne.titres.filter { !etat.refuses.contains($0.uri) }
    etat.listeOuverte = mienne.id
    etat.message = "\(mienne.nom) — \(etat.titres.count) titres"
    journaliser("ma liste « \(mienne.nom) » : \(etat.titres.count) titres")
  }

  func ajouter(_ identifiant: String, _ titre: Titre?) {
    guard let voulu = titre ?? etat.courant else { return }
    mesListes.ajouter(voulu, a: identifiant)
  }

  func creerListe(_ nom: String) {
    guard let liste = mesListes.creer(nom, avec: etat.courant) else { return }
    ouvrirMaListe(liste)
  }

  func supprimerListe(_ identifiant: String) {
    if etat.listeOuverte == identifiant { etat.listeOuverte = nil }
    mesListes.supprimer(identifiant)
  }

  func retirerDeLaListe(_ uri: String) {
    guard let identifiant = etat.listeOuverte else { return }
    mesListes.retirer(uri, de: identifiant)
    // La vue affichee doit suivre, sinon la ligne reste la jusqu au prochain clic.
    if let maj = mesListes.liste(identifiant) { ouvrirMaListe(maj) }
  }

  private var saisieEnCours: Task<Void, Never>?

  /// Propositions pendant la frappe.
  ///
  /// Un delai court annule la demande precedente : trois lettres tapees vite ne
  /// doivent faire qu un aller-retour. Rien ne coute de quota ici — c est D1
  /// qui repond — mais une rafale de requetes se croiserait et ferait clignoter
  /// la liste.
  func surSaisie(_ saisi: String) {
    saisieEnCours?.cancel()
    let propre = saisi.trimmingCharacters(in: .whitespacesAndNewlines)
    guard propre.count >= 2 else {
      etat.propositions = []
      return
    }
    saisieEnCours = Task { @MainActor in
      try? await Task.sleep(nanoseconds: 220_000_000)
      guard !Task.isCancelled else { return }
      let trouvees = await Api.propositions(propre)
      guard !Task.isCancelled,
            etat.requete.trimmingCharacters(in: .whitespacesAndNewlines) == propre
      else { return }
      etat.propositions = trouvees
    }
  }

  /// Ouvre les radios. **Madagascar par defaut, a chaque fois.**
  ///
  /// Le choix d un autre pays ne vaut que pour la session : c est le public du
  /// projet, et le rayon s annonce « Madagascar, en direct ». Garder le dernier
  /// pays visite ferait mentir son libelle au lancement suivant.
  func ouvrirRadios(pays: String? = nil) {
    let code = pays ?? "MG"
    etat.centre = .liste
    etat.listeOuverte = nil
    etat.paysRadio = code
    Task { @MainActor in
      // La liste des pays n est chargee qu une fois, et seulement si on entre
      // dans les radios : elle ne sert a rien pour qui n y va jamais.
      if etat.paysDisponibles.isEmpty {
        etat.paysDisponibles = await Api.paysRadio()
        journaliser("pays avec radios : \(etat.paysDisponibles.count)")
      }
      let nom = etat.paysDisponibles.first { $0.code == code }?.nom ?? code
      etat.message = "Radios — \(nom)…"
      etat.titres = await Api.radios(pays: code)
      journaliser("radios \(code) : \(etat.titres.count) stations")
      etat.message = "\(nom) — \(etat.titres.count) stations en direct"
    }
  }

  func ouvrirPlaylist(_ liste: Playlist) {
    etat.listeOuverte = nil
    etat.paysRadio = nil
    etat.centre = .liste
    journaliser("centre : liste")
    Task { @MainActor in
      etat.message = "Ouverture de \(liste.title)…"
      etat.titres = (try? await Api.playlist(liste.slug)) ?? []
      journaliser("playlist \(liste.slug) : \(etat.titres.count) titres")
      etat.message = "\(liste.title) — \(etat.titres.count) titres"
    }
  }

  func ouvrir(_ genre: Genre) {
    etat.listeOuverte = nil
    etat.paysRadio = nil
    etat.centre = .liste
    journaliser("centre : liste")
    Task { @MainActor in
      etat.message = "Ouverture de \(genre.label)…"
      etat.titres = (try? await Api.genre(genre.slug)) ?? []
      journaliser("\(genre.slug) : \(etat.titres.count) titres")
      etat.message = "\(genre.label) — \(etat.titres.count) titres"
      // Au hasard plutot que le premier : entendre « Moto » a chaque ouverture
      // lasse vite, et la liste est deja triee par vues — le premier titre
      // serait toujours le meme.
      if autoLecture || prefs.valeurs.demarrerEnLecture,
         etat.courant == nil,
         let premier = autoLecture ? etat.titres.first : etat.titres.randomElement() {
        jouer(premier)
        // `--creer-liste <nom>` verifie la persistance sans clavier.
        if let i = CommandLine.arguments.firstIndex(of: "--creer-liste"),
           i + 1 < CommandLine.arguments.count {
          creerListe(CommandLine.arguments[i + 1])
        }
      }
    }
  }

  func jouer(_ titre: Titre) {
    // Choisir un titre dans une liste met la suite de cette liste dans la file :
    // meme regle que cote web, une liste s ecoute d un bout a l autre. En
    // aleatoire, c est tout le reste de la liste qui est battu — pas seulement
    // ce qui suit, sinon choisir l avant-dernier titre ne melangerait rien.
    if let index = etat.titres.firstIndex(of: titre) {
      let reste = etat.aleatoire
        ? etat.titres.enumerated().filter { $0.offset != index }.map(\.element)
        : Array(etat.titres[(index + 1)...])
      etat.file = (etat.aleatoire ? reste.shuffled() : reste)
        .filter { !etat.refuses.contains($0.uri) }
    }
    lancer(titre)
  }

  /// Bat la file en cours, sans toucher au titre qui joue.
  func battreLaFile() {
    etat.file.shuffle()
    journaliser("file battue : \(etat.file.count) titres")
  }

  /// Reprend la liste courante depuis le debut, pour la repetition de liste.
  private func reprendreLaListe() -> Bool {
    let reste = etat.titres.filter {
      !etat.refuses.contains($0.uri) && $0 != etat.courant
    }
    guard !reste.isEmpty else { return false }
    etat.file = etat.aleatoire ? reste.shuffled() : reste
    journaliser("repetition de la liste : \(etat.file.count) titres remis en file")
    return true
  }

  private func lancer(_ titre: Titre, reprise: Bool = false) {
    if !reprise, let courant = etat.courant, courant != titre { historique.append(courant) }
    etat.courant = titre
    etat.paroles = []
    journaliser("joue : \(titre.artiste) — \(titre.title)")
    centreDeLecture.chargerPochette(titre) { [weak self] in self?.publierLecture() }
    publierLecture()

    // Les capacites du titre decident du moteur, pas sa source. Meme frontiere
    // que cote Worker, cote navigateur et cote terminal.
    if let video = titre.video, titre.videoObligatoire {
      audio.arreter()
      lecteur.jouer(video)
    } else if let flux = titre.streamUrl, let url = URL(string: flux) {
      lecteur.stopper()
      audio.jouer(url)
    } else {
      journaliser("ni video ni flux, on saute : \(titre.title)")
      retenirRefus(titre.uri, "ni video ni flux")
      DispatchQueue.main.async { [weak self] in self?.suivant() }
      return
    }

    // `--masquer` verifie le point qui compte : le son continue-t-il quand la
    // video sort de l ecran ? On releve la position deux fois.
    if verifierMasquage, !masquageFait, enVideo {
      masquageFait = true
      let crochet: () -> Void = { [weak self] in
        guard let self else { return }
        self.etat.tailleVideo = .masquee
        journaliser("verification : video masquee a \(self.lecteur.positionMs / 1000) s")
        Task { @MainActor in
          try? await Task.sleep(nanoseconds: 6_000_000_000)
          journaliser("verification : masquee, position \(self.lecteur.positionMs / 1000) s"
                      + " — lecture \(self.lecteur.enLecture ? "en cours" : "arretee")")
        }
      }
      lecteur.surLecture = crochet
    }

    if let rang = rangDeLaFile {
      rangDeLaFile = nil
      Task { @MainActor in
        try? await Task.sleep(nanoseconds: 8_000_000_000)
        guard etat.file.indices.contains(rang) else {
          journaliser("verification : la file n a pas de rang \(rang)")
          return
        }
        let vise = etat.file[rang]
        journaliser("verification : clic sur « \(vise.title) », rang \(rang) de la file")
        jouerDepuisLaFile(vise)
      }
    }

    if let slug = rayonSuivant {
      rayonSuivant = nil
      Task { @MainActor in
        try? await Task.sleep(nanoseconds: 9_000_000_000)
        if let genre = etat.genres.first(where: { $0.slug == slug }) {
          journaliser("verification : on ouvre « \(genre.label) » pendant la lecture")
          ouvrir(genre)
        }
      }
    }

    if etat.aleatoire {
      journaliser("file (aleatoire) : " + etat.file.prefix(4).map(\.title).joined(separator: " · "))
    }

    // On ne regarnit pas en repetition de liste : sinon la file ne se vide
    // jamais, `.liste` ne se declenche pas, et l option ne veut rien dire. Qui
    // demande « repeter la liste » veut la liste, pas des suggestions.
    // Une radio n a pas de voisins : `/v1/similar` n a rien a dire d un direct,
    // et la file garde les stations qu on lui a donnees.
    if !titre.estRadio, etat.file.count < 4, etat.repetition != .liste {
      Task { @MainActor in await regarnir(titre) }
    }

    // Le saut attend que la lecture ait reellement commence. Une attente sur
    // horloge partait avant que le lecteur soit pret, et `aller()` sur une page
    // encore vide ne fait rien — le meme piege que `jouer()` avait deja tendu.
    if sauterVersLaFin, sautsFaits < 3, titre.durationMs > 12_000 {
      let cible = titre.durationMs - 8_000
      let attendu = sautsFaits
      let sauter: () -> Void = { [weak self] in
        guard let self, self.sautsFaits == attendu else { return }
        self.sautsFaits += 1
        journaliser("verification : saut a \(cible / 1000) s pour provoquer la fin")
        self.aller(cible)
      }
      // Le crochet se pose sur le moteur qui va jouer, pas sur un seul des deux.
      if enVideo { lecteur.surLecture = sauter } else { audio.surLecture = sauter }
    }

    // Pas de paroles pour un direct : on ne sait meme pas ce qui passe.
    guard !titre.estRadio else { return }

    Task { @MainActor in
      let lignes = await Api.paroles(titre)
      // Le titre a pu changer pendant l aller-retour.
      guard etat.courant == titre else { return }
      etat.paroles = lignes
      // Les paroles prennent le centre quand elles arrivent, pas avant : sinon
      // on afficherait un panneau vide le temps de l aller-retour.
      // Les paroles ne volent pas la place a la page de pochette : si on la
      // regarde, c est un choix delibere.
      if !lignes.isEmpty, etat.parolesVisibles, etat.centre != .pochette {
        etat.centre = .paroles
        journaliser("centre : paroles")
      }
      journaliser("paroles : \(lignes.count) lignes")
    }
  }

  /// Fin d un titre. La repetition passe avant la file.
  func surFinDeTitre() {
    switch etat.repetition {
    case .titre:
      guard etat.courant != nil else { return }
      journaliser("repetition du titre")
      // Un simple retour a zero : recharger relancerait les paroles et
      // compterait une seconde ecoute.
      aller(0)
    case .liste:
      if etat.file.isEmpty { _ = reprendreLaListe() }
      suivant()
    case .aucune:
      suivant()
    }
  }

  /// Retient un refus, et le retire de tout ce qui est affiche.
  ///
  /// Sans ce nettoyage immediat, le titre reste dans la liste et dans la file
  /// jusqu au prochain chargement — et on peut le recliquer.
  func retenirRefus(_ uri: String, _ pourquoi: String) {
    let chaine = (etat.courant?.uri == uri ? etat.courant : etat.titres.first { $0.uri == uri })?
      .artists.first?.id
    memoire.retenir(uri, chaine: chaine, pourquoi: pourquoi)
    etat.refuses = memoire.uris
    etat.titres.removeAll { $0.uri == uri }
    etat.file.removeAll { $0.uri == uri }
  }

  /// Porte le volume et la vitesse aux deux moteurs.
  ///
  /// Un `AVPlayer` neuf part a plein volume et le lecteur officiel oublie la
  /// consigne a chaque chargement : il faut donc la reposer a chaque titre, et
  /// pas seulement quand l utilisateur bouge le curseur.
  func appliquerSon() {
    let v = prefs.valeurs.volume
    let r = prefs.valeurs.vitesse
    audio.niveauVolume = v
    audio.volume(v)
    audio.vitesse(r)
    lecteur.volume(v)
    lecteur.vitesse(r)
  }

  /// Le moteur en service pour le titre courant.
  private var enVideo: Bool { etat.courant?.videoObligatoire ?? true }

  func basculer() {
    if enVideo { lecteur.basculer() } else { audio.basculer() }
  }

  func aller(_ ms: Int) {
    if enVideo { lecteur.aller(ms) } else { audio.aller(ms) }
  }

  /// Choisir un titre dans « À suivre » saute directement a lui.
  ///
  /// Ce qui le precedait quitte la file : c est ce qu on attend d une file
  /// d attente — on ne reecoute pas ce qu on vient de depasser.
  func jouerDepuisLaFile(_ titre: Titre) {
    guard let index = etat.file.firstIndex(of: titre) else { return }
    let passes = etat.file.prefix(index)
    etat.file.removeFirst(index + 1)
    if !passes.isEmpty { journaliser("saut dans la file : \(passes.count) titres passes") }
    lancer(titre)
  }

  func retirerDeLaFile(_ uri: String) {
    etat.file.removeAll { $0.uri == uri }
    journaliser("retire de la file (\(etat.file.count) restants)")
  }

  func suivant() {
    while let prochain = etat.file.first {
      etat.file.removeFirst()
      if !etat.refuses.contains(prochain.uri) { lancer(prochain); return }
    }
    // File vide : on la regarnit depuis le titre courant plutot que de
    // s arreter. C est ce qui rend la lecture reellement sans fin au lieu de
    // mourir a la fin d un rayon.
    Task { @MainActor in
      if let courant = etat.courant, await regarnir(courant) > 0 {
        suivant()
      } else {
        etat.message = "Plus rien à enchaîner."
        journaliser("file vide, aucune suggestion")
      }
    }
  }

  /// Complete la file depuis les suggestions du Worker.
  ///
  /// Appelee des que la file descend bas, pas seulement quand elle est vide :
  /// « À suivre » doit toujours montrer quelque chose, et l enchainement ne
  /// doit jamais attendre un aller-retour reseau.
  @discardableResult
  func regarnir(_ graine: Titre) async -> Int {
    // Plus de filtre ici : depuis qu AVFoundation est branche, une suggestion
    // en audio direct se lit aussi bien qu un clip. C est tout l interet.
    let suggestions = await Api.similaires(graine)
    let direct = suggestions.filter { !$0.videoObligatoire }.count
    journaliser("le Worker a rendu \(suggestions.count) suggestions"
                + (direct > 0 ? ", dont \(direct) en audio direct" : ""))
    var connus = Set(etat.file.map(\.uri))
    connus.insert(graine.uri)
    if let courant = etat.courant { connus.insert(courant.uri) }
    connus.formUnion(etat.refuses)

    var neufs: [Titre] = []
    for titre in suggestions where !connus.contains(titre.uri) {
      connus.insert(titre.uri)
      neufs.append(titre)
    }
    etat.file.append(contentsOf: neufs)
    journaliser("regarni : \(neufs.count) titres (file \(etat.file.count))")
    return neufs.count
  }

  /// Un refus de l ayant droit fait enchainer ; un refus d origine est notre
  /// faute et doit se voir, pas se contourner en silence.
  func traiter(_ refus: Refus) {
    guard let courant = etat.courant else { return }
    if refus.estLeClip {
      retenirRefus(courant.uri, "erreur \(refus.rawValue)")
      suivant()
    } else {
      etat.message = "Origine refusee par YouTube (153) — le serveur interne n a pas servi la page."
      journaliser("ERREUR 153 : origine refusee, voir desktop/sonde/README.md")
    }
  }
}

/// Tout l assemblage vit sur l acteur principal.
///
/// Le code de premier niveau d un `main.swift` ne l est pas, en Swift 6 : il
/// faut le dire. `assumeIsolated` est exact ici et nulle part ailleurs — au
/// demarrage, nous sommes bel et bien sur le fil principal.
@MainActor
func lancerApplication() -> Never {
  let application = NSApplication.shared
  application.setActivationPolicy(.regular)

  let coordination = Coordination()
  let racine = Fenetre(
    etat: coordination.etat,
    lecteur: coordination.lecteur,
    surGenre: { coordination.ouvrir($0) },
    surTitre: { coordination.jouer($0) },
    surSuivant: { coordination.suivant() },
    surBattre: { coordination.battreLaFile() },
    surChercher: { coordination.chercher($0) },
    surSaisie: { coordination.surSaisie($0) },
    surPlaylist: { coordination.ouvrirPlaylist($0) },
    surRadios: { coordination.ouvrirRadios() },
    surPays: { coordination.ouvrirRadios(pays: $0) },
    mesListes: coordination.mesListes,
    surOuvrirListe: { coordination.ouvrirMaListe($0) },
    surAjouter: { coordination.ajouter($0, $1) },
    surCreerListe: { coordination.creerListe($0) },
    surSupprimerListe: { coordination.supprimerListe($0) },
    surRetirer: { coordination.retirerDeLaListe($0) },
    surTitreDeLaFile: { coordination.jouerDepuisLaFile($0) },
    surRetirerDeLaFile: { coordination.retirerDeLaFile($0) },
    audio: coordination.audio,
    surBasculer: { coordination.basculer() },
    surAller: { coordination.aller($0) },
    surTailleVideo: {
      journaliser("video : \($0)")
      coordination.prefs.valeurs.tailleVideo = $0
    },
    prefs: coordination.prefs,
    surSon: { coordination.appliquerSon() },
    surFavori: { titre in
      // Pas de liste « favoris » a part : s il n y en a aucune, on en cree une
      // nommee ainsi ; sinon on ajoute a la premiere. Deux notions de favori
      // pour la meme chose serait une de trop.
      if let premiere = coordination.mesListes.listes.first {
        coordination.ajouter(premiere.id, titre)
      } else if let creee = coordination.mesListes.creer("Coups de coeur", avec: titre) {
        journaliser("liste « \(creee.nom) » creee par le coeur")
      }
    }
  )

  // La barre de menus. Les reglages y vivent, avec Commande-virgule.
  let menus = Menus(
    ouvrirReglages: { coordination.etat.reglagesOuverts = true },
    basculerLecture: { coordination.basculer() },
    titreSuivant: { coordination.suivant() },
    reglerVolume: { pas in
      let nouveau = min(1, max(0, coordination.prefs.valeurs.volume + pas))
      coordination.prefs.valeurs.volume = nouveau
      coordination.appliquerSon()
      journaliser("volume : \(Int(nouveau * 100)) %")
    })
  menus.poser(nom: "RadiokoLeka")

  let fenetre = NSWindow(
    contentRect: .init(x: 0, y: 0, width: 1040, height: 680),
    styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
    backing: .buffered, defer: false)
  fenetre.title = "RadiokoLeka"
  fenetre.titlebarAppearsTransparent = true
  fenetre.titleVisibility = .hidden
  // Sans fond opaque, le materiau du systeme traverse : c est la condition du verre.
  fenetre.isOpaque = false
  fenetre.backgroundColor = .clear
  // Le materiau est la **vue de contenu de la fenetre**, pas une couche dans
  // SwiftUI.
  //
  // `blendingMode = .behindWindow` melange avec ce qu il y a derriere la
  // fenetre. Pose a l interieur de la hierarchie SwiftUI, il se retrouve sous
  // le `NSHostingView`, qui peint son propre fond : le resultat etait un gris
  // uniforme, sans aucune translucidite. En faisant du materiau la vue de
  // contenu et en lui ajoutant l hebergeur par-dessus, le melange se fait bien
  // au niveau de la fenetre.
  let fond = NSVisualEffectView()
  fond.material = .underWindowBackground
  fond.blendingMode = .behindWindow
  fond.state = .active

  let contenu = NSHostingView(rootView: racine)
  contenu.translatesAutoresizingMaskIntoConstraints = false
  fond.addSubview(contenu)
  NSLayoutConstraint.activate([
    contenu.leadingAnchor.constraint(equalTo: fond.leadingAnchor),
    contenu.trailingAnchor.constraint(equalTo: fond.trailingAnchor),
    contenu.topAnchor.constraint(equalTo: fond.topAnchor),
    contenu.bottomAnchor.constraint(equalTo: fond.bottomAnchor),
  ])
  fenetre.contentView = fond
  fenetre.center()
  fenetre.makeKeyAndOrderFront(nil)

  // La fenetre n est pas observable depuis un terminal, et macOS refuse la
  // capture sans autorisation : on dit donc au moins si le materiau est en
  // place et si le systeme l autorise.
  let effet = fenetre.contentView as? NSVisualEffectView
  journaliser("verre : materiau \(effet.map { "\($0.material.rawValue)" } ?? "absent")"
              + ", fenetre opaque=\(fenetre.isOpaque)"
              + ", transparence reduite=\(NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)")

  // Le cadre de la fenetre doit suivre le theme choisi : sans ca, une barre de
  // titre claire surmonte un contenu sombre.
  let appliquerTheme: (Theme) -> Void = { theme in
    fenetre.appearance = theme.apparence
    NSApplication.shared.appearance = theme.apparence
  }
  appliquerTheme(coordination.prefs.valeurs.theme)
  let suiviTheme = coordination.prefs.$valeurs
    .map(\.theme)
    .removeDuplicates()
    .sink { appliquerTheme($0) }
  defer { suiviTheme.cancel() }

  coordination.brancherSysteme()
  coordination.demarrer()

  // Mode de verification : l app se ferme d elle-meme apres N secondes.
  //
  // Il existe parce que personne ne peut regarder cette fenetre depuis un
  // terminal. `--secondes 25` lance une vraie session, la raconte sur la sortie
  // d erreur, et rend la main. C est ainsi qu on verifie une lecture.
  // `--jouer` lance la lecture au demarrage, sans fermer l app : c est le mode
  // « mets-moi de la musique », pas une verification.
  if CommandLine.arguments.contains("--jouer") { coordination.autoLecture = true }

  if let i = CommandLine.arguments.firstIndex(of: "--secondes"),
     i + 1 < CommandLine.arguments.count,
     let secondes = Double(CommandLine.arguments[i + 1]) {
    journaliser("mode verification : fermeture dans \(Int(secondes)) s")
    coordination.autoLecture = true
    // `--fin` saute pres de la fin du premier titre : c est la seule facon de
    // verifier l enchainement sans attendre quatre minutes.
    if CommandLine.arguments.contains("--fin") { coordination.sauterVersLaFin = true }
    // `--puis <slug>` rejoue le geste que le journal a revele : ouvrir un rayon
    // pendant qu un titre a paroles joue, et verifier que la liste revient.
    if let i = CommandLine.arguments.firstIndex(of: "--file"),
       i + 1 < CommandLine.arguments.count,
       let rang = Int(CommandLine.arguments[i + 1]) {
      coordination.rangDeLaFile = rang
    }
    if let i = CommandLine.arguments.firstIndex(of: "--puis"),
       i + 1 < CommandLine.arguments.count {
      coordination.rayonSuivant = CommandLine.arguments[i + 1]
    }
    if CommandLine.arguments.contains("--aleatoire") { coordination.etat.aleatoire = true }
    if CommandLine.arguments.contains("--masquer") { coordination.verifierMasquage = true }
    if let i = CommandLine.arguments.firstIndex(of: "--repeter"),
       i + 1 < CommandLine.arguments.count,
       let mode = Repetition(rawValue: CommandLine.arguments[i + 1]) {
      coordination.etat.repetition = mode
    }
    journaliser("options : aleatoire=\(coordination.etat.aleatoire) repetition=\(coordination.etat.repetition.rawValue)")
    Timer.scheduledTimer(withTimeInterval: secondes, repeats: false) { _ in
      journaliser("fin de verification")
      NSApplication.shared.terminate(nil)
    }
  }

  // Le refus arrive par evenement ; on le surveille plutot que de l interroger.
  let surveillance = coordination.lecteur.$refus.sink { refus in
    guard let refus else { return }
    Task { @MainActor in coordination.traiter(refus) }
  }
  defer { surveillance.cancel() }

  application.run()
  exit(0)
}

MainActor.assumeIsolated { lancerApplication() }

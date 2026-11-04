//  L interface. Entierement SwiftUI : aucun HTML ne dessine quoi que ce soit.
//
//  Disposition choisie : les paroles tiennent le centre pendant la lecture,
//  rayons et file s ouvrent en tiroirs quand on les appelle. C est ce qui
//  justifie une app plutot qu un onglet.
//
//  Le verre vient de NSVisualEffectView. Il impose une contrainte qu il faut
//  tenir des le depart : une fois la fenetre translucide, plus rien ne garantit
//  le contraste du texte. D ou la couche sombre sous les paroles — sans elle,
//  du blanc sur du verre au-dessus d une pochette claire devient illisible.

import AppKit
import SwiftUI
import WebKit

/// Le materiau du systeme, derriere toute la fenetre.
struct Verre: NSViewRepresentable {
  var materiau: NSVisualEffectView.Material = .hudWindow

  func makeNSView(context: Context) -> NSVisualEffectView {
    let vue = NSVisualEffectView()
    vue.material = materiau
    vue.blendingMode = .behindWindow
    vue.state = .active
    return vue
  }
  func updateNSView(_ vue: NSVisualEffectView, context: Context) {
    vue.material = materiau
  }
}

/// La surface de lecture. Visible, comme les conditions d usage l imposent.
struct SurfaceLecteur: NSViewRepresentable {
  let vue: WKWebView
  func makeNSView(context: Context) -> WKWebView { vue }
  func updateNSView(_ vue: WKWebView, context: Context) {}
}

/// Taille d image demandee a YouTube.
///
/// Mesure sur un clip du catalogue : `maxresdefault` pese 106 Ko, `hqdefault`
/// 13,5, `mqdefault` 9,5. Cinquante vignettes de 36 pixels en pleine resolution
/// feraient 5,3 Mo pour rien. Et `maxresdefault` **n existe pas pour tous les
/// clips** — il rend 404 — alors que les deux petites sont toujours la.
enum TaillePochette: String {
  case vignette = "mqdefault"
  case grande = "hqdefault"
}

/// Reecrit l adresse d une miniature YouTube a la taille voulue. Les autres
/// sources gardent la leur : on ne connait pas leurs variantes.
func adressePochette(_ titre: Titre, _ taille: TaillePochette) -> URL? {
  guard let brute = titre.artworkUrl else { return nil }
  guard brute.contains("i.ytimg.com") else { return URL(string: brute) }
  let reecrite = brute.replacingOccurrences(
    of: #"/[a-z0-9]+default\.jpg"#,
    with: "/\(taille.rawValue).jpg",
    options: .regularExpression)
  return URL(string: reecrite)
}

/// Cote du lecteur reduit, et minimum que l API demande.
let COTE_MINIMAL: CGFloat = 200

/// Ce que montre la colonne centrale.
///
/// Explicite, et non deduit : deduire « s il y a des paroles, montre les
/// paroles » menait a une impasse ou plus rien n etait cliquable.
enum VueCentre: String {
  case liste, paroles, pochette
}

/// Ce qu on voit du lecteur.
///
/// « Masquee » sort la vue de l ecran **sans la demonter** : le son continue,
/// et la vidéo revient d un clic. C est un choix assume du projet, contraire a
/// la demande de l API d afficher le lecteur ; voir le README.
enum TailleVideo: String, CaseIterable {
  case grande, reduite, masquee

  var suivante: TailleVideo {
    switch self {
    case .grande: return .reduite
    case .reduite: return .masquee
    case .masquee: return .grande
    }
  }
  var mot: String {
    switch self {
    case .grande: return "Reduire"
    case .reduite: return "Masquer"
    case .masquee: return "Afficher"
    }
  }
  var symbole: String {
    switch self {
    case .grande: return "arrow.down.right.and.arrow.up.left"
    case .reduite: return "eye.slash"
    case .masquee: return "eye"
    }
  }
  var cote: CGFloat {
    switch self {
    case .grande: return 356
    case .reduite: return COTE_MINIMAL
    case .masquee: return COTE_MINIMAL
    }
  }
}

/// Ce que fait la fin d un titre.
enum Repetition: String, CaseIterable {
  case aucune, titre, liste

  var symbole: String {
    switch self {
    case .aucune: return "repeat"
    case .titre: return "repeat.1"
    case .liste: return "repeat.circle.fill"
    }
  }
  var libelle: String {
    switch self {
    case .aucune: return "Pas de repetition"
    case .titre: return "Repeter ce titre"
    case .liste: return "Repeter la liste"
    }
  }
  var suivante: Repetition {
    switch self {
    case .aucune: return .titre
    case .titre: return .liste
    case .liste: return .aucune
    }
  }
}

@MainActor
final class Etat: ObservableObject {
  @Published var genres: [Genre] = []
  @Published var playlists: [Playlist] = []
  @Published var paysDisponibles: [PaysRadio] = []
  /// Non nul quand le rayon Radios est ouvert : c est ce qui fait apparaitre
  /// le selecteur de pays, et seulement la.
  @Published var paysRadio: String?
  @Published var requete = ""
  @Published var propositions: [String] = []
  /// Identifiant de la liste locale affichee, s il y en a une : c est ce qui
  /// autorise « retirer de cette liste » sur une ligne.
  @Published var listeOuverte: String?
  /// Le panneau de reglages. Dans l etat et non dans la vue, parce que la
  /// barre de menus doit pouvoir l ouvrir — c est sa place sur macOS.
  @Published var reglagesOuverts = false
  @Published var titres: [Titre] = []
  @Published var courant: Titre?
  @Published var file: [Titre] = []
  @Published var paroles: [LigneParole] = []
  @Published var message = "Connexion au Worker…"
  @Published var tiroirGauche = true
  @Published var tiroirDroit = false
  /// Clips refuses par leur ayant droit. Comme cote web, on ne les repropose pas.
  @Published var refuses: Set<String> = []

  // MARK: options de lecture

  @Published var aleatoire = false
  @Published var repetition: Repetition = .aucune
  @Published var centre: VueCentre = .liste
  @Published var parolesVisibles = true
  @Published var tailleVideo: TailleVideo = .grande



  /// Index de la ligne atteinte. Recherche binaire, comme cote web : une liste
  /// de paroles peut faire cent lignes et on la parcourt cinq fois par seconde.
  func ligne(a positionMs: Int) -> Int {
    var bas = 0, haut = paroles.count - 1, trouve = -1
    while bas <= haut {
      let milieu = (bas + haut) / 2
      if paroles[milieu].atMs <= positionMs { trouve = milieu; bas = milieu + 1 }
      else { haut = milieu - 1 }
    }
    return trouve
  }
}

struct Fenetre: View {
  @ObservedObject var etat: Etat
  @ObservedObject var lecteur: Lecteur
  var surGenre: (Genre) -> Void
  var surTitre: (Titre) -> Void
  var surSuivant: () -> Void
  var surBattre: () -> Void
  var surChercher: (String) -> Void
  var surSaisie: (String) -> Void
  var surPlaylist: (Playlist) -> Void
  var surRadios: () -> Void
  var surPays: (String) -> Void
  @ObservedObject var mesListes: MesListes
  var surOuvrirListe: (ListeLocale) -> Void
  var surAjouter: (String, Titre?) -> Void
  var surCreerListe: (String) -> Void
  var surSupprimerListe: (String) -> Void
  var surRetirer: (String) -> Void
  var surTitreDeLaFile: (Titre) -> Void
  var surRetirerDeLaFile: (String) -> Void
  @ObservedObject var audio: LecteurAudio
  var surBasculer: () -> Void
  var surAller: (Int) -> Void
  var surTailleVideo: (String) -> Void
  @ObservedObject var prefs: Preferences
  var surSon: () -> Void
  var surFavori: (Titre) -> Void



  /// Le moteur en service pour le titre courant. La vue ne decide de rien :
  /// elle lit celui qui joue, et delegue les gestes a la coordination.
  private var enVideo: Bool { etat.courant?.videoObligatoire ?? true }
  private var enLecture: Bool { enVideo ? lecteur.enLecture : audio.enLecture }
  private var positionMs: Int { enVideo ? lecteur.positionMs : audio.positionMs }

  @State private var nommerUneListe = false
  @State private var nomEnCours = ""

  var body: some View {
    // La barre de commandes tient toute la largeur de la fenetre.
    //
    // Elle vivait dans la colonne centrale, et sa largeur minimale depassait
    // celle de la colonne : l empilement debordait, et le rayon de gauche se
    // retrouvait coupe hors de la fenetre — « ons » au lieu de « Rayons ».
    VStack(spacing: 0) {
      HStack(spacing: 0) {
        // Le rayon porte son propre materiau, comme une barre laterale native :
        // c est ce qui le detache du reste sans tracer de bordure.
        if etat.tiroirGauche {
          rayons.frame(width: 252).background(Verre(materiau: .sidebar).ignoresSafeArea())
        }
        centre
        if etat.tiroirDroit { suite.frame(width: 260) }
      }
      Divider().opacity(0.25)
      commandes
    }
    .frame(minWidth: 900, minHeight: 600)
    .tint(prefs.accent)
    .preferredColorScheme(prefs.valeurs.theme.schema)
    .sheet(isPresented: $etat.reglagesOuverts) { panneauReglages }
    .sheet(isPresented: $nommerUneListe) {
      VStack(alignment: .leading, spacing: 14) {
        Text("Nouvelle liste").font(.headline)
        TextField("Nom de la liste", text: $nomEnCours)
          .textFieldStyle(.roundedBorder)
          .frame(width: 280)
          .onSubmit { validerLeNom() }
        HStack {
          Spacer()
          Button("Annuler") { nommerUneListe = false }
          Button("Creer") { validerLeNom() }
            .keyboardShortcut(.defaultAction)
            .disabled(nomEnCours.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      }
      .padding(20)
    }
  }

  private func validerLeNom() {
    let propre = nomEnCours.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !propre.isEmpty else { return }
    surCreerListe(propre)
    nommerUneListe = false
  }

  // MARK: tiroir gauche

  private var rayons: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text("Rayons").font(.caption).foregroundStyle(.secondary)
        .padding(.horizontal, 14).padding(.top, 10)
      ScrollView {
        VStack(alignment: .leading, spacing: 1) {
          // Les radios en tete : c est le seul rayon qui joue du direct, et on
          // ne le confond avec aucun autre.
          Button(action: surRadios) {
            HStack(spacing: 9) {
              ZStack {
                RoundedRectangle(cornerRadius: 5).fill(prefs.second.opacity(0.22))
                Image(systemName: "dot.radiowaves.left.and.right")
                  .font(.system(size: 15)).foregroundStyle(prefs.second)
              }
              .frame(width: 38, height: 38)
              VStack(alignment: .leading, spacing: 1) {
                Text("Radios").font(.system(size: 13, weight: .medium))
                Text("Madagascar, en direct").font(.system(size: 10))
                  .foregroundStyle(.secondary)
              }
              Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          Divider().padding(.vertical, 6).padding(.horizontal, 14)

          ForEach(mesListes.listes) { mienne in
            Button { surOuvrirListe(mienne) } label: {
              HStack(spacing: 9) {
                mosaique(mienne.titres.compactMap(\.artworkUrl), cote: 38)
                Text(mienne.nom).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Spacer()
                Text("\(mienne.titres.count)").font(.system(size: 10))
                  .foregroundStyle(.tertiary)
              }
              .padding(.horizontal, 14).padding(.vertical, 6)
              .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .contextMenu {
              Button("Supprimer la liste", role: .destructive) {
                surSupprimerListe(mienne.id)
              }
            }
          }
          if !mesListes.listes.isEmpty {
            Divider().padding(.vertical, 6).padding(.horizontal, 14)
          }
          ForEach(etat.playlists) { liste in
            Button { surPlaylist(liste) } label: {
              HStack(spacing: 9) {
                mosaique(liste.pochettes ?? [], cote: 38)
                VStack(alignment: .leading, spacing: 1) {
                  Text(liste.title).font(.system(size: 13, weight: .medium))
                  Text(liste.description.isEmpty ? liste.kind : liste.description)
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .lineLimit(2).multilineTextAlignment(.leading)
                }
                Spacer()
                Text("\(liste.count)").font(.system(size: 10)).foregroundStyle(.tertiary)
              }
              .padding(.horizontal, 14).padding(.vertical, 6)
              .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
          }
          if !etat.playlists.isEmpty {
            Divider().padding(.vertical, 6).padding(.horizontal, 14)
          }
          ForEach(etat.genres) { genre in
            Button { surGenre(genre) } label: {
              HStack(spacing: 9) {
                mosaique(genre.pochettes ?? [], cote: 38)
                VStack(alignment: .leading, spacing: 1) {
                  Text(genre.label).font(.system(size: 13, weight: .medium))
                  Text(genre.tagline).font(.system(size: 10)).foregroundStyle(.secondary)
                    .lineLimit(2).multilineTextAlignment(.leading)
                }
                Spacer()
                Text("\(genre.count)").font(.system(size: 10)).foregroundStyle(.tertiary)
              }
              .padding(.horizontal, 14).padding(.vertical, 6)
              .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
          }
        }
      }
      Spacer()
    }
  }

  // MARK: centre — les paroles tiennent la place

  private var centre: some View {
    VStack(spacing: 0) {
      enTete
      // Le lecteur ne peut pas etre masque — l API exige 200 x 200 visibles au
      // minimum. Il a donc deux places : un bandeau en haut, ou une vignette
      // posee dans un coin qui rend le centre aux paroles. Jamais zero.
      bandeauLecteur
      ZStack {
        switch etat.centre {
        case .paroles where etat.parolesVisibles && !etat.paroles.isEmpty:
          parolesDefilantes
        case .pochette:
          grandePochette
        default:
          liste
        }
      }
    }
    .frame(maxWidth: .infinity)
  }

  /// La surface du haut. En audio direct il n y a pas de video a montrer : la
  /// pochette prend la place, et le lecteur officiel n est pas affiche pour
  /// rien.
  /// Une seule place, deux tailles.
  ///
  /// La vue etait d abord posee a deux endroits selon l option, et SwiftUI
  /// devait alors deplacer la meme WKWebView d un parent a l autre : AppKit ne
  /// le supporte pas, la video se noircissait ou s arretait. On ne change donc
  /// que ses dimensions. Elle ne peut de toute facon pas disparaitre — l API
  /// exige 200 x 200 visibles au minimum.
  private var bandeauLecteur: some View {
    let masquee = etat.tailleVideo == .masquee
    return HStack(spacing: 0) {
      Spacer(minLength: 0)
      // Masquee, la vue reste **montee** : la demonter couperait le son. Elle
      // garde donc sa taille et sort de l ecran, et le conteneur ne prend plus
      // aucune place.
      SurfaceLecteur(vue: lecteur.vue)
        .frame(width: enVideo ? etat.tailleVideo.cote : 1,
               height: enVideo ? COTE_MINIMAL : 1)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .opacity(enVideo && !masquee ? 1 : 0)
        .offset(x: masquee ? -20_000 : 0)
        .frame(width: masquee ? 0 : nil, height: masquee ? 0 : nil)
      // En audio direct il n y a pas de video a montrer : la pochette prend la
      // place, et la WebView reste montee, reduite a un point invisible.
      if !enVideo { pochette(cote: COTE_MINIMAL) }
      Spacer(minLength: 0)
    }
    .frame(height: enVideo && masquee ? 0 : nil)
    .padding(.bottom, enVideo && masquee ? 0 : 10)
  }

  @ViewBuilder private func pochette(cote: CGFloat) -> some View {
    ZStack {
      Color.black.opacity(0.35)
      if let adresse = etat.courant?.artworkUrl, let url = URL(string: adresse) {
        AsyncImage(url: url) { image in
          image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
          Image(systemName: "waveform").font(.system(size: 34))
            .foregroundStyle(.secondary)
        }
      } else {
        Image(systemName: "waveform").font(.system(size: 34))
          .foregroundStyle(.secondary)
      }
    }
    .frame(width: cote, height: cote)
    .clipShape(RoundedRectangle(cornerRadius: 10))
  }

  private var enTete: some View {
    HStack(spacing: 12) {
      Button { etat.tiroirGauche.toggle() } label: { Image(systemName: "sidebar.left") }
        .buttonStyle(.plain)
      VStack(alignment: .leading, spacing: 1) {
        nomDuProjet
        Text(etat.message).font(.system(size: 11))
          .foregroundStyle(.secondary).lineLimit(1)
      }
      if let courantPays = etat.paysRadio {
        selecteurDePays(courantPays)
      }
      Spacer()
      // Valider lance la recherche. Un champ qui chercherait a chaque frappe
      // brulerait le quota YouTube : `search.list` coute 100 unites par appel.
      HStack(spacing: 6) {
        Image(systemName: "magnifyingglass").foregroundStyle(.tertiary)
        TextField("Un artiste, un titre…", text: $etat.requete)
          .textFieldStyle(.plain)
          .frame(width: 190)
          .onSubmit {
            etat.propositions = []
            surChercher(etat.requete)
          }
          // Forme a un argument, signalee obsolete depuis macOS 14 mais
          // gardee volontairement : la forme a deux arguments exige 14, et
          // elle seule nous coupait de macOS 13. Aucun des deux sites
          // n utilise l ancienne valeur. Voir MIN dans le Makefile.
          .onChange(of: etat.requete) { saisi in surSaisie(saisi) }
        if !etat.requete.isEmpty {
          Button {
            etat.requete = ""
            etat.propositions = []
          } label: {
            Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 10).padding(.vertical, 5)
      .background(Color.black.opacity(0.18), in: Capsule())
      // Un popover, et non une surcouche.
      //
      // Une surcouche SwiftUI declaree avant le lecteur se fait peindre dessus :
      // `WKWebView` est une vraie vue AppKit, elle rend dans sa propre couche.
      // La liste apparaissait vide, derriere la video. Un popover est une
      // fenetre a part, donc toujours au-dessus.
      .popover(isPresented: .constant(!etat.propositions.isEmpty),
               attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(etat.propositions, id: \.self) { proposition in
            Button {
              etat.requete = proposition
              etat.propositions = []
              surChercher(proposition)
            } label: {
              Text(proposition).font(.system(size: 12)).lineLimit(1)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .frame(width: 240, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.vertical, 4)
      }
      Spacer().frame(width: 4)
      Button { etat.tiroirDroit.toggle() } label: { Image(systemName: "list.bullet") }
        .buttonStyle(.plain)
    }
    .padding(.horizontal, 16).padding(.vertical, 10)
  }

  private var parolesDefilantes: some View {
    let active = etat.ligne(a: positionMs)
    return ScrollViewReader { lecteurDeVue in
      ScrollView {
        VStack(spacing: 14) {
          // Le meme rembourrage haut et bas que l app Flutter : la premiere
          // ligne doit pouvoir monter au centre, et la derniere aussi.
          Spacer().frame(height: 120)
          ForEach(Array(etat.paroles.enumerated()), id: \.offset) { index, ligne in
            Text(ligne.text)
              .font(.system(size: index == active ? 26 : 19,
                            weight: index == active ? .semibold : .regular))
              .foregroundStyle(index == active ? AnyShapeStyle(prefs.accent)
                               : index < active ? AnyShapeStyle(.tertiary)
                               : AnyShapeStyle(.secondary))
              .multilineTextAlignment(.center)
              .frame(maxWidth: 620)
              .id(index)
              .onTapGesture { surAller(ligne.atMs) }
              .animation(.easeOut(duration: 0.25), value: active)
          }
          Spacer().frame(height: 120)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
      }
      // Forme a un argument : voir la note dans la barre de recherche.
      .onChange(of: active) { nouveau in
        guard nouveau >= 0 else { return }
        withAnimation(.easeInOut(duration: 0.35)) {
          lecteurDeVue.scrollTo(nouveau, anchor: .center)
        }
      }
      // La couche de contraste, sans laquelle le verre rend le texte illisible.
      .background(Color.black.opacity(0.22))
    }
  }

  private var liste: some View {
    ScrollView {
      VStack(spacing: 0) {
        ForEach(Array(etat.titres.enumerated()), id: \.element.uri) { rang, titre in
          Button { surTitre(titre) } label: {
            HStack(spacing: 12) {
              Text("\(rang + 1)").font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary).frame(width: 24, alignment: .trailing)
              vignette(titre, cote: 36)
              VStack(alignment: .leading, spacing: 1) {
                Text(titre.title).font(.system(size: 13)).lineLimit(1)
                Text(titre.artiste).font(.system(size: 11)).foregroundStyle(.secondary)
              }
              Spacer()
              if titre.estRadio {
                Text("DIRECT").font(.system(size: 9, weight: .semibold))
                  .foregroundStyle(prefs.second)
              } else {
                Text(duree(titre.durationMs)).font(.system(size: 11, design: .monospaced))
                  .foregroundStyle(.tertiary)
              }
            }
            .padding(.horizontal, 20).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(etat.courant == titre ? Color.white.opacity(0.08) : .clear)
          }
          .buttonStyle(.plain)
          .contextMenu {
            if etat.listeOuverte != nil {
              Button("Retirer de cette liste", role: .destructive) {
                surRetirer(titre.uri)
              }
            }
            ForEach(mesListes.listes) { mienne in
              Button("Ajouter a « \(mienne.nom) »") { surAjouter(mienne.id, titre) }
            }
          }
        }
      }
      .padding(.vertical, 8)
    }
  }

  private var commandes: some View {
    HStack(spacing: 18) {
      titreEnCours
      // Le bouton central est plein et rond, comme on en a l habitude ; les
      // autres restent discrets pour qu il porte seul le regard.
      Button(action: surBasculer) {
        ZStack {
          Circle().fill(prefs.accent).frame(width: 34, height: 34)
          Image(systemName: enLecture ? "pause.fill" : "play.fill")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.black)
        }
      }
      .buttonStyle(.plain).disabled(etat.courant == nil)
      .opacity(etat.courant == nil ? 0.4 : 1)

      Button(action: surSuivant) {
        Image(systemName: "forward.fill").font(.system(size: 14))
          .foregroundStyle(.secondary)
      }
      .buttonStyle(.plain).disabled(etat.courant == nil)
      if etat.courant?.estRadio == true {
        // Un direct n a ni debut ni fin : une barre de progression mentirait.
        HStack(spacing: 6) {
          Circle().fill(prefs.second).frame(width: 7, height: 7)
          Text("EN DIRECT").font(.system(size: 10, weight: .semibold))
            .foregroundStyle(prefs.second)
          Text(duree(positionMs)).font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      } else {
        Text(duree(positionMs)).font(.system(size: 11, design: .monospaced))
          .foregroundStyle(.secondary)
        // `maxWidth: .infinity` plutot qu une largeur fixe : la progression
        // absorbe la place restante au lieu d en exiger, donc la barre s adapte
        // a la fenetre et ne la fait jamais deborder.
        ProgressView(value: Double(positionMs),
                     total: Double(max(etat.courant?.durationMs ?? 1, 1)))
          .tint(prefs.second)
          .frame(maxWidth: .infinity)
        Text(duree(etat.courant?.durationMs ?? 0))
          .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
      }
      volumeEtVitesse
      options
    }
    .padding(.horizontal, 20).padding(.vertical, 12)
  }

  // MARK: reglages

  private var panneauReglages: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("Reglages").font(.title3).bold()

      ligne("Theme") {
        Picker("", selection: Binding(
          get: { prefs.valeurs.theme },
          set: { prefs.valeurs.theme = $0 }
        )) {
          ForEach(Theme.allCases, id: \.self) { Text($0.mot).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 260)
      }

      ligne("Couleur principale") {
        nuancier(choisie: prefs.valeurs.accent) { prefs.valeurs.accent = $0 }
      }
      ligne("Couleur secondaire") {
        nuancier(choisie: prefs.valeurs.second) { prefs.valeurs.second = $0 }
      }

      ligne("Format du lecteur") {
        Picker("", selection: Binding(
          get: { TailleVideo(rawValue: prefs.valeurs.tailleVideo) ?? .grande },
          set: {
            prefs.valeurs.tailleVideo = $0.rawValue
            etat.tailleVideo = $0
          }
        )) {
          Text("Grande").tag(TailleVideo.grande)
          Text("Reduite").tag(TailleVideo.reduite)
          Text("Masquee").tag(TailleVideo.masquee)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 260)
      }

      ligne("A l ouverture") {
        Toggle("Lancer la lecture", isOn: Binding(
          get: { prefs.valeurs.demarrerEnLecture },
          set: { prefs.valeurs.demarrerEnLecture = $0 }
        ))
        .toggleStyle(.switch)
        .controlSize(.small)
      }

      ligne("Volume") {
        HStack {
          Slider(value: Binding(
            get: { prefs.valeurs.volume },
            set: { prefs.valeurs.volume = $0; surSon() }
          ), in: 0...1)
          .frame(width: 210)
          Text("\(Int(prefs.valeurs.volume * 100)) %")
            .font(.system(size: 11, design: .monospaced)).frame(width: 42)
        }
      }

      ligne("Vitesse") {
        Picker("", selection: Binding(
          get: { prefs.valeurs.vitesse },
          set: { prefs.valeurs.vitesse = $0; surSon() }
        )) {
          // Les seuls paliers que le lecteur officiel accepte ; il ignore le
          // reste en silence, autant ne pas les proposer.
          ForEach([0.75, 1.0, 1.25, 1.5], id: \.self) { f in
            Text(f == 1.0 ? "Normale" : "\(f, specifier: "%g")x").tag(f)
          }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 260)
      }

      Text("Pas d egaliseur : on ne touche jamais au flux audio d un clip, "
           + "c est le lecteur officiel qui le joue. Un reglage de bandes ne "
           + "vaudrait que pour les titres en audio direct.")
        .font(.system(size: 10)).foregroundStyle(.secondary)
        .frame(width: 420, alignment: .leading)

      HStack {
        Spacer()
        Button("Fermer") { etat.reglagesOuverts = false }
          .keyboardShortcut(.defaultAction)
      }
    }
    .padding(24)
    .frame(width: 470)
  }

  @ViewBuilder private func ligne<Contenu: View>(
    _ titre: String, @ViewBuilder _ contenu: () -> Contenu
  ) -> some View {
    HStack(alignment: .center) {
      Text(titre).font(.system(size: 12)).frame(width: 130, alignment: .leading)
      contenu()
      Spacer()
    }
  }

  @ViewBuilder private func nuancier(
    choisie: String, _ poser: @escaping (String) -> Void
  ) -> some View {
    HStack(spacing: 8) {
      ForEach(Preferences.PALETTE, id: \.hex) { teinte in
        Button { poser(teinte.hex) } label: {
          Circle()
            .fill(Color(hex: teinte.hex))
            .frame(width: 20, height: 20)
            .overlay(
              Circle().strokeBorder(.primary, lineWidth: choisie == teinte.hex ? 2 : 0)
            )
        }
        .buttonStyle(.plain)
        .help(teinte.nom)
      }
    }
  }

  /// Le nom du projet, dans ses deux couleurs. La coupure tombe sur
  /// « radioko » — « ma radio » en malgache — et « leka ».
  private var nomDuProjet: some View {
    HStack(spacing: 0) {
      Text("Radioko").foregroundStyle(prefs.accent)
      Text("Leka").foregroundStyle(prefs.second)
    }
    .font(.system(size: 15, weight: .semibold))
  }

  /// La page de pochette : l image en grand, le titre dessous.
  ///
  /// On y entre en cliquant la pochette de la barre, on en sort en cliquant
  /// n importe ou — un retour evident vaut mieux qu une croix a trouver.
  @ViewBuilder private var grandePochette: some View {
    if let courant = etat.courant {
      VStack(spacing: 22) {
        Spacer(minLength: 0)
        vignette(courant, cote: 300)
          .shadow(radius: 24, y: 10)
        VStack(spacing: 5) {
          Text(courant.title).font(.system(size: 21, weight: .semibold))
            .foregroundStyle(prefs.accent)
            .multilineTextAlignment(.center)
          Text(courant.artiste).font(.system(size: 14))
            .foregroundStyle(.secondary)
          if courant.durationMs > 0 {
            Text(duree(courant.durationMs))
              .font(.system(size: 11, design: .monospaced))
              .foregroundStyle(.tertiary)
          }
        }
        .frame(maxWidth: 420)
        Spacer(minLength: 0)
        Text("Cliquer pour revenir a la liste")
          .font(.system(size: 10)).foregroundStyle(.tertiary)
          .padding(.bottom, 14)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .contentShape(Rectangle())
      .onTapGesture { etat.centre = .liste }
    } else {
      liste
    }
  }

  /// Ce qui joue, a gauche de la barre. La pochette ouvre la grande page.
  @ViewBuilder private var titreEnCours: some View {
    if let courant = etat.courant {
      HStack(spacing: 10) {
        Button {
          etat.centre = etat.centre == .pochette ? .liste : .pochette
        } label: {
          vignette(courant, cote: 42)
            .overlay(
              RoundedRectangle(cornerRadius: 4)
                .strokeBorder(prefs.accent, lineWidth: etat.centre == .pochette ? 2 : 0)
            )
        }
        .buttonStyle(.plain)
        .help(etat.centre == .pochette ? "Revenir a la liste" : "Voir la pochette en grand")

        VStack(alignment: .leading, spacing: 1) {
          Text(courant.title).font(.system(size: 12, weight: .medium))
            .foregroundStyle(prefs.accent).lineLimit(1)
          Text(courant.artiste).font(.system(size: 10))
            .foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(width: 150, alignment: .leading)

        Button { surFavori(courant) } label: {
          Image(systemName: "heart").font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Ajouter a une liste")
      }
      .frame(width: 240, alignment: .leading)
    } else {
      HStack { Text("Rien en lecture").font(.system(size: 11)).foregroundStyle(.tertiary) }
        .frame(width: 240, alignment: .leading)
    }
  }

  /// Mosaique d un rayon : quatre pochettes en carre, une seule si c est tout
  /// ce qu on a. Un rayon sans pochette garde un carre neutre, pour que la
  /// colonne reste alignee.
  @ViewBuilder private func mosaique(_ adresses: [String], cote: CGFloat) -> some View {
    let forme = RoundedRectangle(cornerRadius: 5)
    let urls = adresses.prefix(4).compactMap { brute -> URL? in
      guard brute.contains("i.ytimg.com") else { return URL(string: brute) }
      return URL(string: brute.replacingOccurrences(
        of: #"/[a-z0-9]+default\.jpg"#,
        with: "/\(TaillePochette.vignette.rawValue).jpg",
        options: .regularExpression))
    }
    ZStack {
      forme.fill(Color.primary.opacity(0.08))
      if urls.count >= 4 {
        VStack(spacing: 1) {
          ForEach(0..<2, id: \.self) { rangee in
            HStack(spacing: 1) {
              ForEach(0..<2, id: \.self) { colonne in
                carre(urls[rangee * 2 + colonne], cote: (cote - 1) / 2)
              }
            }
          }
        }
      } else if let premiere = urls.first {
        carre(premiere, cote: cote)
      } else {
        Image(systemName: "square.stack").font(.system(size: cote * 0.38))
          .foregroundStyle(.tertiary)
      }
    }
    .frame(width: cote, height: cote)
    .clipShape(forme)
  }

  @ViewBuilder private func carre(_ url: URL, cote: CGFloat) -> some View {
    AsyncImage(url: url) { image in
      image.resizable().aspectRatio(contentMode: .fill)
    } placeholder: {
      Color.primary.opacity(0.06)
    }
    .frame(width: cote, height: cote)
    .clipped()
  }

  /// Choix du pays des radios.
  ///
  /// Madagascar est epingle en tete : c est le public du projet, et le reste du
  /// monde ne doit pas l enterrer sous deux cent vingt-six autres pays. La
  /// liste complete suit, par ordre alphabetique, avec le nombre de stations.
  @ViewBuilder private func selecteurDePays(_ code: String) -> some View {
    let nom = etat.paysDisponibles.first { $0.code == code }?.nom ?? code
    Menu {
      Button("Madagascar") { surPays("MG") }
      if !etat.paysDisponibles.isEmpty {
        Divider()
        ForEach(etat.paysDisponibles) { pays in
          Button("\(pays.nom) (\(pays.stations))") { surPays(pays.code) }
        }
      }
    } label: {
      HStack(spacing: 5) {
        Image(systemName: "globe").font(.system(size: 11))
        Text(nom).font(.system(size: 11)).lineLimit(1)
      }
      .foregroundStyle(prefs.second)
    }
    .menuStyle(.borderlessButton)
    .fixedSize()
    .help("Choisir le pays des radios")
  }

  /// Pochette d un titre. Un carre neutre tant qu elle charge, et si elle
  /// n existe pas : une liste ne doit pas sautiller au fil des chargements.
  @ViewBuilder private func vignette(_ titre: Titre, cote: CGFloat) -> some View {
    let forme = RoundedRectangle(cornerRadius: cote > 40 ? 6 : 4)
    ZStack {
      forme.fill(Color.primary.opacity(0.08))
      if let url = adressePochette(titre, cote > 120 ? .grande : .vignette) {
        AsyncImage(url: url) { image in
          image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
          Image(systemName: "music.note").font(.system(size: cote * 0.4))
            .foregroundStyle(.tertiary)
        }
      } else {
        Image(systemName: "music.note").font(.system(size: cote * 0.4))
          .foregroundStyle(.tertiary)
      }
    }
    .frame(width: cote, height: cote)
    .clipShape(forme)
  }

  private var volumeEtVitesse: some View {
    HStack(spacing: 8) {
      Button {
        // Clic sur l icone : coupe, ou revient au volume d avant.
        prefs.valeurs.volume = prefs.valeurs.volume > 0 ? 0 : 1
        surSon()
      } label: {
        Image(systemName: symboleVolume).font(.system(size: 12))
          .frame(width: 16)
          .foregroundStyle(.secondary)
      }
      .buttonStyle(.plain)
      .help(prefs.valeurs.volume > 0 ? "Couper le son" : "Retablir le son")

      Slider(value: Binding(
        get: { prefs.valeurs.volume },
        set: { prefs.valeurs.volume = $0; surSon() }
      ), in: 0...1)
      .frame(width: 80)
      .controlSize(.mini)
    }
    .padding(.trailing, 6)
  }

  private var symboleVolume: String {
    switch prefs.valeurs.volume {
    case ..<0.01: return "speaker.slash.fill"
    case ..<0.34: return "speaker.fill"
    case ..<0.67: return "speaker.wave.1.fill"
    default: return "speaker.wave.2.fill"
    }
  }

  /// Un bouton d option : icone **et** mot. Cinq icones muettes, dont deux
  /// faites de traits, se ressemblent trop pour qu on trouve la bonne.
  @ViewBuilder private func option(
    _ symbole: String, _ mot: String, actif: Bool, dispo: Bool = true,
    aide: String, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      VStack(spacing: 2) {
        Image(systemName: symbole).font(.system(size: 13))
        Text(mot).font(.system(size: 9))
      }
      .foregroundStyle(!dispo ? Color.secondary.opacity(0.4)
                       : actif ? Color.accentColor : Color.secondary)
      .frame(width: 52)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(!dispo)
    .help(aide)
  }

  private var options: some View {
    HStack(spacing: 2) {
      Menu {
        if let courant = etat.courant {
          ForEach(mesListes.listes) { mienne in
            Button("\(mienne.nom) (\(mienne.titres.count))") { surAjouter(mienne.id, nil) }
          }
          if !mesListes.listes.isEmpty { Divider() }
          Button("Nouvelle liste avec « \(courant.title.prefix(28)) »…") {
            nomEnCours = ""
            nommerUneListe = true
          }
        } else {
          Text("Aucun titre en cours")
        }
      } label: {
        Image(systemName: "text.badge.plus").foregroundStyle(.secondary)
      }
      .menuStyle(.borderlessButton)
      .fixedSize()
      .help("Ajouter le titre en cours a une liste")

      option("shuffle", "Aleatoire", actif: etat.aleatoire,
             aide: "Battre la file") {
        etat.aleatoire.toggle()
        if etat.aleatoire { surBattre() }
      }

      option(etat.repetition.symbole, "Repeter", actif: etat.repetition != .aucune,
             aide: etat.repetition.libelle) {
        etat.repetition = etat.repetition.suivante
      }

      option(etat.centre == .paroles ? "list.bullet.rectangle" : "text.alignleft",
             etat.centre == .paroles ? "Liste" : "Paroles",
             actif: etat.centre == .paroles,
             dispo: !etat.paroles.isEmpty || etat.centre == .paroles,
             aide: etat.centre == .paroles ? "Revenir a la liste"
                   : etat.paroles.isEmpty ? "Pas de paroles pour ce titre"
                   : "Voir les paroles") {
        if etat.centre == .paroles {
          etat.centre = .liste
        } else if !etat.paroles.isEmpty {
          etat.parolesVisibles = true
          etat.centre = .paroles
        }
      }

      option(etat.tailleVideo.symbole, etat.tailleVideo.mot,
             actif: etat.tailleVideo != .grande, dispo: enVideo,
             aide: enVideo ? "Grande, reduite, masquee — le son continue masque"
                   : "Pas de video pour ce titre") {
        etat.tailleVideo = etat.tailleVideo.suivante
        surTailleVideo(etat.tailleVideo.rawValue)
      }
    }
  }

  private var suite: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text("À suivre").font(.caption).foregroundStyle(.secondary)
        .padding(.horizontal, 14).padding(.top, 10)
      ScrollView {
        VStack(alignment: .leading, spacing: 1) {
          ForEach(etat.file) { titre in
            // Cliquable, comme toute ligne de titre. L oubli du bouton rendait
            // « À suivre » purement decoratif.
            Button { surTitreDeLaFile(titre) } label: {
              HStack(spacing: 9) {
                vignette(titre, cote: 32)
                VStack(alignment: .leading, spacing: 1) {
                  Text(titre.title).font(.system(size: 12)).lineLimit(1)
                  Text(titre.artiste).font(.system(size: 10)).foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
              }
              .padding(.horizontal, 14).padding(.vertical, 5)
              .frame(maxWidth: .infinity, alignment: .leading)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
              Button("Retirer de la file") { surRetirerDeLaFile(titre.uri) }
              ForEach(mesListes.listes) { mienne in
                Button("Ajouter a « \(mienne.nom) »") { surAjouter(mienne.id, titre) }
              }
            }
          }
        }
      }
      Spacer()
    }
  }
}

func duree(_ ms: Int) -> String {
  let total = ms / 1000
  return String(format: "%d:%02d", total / 60, total % 60)
}

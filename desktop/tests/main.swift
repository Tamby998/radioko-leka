//  Tests de la logique pure de l app.
//
//  Pas de XCTest, pas d Xcode : un binaire qui affirme et qui sort non nul si
//  quelque chose casse. Meme principe que le banc, et c est deja ce qui a sauve
//  deux fois le banc lui-meme.
//
//  Ils existent parce que le journal a trouve quatre defauts en une journee que
//  des tests auraient attrapes avant l utilisateur : la fin de titre non
//  branchee, la file non cliquable, le double encodage d uri, les paroles qui
//  mangeaient la liste. Les trois premiers etaient du cablage — intestables
//  sans interface. Le quatrieme etait une machine a etats, et celle-la se
//  teste.

import AppKit
import Foundation
import SwiftUI

var echecs = 0
var passes = 0

func verifier(_ quoi: String, _ condition: @autoclosure () -> Bool) {
  if condition() {
    passes += 1
    print("  ok   \(quoi)")
  } else {
    echecs += 1
    print("  ECHEC \(quoi)")
  }
}

func egal<T: Equatable>(_ quoi: String, _ obtenu: T, _ attendu: T) {
  if obtenu == attendu {
    passes += 1
    print("  ok   \(quoi)")
  } else {
    echecs += 1
    print("  ECHEC \(quoi) — obtenu \(obtenu), attendu \(attendu)")
  }
}

// --- Adresses de pochettes ---------------------------------------------

func titreYouTube(_ id: String, pochette: String?) -> Titre {
  Titre(uri: "youtube:\(id)", title: "T", artists: [Artiste(name: "A", id: "chaine")],
        durationMs: 200_000, artworkUrl: pochette, capabilities: ["stream"],
        requiresVisiblePlayer: true, streamUrl: nil)
}

print("\nAdresses de pochettes")

egal("la vignette demande mqdefault",
     adressePochette(titreYouTube("abc", pochette:
       "https://i.ytimg.com/vi/abc/maxresdefault.jpg"), .vignette)?.absoluteString,
     "https://i.ytimg.com/vi/abc/mqdefault.jpg")

egal("la grande demande hqdefault",
     adressePochette(titreYouTube("abc", pochette:
       "https://i.ytimg.com/vi/abc/maxresdefault.jpg"), .grande)?.absoluteString,
     "https://i.ytimg.com/vi/abc/hqdefault.jpg")

egal("une adresse deja en hqdefault est reecrite quand meme",
     adressePochette(titreYouTube("abc", pochette:
       "https://i.ytimg.com/vi/abc/hqdefault.jpg"), .vignette)?.absoluteString,
     "https://i.ytimg.com/vi/abc/mqdefault.jpg")

egal("une source etrangere garde son adresse",
     adressePochette(titreYouTube("abc", pochette:
       "https://creatornode.audius.co/image/xyz.jpg"), .vignette)?.absoluteString,
     "https://creatornode.audius.co/image/xyz.jpg")

verifier("pas de pochette rend nil",
         adressePochette(titreYouTube("abc", pochette: nil), .vignette) == nil)

// --- Calage des paroles -------------------------------------------------
//
// La recherche binaire est le seul vrai algorithme de l app, et une erreur de
// borne y est invisible a l oeil : la ligne surlignee a juste « l air » en
// retard. D ou les bornes testees une par une.

print("\nCalage des paroles")

MainActor.assumeIsolated {
  let etat = Etat()
  etat.paroles = [
    LigneParole(atMs: 0, text: "zero"),
    LigneParole(atMs: 5_000, text: "cinq"),
    LigneParole(atMs: 10_000, text: "dix"),
    LigneParole(atMs: 20_000, text: "vingt"),
  ]

  egal("au tout debut, la premiere ligne", etat.ligne(a: 0), 0)
  egal("entre deux lignes, la precedente", etat.ligne(a: 7_000), 1)
  egal("pile sur une ligne, celle-la", etat.ligne(a: 10_000), 2)
  egal("une milliseconde avant, la precedente", etat.ligne(a: 9_999), 1)
  egal("apres la derniere, la derniere", etat.ligne(a: 999_000), 3)

  let vide = Etat()
  egal("sans paroles, aucune ligne", vide.ligne(a: 1_000), -1)

  // Un seul horodatage, place plus loin que zero : avant lui, rien n est
  // atteint. C est le cas qui faisait surligner la ligne 0 a tort.
  let tardive = Etat()
  tardive.paroles = [LigneParole(atMs: 8_000, text: "tard")]
  egal("avant le premier horodatage, aucune ligne", tardive.ligne(a: 3_000), -1)
  egal("apres, la ligne", tardive.ligne(a: 8_000), 0)
}

// --- Cycles des options -------------------------------------------------

print("\nCycles des options")

egal("repetition : aucune -> titre", Repetition.aucune.suivante, .titre)
egal("repetition : titre -> liste", Repetition.titre.suivante, .liste)
egal("repetition : liste -> aucune", Repetition.liste.suivante, .aucune)

egal("video : grande -> reduite", TailleVideo.grande.suivante, .reduite)
egal("video : reduite -> masquee", TailleVideo.reduite.suivante, .masquee)
egal("video : masquee -> grande", TailleVideo.masquee.suivante, .grande)

// Le minimum que l API demande ne doit pas se perdre dans un refactor.
egal("la taille reduite reste au minimum", TailleVideo.reduite.cote, COTE_MINIMAL)
egal("le minimum vaut 200", COTE_MINIMAL, 200)

// --- Couleurs -----------------------------------------------------------

print("\nCouleurs")

// On ne compare pas des `Color`, on verifie qu une valeur illisible ne fait
// pas tomber l interface.
verifier("un hexadecimal trop court ne plante pas", {
  _ = Color(hex: "ABC")
  return true
}())
verifier("un hexadecimal invalide ne plante pas", {
  _ = Color(hex: "ZZZZZZ")
  return true
}())
verifier("le diese est tolere", {
  _ = Color(hex: "#F2C94C")
  return true
}())

// --- Bilan --------------------------------------------------------------

print("\n\(passes) verifications passent, \(echecs) echouent\n")
exit(echecs == 0 ? 0 : 1)

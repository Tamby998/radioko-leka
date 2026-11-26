import 'dart:convert';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

/// Le pont vers la page du lecteur, servie par le Worker.
///
/// Pourquoi pas `youtube_player_iframe` : ce paquet fabrique sa page et la
/// charge en lui donnant pour base `https://www.youtube.com`, une origine
/// qu elle n a pas. Sur Android, YouTube la refuse — « This video is
/// unavailable, error 152 - 4 » — et aucun titre ne jouait. Mesure du
/// 5 novembre 2026 : ni le reseau (le telephone et le Mac sortaient par la
/// meme adresse), ni l agent de la WebView, ni la video cachee. La meme
/// integration, servie par une vraie URL https, a joue du premier coup dans
/// une WebView ordinaire.
///
/// C est aussi le montage du bureau depuis le debut, et il n a jamais eu ce
/// probleme.
class LecteurWeb {
  LecteurWeb({required this.surEtat, required this.surErreur}) {
    // Chaque hote a ses deux reglages, et ce sont les memes deux questions :
    // le media a-t-il le droit de demarrer sans geste, et a-t-il le droit de
    // rester dans son cadre.
    //
    // Sur iPhone, `allowsInlineMediaPlayback` vaut faux par defaut : WKWebView
    // bascule alors tout clip en plein ecran natif. Mesure du 15 novembre
    // 2026 sur iPhone 17 — la video prenait l'ecran entier, l'app derriere,
    // et plus un seul bouton pour en sortir. Le lecteur de ce projet est
    // justement monte hors cadre la plupart du temps : il lui faut rester ou
    // on le met.
    final params = switch (defaultTargetPlatform) {
      TargetPlatform.android => AndroidWebViewControllerCreationParams(),
      TargetPlatform.iOS || TargetPlatform.macOS =>
        WebKitWebViewControllerCreationParams(
          allowsInlineMediaPlayback: true,
          mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
        ),
      _ => const PlatformWebViewControllerCreationParams(),
    };

    _ctrl = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF000000))
      ..addJavaScriptChannel('RadiokoLeka', onMessageReceived: _recevoir)
      ..loadRequest(Uri.parse(_page));

    // Sans cela Android exige un geste pour tout demarrage de media, et
    // `playVideo()` ne fait rien : le titre reste a 0:00, silencieux, sans
    // la moindre erreur pour le dire.
    final androide = _ctrl.platform;
    if (androide is AndroidWebViewController) {
      androide.setMediaPlaybackRequiresUserGesture(false);
    }
  }

  static const _page = 'https://radiokoleka-api.radiokoleka.workers.dev/lecteur';

  /// Etat du lecteur officiel : 1 joue, 2 pause, 3 tampon, 0 fini.
  final void Function(int etat) surEtat;

  /// Code de refus de YouTube, tel quel. On ne l interprete pas ici.
  final void Function(int code) surErreur;

  late final WebViewController _ctrl;
  WebViewController get controleur => _ctrl;

  bool _pret = false;
  String? _attendu;

  void _recevoir(JavaScriptMessage message) {
    final Map<String, dynamic> m;
    try {
      m = jsonDecode(message.message) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch (m['quoi']) {
      case 'pret':
        _pret = true;
        final id = _attendu;
        _attendu = null;
        if (id != null) jouer(id);
      case 'etat':
        surEtat(m['valeur'] as int? ?? -1);
      case 'erreur':
        surErreur(m['valeur'] as int? ?? -1);
    }
  }

  /// Une demande arrivee avant que la page soit la est gardee, pas perdue.
  ///
  /// Sans cette file d un seul element, un clic dans la premiere seconde ne
  /// faisait rien : la fonction n existait pas encore dans la page.
  Future<void> jouer(String videoId) async {
    if (!_pret) {
      _attendu = videoId;
      return;
    }
    await _ctrl.runJavaScript("jouer('$videoId')");
  }

  Future<void> basculer() => _ctrl.runJavaScript('basculer()');
  Future<void> stopper() => _ctrl.runJavaScript('stopper()');
  Future<void> aller(Duration ou) =>
      _ctrl.runJavaScript('aller(${ou.inMilliseconds})');
  Future<void> volume(int sur100) => _ctrl.runJavaScript('volume($sur100)');

  /// Chaque hote rend ses nombres a sa facon, et il faut lire les deux.
  ///
  /// Android rend la chaine `12345`, WKWebView un nombre dont `toString()`
  /// donne `12345.0`. `int.tryParse` refuse la seconde forme et rendait zero :
  /// sur iPhone le compteur restait a 0:00 pendant tout le morceau, la barre
  /// ne bougeait pas, et le karaoke ne surlignait aucune ligne — mesure du
  /// 15 novembre 2026 sur iPhone 17, clip en cours de lecture. `num` lit les
  /// deux formes.
  static Duration _millisecondes(Object? r) {
    final n = r is num ? r : num.tryParse(r.toString());
    if (n == null || !n.isFinite) return Duration.zero;
    return Duration(milliseconds: n.round());
  }

  /// La position vient du lecteur, jamais d une horloge locale : une horloge
  /// continue d avancer quand le lecteur, lui, est bloque.
  Future<Duration> position() async =>
      _millisecondes(await _ctrl.runJavaScriptReturningResult('position()'));

  Future<Duration> duree() async =>
      _millisecondes(await _ctrl.runJavaScriptReturningResult('duree()'));
}

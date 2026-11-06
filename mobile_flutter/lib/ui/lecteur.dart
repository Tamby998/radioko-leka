import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../main.dart' show Pochette;
import '../models/lyrics.dart';
import '../models/track.dart';
import '../player/playback_controller.dart';
import '../services/api_client.dart';
import 'barre_flottante.dart';
import 'karaoke_view.dart';
import 'listes.dart';

enum VoletLecteur { file, lecture, paroles }

/// L'ecran de lecture : file d'attente, lecture, paroles.
///
/// La video n'est pas la scene par defaut. On vient ecouter — et un clip
/// affiche en grand sur un telephone mange toute la place qu'il faudrait a ce
/// qui suit. Le lecteur officiel reste monte et continue de tourner, hors du
/// cadre visible ; le bouton « Video » le ramene.
class VueLecteur extends StatefulWidget {
  const VueLecteur({
    super.key,
    required this.api,
    required this.lecture,
    required this.titre,
    this.liste,
    this.depart,
  });

  final RadiokoLekaApi api;
  final PlaybackController lecture;
  final Track titre;

  /// La liste dans laquelle on a clique, pour que « suivant » ait un sens.
  final List<Track>? liste;
  final int? depart;

  @override
  State<VueLecteur> createState() => _VueLecteurState();
}

class _VueLecteurState extends State<VueLecteur> {
  VoletLecteur _volet = VoletLecteur.lecture;
  SyncedLyrics? _paroles;
  bool _parolesEnCours = true;
  String? _uriDesParoles;

  /// Le carre ou la video doit venir se poser, et la pile qui l'accueille.
  ///
  /// On mesure plutot que de deviner : le lecteur est monte une seule fois,
  /// au meme endroit de l'arbre, et seule sa geometrie change. Le deplacer
  /// d'un noeud a l'autre detruisait la vue native — mesure du 6 novembre
  /// 2026, `abandonAudioFocus()` a l'instant exact du clic « Video » — et le
  /// son se coupait net en montrant le clip.
  final GlobalKey _pile = GlobalKey();
  final GlobalKey _creneau = GlobalKey();
  Rect? _cadreVideo;

  void _mesurerLeCreneau() {
    final creneau = _creneau.currentContext?.findRenderObject() as RenderBox?;
    final pile = _pile.currentContext?.findRenderObject() as RenderBox?;
    if (creneau == null || pile == null) return;
    if (!creneau.hasSize || !pile.hasSize) return;
    final cadre =
        creneau.localToGlobal(Offset.zero, ancestor: pile) & creneau.size;
    if (cadre != _cadreVideo) setState(() => _cadreVideo = cadre);
  }

  @override
  void initState() {
    super.initState();
    widget.lecture.addListener(_rafraichir);

    // L'enchainement n'est pas branche ici par hasard : le controleur ne
    // connait pas le Worker, et c'est l'ecran qui a l'API sous la main.
    widget.lecture.surFileVide = (dernier) async {
      if (dernier.estRadio) return const [];
      try {
        return await widget.api.similaires(dernier);
      } catch (_) {
        return const [];
      }
    };

    _demarrer();
  }

  Future<void> _demarrer() async {
    final l = widget.lecture;
    if (l.current?.uri != widget.titre.uri) {
      await l.jouerListe(widget.liste ?? [widget.titre], widget.depart ?? 0);
    }
    _chargerParoles();
  }

  Future<void> _chargerParoles() async {
    final titre = widget.lecture.current;
    if (titre == null || _uriDesParoles == titre.uri) return;
    _uriDesParoles = titre.uri;

    if (titre.estRadio) {
      if (mounted) setState(() => _parolesEnCours = false);
      return;
    }
    setState(() {
      _parolesEnCours = true;
      _paroles = null;
    });
    try {
      final p = await widget.api.lyricsFor(titre);
      if (mounted) setState(() => _paroles = p);
    } catch (_) {
      // Pas de paroles n'est pas une panne : la lecture continue.
    } finally {
      if (mounted) setState(() => _parolesEnCours = false);
    }
  }

  void _rafraichir() {
    if (!mounted) return;
    setState(() {});
    // Le titre a change tout seul (enchainement) : les paroles suivent.
    _chargerParoles();
  }

  @override
  void dispose() {
    widget.lecture.removeListener(_rafraichir);
    widget.lecture.surFileVide = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.lecture;
    final titre = l.current ?? widget.titre;

    // Tant que le carre n'est pas mesure, le lecteur reste hors cadre : une
    // image d'attente vaut mieux qu'un lecteur pose au hasard.
    final montreLaVideo = l.videoVisible &&
        l.aUneVideo &&
        _volet == VoletLecteur.lecture &&
        _cadreVideo != null;

    WidgetsBinding.instance.addPostFrameCallback((_) => _mesurerLeCreneau());

    return Scaffold(
      appBar: AppBar(
        title: Text(
          switch (_volet) {
            VoletLecteur.file => 'File d attente',
            VoletLecteur.lecture => titre.estRadio ? 'En direct' : 'Lecture',
            VoletLecteur.paroles => 'Paroles',
          },
          style: Theme.of(context).textTheme.titleMedium,
        ),
        centerTitle: true,
      ),
      body: Stack(
        key: _pile,
        clipBehavior: Clip.none,
        children: [
          SafeArea(
            bottom: false,
            child: switch (_volet) {
              VoletLecteur.file => _VoletFile(lecture: l),
              VoletLecteur.lecture => _voletLecture(titre),
              VoletLecteur.paroles => _voletParoles(),
            },
          ),
          // Monte en permanence, au meme noeud, et place hors cadre quand on
          // ne le montre pas : seule sa geometrie bouge. Le demonter — ou le
          // deplacer ailleurs dans l'arbre — detache la vue native et coupe
          // le son. Le reduire a quelques pixels ne marche pas davantage :
          // le lecteur officiel exige 200 points de cote.
          if (l.aUneVideo)
            Positioned(
              left: montreLaVideo ? _cadreVideo!.left : -400,
              top: montreLaVideo ? _cadreVideo!.top : 0,
              width: montreLaVideo ? _cadreVideo!.width : 240,
              height: montreLaVideo ? _cadreVideo!.height : 135,
              child: _video(l),
            ),
          // Les coins de la video, peints par-dessus et non decoupes.
          //
          // Un `ClipRRect` autour d'une vue native la fait recomposer : mesure
          // du 6 novembre 2026, un `abandonAudioFocus()` a chaque bascule, la
          // ou le meme ecran sans decoupe en comptait zero. C'est le bug qu'on
          // venait de corriger. Quatre coins peints coutent un chemin et ne
          // touchent a rien.
          if (l.aUneVideo && montreLaVideo)
            Positioned.fromRect(
              rect: _cadreVideo!,
              child: IgnorePointer(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: CustomPaint(
                      painter: _CoinsPeints(
                        couleur: Theme.of(context).colorScheme.surface,
                        rayon: 18,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: _barreDesVolets(),
    );
  }

  Widget _video(PlaybackController l) {
    final web = l.lecteurWeb;
    if (web == null) return const SizedBox.shrink();
    return Center(
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: WebViewWidget(controller: web.controleur),
      ),
    );
  }

  Widget _voletLecture(Track titre) {
    final l = widget.lecture;
    final couleurs = Theme.of(context).colorScheme;

    return Column(
      children: [
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: AspectRatio(
                key: _creneau,
                aspectRatio: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    // La pochette ne flotte pas sur rien : une ombre large et
                    // basse la decolle du fond sans l'encadrer.
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.55),
                        blurRadius: 36,
                        offset: const Offset(0, 18),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    // Quand la video se montre, ce carre lui cede la place :
                    // le lecteur n'est pas ici, il est pose par-dessus depuis
                    // la pile, pour ne jamais changer de noeud.
                    child: l.videoVisible && l.aUneVideo
                        ? const SizedBox.expand()
                        : _grandePochette(titre),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              Text(
                titre.title,
                maxLines: 1,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
              ),
              const SizedBox(height: 6),
              // L'artiste porte la couleur du projet. C'est le seul endroit
              // de l'ecran ou un texte est colore, et c'est ce qui dit au
              // premier coup d'oeil a qui on ecoute.
              Text(
                titre.estRadio ? 'En direct' : titre.artistNames,
                maxLines: 1,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: couleurs.primary,
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        _progression(titre),
        const SizedBox(height: 10),
        _transport(),
        const SizedBox(height: 22),
        _actions(titre),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _grandePochette(Track titre) {
    final art = titre.artworkUrl;
    final fond = Theme.of(context).colorScheme.surfaceContainerHighest;
    final repli = ColoredBox(
      color: fond,
      child: Icon(titre.estRadio ? Icons.radio : Icons.music_note, size: 72),
    );
    if (art == null) return repli;
    return Image.network(
      art,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => repli,
    );
  }

  Widget _progression(Track titre) {
    final l = widget.lecture;
    final total = titre.duration.inMilliseconds;

    final couleurs = Theme.of(context).colorScheme;
    final chiffres = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: couleurs.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    // Une radio n'a pas de fin : une barre serait un mensonge. On met a sa
    // place le seul chiffre qui ait un sens, le temps ecoule.
    if (titre.estRadio) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: couleurs.secondary,
              ),
            ),
            const SizedBox(width: 8),
            Text('Flux continu', style: chiffres),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackShape: const RectangularSliderTrackShape(),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            ),
            child: Slider(
              value: total == 0
                  ? 0
                  : (l.position.inMilliseconds / total).clamp(0.0, 1.0),
              onChanged: (v) =>
                  l.seek(Duration(milliseconds: (v * total).round())),
            ),
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(duree(l.position), style: chiffres),
                Text(duree(titre.duration), style: chiffres),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _transport() {
    final l = widget.lecture;
    final couleurs = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          onPressed: l.basculerAleatoire,
          icon: const Icon(Icons.shuffle),
          color: l.aleatoire ? couleurs.primary : couleurs.onSurfaceVariant,
          tooltip: 'Aleatoire',
        ),
        IconButton(
          iconSize: 36,
          onPressed: l.precedent,
          icon: const Icon(Icons.skip_previous_rounded),
        ),
        // Le gros bouton rond : la cible la plus facile a atteindre au pouce,
        // et le seul aplat de couleur de l'ecran. La lueur sous lui n'est pas
        // decorative — elle le pose au-dessus des autres au lieu de le laisser
        // flotter dans le noir.
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: couleurs.primary,
            boxShadow: [
              BoxShadow(
                color: couleurs.primary.withValues(alpha: 0.28),
                blurRadius: 26,
                spreadRadius: 1,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: IconButton(
            iconSize: 38,
            color: couleurs.onPrimary,
            onPressed: l.togglePlayPause,
            icon: Icon(
              l.enLecture ? Icons.pause_rounded : Icons.play_arrow_rounded,
            ),
          ),
        ),
        IconButton(
          iconSize: 36,
          onPressed: l.suivant,
          icon: const Icon(Icons.skip_next_rounded),
        ),
        IconButton(
          onPressed: l.cyclerRepetition,
          color: l.repetition == Repetition.aucune
              ? couleurs.onSurfaceVariant
              : couleurs.primary,
          tooltip: switch (l.repetition) {
            Repetition.aucune => 'Pas de repetition',
            Repetition.liste => 'Repeter la liste',
            Repetition.titre => 'Repeter le titre',
          },
          icon: Icon(
            l.repetition == Repetition.titre ? Icons.repeat_one : Icons.repeat,
          ),
        ),
      ],
    );
  }

  /// Les actions secondaires tiennent dans une capsule.
  ///
  /// Posees a nu sur le fond, elles avaient le meme poids visuel que le
  /// transport juste au-dessus et se disputaient l'oeil. Regroupees sur une
  /// surface, elles redeviennent ce qu'elles sont : un second rang.
  Widget _actions(Track titre) {
    final l = widget.lecture;
    final couleurs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          // Une surface plus haute que la barre du bas : empilees dans la
          // meme teinte, les deux capsules se lisaient comme un seul bloc.
          color: couleurs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(26),
        ),
        child: _rangeeDActions(titre, l),
      ),
    );
  }

  Widget _rangeeDActions(Track titre, PlaybackController l) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _Action(
          icone: l.videoVisible ? Icons.videocam_off : Icons.videocam,
          texte: l.videoVisible ? 'Masquer' : 'Video',
          // Une radio n'a pas de video a montrer.
          actif: l.aUneVideo,
          surClic: l.basculerVideo,
        ),
        _Action(
          icone: Icons.playlist_add,
          texte: 'Ajouter',
          actif: true,
          surClic: () => montrerAjoutAListe(context, titre),
        ),
        _Action(
          icone: Icons.lyrics_outlined,
          texte: 'Paroles',
          actif: !titre.estRadio,
          surClic: () => setState(() => _volet = VoletLecteur.paroles),
        ),
      ],
    );
  }

  Widget _voletParoles() {
    final titre = widget.lecture.current ?? widget.titre;
    if (titre.estRadio) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Une radio n a pas de paroles : ce qui passe change sans que la '
            'station le dise.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (_parolesEnCours) {
      return const Center(child: CircularProgressIndicator());
    }
    final p = _paroles;
    if (p == null) {
      return const Center(child: Text('Paroles indisponibles pour ce titre'));
    }
    return KaraokeView(
      lyrics: p,
      position: widget.lecture.position,
      onSeek: widget.lecture.seek,
    );
  }

  Widget _barreDesVolets() => BarreFlottante(
        onglets: const [
          Onglet(Icons.queue_music_rounded, 'File'),
          Onglet(Icons.play_circle_rounded, 'Lecture'),
          Onglet(Icons.lyrics_rounded, 'Paroles'),
        ],
        choisi: VoletLecteur.values.indexOf(_volet),
        surChoix: (i) => setState(() => _volet = VoletLecteur.values[i]),
      );
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icone,
    required this.texte,
    required this.actif,
    required this.surClic,
  });

  final IconData icone;
  final String texte;
  final bool actif;
  final VoidCallback surClic;

  @override
  Widget build(BuildContext context) {
    final couleurs = Theme.of(context).colorScheme;
    final couleur =
        actif ? couleurs.onSurface : couleurs.onSurface.withValues(alpha: 0.3);
    return TextButton(
      onPressed: actif ? surClic : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 22, color: couleur),
          const SizedBox(height: 2),
          Text(texte, style: TextStyle(fontSize: 11, color: couleur)),
        ],
      ),
    );
  }
}

/// Ce qui suit, et d'ou ca vient.
class _VoletFile extends StatelessWidget {
  const _VoletFile({required this.lecture});

  final PlaybackController lecture;

  @override
  Widget build(BuildContext context) {
    final couleurs = Theme.of(context).colorScheme;
    final suite = lecture.aSuivre;
    final courant = lecture.current;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        if (courant != null) ...[
          Text('EN COURS',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: couleurs.onSurfaceVariant,
                    letterSpacing: 1.2,
                  )),
          const SizedBox(height: 8),
          Card(
            color: couleurs.surfaceContainerHighest,
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: Pochette(url: courant.artworkUrl, taille: 44),
              title: Text(courant.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                courant.estRadio ? 'En direct' : courant.artistNames,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Icon(
                lecture.enLecture ? Icons.pause_circle : Icons.play_circle,
                color: couleurs.primary,
              ),
              onTap: lecture.togglePlayPause,
            ),
          ),
          const SizedBox(height: 20),
        ],
        Row(
          children: [
            Text('A SUIVRE',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: couleurs.onSurfaceVariant,
                      letterSpacing: 1.2,
                    )),
            const Spacer(),
            if (suite.isNotEmpty)
              TextButton(
                onPressed: lecture.viderLaSuite,
                child: const Text('Vider'),
              ),
          ],
        ),
        if (suite.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              courant != null && courant.estRadio
                  ? 'Une radio ne s enchaine pas : elle ne finit pas.'
                  : 'Rien encore. A la fin du titre, des morceaux proches '
                      'seront proposes automatiquement.',
              textAlign: TextAlign.center,
              style: TextStyle(color: couleurs.onSurfaceVariant),
            ),
          )
        else
          for (var i = 0; i < suite.length; i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Pochette(url: suite[i].artworkUrl, taille: 44),
              title: Text(suite[i].title,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(suite[i].artistNames,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: Text(duree(suite[i].duration),
                  style: Theme.of(context).textTheme.bodySmall),
              onTap: () => lecture.allerA(lecture.index + 1 + i),
            ),
      ],
    );
  }
}

String duree(Duration d) {
  final m = d.inMinutes.remainder(60).toString();
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}

/// Une ligne de liste, identique partout : rayons, radios, recherche.
///
/// Elle passe la liste entiere au lecteur, pas seulement le titre clique :
/// c'est ce qui donne un sens a « suivant ».
class LigneTitre extends StatelessWidget {
  const LigneTitre({
    super.key,
    required this.titre,
    required this.api,
    required this.lecture,
    this.liste,
    this.rang,
  });

  final Track titre;
  final RadiokoLekaApi api;
  final PlaybackController lecture;
  final List<Track>? liste;
  final int? rang;

  @override
  Widget build(BuildContext context) {
    final couleurs = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: lecture,
      builder: (context, _) {
        // Le titre en cours se signale dans la liste. Sans cela on perd de
        // vue ce qui joue des qu'on fait defiler, et on relance le meme
        // morceau en croyant en lancer un autre.
        final enCours = lecture.current?.uri == titre.uri;

        return InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => VueLecteur(
                api: api,
                lecture: lecture,
                titre: titre,
                liste: liste,
                depart: rang,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 6, 8),
            child: Row(
              children: [
                Pochette(url: titre.artworkUrl, taille: 54),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        titre.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: enCours ? couleurs.primary : null,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        titre.estRadio ? 'En direct' : titre.artistNames,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: couleurs.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                if (enCours)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(
                      lecture.enLecture
                          ? Icons.graphic_eq_rounded
                          : Icons.pause_rounded,
                      size: 18,
                      color: couleurs.primary,
                    ),
                  )
                else if (!titre.estRadio && titre.duration > Duration.zero)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      duree(titre.duration),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: couleurs.onSurfaceVariant,
                          ),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.more_vert_rounded, size: 20),
                  color: couleurs.onSurfaceVariant,
                  onPressed: () => montrerAjoutAListe(context, titre),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Peint les quatre coins d'un rectangle dans la couleur du fond, pour
/// arrondir ce qui est dessous sans y toucher.
class _CoinsPeints extends CustomPainter {
  const _CoinsPeints({required this.couleur, required this.rayon});

  final Color couleur;
  final double rayon;

  @override
  void paint(Canvas toile, Size taille) {
    final cadre = Offset.zero & taille;
    final dehors = Path()..addRect(cadre);
    final dedans = Path()
      ..addRRect(RRect.fromRectAndRadius(cadre, Radius.circular(rayon)));
    toile.drawPath(
      Path.combine(PathOperation.difference, dehors, dedans),
      Paint()
        ..color = couleur
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_CoinsPeints ancien) =>
      ancien.couleur != couleur || ancien.rayon != rayon;
}

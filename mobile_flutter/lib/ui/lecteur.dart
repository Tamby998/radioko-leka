import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../main.dart' show Pochette;
import '../models/lyrics.dart';
import '../models/track.dart';
import '../player/playback_controller.dart';
import '../services/api_client.dart';
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
          // Monte en permanence, place hors cadre quand on ne le montre pas.
          // Le demonter couperait le son, et le reduire a quelques pixels
          // fait refuser le lecteur : il lui faut 200 points de cote.
          if (l.aUneVideo && !(l.videoVisible && _volet == VoletLecteur.lecture))
            Positioned(
              left: -400,
              top: 0,
              width: 240,
              height: 135,
              child: _video(l),
            ),
        ],
      ),
      bottomNavigationBar: _barreDesVolets(),
    );
  }

  Widget _video(PlaybackController l) {
    final c = l.youtubeController;
    if (c == null) return const SizedBox.shrink();
    return YoutubePlayer(controller: c, aspectRatio: 16 / 9);
  }

  Widget _voletLecture(Track titre) {
    final l = widget.lecture;
    final couleurs = Theme.of(context).colorScheme;

    return Column(
      children: [
        const SizedBox(height: 8),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: l.videoVisible && l.aUneVideo
                      ? Center(child: _video(l))
                      : _grandePochette(titre),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              Text(
                titre.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                titre.estRadio ? 'En direct' : titre.artistNames,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: couleurs.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _progression(titre),
        const SizedBox(height: 8),
        _transport(),
        const SizedBox(height: 8),
        _actions(titre),
        const SizedBox(height: 8),
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

    if (titre.estRadio) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 28),
        child: Text('Flux continu'),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: total == 0
                  ? 0
                  : (l.position.inMilliseconds / total).clamp(0.0, 1.0),
              onChanged: (v) =>
                  l.seek(Duration(milliseconds: (v * total).round())),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(duree(l.position),
                    style: Theme.of(context).textTheme.bodySmall),
                Text(duree(titre.duration),
                    style: Theme.of(context).textTheme.bodySmall),
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
          iconSize: 34,
          onPressed: l.precedent,
          icon: const Icon(Icons.skip_previous),
        ),
        // Le gros bouton rond : la cible la plus facile a atteindre au pouce.
        Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: couleurs.primary,
          ),
          child: IconButton(
            iconSize: 34,
            color: couleurs.onPrimary,
            onPressed: l.togglePlayPause,
            icon: Icon(l.enLecture ? Icons.pause : Icons.play_arrow),
          ),
        ),
        IconButton(
          iconSize: 34,
          onPressed: l.suivant,
          icon: const Icon(Icons.skip_next),
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
            l.repetition == Repetition.titre
                ? Icons.repeat_one
                : Icons.repeat,
          ),
        ),
      ],
    );
  }

  Widget _actions(Track titre) {
    final l = widget.lecture;
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

  Widget _barreDesVolets() {
    return NavigationBar(
      height: 64,
      selectedIndex: VoletLecteur.values.indexOf(_volet),
      onDestinationSelected: (i) =>
          setState(() => _volet = VoletLecteur.values[i]),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.queue_music_outlined),
          selectedIcon: Icon(Icons.queue_music),
          label: 'File',
        ),
        NavigationDestination(
          icon: Icon(Icons.play_circle_outline),
          selectedIcon: Icon(Icons.play_circle),
          label: 'Lecture',
        ),
        NavigationDestination(
          icon: Icon(Icons.lyrics_outlined),
          selectedIcon: Icon(Icons.lyrics),
          label: 'Paroles',
        ),
      ],
    );
  }
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
    final couleur = actif ? couleurs.onSurface : couleurs.onSurface.withValues(alpha: 0.3);
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
              title: Text(courant.title, maxLines: 1,
                  overflow: TextOverflow.ellipsis),
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
    return ListTile(
      leading: Pochette(url: titre.artworkUrl, taille: 48),
      title: Text(titre.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        titre.estRadio ? 'En direct' : titre.artistNames,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        icon: const Icon(Icons.more_vert, size: 20),
        onPressed: () => montrerAjoutAListe(context, titre),
      ),
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
    );
  }
}

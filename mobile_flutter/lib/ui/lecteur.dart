import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../main.dart' show Pochette;
import '../models/lyrics.dart';
import '../models/track.dart';
import '../player/playback_controller.dart';
import '../services/api_client.dart';
import 'karaoke_view.dart';

/// Ecran de lecture. La scene du haut change selon ce qui joue : lecteur
/// officiel pour un clip, pochette pour une radio ou un titre sous licence.
class VueLecteur extends StatefulWidget {
  const VueLecteur({
    super.key,
    required this.api,
    required this.lecture,
    required this.titre,
  });

  final RadiokoLekaApi api;
  final PlaybackController lecture;
  final Track titre;

  @override
  State<VueLecteur> createState() => _VueLecteurState();
}

class _VueLecteurState extends State<VueLecteur> {
  SyncedLyrics? _paroles;
  bool _parolesEnCours = true;

  @override
  void initState() {
    super.initState();
    widget.lecture.addListener(_rafraichir);
    _demarrer();
  }

  Future<void> _demarrer() async {
    // Si le titre joue deja — on vient de la barre du bas — le relancer le
    // ferait repartir de zero.
    if (widget.lecture.current?.uri != widget.titre.uri) {
      await widget.lecture.play(widget.titre);
    }

    // Une radio n'a pas de paroles a chercher : le titre est celui de la
    // station, pas celui du morceau qui passe.
    if (widget.titre.estRadio) {
      if (mounted) setState(() => _parolesEnCours = false);
      return;
    }
    try {
      final p = await widget.api.lyricsFor(widget.titre);
      if (mounted) setState(() => _paroles = p);
    } catch (_) {
      // Pas de paroles n'est pas une panne : la lecture continue.
    } finally {
      if (mounted) setState(() => _parolesEnCours = false);
    }
  }

  void _rafraichir() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.lecture.removeListener(_rafraichir);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final titre = widget.titre;
    return Scaffold(
      appBar: AppBar(title: Text(titre.title, overflow: TextOverflow.ellipsis)),
      body: Column(
        children: [
          AspectRatio(aspectRatio: 16 / 9, child: _scene()),
          _entete(titre),
          const Divider(height: 1),
          Expanded(child: _volet()),
          _transport(),
        ],
      ),
    );
  }

  /// Pour un clip, afficher le lecteur n'est pas un choix de mise en page :
  /// c'est la condition d'une lecture legitime, et la vue revient a la chaine.
  Widget _scene() {
    final yt = widget.lecture.youtubeController;
    if (yt != null) return YoutubePlayer(controller: yt, aspectRatio: 16 / 9);

    final art = widget.titre.artworkUrl;
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: art == null
          ? Icon(
              widget.titre.estRadio ? Icons.radio : Icons.music_note,
              size: 64,
            )
          : Image.network(art, fit: BoxFit.cover, width: double.infinity),
    );
  }

  Widget _entete(Track titre) {
    final mention = titre.estRadio
        ? 'En direct'
        : switch (widget.lecture.engine) {
            PlaybackEngine.youtubeOfficial => 'Lecteur officiel',
            PlaybackEngine.licensedAudio => 'Sous licence',
            PlaybackEngine.none => '',
          };

    return ListTile(
      title: Text(titre.artistNames),
      subtitle: Text(mention),
      trailing: titre.estRadio ? null : Text(_duree(titre.duration)),
    );
  }

  Widget _volet() {
    if (widget.titre.estRadio) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Une radio n a pas de paroles : ce qui passe change sans '
            'que la station le dise.',
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

  Widget _transport() {
    final l = widget.lecture;
    final total = widget.titre.duration.inMilliseconds;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            IconButton(
              iconSize: 40,
              icon: Icon(l.enLecture ? Icons.pause : Icons.play_arrow),
              onPressed: l.togglePlayPause,
            ),
            // Une radio n'a ni position ni fin : une barre a 0 % mentirait.
            if (widget.titre.estRadio)
              const Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text('Flux continu'),
                ),
              )
            else ...[
              Text(_duree(l.position)),
              Expanded(
                child: Slider(
                  value: total == 0
                      ? 0
                      : (l.position.inMilliseconds / total).clamp(0.0, 1.0),
                  onChanged: (v) =>
                      l.seek(Duration(milliseconds: (v * total).round())),
                ),
              ),
              Text(_duree(widget.titre.duration)),
            ],
          ],
        ),
      ),
    );
  }

  static String _duree(Duration d) {
    final m = d.inMinutes.remainder(60).toString();
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

/// Une ligne de liste, identique partout : rayons, radios, recherche.
class LigneTitre extends StatelessWidget {
  const LigneTitre({
    super.key,
    required this.titre,
    required this.api,
    required this.lecture,
  });

  final Track titre;
  final RadiokoLekaApi api;
  final PlaybackController lecture;

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
      trailing: Icon(
        titre.estRadio ? Icons.radio : Icons.play_circle_outline,
        size: 20,
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VueLecteur(api: api, lecture: lecture, titre: titre),
        ),
      ),
    );
  }
}

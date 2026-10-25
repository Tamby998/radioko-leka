import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../models/lyrics.dart';
import '../models/track.dart';
import '../player/playback_controller.dart';
import '../services/api_client.dart';
import 'karaoke_view.dart';

/// Ecran de lecture. La scene du haut change selon le moteur : lecteur officiel
/// pour le catalogue mondial, pochette pour le catalogue sous licence.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.api,
    required this.controller,
    required this.track,
  });

  final HiraApi api;
  final PlaybackController controller;
  final Track track;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  SyncedLyrics? _lyrics;
  bool _loadingLyrics = true;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onPlayback);
    _start();
  }

  Future<void> _start() async {
    await widget.controller.play(widget.track);
    try {
      final lyrics = await widget.api.lyricsFor(widget.track);
      if (mounted) setState(() => _lyrics = lyrics);
    } finally {
      if (mounted) setState(() => _loadingLyrics = false);
    }
  }

  void _onPlayback() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onPlayback);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    final offlineCapable = track.can(Capability.offline);

    return Scaffold(
      appBar: AppBar(
        title: Text(track.title, overflow: TextOverflow.ellipsis),
        actions: [
          // Le bouton n'existe pas pour le catalogue mondial : l'interface ne
          // propose jamais une action que le modele refuse.
          if (offlineCapable)
            IconButton(
              icon: const Icon(Icons.download_outlined),
              tooltip: 'Telecharger pour ecouter hors connexion',
              onPressed: () {},
            ),
        ],
      ),
      body: Column(
        children: [
          AspectRatio(aspectRatio: 16 / 9, child: _stage()),
          _trackHeader(track),
          const Divider(height: 1),
          Expanded(child: _lyricsPane()),
          _transport(),
        ],
      ),
    );
  }

  /// Pour YouTube, afficher le lecteur n'est pas un choix de design : c'est la
  /// condition d'une lecture legitime, et la vue revient a la chaine.
  Widget _stage() {
    final yt = widget.controller.youtubeController;
    if (yt != null) {
      return YoutubePlayer(controller: yt, aspectRatio: 16 / 9);
    }
    final art = widget.track.artworkUrl;
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: art == null
          ? const Center(child: Icon(Icons.music_note, size: 48))
          : Image.network(art, fit: BoxFit.cover),
    );
  }

  Widget _trackHeader(Track track) {
    final badge = switch (widget.controller.engine) {
      PlaybackEngine.youtubeOfficial => 'Lecteur officiel',
      PlaybackEngine.licensedAudio => 'Sous licence · hors connexion possible',
      PlaybackEngine.none => '',
    };

    return ListTile(
      title: Text(track.artistNames),
      subtitle: Text(badge),
      trailing: Text(_fmt(track.duration)),
    );
  }

  Widget _lyricsPane() {
    if (_loadingLyrics) {
      return const Center(child: CircularProgressIndicator());
    }
    final lyrics = _lyrics;
    if (lyrics == null) {
      return const Center(child: Text('Paroles indisponibles pour ce titre'));
    }
    return KaraokeView(
      lyrics: lyrics,
      position: widget.controller.position,
      onSeek: widget.controller.seek,
    );
  }

  Widget _transport() {
    final c = widget.controller;
    final total = widget.track.duration.inMilliseconds;
    final value = total == 0
        ? 0.0
        : (c.position.inMilliseconds / total).clamp(0.0, 1.0);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            IconButton(
              iconSize: 40,
              icon: const Icon(Icons.play_arrow),
              onPressed: c.togglePlayPause,
            ),
            Text(_fmt(c.position)),
            Expanded(
              child: Slider(
                value: value,
                onChanged: (v) => c.seek(
                  Duration(milliseconds: (v * total).round()),
                ),
              ),
            ),
            Text(_fmt(widget.track.duration)),
          ],
        ),
      ),
    );
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString();
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

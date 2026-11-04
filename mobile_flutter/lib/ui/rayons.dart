import 'package:flutter/material.dart';

import '../models/genre.dart';
import '../models/track.dart';
import '../player/playback_controller.dart';
import '../services/api_client.dart';
import 'echec.dart';
import 'lecteur.dart';

/// Les rayons : un genre racine par carte, avec une mosaique de quatre
/// pochettes prises parmi ses titres les plus vus.
class VueRayons extends StatefulWidget {
  const VueRayons({super.key, required this.api, required this.lecture});

  final RadiokoLekaApi api;
  final PlaybackController lecture;

  @override
  State<VueRayons> createState() => _VueRayonsState();
}

class _VueRayonsState extends State<VueRayons> {
  List<Genre> _rayons = const [];
  bool _chargement = true;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final g = await widget.api.genres();
      if (mounted) setState(() => _rayons = g);
    } catch (e) {
      if (mounted) setState(() => _erreur = '$e');
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_chargement) return const Center(child: CircularProgressIndicator());
    if (_erreur != null) return Echec(message: _erreur!, reessayer: _charger);

    return RefreshIndicator(
      onRefresh: _charger,
      child: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.78,
        ),
        itemCount: _rayons.length,
        itemBuilder: (_, i) => _CarteRayon(
          rayon: _rayons[i],
          api: widget.api,
          lecture: widget.lecture,
        ),
      ),
    );
  }
}

class _CarteRayon extends StatelessWidget {
  const _CarteRayon({
    required this.rayon,
    required this.api,
    required this.lecture,
  });

  final Genre rayon;
  final RadiokoLekaApi api;
  final PlaybackController lecture;

  @override
  Widget build(BuildContext context) {
    final couleurs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VueRayon(rayon: rayon, api: api, lecture: lecture),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _Mosaique(pochettes: rayon.pochettes)),
          const SizedBox(height: 8),
          Text(
            rayon.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Text(
            '${rayon.count} titres',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: couleurs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Quatre pochettes en carre, ou moins si le rayon en a moins.
///
/// Un rayon neuf n'en a qu'une ou deux ; forcer quatre cases laisserait des
/// trous gris plus visibles que les images.
class _Mosaique extends StatelessWidget {
  const _Mosaique({required this.pochettes});

  final List<String> pochettes;

  @override
  Widget build(BuildContext context) {
    final fond = Theme.of(context).colorScheme.surfaceContainerHighest;
    final images = pochettes.take(4).toList(growable: false);

    Widget image(String url) => Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => ColoredBox(color: fond),
        );

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: switch (images.length) {
        0 => ColoredBox(
            color: fond,
            child: const Center(child: Icon(Icons.library_music, size: 32)),
          ),
        1 => image(images.first),
        _ => GridView.count(
            crossAxisCount: 2,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              // Les cases manquantes reprennent les images presentes plutot
              // que de laisser du vide.
              for (var i = 0; i < 4; i++) image(images[i % images.length]),
            ],
          ),
      },
    );
  }
}

/// Le contenu d'un rayon.
class VueRayon extends StatefulWidget {
  const VueRayon({
    super.key,
    required this.rayon,
    required this.api,
    required this.lecture,
  });

  final Genre rayon;
  final RadiokoLekaApi api;
  final PlaybackController lecture;

  @override
  State<VueRayon> createState() => _VueRayonState();
}

class _VueRayonState extends State<VueRayon> {
  List<Track> _titres = const [];
  bool _chargement = true;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final t = await widget.api.genre(widget.rayon.slug);
      if (mounted) setState(() => _titres = t);
    } catch (e) {
      if (mounted) setState(() => _erreur = '$e');
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.rayon.label)),
      body: switch ((_chargement, _erreur)) {
        (true, _) => const Center(child: CircularProgressIndicator()),
        (_, final String e) => Echec(message: e, reessayer: _charger),
        _ => ListView.separated(
            itemCount: _titres.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) => LigneTitre(
              titre: _titres[i],
              api: widget.api,
              lecture: widget.lecture,
            ),
          ),
      },
    );
  }
}

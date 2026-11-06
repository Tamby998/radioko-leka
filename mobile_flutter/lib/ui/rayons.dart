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
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
              child: Text(
                'Rayons',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                    ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            sliver: SliverGrid(
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 0.80,
              ),
              delegate: SliverChildBuilderDelegate(
                (_, i) => _CarteRayon(
                  rayon: _rayons[i],
                  api: widget.api,
                  lecture: widget.lecture,
                ),
                childCount: _rayons.length,
              ),
            ),
          ),
        ],
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
      borderRadius: BorderRadius.circular(22),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VueRayon(rayon: rayon, api: api, lecture: lecture),
        ),
      ),
      // Une carte, et non une mosaique posee sur le fond : le nom du rayon
      // et son compte appartiennent a l'image, ils ne flottent pas dessous.
      child: Container(
        decoration: BoxDecoration(
          color: couleurs.surfaceContainer,
          borderRadius: BorderRadius.circular(22),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _Mosaique(pochettes: rayon.pochettes)),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    rayon.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${rayon.count} titres',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: couleurs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
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
            separatorBuilder: (_, __) => const SizedBox(height: 2),
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

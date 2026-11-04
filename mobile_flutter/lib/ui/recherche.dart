import 'dart:async';

import 'package:flutter/material.dart';

import '../models/track.dart';
import '../player/playback_controller.dart';
import '../services/api_client.dart';
import 'echec.dart';
import 'lecteur.dart';

/// La recherche, avec autocompletion.
///
/// Le Worker classe deja les resultats — officiel d'abord, reprises et remix
/// ensuite, radios dont le nom correspond en tete — donc l'app ne retrie rien :
/// elle afficherait un ordre different de celui du site et de l'app macOS.
class VueRecherche extends StatefulWidget {
  const VueRecherche({super.key, required this.api, required this.lecture});

  final RadiokoLekaApi api;
  final PlaybackController lecture;

  @override
  State<VueRecherche> createState() => _VueRechercheState();
}

class _VueRechercheState extends State<VueRecherche> {
  final TextEditingController _saisie = TextEditingController();
  Timer? _attente;
  List<String> _propositions = const [];
  List<Track> _resultats = const [];
  bool _chargement = false;
  String? _erreur;

  @override
  void dispose() {
    _attente?.cancel();
    _saisie.dispose();
    super.dispose();
  }

  /// Une frappe ne declenche pas un appel : on attend que la saisie se pose.
  /// Sans ce delai, « mahaleo » coute sept requetes au lieu d'une.
  void _surSaisie(String texte) {
    _attente?.cancel();
    if (texte.trim().isEmpty) {
      setState(() => _propositions = const []);
      return;
    }
    _attente = Timer(const Duration(milliseconds: 250), () async {
      try {
        final p = await widget.api.suggestions(texte);
        if (mounted) setState(() => _propositions = p);
      } catch (_) {
        // L'autocompletion est un confort : son echec ne se montre pas.
      }
    });
  }

  Future<void> _chercher(String quoi) async {
    if (quoi.trim().isEmpty) return;
    _attente?.cancel();
    FocusScope.of(context).unfocus();
    setState(() {
      _chargement = true;
      _erreur = null;
      _propositions = const [];
    });
    try {
      final t = await widget.api.search(quoi, limit: 30);
      if (mounted) setState(() => _resultats = t);
    } catch (e) {
      if (mounted) setState(() => _erreur = '$e');
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: SearchBar(
            controller: _saisie,
            hintText: 'Un artiste, un titre, une radio…',
            leading: const Icon(Icons.search),
            onChanged: _surSaisie,
            onSubmitted: _chercher,
          ),
        ),
        if (_propositions.isNotEmpty) _volet(),
        Expanded(child: _corps()),
      ],
    );
  }

  Widget _volet() {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Column(
        children: [
          for (final p in _propositions.take(6))
            ListTile(
              dense: true,
              leading: const Icon(Icons.north_west, size: 18),
              title: Text(p),
              onTap: () {
                _saisie.text = p;
                _chercher(p);
              },
            ),
        ],
      ),
    );
  }

  Widget _corps() {
    if (_chargement) return const Center(child: CircularProgressIndicator());
    if (_erreur != null) {
      return Echec(
        message: _erreur!,
        reessayer: () => _chercher(_saisie.text),
      );
    }
    if (_resultats.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Cherche un titre, un artiste, ou le nom d une radio.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.separated(
      itemCount: _resultats.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) => LigneTitre(
        titre: _resultats[i],
        api: widget.api,
        lecture: widget.lecture,
      ),
    );
  }
}

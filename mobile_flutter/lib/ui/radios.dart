import 'package:flutter/material.dart';

import '../models/track.dart';
import '../player/playback_controller.dart';
import '../services/api_client.dart';
import 'echec.dart';
import 'lecteur.dart';

/// Les radios en direct. Madagascar ouvert par defaut, le monde au menu.
class VueRadios extends StatefulWidget {
  const VueRadios({super.key, required this.api, required this.lecture});

  final RadiokoLekaApi api;
  final PlaybackController lecture;

  @override
  State<VueRadios> createState() => _VueRadiosState();
}

class _VueRadiosState extends State<VueRadios> {
  static const _parDefaut = 'MG';

  String _pays = _parDefaut;
  List<({String code, String nom, int stations})> _paysDisponibles = const [];
  List<Track> _stations = const [];
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
      final stations = await widget.api.radios(pays: _pays);
      // La liste des pays ne sert qu'au menu : son echec ne doit pas priver
      // de radios celui qui en voulait.
      final pays = _paysDisponibles.isEmpty
          ? await widget.api.paysDesRadios().catchError(
              (_) => const <({String code, String nom, int stations})>[],
            )
          : _paysDisponibles;
      if (!mounted) return;
      setState(() {
        _stations = stations;
        _paysDisponibles = pays;
      });
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
        _selecteurDePays(),
        const Divider(height: 1),
        Expanded(child: _corps()),
      ],
    );
  }

  Widget _selecteurDePays() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Text('Radios', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(width: 12),
          if (_paysDisponibles.isEmpty)
            const SizedBox.shrink()
          else
            // `Flexible` + `isExpanded` : sans eux le menu se dimensionne sur
            // son item le plus large — « United States of America (312) » —
            // et vient recouvrir le titre sur un ecran de telephone.
            Flexible(
              child: DropdownButton<String>(
              value: _pays,
              isExpanded: true,
              alignment: Alignment.centerRight,
              underline: const SizedBox.shrink(),
              items: [
                for (final p in _paysDisponibles)
                  DropdownMenuItem(
                    value: p.code,
                    child: Text(
                      '${p.nom} (${p.stations})',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                    ),
                  ),
              ],
              onChanged: (code) {
                if (code == null || code == _pays) return;
                setState(() => _pays = code);
                _charger();
              },
            ),
            ),
        ],
      ),
    );
  }

  Widget _corps() {
    if (_chargement) return const Center(child: CircularProgressIndicator());
    if (_erreur != null) {
      return Echec(message: _erreur!, reessayer: _charger);
    }
    if (_stations.isEmpty) {
      return const Center(child: Text('Aucune station pour ce pays.'));
    }
    return RefreshIndicator(
      onRefresh: _charger,
      child: ListView.separated(
        itemCount: _stations.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) => LigneTitre(
          titre: _stations[i],
          api: widget.api,
          lecture: widget.lecture,
        ),
      ),
    );
  }
}

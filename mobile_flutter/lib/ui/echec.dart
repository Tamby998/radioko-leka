import 'package:flutter/material.dart';

/// Un echec reseau se dit, avec de quoi recommencer.
///
/// Sur un telephone la connexion tombe souvent, et une liste vide ne distingue
/// pas la panne du catalogue vide : l'une se reessaie, l'autre non.
///
/// Ce qu'on montre est une phrase, pas une exception. « ClientException with
/// SocketException: Connection reset by peer (OS Error: Connection reset by
/// peer, errno = 104), address = ... » s'affichait tel quel sur quatre lignes
/// a l'utilisateur : c'est une trace de developpeur, elle n'apprend rien a
/// celui qui voulait ecouter une radio. Le detail reste disponible, replie.
class Echec extends StatefulWidget {
  const Echec({super.key, required this.message, required this.reessayer});

  final String message;
  final VoidCallback reessayer;

  @override
  State<Echec> createState() => _EchecState();
}

class _EchecState extends State<Echec> {
  bool _detailVisible = false;

  /// Traduit la panne en une phrase. On ne reconnait que ce qu'on a vu.
  ({String titre, String conseil}) _dire(String brut) {
    final m = brut.toLowerCase();
    if (m.contains('socketexception') ||
        m.contains('connection reset') ||
        m.contains('failed host lookup') ||
        m.contains('network is unreachable')) {
      return (
        titre: 'Pas de reseau',
        conseil: 'Verifie la connexion, puis reessaie.',
      );
    }
    if (m.contains('timeout') || m.contains('timed out')) {
      return (
        titre: 'Le serveur met trop de temps',
        conseil: 'La connexion est peut-etre lente. Reessaie.',
      );
    }
    if (m.contains('apiexception(5')) {
      return (
        titre: 'Le serveur a un probleme',
        conseil: 'Ce n est pas de ton cote. Reessaie dans un moment.',
      );
    }
    return (
      titre: 'Ca n a pas marche',
      conseil: 'Reessaie — si ca recommence, le detail est en dessous.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final couleurs = Theme.of(context).colorScheme;
    final dit = _dire(widget.message);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.wifi_off_rounded,
              size: 44,
              color: couleurs.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              dit.titre,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              dit.conseil,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: couleurs.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: widget.reessayer,
              style: FilledButton.styleFrom(
                backgroundColor: couleurs.primary,
                foregroundColor: couleurs.onPrimary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 14,
                ),
                shape: const StadiumBorder(),
              ),
              child: const Text('Reessayer'),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () =>
                  setState(() => _detailVisible = !_detailVisible),
              style: TextButton.styleFrom(
                foregroundColor: couleurs.onSurfaceVariant,
              ),
              child: Text(_detailVisible ? 'Masquer le detail' : 'Detail'),
            ),
            if (_detailVisible)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: SelectableText(
                  widget.message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: couleurs.onSurfaceVariant,
                      ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

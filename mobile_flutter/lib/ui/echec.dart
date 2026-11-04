import 'package:flutter/material.dart';

/// Un echec reseau se dit, avec de quoi recommencer.
///
/// Sur un telephone la connexion tombe souvent, et une liste vide ne distingue
/// pas la panne du catalogue vide : l'une se reessaie, l'autre non.
class Echec extends StatelessWidget {
  const Echec({super.key, required this.message, required this.reessayer});

  final String message;
  final VoidCallback reessayer;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off, size: 40),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: reessayer,
              child: const Text('Reessayer'),
            ),
          ],
        ),
      ),
    );
  }
}

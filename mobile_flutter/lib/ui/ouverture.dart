import 'dart:math' as math;

import 'package:flutter/material.dart';

/// L'ouverture de l'app : des ondes, le logo, le nom, puis on s'efface.
///
/// Elle est posee *par-dessus* l'app, qui est construite dessous des la
/// premiere frame. Les trois secondes ne sont donc pas une attente sèche :
/// pendant qu'elles passent, les radios et les rayons sont deja en train
/// d'arriver du Worker, et la liste est prête quand le voile se leve.
///
/// Le nom se coupe en deux couleurs, comme il se coupe en deux mots :
/// « Radioko » porte l'or, « Leka » le vert. C'est la regle du projet,
/// rendue visible une fois par lancement.
class Ouverture extends StatefulWidget {
  const Ouverture({super.key, required this.enfant});

  final Widget enfant;

  /// Assez pour voir les ondes partir et le nom se poser, pas assez pour
  /// qu'on attende. Au-dela, un ecran d'ouverture devient une porte fermee.
  static const duree = Duration(milliseconds: 3200);

  @override
  State<Ouverture> createState() => _OuvertureState();
}

class _OuvertureState extends State<Ouverture>
    with SingleTickerProviderStateMixin {
  late final AnimationController _temps = AnimationController(
    vsync: this,
    duration: Ouverture.duree,
  );

  bool _fini = false;

  @override
  void initState() {
    super.initState();
    _temps.forward().whenComplete(() {
      if (mounted) setState(() => _fini = true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Qui a demande moins d'animations au systeme n'a pas demande la notre.
    if (MediaQuery.disableAnimationsOf(context) && !_fini) {
      _temps.stop();
      _fini = true;
    }
  }

  @override
  void dispose() {
    _temps.dispose();
    super.dispose();
  }

  /// Une part de l'animation, bornee et adoucie.
  double _part(double debut, double fin, Curve courbe) {
    final t = ((_temps.value - debut) / (fin - debut)).clamp(0.0, 1.0);
    return courbe.transform(t);
  }

  @override
  Widget build(BuildContext context) {
    if (_fini) return widget.enfant;

    final couleurs = Theme.of(context).colorScheme;

    return Stack(
      children: [
        // L'app vit déjà dessous : ses appels reseau sont partis.
        widget.enfant,
        Positioned.fill(
          child: ListenableBuilder(
            listenable: _temps,
            builder: (context, _) {
              final sortie = _part(0.84, 1.0, Curves.easeInCubic);
              return IgnorePointer(
                ignoring: sortie > 0.5,
                child: Opacity(
                  opacity: 1 - sortie,
                  // `Material` et non un `ColoredBox` : sans ancetre Material,
                  // Flutter dessine le texte avec son style de secours, et le
                  // nom sortait souligne en jaune. Vu a l'ecran, invisible a
                  // la compilation.
                  child: Material(
                    color: couleurs.surface,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _logo(couleurs),
                          const SizedBox(height: 28),
                          _nom(couleurs),
                          const SizedBox(height: 34),
                          _fil(couleurs),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _logo(ColorScheme couleurs) {
    final pose = _part(0.0, 0.30, Curves.easeOutBack);
    // Trois ondes decalees, qui repartent en boucle : c'est une radio.
    return SizedBox(
      width: 220,
      height: 220,
      child: CustomPaint(
        painter: _Ondes(
          avancement: _temps.value,
          couleur: couleurs.primary,
          jusqua: 0.86,
        ),
        child: Center(
          child: Transform.scale(
            scale: 0.55 + 0.45 * pose,
            child: Opacity(
              opacity: pose.clamp(0.0, 1.0),
              child: Image.asset('assets/logo.png', width: 86, height: 86),
            ),
          ),
        ),
      ),
    );
  }

  Widget _nom(ColorScheme couleurs) {
    final pose = _part(0.18, 0.46, Curves.easeOutCubic);
    return Opacity(
      opacity: pose,
      child: Transform.translate(
        offset: Offset(0, 16 * (1 - pose)),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'Radioko',
                style: TextStyle(color: couleurs.primary),
              ),
              TextSpan(
                text: 'Leka',
                style: TextStyle(color: couleurs.secondary),
              ),
            ],
          ),
          style: const TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
      ),
    );
  }

  /// Un fil qui se remplit : il dit que quelque chose se prepare, et il dit
  /// vrai — c'est le temps que met la premiere liste a arriver.
  Widget _fil(ColorScheme couleurs) {
    final pose = _part(0.30, 0.86, Curves.easeInOut);
    return Opacity(
      opacity: _part(0.26, 0.40, Curves.easeOut),
      child: SizedBox(
        width: 132,
        height: 3,
        child: Stack(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: couleurs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
              child: const SizedBox(width: 132, height: 3),
            ),
            FractionallySizedBox(
              widthFactor: pose,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: couleurs.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: const SizedBox(height: 3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Trois cercles qui s'ecartent et s'effacent, decales dans le temps.
///
/// Dessines, pas animes un par un : un seul `CustomPainter` qui lit
/// l'avancement coute une repeinture, la ou trois widgets animes en
/// couteraient trois.
class _Ondes extends CustomPainter {
  const _Ondes({
    required this.avancement,
    required this.couleur,
    required this.jusqua,
  });

  final double avancement;
  final Color couleur;

  /// Les ondes s'arretent avant la fin : elles ne doivent pas etre coupees
  /// net par le fondu de sortie.
  final double jusqua;

  @override
  void paint(Canvas toile, Size taille) {
    if (avancement > jusqua) return;
    final centre = Offset(taille.width / 2, taille.height / 2);
    final rayonMax = taille.width / 2;

    for (var i = 0; i < 3; i++) {
      // Chaque onde repart toutes les 1,1 s, decalee d'un tiers.
      final t = ((avancement * Ouverture.duree.inMilliseconds / 1100) + i / 3) %
          1.0;
      final adouci = Curves.easeOut.transform(t);
      final rayon = 46 + (rayonMax - 46) * adouci;
      final opacite = (1 - adouci) * 0.55 * math.min(1.0, avancement * 6);
      if (opacite <= 0.01) continue;

      toile.drawCircle(
        centre,
        rayon,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = couleur.withValues(alpha: opacite),
      );
    }
  }

  @override
  bool shouldRepaint(_Ondes ancien) =>
      ancien.avancement != avancement || ancien.couleur != couleur;
}

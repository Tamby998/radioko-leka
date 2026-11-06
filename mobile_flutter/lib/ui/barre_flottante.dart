import 'package:flutter/material.dart';

/// Un onglet de la barre du bas.
class Onglet {
  const Onglet(this.icone, this.texte);

  final IconData icone;
  final String texte;
}

/// La barre du bas, posee et non collee au bord.
///
/// Une barre pleine largeur colle l'app au bas de l'ecran et l'ecrase ; la
/// meme barre avec une marge et des coins larges laisse le contenu respirer.
/// C'est la forme que prennent les deux references, et la seule qui se voie
/// sur tous les ecrans — elle est donc partagee, pas recopiee.
///
/// Elle reste un `bottomNavigationBar` de Scaffold partout ou elle sert : la
/// poser dans une pile changerait les coordonnees que l'ecran de lecture
/// calcule pour y placer le lecteur video.
class BarreFlottante extends StatelessWidget {
  const BarreFlottante({
    super.key,
    required this.onglets,
    required this.choisi,
    required this.surChoix,
    this.marge = const EdgeInsets.fromLTRB(20, 0, 20, 12),
  });

  final List<Onglet> onglets;
  final int choisi;
  final ValueChanged<int> surChoix;
  final EdgeInsets marge;

  @override
  Widget build(BuildContext context) {
    final couleurs = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: Padding(
        padding: marge,
        child: Container(
          height: 66,
          decoration: BoxDecoration(
            color: couleurs.surfaceContainer,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            children: [
              for (var i = 0; i < onglets.length; i++)
                Expanded(
                  child: _Onglet(
                    onglet: onglets[i],
                    choisi: i == choisi,
                    surClic: () => surChoix(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Onglet extends StatelessWidget {
  const _Onglet({
    required this.onglet,
    required this.choisi,
    required this.surClic,
  });

  final Onglet onglet;
  final bool choisi;
  final VoidCallback surClic;

  @override
  Widget build(BuildContext context) {
    final couleurs = Theme.of(context).colorScheme;
    final couleur = choisi ? couleurs.primary : couleurs.onSurfaceVariant;

    return InkWell(
      onTap: surClic,
      borderRadius: BorderRadius.circular(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(onglet.icone, size: 24, color: couleur),
          const SizedBox(height: 3),
          Text(
            onglet.texte,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: couleur,
                  fontWeight: choisi ? FontWeight.w600 : FontWeight.w400,
                ),
          ),
        ],
      ),
    );
  }
}

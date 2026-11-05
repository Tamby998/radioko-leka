import 'package:flutter/material.dart';

import 'player/playback_controller.dart';
import 'services/api_client.dart';
import 'ui/rayons.dart';
import 'ui/lecteur.dart';
import 'ui/listes.dart';
import 'ui/radios.dart';
import 'ui/recherche.dart';

/// Le Worker deploye, et non `127.0.0.1` : un telephone ne joint pas la boucle
/// locale d'un portable. Surchargeable au build pour pointer un Worker de test.
///
///   flutter run --dart-define=RADIOKOLEKA_API_URL=http://192.168.1.12:8787
const apiBaseUrl = String.fromEnvironment(
  'RADIOKOLEKA_API_URL',
  defaultValue: 'https://radiokoleka-api.radiokoleka.workers.dev',
);

/// Les deux couleurs du projet, celles que porte le nom : « radio » pour la
/// premiere, « leka » pour la seconde. Memes valeurs que l'app macOS.
const couleurRadio = Color(0xFFF2C94C);
const couleurLeka = Color(0xFF7BD88F);

void main() => runApp(const RadiokoLekaApp());

class RadiokoLekaApp extends StatefulWidget {
  const RadiokoLekaApp({super.key});

  @override
  State<RadiokoLekaApp> createState() => _RadiokoLekaAppState();
}

class _RadiokoLekaAppState extends State<RadiokoLekaApp> {
  final RadiokoLekaApi _api = RadiokoLekaApi(baseUrl: apiBaseUrl);
  final PlaybackController _lecture = PlaybackController();

  @override
  void initState() {
    super.initState();
    // Les listes sont sur le disque : on les relit avant que l'onglet ne
    // s'ouvre, sinon il s'affiche vide une fraction de seconde.
    magasinListes.charger();
  }

  @override
  void dispose() {
    _lecture.dispose();
    _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sombre = ColorScheme.fromSeed(
      seedColor: couleurRadio,
      brightness: Brightness.dark,
    ).copyWith(secondary: couleurLeka);

    return MaterialApp(
      title: 'RadiokoLeka',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: couleurRadio)
            .copyWith(secondary: couleurLeka),
      ),
      darkTheme: ThemeData(useMaterial3: true, colorScheme: sombre),
      themeMode: ThemeMode.dark,
      home: Accueil(api: _api, lecture: _lecture),
    );
  }
}

/// La coque : trois onglets et, sous eux, la barre du titre en cours.
class Accueil extends StatefulWidget {
  const Accueil({super.key, required this.api, required this.lecture});

  final RadiokoLekaApi api;
  final PlaybackController lecture;

  @override
  State<Accueil> createState() => _AccueilState();
}

class _AccueilState extends State<Accueil> {
  int _onglet = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack et non un simple switch : changer d'onglet ne doit pas
      // relancer les appels reseau de celui qu'on quitte.
      body: SafeArea(
        child: Column(
          children: [
            const EnTete(),
            Expanded(
              child: IndexedStack(
          index: _onglet,
          children: [
            VueRadios(api: widget.api, lecture: widget.lecture),
            VueRayons(api: widget.api, lecture: widget.lecture),
            VueRecherche(api: widget.api, lecture: widget.lecture),
            VueListes(api: widget.api, lecture: widget.lecture),
          ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BarreDuTitre(api: widget.api, lecture: widget.lecture),
          NavigationBar(
            selectedIndex: _onglet,
            onDestinationSelected: (i) => setState(() => _onglet = i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.radio_outlined),
                selectedIcon: Icon(Icons.radio),
                label: 'Radios',
              ),
              NavigationDestination(
                icon: Icon(Icons.library_music_outlined),
                selectedIcon: Icon(Icons.library_music),
                label: 'Rayons',
              ),
              NavigationDestination(
                icon: Icon(Icons.search),
                label: 'Recherche',
              ),
              NavigationDestination(
                icon: Icon(Icons.queue_music_outlined),
                selectedIcon: Icon(Icons.queue_music),
                label: 'Listes',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Le bandeau du haut : le logo, et le nom qu'il porte.
class EnTete extends StatelessWidget {
  const EnTete({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: [
          Image.asset('assets/logo.png', width: 28, height: 28),
          const SizedBox(width: 8),
          Text(
            'RadiokoLeka',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
          ),
        ],
      ),
    );
  }
}

/// La barre toujours visible quand quelque chose joue.
///
/// Elle ne porte pas le lecteur : elle y mene. Un clip YouTube exige que son
/// lecteur reste a l'ecran, ce qu'une barre de 64 pixels ne peut pas offrir.
class BarreDuTitre extends StatelessWidget {
  const BarreDuTitre({super.key, required this.api, required this.lecture});

  final RadiokoLekaApi api;
  final PlaybackController lecture;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: lecture,
      builder: (context, _) {
        final titre = lecture.current;
        if (titre == null) return const SizedBox.shrink();

        final couleurs = Theme.of(context).colorScheme;
        return Material(
          color: couleurs.surfaceContainerHigh,
          child: InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => VueLecteur(
                  api: api,
                  lecture: lecture,
                  titre: titre,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Pochette(url: titre.artworkUrl, taille: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          titre.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        Text(
                          titre.estRadio ? 'En direct' : titre.artistNames,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: couleurs.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: lecture.togglePlayPause,
                    icon: Icon(
                      lecture.enLecture ? Icons.pause : Icons.play_arrow,
                    ),
                  ),
                  IconButton(
                    onPressed: lecture.suivant,
                    icon: const Icon(Icons.skip_next),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Pochette carree, avec le repli qui va avec : beaucoup de radios n'en ont
/// pas, et une URL morte ne doit pas casser une liste.
class Pochette extends StatelessWidget {
  const Pochette({super.key, required this.url, this.taille = 56});

  final String? url;
  final double taille;

  @override
  Widget build(BuildContext context) {
    final repli = Container(
      width: taille,
      height: taille,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(Icons.music_note, size: taille * 0.5),
    );

    // Le SizedBox n est pas decoratif : sur le web, une image refusee par
    // CORS ne declenche pas toujours `errorBuilder`, et la case se reduisait
    // a rien — quatre stations sur dix affichaient un titre decale, sans
    // vignette ni trou. Le cadre est reserve d abord, rempli ensuite.
    return SizedBox(
      width: taille,
      height: taille,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: url == null
            ? repli
            : Image.network(
                url!,
                width: taille,
                height: taille,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => repli,
              ),
      ),
    );
  }
}

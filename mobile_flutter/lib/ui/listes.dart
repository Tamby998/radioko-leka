import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart' show Pochette;
import '../models/track.dart';
import '../player/playback_controller.dart';
import '../services/api_client.dart';
import 'lecteur.dart';

/// Les listes vivent sur le telephone, pas sur un serveur.
///
/// Il n'y a pas de compte dans cette app, et en ajouter un pour garder six
/// titres serait disproportionne. La contrepartie est assumee : une liste ne
/// suit pas d'un appareil a l'autre, et elle part avec l'app.
///
/// Chaque liste garde les titres entiers et non des identifiants : elle doit
/// rester lisible quand le reseau manque.
class MagasinListes extends ChangeNotifier {
  static const _cle = 'radiokoleka.listes.v1';

  Map<String, List<Track>> _listes = {};
  bool _charge = false;

  Map<String, List<Track>> get listes => Map.unmodifiable(_listes);
  bool get pret => _charge;

  Future<void> charger() async {
    final prefs = await SharedPreferences.getInstance();
    final brut = prefs.getString(_cle);
    if (brut != null) {
      try {
        final decode = jsonDecode(brut) as Map<String, dynamic>;
        _listes = {
          for (final e in decode.entries)
            e.key: [
              for (final t in e.value as List<dynamic>)
                Track.fromJson(t as Map<String, dynamic>),
            ],
        };
      } catch (_) {
        // Un magasin illisible ne doit pas empecher l'app de demarrer :
        // on repart vide plutot que de planter au lancement.
        _listes = {};
      }
    }
    _charge = true;
    notifyListeners();
  }

  Future<void> _enregistrer() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _cle,
      jsonEncode({
        for (final e in _listes.entries)
          e.key: [for (final t in e.value) t.toJson()],
      }),
    );
  }

  Future<void> creer(String nom) async {
    final propre = nom.trim();
    if (propre.isEmpty || _listes.containsKey(propre)) return;
    _listes = {..._listes, propre: const []};
    notifyListeners();
    await _enregistrer();
  }

  Future<void> supprimer(String nom) async {
    _listes = {..._listes}..remove(nom);
    notifyListeners();
    await _enregistrer();
  }

  /// Renvoie vrai si le titre a ete ajoute, faux s'il y etait deja — de quoi
  /// le dire a l'ecran plutot que de laisser croire a un double ajout.
  Future<bool> ajouter(String nom, Track titre) async {
    final liste = _listes[nom];
    if (liste == null) return false;
    if (liste.any((t) => t.uri == titre.uri)) return false;
    _listes = {..._listes, nom: [...liste, titre]};
    notifyListeners();
    await _enregistrer();
    return true;
  }

  Future<void> retirer(String nom, Track titre) async {
    final liste = _listes[nom];
    if (liste == null) return;
    _listes = {
      ..._listes,
      nom: liste.where((t) => t.uri != titre.uri).toList(growable: false),
    };
    notifyListeners();
    await _enregistrer();
  }
}

/// Une seule instance pour toute l'app.
///
/// Le reste du code passe ses dependances explicitement, mais une feuille de
/// liste s'ouvre depuis n'importe quelle ligne de n'importe quel ecran :
/// faire descendre le magasin jusque-la encombrerait cinq constructeurs pour
/// un seul objet qui n'existe qu'en un exemplaire.
final magasinListes = MagasinListes();

/// La feuille « ajouter a une liste », depuis une ligne ou depuis le lecteur.
Future<void> montrerAjoutAListe(BuildContext context, Track titre) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (contexteFeuille) => _FeuilleAjout(titre: titre),
  );
}

class _FeuilleAjout extends StatefulWidget {
  const _FeuilleAjout({required this.titre});

  final Track titre;

  @override
  State<_FeuilleAjout> createState() => _FeuilleAjoutState();
}

class _FeuilleAjoutState extends State<_FeuilleAjout> {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: magasinListes,
      builder: (context, _) {
        final noms = magasinListes.listes.keys.toList(growable: false);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Pochette(url: widget.titre.artworkUrl, taille: 40),
                title: Text(widget.titre.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(widget.titre.artistNames,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              const Divider(height: 1),
              for (final nom in noms)
                ListTile(
                  leading: const Icon(Icons.playlist_add),
                  title: Text(nom),
                  subtitle: Text('${magasinListes.listes[nom]!.length} titres'),
                  onTap: () async {
                    final ajoute =
                        await magasinListes.ajouter(nom, widget.titre);
                    if (!context.mounted) return;
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(ajoute
                            ? 'Ajoute a « $nom »'
                            : 'Deja dans « $nom »'),
                      ),
                    );
                  },
                ),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('Nouvelle liste'),
                onTap: () async {
                  final nom = await _demanderUnNom(context);
                  if (nom == null) return;
                  await magasinListes.creer(nom);
                  await magasinListes.ajouter(nom, widget.titre);
                  if (!context.mounted) return;
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

Future<String?> _demanderUnNom(BuildContext context) {
  final champ = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Nouvelle liste'),
      content: TextField(
        controller: champ,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Son nom'),
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(champ.text),
          child: const Text('Creer'),
        ),
      ],
    ),
  );
}

/// L'onglet des listes.
class VueListes extends StatelessWidget {
  const VueListes({super.key, required this.api, required this.lecture});

  final RadiokoLekaApi api;
  final PlaybackController lecture;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: magasinListes,
      builder: (context, _) {
        final noms = magasinListes.listes.keys.toList(growable: false);
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Text('Mes listes',
                      style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.add),
                    tooltip: 'Nouvelle liste',
                    onPressed: () async {
                      final nom = await _demanderUnNom(context);
                      if (nom != null) await magasinListes.creer(nom);
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: noms.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Aucune liste. Les trois points a droite d un titre '
                          'permettent de l ajouter a une liste.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView(
                      children: [
                        for (final nom in noms)
                          ListTile(
                            leading: const Icon(Icons.queue_music),
                            title: Text(nom),
                            subtitle: Text(
                                '${magasinListes.listes[nom]!.length} titres'),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => magasinListes.supprimer(nom),
                            ),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => _VueUneListe(
                                  nom: nom,
                                  api: api,
                                  lecture: lecture,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _VueUneListe extends StatelessWidget {
  const _VueUneListe({
    required this.nom,
    required this.api,
    required this.lecture,
  });

  final String nom;
  final RadiokoLekaApi api;
  final PlaybackController lecture;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: magasinListes,
      builder: (context, _) {
        final titres = magasinListes.listes[nom] ?? const <Track>[];
        return Scaffold(
          appBar: AppBar(title: Text(nom)),
          body: titres.isEmpty
              ? const Center(child: Text('Cette liste est vide.'))
              : ListView.separated(
                  itemCount: titres.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) => Dismissible(
                    key: ValueKey(titres[i].uri),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      color: Theme.of(context).colorScheme.errorContainer,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 24),
                      child: const Icon(Icons.delete_outline),
                    ),
                    onDismissed: (_) =>
                        magasinListes.retirer(nom, titres[i]),
                    child: LigneTitre(
                      titre: titres[i],
                      api: api,
                      lecture: lecture,
                      liste: titres,
                      rang: i,
                    ),
                  ),
                ),
        );
      },
    );
  }
}

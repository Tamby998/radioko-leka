import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/track.dart';
import '../services/api_client.dart';

/// Ecriture de fichiers locaux — reserve au catalogue sous licence.
///
/// Second verrou apres celui du Worker : meme si un appel arrivait ici avec un
/// titre du catalogue mondial, [Track.requireCapability] leve avant la moindre
/// requete reseau.
class DownloadManager {
  DownloadManager(this._api);

  final RadiokoLekaApi _api;

  Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/offline');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  String _fileName(Track track) =>
      '${track.uri.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_')}.audio';

  Future<File?> fileFor(Track track) async {
    if (!track.can(Capability.offline)) return null;
    final file = File('${(await _dir()).path}/${_fileName(track)}');
    return file.existsSync() ? file : null;
  }

  Future<bool> isAvailableOffline(Track track) async =>
      (await fileFor(track)) != null;

  /// Telecharge le titre pour une ecoute sans reseau.
  ///
  /// Leve [CapabilityError] sur un titre du catalogue mondial : c'est le
  /// comportement voulu, l'UI ne doit meme pas proposer le bouton.
  Future<File> download(Track track, {void Function(double)? onProgress}) async {
    track.requireCapability(Capability.offline);

    final url = await _api.resolveDownloadUrl(track);
    final req = http.Request('GET', Uri.parse(url));
    final res = await http.Client().send(req);
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, 'telechargement refuse', Uri.parse(url));
    }

    final file = File('${(await _dir()).path}/${_fileName(track)}');
    final sink = file.openWrite();
    final total = res.contentLength ?? 0;
    var received = 0;

    await res.stream.forEach((chunk) {
      sink.add(chunk);
      received += chunk.length;
      if (total > 0) onProgress?.call(received / total);
    });

    await sink.flush();
    await sink.close();
    return file;
  }

  Future<void> remove(Track track) async {
    final file = await fileFor(track);
    if (file != null) await file.delete();
  }
}

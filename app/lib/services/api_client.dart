import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/lyrics.dart';
import '../models/track.dart';

/// Seul point de contact avec le Worker. Aucune cle d'API ne vit dans l'app.
class HiraApi {
  HiraApi({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  Future<List<Track>> search(String query, {int limit = 20}) async {
    final uri = Uri.parse('$baseUrl/v1/search').replace(
      queryParameters: {'q': query, 'limit': '$limit'},
    );
    final body = await _getJson(uri);
    return ((body['tracks'] as List<dynamic>?) ?? const [])
        .map((t) => Track.fromJson(t as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<List<Track>> licensedTrending() async {
    final body = await _getJson(Uri.parse('$baseUrl/v1/charts/licensed-trending'));
    return ((body['tracks'] as List<dynamic>?) ?? const [])
        .map((t) => Track.fromJson(t as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<SyncedLyrics?> lyricsFor(Track track) async {
    final uri = Uri.parse('$baseUrl/v1/lyrics').replace(
      queryParameters: {
        'artist': track.primaryArtist,
        'title': track.title,
        'duration': '${track.duration.inSeconds}',
      },
    );
    final body = await _getJson(uri);
    final raw = body['lyrics'];
    if (raw == null) return null;
    return SyncedLyrics.fromJson(raw as Map<String, dynamic>);
  }

  /// Demande au serveur le feu vert avant d'ecrire un fichier local.
  /// Repond 403 pour le catalogue mondial : c'est attendu, pas une panne.
  Future<String> resolveDownloadUrl(Track track) async {
    track.requireCapability(Capability.offline);
    final uri = Uri.parse('$baseUrl/v1/download/${Uri.encodeComponent(track.uri)}');
    final body = await _getJson(uri);
    return body['streamUrl'] as String;
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final res = await _client.get(uri);
    if (res.statusCode >= 400) {
      throw HiraApiException(res.statusCode, res.body, uri);
    }
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  void close() => _client.close();
}

class HiraApiException implements Exception {
  const HiraApiException(this.statusCode, this.body, this.uri);

  final int statusCode;
  final String body;
  final Uri uri;

  @override
  String toString() => 'HiraApiException($statusCode) sur $uri : $body';
}

import 'package:flutter/material.dart';

import 'models/track.dart';
import 'player/playback_controller.dart';
import 'services/api_client.dart';
import 'ui/player_screen.dart';

/// Pointer vers le Worker deploye, ou `http://127.0.0.1:8787` en dev.
const apiBaseUrl = String.fromEnvironment(
  'HIRA_API_URL',
  defaultValue: 'http://127.0.0.1:8787',
);

void main() => runApp(const HiraApp());

class HiraApp extends StatefulWidget {
  const HiraApp({super.key});

  @override
  State<HiraApp> createState() => _HiraAppState();
}

class _HiraAppState extends State<HiraApp> {
  final HiraApi _api = HiraApi(baseUrl: apiBaseUrl);
  final PlaybackController _controller = PlaybackController();

  @override
  void dispose() {
    _controller.dispose();
    _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hira',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1DB954)),
        useMaterial3: true,
      ),
      home: SearchScreen(api: _api, controller: _controller),
    );
  }
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.api, required this.controller});

  final HiraApi api;
  final PlaybackController controller;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _query = TextEditingController();
  List<Track> _results = const [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTrending();
  }

  Future<void> _loadTrending() async {
    setState(() => _loading = true);
    try {
      final tracks = await widget.api.licensedTrending();
      if (mounted) setState(() => _results = tracks);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) return _loadTrending();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tracks = await widget.api.search(q);
      if (mounted) setState(() => _results = tracks);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _query,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Un artiste, un titre…',
            border: InputBorder.none,
          ),
          onSubmitted: _search,
        ),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }

    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final track = _results[i];
        return ListTile(
          leading: track.artworkUrl == null
              ? const Icon(Icons.music_note)
              : Image.network(track.artworkUrl!, width: 48, height: 48,
                  fit: BoxFit.cover),
          title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(track.artistNames, maxLines: 1),
          // Marqueur discret de ce que le titre permet.
          trailing: track.can(Capability.offline)
              ? const Icon(Icons.download_for_offline_outlined, size: 20)
              : const Icon(Icons.play_circle_outline, size: 20),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => PlayerScreen(
                api: widget.api,
                controller: widget.controller,
                track: track,
              ),
            ),
          ),
        );
      },
    );
  }
}

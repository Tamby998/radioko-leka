import 'package:flutter/material.dart';

void main() => runApp(const RadiokoLekaApp());

class RadiokoLekaApp extends StatelessWidget {
  const RadiokoLekaApp({super.key});

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF0B0B0E);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Radioko Leka',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: background,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFC7FF32),
          surface: Color(0xFF18181C),
        ),
        fontFamily: 'Arial',
      ),
      home: const RadioHomePage(),
    );
  }
}

class Station {
  const Station(this.name, this.subtitle, this.color, this.icon);

  final String name;
  final String subtitle;
  final Color color;
  final IconData icon;
}

class RadioHomePage extends StatefulWidget {
  const RadioHomePage({super.key});

  @override
  State<RadioHomePage> createState() => _RadioHomePageState();
}

class _RadioHomePageState extends State<RadioHomePage> {
  final _stations = const [
    Station('Viva Radio', 'Antananarivo · Pop', Color(0xFF6B39F4), Icons.bolt),
    Station(
      'Radio Don Bosco',
      'Madagascar · Actualités',
      Color(0xFFF0544F),
      Icons.public,
    ),
    Station(
      'RDJ 96.6',
      'Antananarivo · Hits',
      Color(0xFF147D91),
      Icons.graphic_eq,
    ),
    Station(
      'Radio Vazo Gasy',
      'Madagascar · Malagasy',
      Color(0xFFE59E32),
      Icons.music_note,
    ),
    Station(
      'Record Radio',
      'Madagascar · Dance',
      Color(0xFFBB42C8),
      Icons.album,
    ),
    Station(
      'Top Radio 102.8',
      'Antananarivo · Variétés',
      Color(0xFF218C65),
      Icons.headphones,
    ),
  ];

  String _query = '';
  int _tab = 0;
  Station? _playing;
  bool _isPlaying = false;
  final Set<String> _favorites = {'Viva Radio', 'RDJ 96.6'};

  @override
  Widget build(BuildContext context) {
    final filtered = _stations
        .where(
          (station) =>
              station.name.toLowerCase().contains(_query.toLowerCase()),
        )
        .toList();

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _header()),
                  SliverToBoxAdapter(child: _search()),
                  SliverToBoxAdapter(child: _categories()),
                  SliverToBoxAdapter(child: _sectionTitle()),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                    sliver: SliverGrid(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _stationCard(filtered[index]),
                        childCount: filtered.length,
                      ),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: .92,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            if (_playing != null) _miniPlayer(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        height: 68,
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        backgroundColor: const Color(0xFF111114),
        indicatorColor: const Color(0xFFC7FF32).withValues(alpha: .16),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Accueil',
          ),
          NavigationDestination(icon: Icon(Icons.search), label: 'Explorer'),
          NavigationDestination(
            icon: Icon(Icons.favorite_border),
            selectedIcon: Icon(Icons.favorite),
            label: 'Favoris',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: 'Profil',
          ),
        ],
      ),
    );
  }

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
    child: Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: const BoxDecoration(
            color: Color(0xFFC7FF32),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.radio_rounded, color: Colors.black),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'RADIOKO LEKA',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                ),
              ),
              Text(
                'Ny onjam-peonao, na aiza na aiza',
                style: TextStyle(fontSize: 12, color: Color(0xFF929298)),
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          onPressed: () {},
          icon: const Icon(Icons.notifications_none_rounded),
        ),
      ],
    ),
  );

  Widget _search() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 18),
    child: TextField(
      onChanged: (value) => setState(() => _query = value),
      decoration: InputDecoration(
        hintText: 'Rechercher une radio...',
        hintStyle: const TextStyle(color: Color(0xFF77777D)),
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: const Icon(Icons.tune_rounded),
        filled: true,
        fillColor: const Color(0xFF1A1A1E),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    ),
  );

  Widget _categories() => SizedBox(
        height: 116,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
      children: const [
        _Category('Malagasy', Icons.flag_rounded, Color(0xFF6246EA)),
        _Category('Actualités', Icons.newspaper_rounded, Color(0xFFD94B4B)),
        _Category('Musique', Icons.music_note_rounded, Color(0xFF14867B)),
        _Category('Gospel', Icons.wb_sunny_rounded, Color(0xFFD08A28)),
      ],
    ),
  );

  Widget _sectionTitle() => const Padding(
    padding: EdgeInsets.fromLTRB(20, 12, 20, 14),
    child: Row(
      children: [
        Expanded(
          child: Text(
            'Radios populaires',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
          ),
        ),
        Text(
          'Voir tout',
          style: TextStyle(
            color: Color(0xFFC7FF32),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );

  Widget _stationCard(Station station) {
    final favorite = _favorites.contains(station.name);
    final active = _playing?.name == station.name;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => setState(() {
        _playing = station;
        _isPlaying = true;
      }),
      child: Ink(
        decoration: BoxDecoration(
          color: const Color(0xFF19191D),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? const Color(0xFFC7FF32) : Colors.white10,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        station.color,
                        station.color.withValues(alpha: .45),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Stack(
                    children: [
                      Center(
                        child: Icon(
                          station.icon,
                          size: 54,
                          color: Colors.white.withValues(alpha: .9),
                        ),
                      ),
                      Positioned(
                        right: 6,
                        top: 6,
                        child: IconButton.filled(
                          visualDensity: VisualDensity.compact,
                          onPressed: () => setState(
                            () => favorite
                                ? _favorites.remove(station.name)
                                : _favorites.add(station.name),
                          ),
                          icon: Icon(
                            favorite ? Icons.favorite : Icons.favorite_border,
                            size: 18,
                            color: favorite
                                ? const Color(0xFFC7FF32)
                                : Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                station.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                station.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF96969C), fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniPlayer() {
    final station = _playing!;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF232328),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: station.color,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(station.icon),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  station.name,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const Text(
                  'EN DIRECT  •  Madagascar',
                  style: TextStyle(fontSize: 11, color: Color(0xFFC7FF32)),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.skip_previous_rounded),
          ),
          IconButton.filled(
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFFC7FF32),
              foregroundColor: Colors.black,
            ),
            onPressed: () => setState(() => _isPlaying = !_isPlaying),
            icon: Icon(
              _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            ),
          ),
        ],
      ),
    );
  }
}

class _Category extends StatelessWidget {
  const _Category(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 104,
    margin: const EdgeInsets.only(right: 10),
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: [color, color.withValues(alpha: .55)]),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, size: 25),
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}

import 'package:flutter/material.dart';

import '../models/lyrics.dart';

/// Paroles qui defilent ligne a ligne, calees sur la position du lecteur.
///
/// La ligne active est centree et mise en avant ; les voisines restent lisibles
/// en retrait. Le defilement n'est declenche qu'au changement de ligne, pas a
/// chaque tick, pour ne pas lutter contre un geste de l'utilisateur.
class KaraokeView extends StatefulWidget {
  const KaraokeView({
    super.key,
    required this.lyrics,
    required this.position,
    this.onSeek,
  });

  final SyncedLyrics lyrics;
  final Duration position;

  /// Taper une ligne saute a cet instant du morceau.
  final void Function(Duration)? onSeek;

  @override
  State<KaraokeView> createState() => _KaraokeViewState();
}

class _KaraokeViewState extends State<KaraokeView> {
  static const _lineExtent = 56.0;

  final ScrollController _scroll = ScrollController();
  int _activeIndex = -1;

  @override
  void didUpdateWidget(KaraokeView old) {
    super.didUpdateWidget(old);
    final next = widget.lyrics.indexAt(widget.position);
    if (next != _activeIndex) {
      _activeIndex = next;
      _centerOn(next);
    }
  }

  void _centerOn(int index) {
    if (index < 0 || !_scroll.hasClients) return;
    final viewport = _scroll.position.viewportDimension;
    final target = (index * _lineExtent) - (viewport / 2) + (_lineExtent / 2);
    _scroll.animateTo(
      target.clamp(0.0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lyrics.instrumental) {
      return const Center(child: Text('Instrumental'));
    }
    if (widget.lyrics.isEmpty) {
      return const Center(child: Text('Paroles indisponibles pour ce titre'));
    }

    final theme = Theme.of(context);

    return ListView.builder(
      controller: _scroll,
      itemCount: widget.lyrics.lines.length,
      itemExtent: _lineExtent,
      padding: const EdgeInsets.symmetric(vertical: 120),
      itemBuilder: (context, i) {
        final line = widget.lyrics.lines[i];
        final isActive = i == _activeIndex;
        final isPast = i < _activeIndex;

        return GestureDetector(
          onTap: widget.onSeek == null ? null : () => widget.onSeek!(line.at),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOut,
            style: (theme.textTheme.titleLarge ?? const TextStyle()).copyWith(
              fontSize: isActive ? 26 : 20,
              fontWeight: isActive ? FontWeight.w800 : FontWeight.w500,
              color: isActive
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface
                      .withValues(alpha: isPast ? 0.38 : 0.62),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(line.text, maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
            ),
          ),
        );
      },
    );
  }
}

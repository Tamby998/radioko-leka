import 'package:flutter/material.dart';

/// Une image de pochette, avec le repli qu'il faut pour YouTube.
///
/// L'API demande `maxresdefault.jpg`, la meilleure vignette. Elle n'existe
/// que pour les videos publiees en haute definition : pour toutes les autres
/// YouTube repond 404, et la case restait grise. Sur un rayon malgache, la
/// moitie des titres n'avait pas de pochette pour cette seule raison.
///
/// `mqdefault.jpg` existe toujours. On la demande en second, et seulement si
/// la premiere a echoue : rien n'est telecharge en trop quand tout va bien.
///
/// Pourquoi `mqdefault` et non `hqdefault`, plus grande : YouTube incruste
/// des bandes noires dans `hqdefault` (480x360, du 4:3 pour une video 16:9).
/// Elles ne sont pas un cadrage, elles sont dans les pixels — aucun `BoxFit`
/// ne les enleve. Vu le 15 novembre 2026 sur iPhone : une liste entiere de
/// vignettes barrees de noir en haut et en bas. `mqdefault` fait 320x180,
/// pile le format de la video, et suffit partout ici.
class ImagePochette extends StatefulWidget {
  const ImagePochette({
    super.key,
    required this.url,
    required this.repli,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
  });

  final String url;

  /// Ce qu'on montre quand meme le repli echoue.
  final Widget repli;

  final BoxFit fit;
  final double? width;
  final double? height;

  /// `https://i.ytimg.com/vi/<id>/maxresdefault.jpg` → la meme en `mqdefault`.
  /// Rend `null` pour toute autre adresse : on ne devine pas chez les autres.
  static String? _secondChoix(String url) {
    if (!url.contains('i.ytimg.com/vi/')) return null;
    if (!url.endsWith('/maxresdefault.jpg')) return null;
    return url.replaceFirst('/maxresdefault.jpg', '/mqdefault.jpg');
  }

  @override
  State<ImagePochette> createState() => _ImagePochetteState();
}

class _ImagePochetteState extends State<ImagePochette> {
  late String _adresse = widget.url;
  bool _repliEssaye = false;

  @override
  void didUpdateWidget(ImagePochette ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.url != widget.url) {
      _adresse = widget.url;
      _repliEssaye = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Image.network(
      _adresse,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      errorBuilder: (_, __, ___) {
        final second = ImagePochette._secondChoix(_adresse);
        if (!_repliEssaye && second != null) {
          // Pendant la construction : on repasse par une frame avant de
          // changer d'adresse, sinon `setState` lance ici.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              _adresse = second;
              _repliEssaye = true;
            });
          });
        }
        return widget.repli;
      },
    );
  }
}

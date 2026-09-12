import 'package:flutter/material.dart';

/// The marker for a Holfuy weather station, drawn as Holfuy's own symbol.
///
/// Painted rather than set from the icon font because the glyph *is* the
/// station's identity: Material's nearest, `Icons.air`, is three motion lines,
/// which is already what a data-less station from every other provider looks
/// like. Holfuy's mark - the wind arc over a mountain peak - keeps its pins
/// tellable apart from a METAR or FFVL ring at a glance.
///
/// The geometry is the Arcticons `holfuy` icon, hand-converted from its SVG so
/// the app carries no SVG-parsing dependency for one two-path glyph.
///
/// Arcticons licenses its icons CC BY-SA 4.0 (its own app is GPL-3.0, which
/// does not cover the artwork). Changes made here, which CC BY-SA requires
/// stating: the two paths are transcribed verbatim but drawn on a [Canvas] with
/// a thicker stroke, because the source's 1-unit stroke would be a third of a
/// pixel at marker size and vanish. The glyph is otherwise the original.
/// Attribution is in `about_screen.dart`; keep this conversion in this file so
/// the share-alike obligation stays scoped to it.
class HolfuyMarker extends StatelessWidget {
  const HolfuyMarker({super.key});

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(painter: HolfuyIconPainter());
  }
}

/// Draws Holfuy's station symbol: the wind arc over the mountain peak.
///
/// Stroke-only, like the source icon (`fill:none`), so it reads as a map
/// symbol rather than a filled pin that would hide the basemap underneath.
///
/// The colour is fixed at black, matching the `Colors.grey[800]` weight the
/// wind-barb ring and barbs are drawn in: the glyph is detail rather than a
/// flyability signal, so it must read as ink on the basemap instead of
/// competing with the green/amber/red the site pins use. There is deliberately
/// no `color` parameter, following `WindsockMarker`: the symbol states which
/// source the station belongs to, and a caller able to recolour it could take
/// that away.
class HolfuyIconPainter extends CustomPainter {
  /// The source SVG's `viewBox`. Every coordinate below is stated in it, so
  /// the paths can be diffed against the original without rescaling.
  static const double viewBox = 48.0;

  /// The square the `viewBox` is mapped into, centred in the marker.
  ///
  /// The glyph fills about 39x37 of the 48-unit box, so the drawn mark lands
  /// near 16 px - the size of the wind-barb ring it replaces, which is what
  /// keeps a Holfuy pin looking like the same class of thing as its
  /// neighbours rather than a logo dropped on the map.
  static const double _boxSize = 20.0;

  /// Stroke width in device pixels, held in screen space rather than scaled
  /// with the glyph: at marker size the source's own 1-unit stroke would
  /// render at a third of a pixel and vanish.
  static const double _strokeWidth = 1.5;

  /// Black, so a Holfuy pin sits in the same visual family as the grey station
  /// rings and barbs it replaces.
  static const Color color = Colors.black;

  const HolfuyIconPainter();

  /// The arc over the peak - SVG
  /// `M7.2493,34.7906a19.4991,19.4991,0,1,1,30.6346,3.7121`.
  ///
  /// `arcToPoint` takes the same radius / large-arc / clockwise triple the SVG
  /// `a` command carries, so this is the source's own arc rather than a
  /// re-fitting of it. The endpoint is the relative `30.6346,3.7121` resolved
  /// against the move-to.
  static Path _windArc() => Path()
    ..moveTo(7.2493, 34.7906)
    ..arcToPoint(
      const Offset(37.8839, 38.5027),
      radius: const Radius.circular(19.4991),
      largeArc: true,
      clockwise: true,
    );

  /// The peak - SVG
  /// `M40.0523,42.6892 24.0722,15.32 8.26,42.5593 24.2513,34.39l7.79,4.1124`:
  /// right base, apex, left base, the notch, then the short run up the far
  /// side. Extra coordinate pairs after a move-to are implicit line-tos, which
  /// is why only the last leg is written as a relative `l`.
  static Path _mountain() => Path()
    ..moveTo(40.0523, 42.6892)
    ..lineTo(24.0722, 15.32)
    ..lineTo(8.26, 42.5593)
    ..lineTo(24.2513, 34.39)
    ..lineTo(32.0413, 38.5024);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = _boxSize / viewBox;

    canvas.save();
    canvas.translate(
      (size.width - _boxSize) / 2,
      (size.height - _boxSize) / 2,
    );
    canvas.scale(scale);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth / scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(_windArc(), paint);
    canvas.drawPath(_mountain(), paint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(HolfuyIconPainter oldDelegate) => false;
}

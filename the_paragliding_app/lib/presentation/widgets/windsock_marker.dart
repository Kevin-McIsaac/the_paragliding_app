import 'package:flutter/material.dart';

/// A windsock, drawn for catalogue landing sites.
///
/// Painted rather than set from the icon font because Material has no windsock:
/// `Icons.wind_power` is a turbine and `Icons.air` is three motion lines. Both
/// name the wind; neither names a place to land.
///
/// The palette is fixed - orange and white bands on a slate mast, the real
/// windsock livery - so there is deliberately no `color` parameter. A landing
/// has no wind directions to be graded against, which is why the flag it
/// replaces was slate rather than a colour from the flyability scale, and the
/// same reasoning applies here: the symbol says what the place is, not whether
/// you can fly today.
class WindsockMarker extends StatelessWidget {
  /// The box the sock is drawn in. Defaults to the landing marker size, which
  /// is two thirds of a launch pin - a landing is supporting information.
  final double size;

  static const double markerSize = 28.0;

  const WindsockMarker({super.key, this.size = markerSize});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: const _WindsockPainter()),
    );
  }
}

/// Draws the windsock on Material's 24x24 icon grid, scaled to fit.
///
/// Working on the same grid as the stock glyphs is what lets the sock sit
/// beside a `location_on` pin without looking like it came from somewhere else.
class _WindsockPainter extends CustomPainter {
  const _WindsockPainter();

  // Blue Grey 400 - the colour the landing flag used, kept for the mast so the
  // marker still reads as the same family of thing on the map.
  static const Color _mast = Color(0xFF78909C);
  static const Color _band = Color(0xFFF4511E); // Deep Orange 600
  static const Color _outline = Color(0xFF546E7A); // Blue Grey 600

  /// The four bands, wide mouth to narrow tip.
  ///
  /// Listed as corner quads rather than computed from a taper, because the
  /// numbers came off a drawing and reproducing them exactly matters more than
  /// showing the arithmetic.
  static const List<List<Offset>> _bands = [
    [Offset(5, 5), Offset(9, 5.875), Offset(9, 12.625), Offset(5, 13)],
    [Offset(9, 5.875), Offset(13, 6.75), Offset(13, 12.25), Offset(9, 12.625)],
    [Offset(13, 6.75), Offset(17, 7.625), Offset(17, 11.875), Offset(13, 12.25)],
    [Offset(17, 7.625), Offset(21, 8.5), Offset(21, 11.5), Offset(17, 11.875)],
  ];

  /// The three lines between the bands, so the outline can draw them.
  static const List<List<Offset>> _dividers = [
    [Offset(9, 5.875), Offset(9, 12.625)],
    [Offset(13, 6.75), Offset(13, 12.25)],
    [Offset(17, 7.625), Offset(17, 11.875)],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24.0;
    Offset p(Offset o) => Offset(o.dx * scale, o.dy * scale);

    final mastRect = Rect.fromLTWH(3.2 * scale, 3 * scale, 1.8 * scale, 18 * scale);
    final hoopRect = Rect.fromLTWH(5 * scale, 4.4 * scale, 1.4 * scale, 9.2 * scale);

    final sock = Path()
      ..moveTo(5 * scale, 5 * scale)
      ..lineTo(21 * scale, 8.5 * scale)
      ..lineTo(21 * scale, 11.5 * scale)
      ..lineTo(5 * scale, 13 * scale)
      ..close();

    // A white keyline under everything else. Dropping it was tried on screen:
    // over Esri satellite imagery of dry paddock the slate mast and the slate
    // outline both fall to about the same value as the ground, and the sock
    // goes from a marker you can pick out to a smudge you have to look for.
    // This is the job the flag's white halo did, in one paint pass rather than
    // a second larger copy of the whole marker stacked underneath.
    final keyline = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2 * scale
      ..strokeJoin = StrokeJoin.round;
    canvas.drawRect(mastRect, keyline);
    canvas.drawPath(sock, keyline);

    canvas.drawRect(mastRect, Paint()..color = _mast);
    canvas.drawRect(hoopRect, Paint()..color = _band);

    // Alternating orange and white, starting orange at the mouth.
    for (var i = 0; i < _bands.length; i++) {
      final corners = _bands[i];
      final path = Path()..moveTo(p(corners[0]).dx, p(corners[0]).dy);
      for (final corner in corners.skip(1)) {
        path.lineTo(p(corner).dx, p(corner).dy);
      }
      path.close();
      canvas.drawPath(path, Paint()..color = i.isEven ? _band : Colors.white);
    }

    // The outline is the sock's only edge, and it is load-bearing rather than
    // decoration: without it the two white bands bleed into any pale ground -
    // dry paddock, snow, the Street Map's paper - and what is left reads as two
    // orange chunks adrift of a mast.
    final stroke = Paint()
      ..color = _outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9 * scale
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(sock, stroke);
    for (final divider in _dividers) {
      canvas.drawLine(p(divider[0]), p(divider[1]), stroke);
    }

  }

  @override
  bool shouldRepaint(_WindsockPainter oldDelegate) => false;
}

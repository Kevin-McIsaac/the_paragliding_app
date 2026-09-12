import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_paragliding_app/data/models/weather_station.dart';
import 'package:the_paragliding_app/data/models/weather_station_source.dart';
import 'package:the_paragliding_app/data/models/wind_data.dart';
import 'package:the_paragliding_app/presentation/widgets/holfuy_marker.dart';
import 'package:the_paragliding_app/presentation/widgets/weather_station_marker.dart';

/// The Holfuy marker is a hand-conversion of an SVG, so the geometry is the one
/// thing that can silently go wrong: a wrong arc flag still draws *an* arc, and
/// a wrong scale still draws *a* mark. These tests rasterise the painter and
/// measure the pixels, rather than re-deriving the numbers the painter already
/// contains - a test that recomputes the same arithmetic only proves the test
/// agrees with itself.

/// The wind every station in this file is given: strong, out of the east, so a
/// wind barb's 25 px shaft would run straight off to the right of the marker.
final _wind = WindData(
  speedKmh: 40,
  directionDegrees: 90,
  gustsKmh: 55,
  timestamp: DateTime.utc(2026, 9, 12, 12),
);

void main() {
  test('the glyph is the source arc over the peak, not a redrawn shape',
      () async {
    final bounds = await _paintIcon();

    // The arc is the top of the mark. Its position comes from the `a` command's
    // radius plus its large-arc and clockwise flags - the two flags that are
    // easy to transpose and impossible to see at 16 px. Transposing them moves
    // the arc to the bottom of the box, which drops the top of the paint from
    // ~11 px to ~16 px, so this single assertion is what pins the conversion.
    expect(
      bounds.top,
      inInclusiveRange(10.0, 13.2),
      reason: 'the wind arc must sweep over the top of the peak',
    );

    // The rest of the extent is the arc (widest at its own radius) and the
    // mountain's base.
    expect(bounds.left, inInclusiveRange(10.0, 12.5));
    expect(bounds.right, inInclusiveRange(27.5, 31.0));
    expect(bounds.bottom, inInclusiveRange(27.5, 30.0));

    // Centred in the 40 px marker, and about the size of the wind-barb ring
    // this replaces rather than the whole pin.
    expect(bounds.center.dx, closeTo(20, 1.0));
    expect(bounds.center.dy, closeTo(20, 1.0));
    expect(bounds.width, inInclusiveRange(16.0, 21.0));
    expect(bounds.height, inInclusiveRange(15.0, 20.0));
  });

  test('it is an outline in one flat ink colour - no fill, no white glyph',
      () async {
    final shot = await _paintIconShot();

    final argb = HolfuyIconPainter.color.toARGB32();
    final expectedRed = (argb >> 16) & 0xFF;
    final expectedGreen = (argb >> 8) & 0xFF;
    final expectedBlue = argb & 0xFF;

    var painted = 0;
    for (var i = 0; i < shot.rgba.length; i += 4) {
      final alpha = shot.rgba[i + 3];
      // Below this the premultiplied bytes have lost too much precision to
      // recover a colour from.
      if (alpha <= 64) continue;
      painted++;

      final red = shot.rgba[i] * 255 / alpha;
      final green = shot.rgba[i + 1] * 255 / alpha;
      final blue = shot.rgba[i + 2] * 255 / alpha;

      expect(red, closeTo(expectedRed, 6),
          reason: 'pixel $i is not the marker colour');
      expect(green, closeTo(expectedGreen, 6));
      expect(blue, closeTo(expectedBlue, 6));
    }

    // One flat colour and nothing else rules out the white wind glyph the disc
    // marker used to carry. The ceiling rules out a return to a *filled* disc:
    // a stroke of this length covers roughly 110 px, a disc of the same extent
    // over 300.
    expect(painted, greaterThan(60), reason: 'the glyph should draw something');
    expect(painted, lessThan(230), reason: 'the mark is an outline, not a disc');
  });

  testWidgets('every Holfuy station is the icon, read or not', (tester) async {
    final unread = await _captureMarker(tester, _station(read: false));
    final read = await _captureMarker(tester, _station(read: true));

    final unreadBounds = _paintedBounds(unread);
    final readBounds = _paintedBounds(read);

    // A reading arriving must not swap the mark for a wind barb: the whole
    // point of the Holfuy glyph is that the source stays identifiable.
    expect(
      readBounds,
      unreadBounds,
      reason: 'a Holfuy station must look the same before and after a reading',
    );

    // And the mark it settles on is the icon, centred, not a barb: with the
    // wind blowing due east a barb would paint out to ~71 px.
    expect(readBounds.center.dx, closeTo(40, 1.0));
    expect(readBounds.center.dy, closeTo(40, 1.0));
    expect(readBounds.right, lessThan(52));
  });

  testWidgets('a non-Holfuy station with the same wind still draws its barb',
      (tester) async {
    // The companion to the test above: without this, a painter that silently
    // drew nothing would satisfy every Holfuy assertion.
    final shot = await _captureMarker(tester, _station(read: true, source: WeatherStationSource.awcMetar));

    final bounds = _paintedBounds(shot);

    expect(
      bounds.right,
      greaterThan(60),
      reason: 'the 25 px wind-barb shaft should still be drawn for a METAR station',
    );
  });
}

WeatherStation _station({
  required bool read,
  WeatherStationSource source = WeatherStationSource.holfuy,
}) {
  return WeatherStation(
    id: source == WeatherStationSource.holfuy ? '142' : 'KSEA',
    source: source,
    name: source == WeatherStationSource.holfuy ? 'FlyStanwell' : 'Seattle-Tacoma',
    latitude: 47.4,
    longitude: 8.5,
    windData: read ? _wind : null,
    observationType: source == WeatherStationSource.holfuy
        ? 'Holfuy launch station'
        : 'Airport (METAR)',
  );
}

class _Shot {
  final Uint8List rgba;
  final int width;
  final int height;

  _Shot(this.rgba, this.width, this.height);
}

/// Rasterises just the painter on a transparent 40x40 canvas - the marker's own
/// size - so the measurements below are in the coordinates it actually paints.
Future<_Shot> _paintIconShot() async {
  final recorder = ui.PictureRecorder();
  const HolfuyIconPainter().paint(Canvas(recorder), const Size(40, 40));
  final image = await recorder.endRecording().toImage(40, 40);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  return _Shot(data!.buffer.asUint8List(), 40, 40);
}

Future<Rect> _paintIcon() async => _paintedBounds(await _paintIconShot());

/// Pumps one marker inside an 80x80 boundary.
///
/// Larger than the marker on purpose: the wind barb paints up to 31 px from the
/// centre, past the marker's own 40 px box, and a capture the size of the box
/// would clip the very thing these tests measure.
Future<_Shot> _captureMarker(WidgetTester tester, WeatherStation station) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: RepaintBoundary(
          key: key,
          child: SizedBox(
            width: 80,
            height: 80,
            child: Center(
              child: WeatherStationMarker(
                station: station,
                maxWindSpeed: 40,
                cautionWindSpeed: 25,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;

  // Rasterising is real engine work, not widget work: under the test binding's
  // fake async it never completes, so it has to run inside runAsync.
  final image = await tester.runAsync(() => boundary.toImage());
  final data = await tester.runAsync(
    () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
  );
  return _Shot(data!.buffer.asUint8List(), image!.width, image.height);
}

/// The box containing every pixel with meaningful alpha, or [Rect.zero].
Rect _paintedBounds(_Shot shot, {int alphaThreshold = 16}) {
  var minX = shot.width;
  var minY = shot.height;
  var maxX = -1;
  var maxY = -1;

  for (var y = 0; y < shot.height; y++) {
    for (var x = 0; x < shot.width; x++) {
      if (shot.rgba[(y * shot.width + x) * 4 + 3] > alphaThreshold) {
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
      }
    }
  }

  if (maxX < 0) return Rect.zero;
  return Rect.fromLTRB(
    minX.toDouble(),
    minY.toDouble(),
    maxX + 1.0,
    maxY + 1.0,
  );
}

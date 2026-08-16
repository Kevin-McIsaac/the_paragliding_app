import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:the_paragliding_app/data/models/paragliding_site.dart';
import 'package:the_paragliding_app/presentation/widgets/nearby_sites_map.dart';

/// Landings cluster with launches, and that is deliberate.
///
/// They were briefly pulled out into their own layer so a launch's landing was
/// always visible. On a real map that was worse than the problem it solved: a
/// third of the catalogue is landings, so an Alpine viewport drew 78 of them and
/// the launches the map exists to show could not be read through them - first
/// with their labels colliding, then, labels suppressed, as 78 flags competing
/// with 148 launches.
///
/// So this pins the decision rather than the mechanism: whatever the marker code
/// does, a landing beside a launch must not add a pin at overview zoom. Above
/// `disableClusteringAtZoom` they draw individually anyway, which is the zoom
/// where "where do I land" is a question you are actually asking.
///
/// Nothing else in `test/` covers this map at all.
void main() {
  // Two sites 100m apart, well inside the 50px cluster radius, at a zoom below
  // `disableClusteringAtZoom: 14`. Clustered, they collapse into one circle
  // showing "2" and neither name is on screen.
  final launch = ParaglidingSite(
    name: 'Mt Broughton (Thistle Hill)',
    latitude: -37.12269,
    longitude: 145.41304,
    siteType: 'launch',
    windDirections: const ['N', 'NE'],
  );
  final landing = ParaglidingSite(
    name: 'Hang gliders',
    latitude: -37.12359,
    longitude: 145.41304,
    siteType: 'landing',
  );

  Future<void> pumpMap(WidgetTester tester, List<ParaglidingSite> sites,
      {double zoom = 12}) async {
    tester.view.physicalSize = const Size(411, 923);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NearbySitesMap(
          sites: sites,
          selectedDateTime: DateTime(2026, 8, 16, 12),
          initialCenter: const LatLng(-37.123, 145.413),
          initialZoom: zoom,
          forecastEnabled: false,
          showUserLocation: false,
          weatherStationsEnabled: false,
        ),
      ),
    ));

    // Tiles fetch and fail in a test binding; the frames are pumped by hand
    // rather than settled, because a failing tile layer never settles.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('a landing beside a launch adds no pin at overview zoom',
      (tester) async {
    await pumpMap(tester, [launch, landing]);

    // One cluster of two, not a cluster and a flag beside it. Found by tooltip
    // rather than by icon because the legend carries a flag of its own.
    expect(find.text('2'), findsOneWidget);
    expect(find.byTooltip('Landing site'), findsNothing,
        reason: 'a landing must not draw its own pin over the launches');
    expect(find.text('Hang gliders'), findsNothing);
  });

  testWidgets('and draws individually once the map shows detail',
      (tester) async {
    // Past disableClusteringAtZoom nothing clusters, so the landing is there
    // with its name - the zoom at which you are looking at one hill.
    await pumpMap(tester, [launch, landing], zoom: 15);

    expect(find.text('Hang gliders'), findsOneWidget);
    expect(find.byTooltip('Landing site'), findsOneWidget);
  });
}

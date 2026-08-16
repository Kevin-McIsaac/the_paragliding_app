import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:the_paragliding_app/data/models/paragliding_site.dart';
import 'package:the_paragliding_app/presentation/widgets/nearby_sites_map.dart';

/// A landing must never be swallowed by a cluster.
///
/// Landings are a third of the catalogue and sit a median 1.7km from the launch
/// they serve, so clustered they were reliably invisible: at the zoom that
/// frames a launch its landing is off-screen, and at the zoom that includes it
/// both have merged into one numbered circle. A pilot asking "where do I land"
/// got a number.
///
/// `flutter_map_marker_cluster` has no per-marker opt-out, so the only way to
/// keep a marker out of a cluster is to keep it out of the list handed to the
/// cluster layer. That partition is what this pins - and nothing in `test/`
/// covered this map in either direction before.
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

  testWidgets('a landing beside its launch is still its own marker',
      (tester) async {
    await pumpMap(tester, [launch, landing]);

    // The pin, not the name: below the detail zoom a landing draws its flag
    // and nothing else, because 78 of them in one Alpine viewport buried the
    // launches behind their labels. Found by its tooltip rather than its icon,
    // because the legend carries a flag of its own.
    expect(find.byTooltip('Landing site'), findsOneWidget,
        reason: 'the landing is drawn individually, not folded into a cluster');
    expect(find.text('Hang gliders'), findsNothing,
        reason: 'its name would collide with every other landing at this zoom');
  });

  testWidgets('and takes its name back once the map shows detail',
      (tester) async {
    await pumpMap(tester, [launch, landing], zoom: 15);

    expect(find.text('Hang gliders'), findsOneWidget);
  });

  testWidgets('the launch beside it still clusters', (tester) async {
    // The other half, so this cannot pass by clustering having been turned off
    // altogether. Two launches this close collapse to one marker labelled "2".
    await pumpMap(tester, [
      launch,
      ParaglidingSite(
        name: 'Mt Broughton - South launch',
        latitude: -37.12359,
        longitude: 145.41304,
        siteType: 'launch',
        windDirections: const ['S'],
      ),
    ]);

    expect(find.text('2'), findsOneWidget);
    expect(find.text('Mt Broughton (Thistle Hill)'), findsNothing);
  });
}

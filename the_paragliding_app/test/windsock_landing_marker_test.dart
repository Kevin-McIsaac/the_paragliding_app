import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_paragliding_app/presentation/widgets/windsock_marker.dart';
import 'package:the_paragliding_app/utils/site_marker_utils.dart';

/// A landing is drawn as a windsock, and the legend says the same thing.
///
/// The map and its legend used to state the landing's symbol separately - the
/// map through `buildSiteMarkerIcon`, the legend by naming an `IconData` at the
/// call site - so the legend could go on describing a marker the map no longer
/// drew. #362 narrowed that to one glyph lookup; this pins the result of
/// finishing the job, where both now ask `SiteMarkerUtils.siteSymbol` for the
/// widget itself.
///
/// The launch case is here for the same reason: the windsock arrived by
/// collapsing the legend's hand-built pin stack into the shared function, and
/// that is exactly the kind of change that silently drops the white outline
/// keeping a pin legible over satellite imagery.
///
/// These need no map, so they skip the hand-pumped frames that
/// `landing_markers_test.dart` needs for its tile layer.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: Center(child: child))),
    );
  }

  testWidgets('a landing marker is a windsock, not a flag', (tester) async {
    await pump(
      tester,
      SiteMarkerUtils.buildSiteMarkerIcon(
        color: SiteMarkerUtils.landingSiteColor,
        siteType: 'landing',
      ),
    );

    expect(find.byType(WindsockMarker), findsOneWidget);
    expect(find.byIcon(Icons.flag), findsNothing,
        reason: 'the flag said "a spot", not "land here"');
  });

  testWidgets('a launch keeps its outlined pin', (tester) async {
    await pump(
      tester,
      SiteMarkerUtils.buildSiteMarkerIcon(
        color: SiteMarkerUtils.flyableSiteColor,
        siteType: 'launch',
      ),
    );

    expect(find.byType(WindsockMarker), findsNothing);
    // Two: the white copy underneath is what keeps the pin readable against
    // terrain, so its absence is a real regression rather than a detail.
    expect(find.byIcon(Icons.location_on), findsNWidgets(2));
  });

  testWidgets('the legend shows the marker the map draws', (tester) async {
    // buildMapLegend returns a Positioned, so it needs a Stack rather than the
    // Center the marker cases use.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Builder(
                builder: (context) => SiteMarkerUtils.buildMapLegend(
                  context: context,
                  showSites: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Landings'), findsOneWidget);
    expect(find.byType(WindsockMarker), findsOneWidget,
        reason: 'the legend must not go on advertising a flag');
  });
}

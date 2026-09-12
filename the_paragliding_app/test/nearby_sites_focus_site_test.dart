import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:the_paragliding_app/data/models/paragliding_site.dart';
import 'package:the_paragliding_app/presentation/screens/nearby_sites_screen.dart';

/// The Nearby Sites screen aims point-based discovery (WU PWS) at the site the
/// pilot is looking at rather than the viewport centre, so the station at that
/// launch is the one asked for. See `focusSiteFor`.
void main() {
  ParaglidingSite site(String name, double lat, double lon) => ParaglidingSite(
        name: name,
        latitude: lat,
        longitude: lon,
        siteType: 'launch',
      );

  test('no displayed sites means no focus point', () {
    expect(
      NearbySitesScreenState.focusSiteFor(
        const <ParaglidingSite>[],
        const LatLng(-31.66, 115.69),
      ),
      isNull,
    );
  });

  test('picks the displayed site nearest the map centre', () {
    final sites = [
      site('Far', -31.50, 115.90),
      site('Quinns Beach Launch', -31.6632, 115.689),
      site('Further', -32.00, 115.60),
    ];

    final focus = NearbySitesScreenState.focusSiteFor(
      sites,
      const LatLng(-31.6684, 115.6945), // the Quinns Rocks viewport centre
    );

    expect(focus, const LatLng(-31.6632, 115.689));
  });

  test('reports the site position, not the map centre', () {
    final focus = NearbySitesScreenState.focusSiteFor(
      [site('Quinns Beach Launch', -31.6632, 115.689)],
      const LatLng(-31.0, 115.0),
    );

    expect(focus, isNotNull);
    expect(focus!.latitude, closeTo(-31.6632, 1e-9));
    expect(focus.longitude, closeTo(115.689, 1e-9));
  });
}
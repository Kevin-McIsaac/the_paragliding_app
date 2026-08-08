@Tags(['network'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:the_paragliding_app/services/paragliding_earth_api.dart';

/// ParaglidingEarth has no fetch-by-id query, so a known site is found by
/// position and then picked out of the results by id. Two things make that
/// fragile, and both were live bugs:
///
///  * the id element is `<pge_site_id>`, not `<id>`. Matching on `<id>` never
///    succeeded, and the "use the first result" fallback hid it completely -
///    the app had been picking by position in a search box for a long time.
///  * the search radius has to exceed how far two guides place the same
///    launch apart. PGE's pin for Mt Bakewell is 190m from the Australian
///    Site Guide's, and the old ~100m box simply returned nothing.
///
/// Network-tagged, so skipped by default; run with
/// `flutter test --tags network --run-skipped`.
void main() {
  // Mt Bakewell, Western Australia. The catalogue holds the Australian Site
  // Guide's position for it, which is 190m from PGE's own.
  const catalogLat = -31.853;
  const catalogLon = 116.761;
  const pgeSiteId = 6724;

  test('finds a site by id from the position another guide records', () async {
    final details = await ParaglidingEarthApi.instance.getSiteDetails(
      catalogLat,
      catalogLon,
      siteId: pgeSiteId,
    );

    expect(details, isNotNull,
        reason: 'the search radius must reach PGE pin 190m away');
    expect(details!['pge_site_id'].toString(), '$pgeSiteId',
        reason: 'must be the requested site, not whichever came back first');
    expect(details['name'].toString().toLowerCase(), contains('bakewell'));
  });

  test('returns nothing rather than a neighbour when the id is absent', () async {
    // Guessing here would put another launch's takeoff notes, rules and
    // hazards under this site's name with nothing to say they belong
    // elsewhere - the same class of error as linking to the wrong site.
    final details = await ParaglidingEarthApi.instance.getSiteDetails(
      catalogLat,
      catalogLon,
      siteId: 999999999,
    );

    expect(details, isNull);
  });
}

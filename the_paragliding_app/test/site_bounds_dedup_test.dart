import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:the_paragliding_app/data/datasources/database_helper.dart';
import 'package:the_paragliding_app/services/pge_sites_database_service.dart';
import 'package:the_paragliding_app/services/site_bounds_loader_v2.dart';

import 'helpers/test_helpers.dart';

/// Covers deduplicating a flown site against its catalog entry in
/// [SiteBoundsLoaderV2.loadSitesForBounds].
///
/// The loader used to dedup by comparing coordinates to 6 decimal places
/// (~11cm). That only holds while a flown site's position is a byte-exact
/// copy of the catalog's - the moment a pilot repositions a site (supported
/// by edit_site_screen.dart) or the catalog regenerates around it, the two
/// markers split. `sites.catalog_ref` is the real link and does not
/// depend on coordinates staying in sync, so the loader now dedups by that
/// FK instead, falling back to coordinates only for a local site with no
/// link at all.
void main() {
  setUpAll(() async {
    await TestHelpers.initializeDatabaseForTesting();
  });

  setUp(() async {
    // Fresh schema per test: close and let the next `.database` access
    // recreate it, rather than truncating tables by hand.
    await DatabaseHelper.instance.close();
    await DatabaseHelper.instance.database;
    await PgeSitesDatabaseService.instance.initializeTables();
  });

  tearDown(() async {
    await DatabaseHelper.instance.close();
  });

  Future<String> insertCatalogSite({
    required String ref,
    required String name,
    required double latitude,
    required double longitude,
  }) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('pge_sites', {
      'ref': ref,
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'country': 'au',
    });
    return ref;
  }

  Future<int> insertFlownSite({
    required String name,
    required double latitude,
    required double longitude,
    String? catalogRef,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final siteId = await db.insert('sites', {
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'catalog_ref': catalogRef,
      'created_at': DateTime.now().toIso8601String(),
    });

    // A flight, not just a bare row - the loader marks a site "flown" via
    // flight_count from the JOIN, and hasFlights would otherwise be false
    // regardless of which dedup rule is under test.
    await db.insert('flights', {
      'date': '2026-08-08',
      'launch_time': '10:00',
      'landing_time': '11:00',
      'duration': 3600,
      'launch_site_id': siteId,
    });

    return siteId;
  }

  LatLngBounds boundsAround(double latitude, double longitude, {double pad = 1.0}) {
    return LatLngBounds(
      LatLng(latitude - pad, longitude - pad),
      LatLng(latitude + pad, longitude + pad),
    );
  }

  test(
      'dedups a flown site against its catalog entry even when coordinates '
      "don't match - reproduces Mt Bakewell: 'top launches' flown at PGE's "
      'old coordinates, relinked to a federated catalog entry whose '
      'coordinates moved', () async {
    // The federated catalog regenerated Mt Bakewell's coordinates away from
    // the pre-federation PGE export the flown site was originally created
    // from - the exact history behind the real bug.
    const catalogLat = -31.853, catalogLon = 116.761; // federated catalog
    const flownLat = -31.8528, flownLon = 116.763; // old PGE coordinates

    final catalogRef = await insertCatalogSite(
      ref: 'pge:9643',
      name: 'Mount Bakewell (top launches)',
      latitude: catalogLat,
      longitude: catalogLon,
    );
    await insertFlownSite(
      name: 'Mt Bakewell',
      latitude: flownLat,
      longitude: flownLon,
      catalogRef: catalogRef,
    );

    final result = await SiteBoundsLoaderV2.instance
        .loadSitesForBounds(boundsAround(catalogLat, catalogLon));

    final bakewellSites =
        result.sites.where((s) => s.name.contains('Bakewell')).toList();
    expect(bakewellSites, hasLength(1),
        reason: 'the flown site and its catalog entry are the same launch '
            'and must render as one marker, however far their coordinates '
            'have drifted apart');
    expect(bakewellSites.single.hasFlights, isTrue,
        reason: 'the surviving marker must be the flown one, not a PGE-only '
            'stand-in with a reset flight count');
  });

  test('keeps two distinct catalog launches that share coordinates',
      () async {
    // Regression for a second bug the coordinate-keyed loop had: it deduped
    // catalog entries against each other too, so any two real, separate
    // launches sharing a lat/lon collapsed into one marker.
    const lat = -31.848, lon = 116.777;
    await insertCatalogSite(
        ref: 'pge:11657',
        name: 'Mount Bakewell (lower launch)',
        latitude: lat,
        longitude: lon);
    await insertCatalogSite(
        ref: 'ansg:136-99',
        name: 'Some Other Launch',
        latitude: lat,
        longitude: lon);

    final result =
        await SiteBoundsLoaderV2.instance.loadSitesForBounds(boundsAround(lat, lon));

    // hasLength as well as containsAll: containsAll alone would pass if the
    // loader also emitted duplicates of them.
    expect(result.sites, hasLength(2));
    expect(result.sites.map((s) => s.name),
        containsAll(['Mount Bakewell (lower launch)', 'Some Other Launch']));
  });

  test('falls back to coordinates for a flown site with no catalog link',
      () async {
    // A local site whose catalog_ref is null (no match at import, or
    // cleared by _relinkToFederatedCatalog) has no FK to dedup by. The old
    // coordinate rule is the only signal left for this case, and must still
    // suppress the catalog entry it was originally copied from.
    const lat = -31.86, lon = 116.75;
    await insertCatalogSite(
        ref: 'pge:42', name: 'Unlinked Hill (catalog)', latitude: lat, longitude: lon);
    await insertFlownSite(
        name: 'Unlinked Hill', latitude: lat, longitude: lon, catalogRef: null);

    final result =
        await SiteBoundsLoaderV2.instance.loadSitesForBounds(boundsAround(lat, lon));

    final matches = result.sites.where((s) => s.name.contains('Unlinked Hill')).toList();
    expect(matches, hasLength(1),
        reason: 'an unlinked flown site still has coordinates matching its '
            'catalog origin, and should not show a duplicate marker');
    expect(matches.single.hasFlights, isTrue);
  });
}

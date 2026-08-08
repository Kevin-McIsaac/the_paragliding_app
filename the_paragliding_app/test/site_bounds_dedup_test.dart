import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:the_paragliding_app/data/datasources/database_helper.dart';
import 'package:the_paragliding_app/data/models/paragliding_site.dart';
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
/// markers split. `sites.catalog_site_id` is the real link and does not
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

  Future<int> insertCatalogSite({
    required int id,
    required String name,
    required double latitude,
    required double longitude,
  }) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('pge_sites', {
      'id': id,
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'country': 'au',
    });
    return id;
  }

  Future<int> insertFlownSite({
    required String name,
    required double latitude,
    required double longitude,
    int? catalogSiteId,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final siteId = await db.insert('sites', {
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'catalog_site_id': catalogSiteId,
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

    final catalogId = await insertCatalogSite(
      id: 9643,
      name: 'Mount Bakewell (top launches)',
      latitude: catalogLat,
      longitude: catalogLon,
    );
    await insertFlownSite(
      name: 'Mt Bakewell',
      latitude: flownLat,
      longitude: flownLon,
      catalogSiteId: catalogId,
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
        id: 11657, name: 'Mount Bakewell (lower launch)', latitude: lat, longitude: lon);
    await insertCatalogSite(
        id: 99999, name: 'Some Other Launch', latitude: lat, longitude: lon);

    final result =
        await SiteBoundsLoaderV2.instance.loadSitesForBounds(boundsAround(lat, lon));

    expect(result.sites.map((s) => s.name),
        containsAll(['Mount Bakewell (lower launch)', 'Some Other Launch']));
  });

  group('site identity', () {
    // nearby_sites_screen.dart keys _siteFlyabilityStatus and _siteFlightStatus
    // by siteKey, and nearby_sites_map.dart keys marker widgets by
    // ValueKey(site). Both assumed one site per coordinate - an invariant that
    // held only because the old loader deduped every coordinate collision
    // away. Now that two launches can legitimately share a point, they have to
    // be distinguishable or one silently takes on the other's wind verdict.
    ParaglidingSite siteAt({
      int? id,
      required String name,
      bool isFromLocalDb = false,
      double latitude = -31.848,
      double longitude = 116.777,
    }) =>
        ParaglidingSite(
          id: id,
          name: name,
          latitude: latitude,
          longitude: longitude,
          siteType: 'launch',
          isFromLocalDb: isFromLocalDb,
        );

    test('distinguishes two catalog launches sharing name and point', () {
      // Catalog ids 166 and 210: both named "Øksnanuten", both at
      // 58.7608,5.98167. Same name and same point is what the old
      // name-plus-coordinates equality could not tell apart - and there are
      // 23 shared-coordinate pairs in the bundled catalog.
      final first = siteAt(id: 166, name: 'Øksnanuten');
      final second = siteAt(id: 210, name: 'Øksnanuten');

      expect(first.siteKey, isNot(second.siteKey));
      expect(first, isNot(equals(second)),
          reason: 'marker widgets are keyed ValueKey(site); equal keys let '
              'Flutter reconcile one marker onto the other');

      // The concrete failure this prevents: a per-site map collapsing to one
      // entry, so the second site read back the first site's verdict.
      final flyability = {first.siteKey: 'S only', second.siteKey: 'E/SE/S'};
      expect(flyability, hasLength(2),
          reason: 'per-site state must not collapse for co-located sites');
    });

    test('separates local and catalog id spaces, which overlap', () {
      final flown = siteAt(id: 42, name: 'Flown', isFromLocalDb: true);
      final catalog = siteAt(id: 42, name: 'Catalog');

      expect(flown.siteKey, isNot(catalog.siteKey),
          reason: 'sites.id 42 and pge_sites.id 42 are unrelated rows');
    });

    test('falls back to coordinates when there is no id', () {
      final unsaved = siteAt(id: null, name: 'Unsaved API result');

      expect(unsaved.siteKey, 'coord:-31.848000,116.777000');
      expect(unsaved, equals(siteAt(id: null, name: 'Different name')),
          reason: 'without an id, coordinates are the only identity available');
    });
  });

  test('falls back to coordinates for a flown site with no catalog link',
      () async {
    // A local site whose catalog_site_id is null (no match at import, or
    // cleared by _relinkToFederatedCatalog) has no FK to dedup by. The old
    // coordinate rule is the only signal left for this case, and must still
    // suppress the catalog entry it was originally copied from.
    const lat = -31.86, lon = 116.75;
    await insertCatalogSite(
        id: 42, name: 'Unlinked Hill (catalog)', latitude: lat, longitude: lon);
    await insertFlownSite(
        name: 'Unlinked Hill', latitude: lat, longitude: lon, catalogSiteId: null);

    final result =
        await SiteBoundsLoaderV2.instance.loadSitesForBounds(boundsAround(lat, lon));

    final matches = result.sites.where((s) => s.name.contains('Unlinked Hill')).toList();
    expect(matches, hasLength(1),
        reason: 'an unlinked flown site still has coordinates matching its '
            'catalog origin, and should not show a duplicate marker');
    expect(matches.single.hasFlights, isTrue);
  });
}

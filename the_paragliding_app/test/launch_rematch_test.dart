import 'package:flutter_test/flutter_test.dart';
import 'package:the_paragliding_app/data/datasources/database_helper.dart';
import 'package:the_paragliding_app/services/database_service.dart';
import 'package:the_paragliding_app/services/launch_rematch_service.dart';
import 'package:the_paragliding_app/services/pge_sites_database_service.dart';
import 'package:the_paragliding_app/services/site_matching_service.dart';

import 'helpers/test_helpers.dart';

/// Covers moving already-imported flights onto the launch they actually left
/// from.
///
/// Built on the real Mt Borah geometry, because the spacing is the whole
/// point: the four launches sit 180m to 1km apart, inside the 500m radius at
/// which SiteMatchingService's flight-log tier stops looking. Coordinates are
/// the bundled catalogue's, and the takeoff fixes are real ones from a log
/// where all 17 flights had been collapsed onto the west launch.
void main() {
  // Catalogue rows (assets/data/world_sites_extracted.csv.gz).
  const west = (id: 9247, name: 'Manilla - Mt Borah - West launch', lat: -30.6792, lon: 150.6086);
  const northeast = (id: 11528, name: 'Manilla - Mt Borah - Northeast launch', lat: -30.6728, lon: 150.6156);
  const east = (id: 11526, name: 'Manilla - Mt Borah - East launch', lat: -30.6793, lon: 150.6116);

  setUpAll(() async {
    await TestHelpers.initializeDatabaseForTesting();
  });

  setUp(() async {
    await DatabaseHelper.instance.close();
    await DatabaseHelper.instance.database;
    await PgeSitesDatabaseService.instance.initializeTables();

    // The matcher is a singleton holding a cached site list, and apply()
    // reloads it. Without resetting it here a test inherits a cache built from
    // the *previous* test's now-discarded in-memory database, which made these
    // results order-dependent: one test passed only because a stale local
    // match pointed at a site id that no longer existed.
    await SiteMatchingService.instance.reload();
  });

  tearDown(() async {
    await DatabaseHelper.instance.close();
  });

  Future<void> insertCatalogSite(
      ({int id, String name, double lat, double lon}) site) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('pge_sites', {
      'id': site.id,
      'name': site.name,
      'latitude': site.lat,
      'longitude': site.lon,
      'altitude': 880,
      'country': 'au',
    });
  }

  /// A flown site, as an import would have left it: linked to [catalogSiteId]
  /// and sitting on that catalogue row's coordinates.
  Future<int> insertFlownSite(
    ({int id, String name, double lat, double lon}) site, {
    bool customName = false,
  }) async {
    final db = await DatabaseHelper.instance.database;
    return db.insert('sites', {
      'name': site.name,
      'latitude': site.lat,
      'longitude': site.lon,
      'catalog_site_id': site.id,
      'custom_name': customName ? 1 : 0,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<int> insertFlight({
    required int siteId,
    required double latitude,
    required double longitude,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final id = await db.insert('flights', {
      'date': '2026-08-08',
      'launch_time': '10:00',
      'landing_time': '11:00',
      'duration': 3600,
      'launch_site_id': siteId,
      'launch_latitude': latitude,
      'launch_longitude': longitude,
    });

    // The matcher's flight-log tier caches getSitesUsedInFlights(), so a site
    // only enters it once a flight references it. Without this reload the
    // whole preview runs catalogue-only and would pass with
    // _findNearestSiteLocal deleted - it would not be testing the comparison
    // these tests are named for.
    await SiteMatchingService.instance.reload();
    return id;
  }

  Future<void> insertAllBorahLaunches() async {
    await insertCatalogSite(west);
    await insertCatalogSite(northeast);
    await insertCatalogSite(east);
  }

  group('preview', () {
    test('proposes moving a flight that launched from a different launch',
        () async {
      await insertAllBorahLaunches();
      final westSiteId = await insertFlownSite(west);

      // Flight 47's real takeoff: 21m from the northeast launch, 996m from
      // west, where it had been recorded.
      final flightId = await insertFlight(
          siteId: westSiteId, latitude: -30.67262, longitude: 150.61567);

      final proposals = await LaunchRematchService.instance.preview();

      expect(proposals, hasLength(1));
      final proposal = proposals.single;
      expect(proposal.flightId, flightId);
      expect(proposal.toSite.id, northeast.id);
      expect(proposal.toDistanceMeters, lessThan(50));
      expect(proposal.fromDistanceMeters, greaterThan(900));
      expect(proposal.improvementMeters, greaterThan(900));
    });

    test('leaves a flight that is already on its nearest launch', () async {
      await insertAllBorahLaunches();
      final westSiteId = await insertFlownSite(west);

      // Flight 20's real takeoff: 15m from west, which is where it sits.
      await insertFlight(
          siteId: westSiteId, latitude: -30.67912, longitude: 150.60873);

      expect(await LaunchRematchService.instance.preview(), isEmpty);
    });

    test('resolves neighbours the 500m flight-log tier cannot', () async {
      await insertAllBorahLaunches();
      final westSiteId = await insertFlownSite(west);

      // Flight 49: 87m from east but 355m from west. Both are inside the 500m
      // radius at which findNearestSite stops at the already-flown west site,
      // which is exactly why this flight was misfiled.
      await insertFlight(
          siteId: westSiteId, latitude: -30.67878, longitude: 150.61228);

      final proposals = await LaunchRematchService.instance.preview();

      expect(proposals, hasLength(1));
      expect(proposals.single.toSite.id, east.id);
    });

    test('ignores a site the pilot named themselves', () async {
      await insertAllBorahLaunches();
      final siteId = await insertFlownSite(west, customName: true);
      await insertFlight(
          siteId: siteId, latitude: -30.67262, longitude: 150.61567);

      expect(await LaunchRematchService.instance.preview(), isEmpty,
          reason: 'a custom name is a deliberate choice and must not be '
              'overruled silently');
    });

    test('ignores a flight with no valid launch fix', () async {
      await insertAllBorahLaunches();
      final siteId = await insertFlownSite(west);
      await insertFlight(siteId: siteId, latitude: 0, longitude: 0);

      expect(await LaunchRematchService.instance.preview(), isEmpty,
          reason: 'no radius rescues Null Island; matching it would attach the '
              'flight to whatever happens to be nearest');
    });

    test('ignores an improvement below the threshold', () async {
      await insertAllBorahLaunches();
      final westSiteId = await insertFlownSite(west);

      // 60m east of the west pin: nearer to west anyway, and nowhere near
      // enough of an improvement elsewhere to justify rewriting the log.
      await insertFlight(
          siteId: westSiteId, latitude: -30.6792, longitude: 150.60922);

      expect(await LaunchRematchService.instance.preview(), isEmpty);
    });
  });

  group('apply', () {
    test('moves the flight and creates the launch it moved to', () async {
      await insertAllBorahLaunches();
      final westSiteId = await insertFlownSite(west);
      final flightId = await insertFlight(
          siteId: westSiteId, latitude: -30.67262, longitude: 150.61567);

      final proposals = await LaunchRematchService.instance.preview();
      final result = await LaunchRematchService.instance.apply(proposals);

      expect(result['success'], isTrue);
      expect(result['flights_moved'], 1);
      expect(result['sites_created'], 1);

      // Assert against the database, not the returned summary.
      final db = await DatabaseHelper.instance.database;
      final sites = await db.query('sites', where: 'catalog_site_id = ?', whereArgs: [northeast.id]);
      expect(sites, hasLength(1));
      expect(sites.single['name'], northeast.name);

      final flight = await DatabaseService.instance.getFlight(flightId);
      expect(flight!.launchSiteId, sites.single['id']);
    });

    test('creates one site for several flights on the same launch', () async {
      await insertAllBorahLaunches();
      final westSiteId = await insertFlownSite(west);
      // Flights 45, 47 and 17 - all real northeast takeoffs.
      await insertFlight(siteId: westSiteId, latitude: -30.67297, longitude: 150.61573);
      await insertFlight(siteId: westSiteId, latitude: -30.67262, longitude: 150.61567);
      await insertFlight(siteId: westSiteId, latitude: -30.67282, longitude: 150.6157);

      final result = await LaunchRematchService.instance
          .apply(await LaunchRematchService.instance.preview());

      expect(result['flights_moved'], 3);
      expect(result['sites_created'], 1,
          reason: 'three flights on one launch is one new site, not three');
    });

    test('reuses a launch that is already in the log book', () async {
      await insertAllBorahLaunches();
      final westSiteId = await insertFlownSite(west);
      final northeastSiteId = await insertFlownSite(northeast);
      final flightId = await insertFlight(
          siteId: westSiteId, latitude: -30.67262, longitude: 150.61567);

      final result = await LaunchRematchService.instance
          .apply(await LaunchRematchService.instance.preview());

      expect(result['sites_created'], 0);
      final flight = await DatabaseService.instance.getFlight(flightId);
      expect(flight!.launchSiteId, northeastSiteId);
    });

    test('reports a site left with no flights rather than deleting it',
        () async {
      await insertAllBorahLaunches();
      final westSiteId = await insertFlownSite(west);
      await insertFlight(
          siteId: westSiteId, latitude: -30.67262, longitude: 150.61567);

      final result = await LaunchRematchService.instance
          .apply(await LaunchRematchService.instance.preview());

      expect(result['sites_left_empty'], contains(west.name));

      final db = await DatabaseHelper.instance.database;
      final remaining =
          await db.query('sites', where: 'id = ?', whereArgs: [westSiteId]);
      expect(remaining, hasLength(1),
          reason: 'an empty site may be favourited, and is recoverable where '
              'a deleted one is not');
    });

    test('writes nothing when there is nothing to do', () async {
      await insertAllBorahLaunches();
      final westSiteId = await insertFlownSite(west);
      await insertFlight(
          siteId: westSiteId, latitude: -30.67912, longitude: 150.60873);

      final result = await LaunchRematchService.instance.apply([]);

      expect(result['flights_moved'], 0);
      final db = await DatabaseHelper.instance.database;
      expect(await db.query('sites'), hasLength(1));
    });
  });
}

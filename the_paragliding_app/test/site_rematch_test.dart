import 'package:flutter_test/flutter_test.dart';
import 'package:the_paragliding_app/data/datasources/database_helper.dart';
import 'package:the_paragliding_app/services/paragliding_earth_api.dart';
import 'package:the_paragliding_app/services/pge_sites_database_service.dart';
import 'package:the_paragliding_app/services/site_matching_service.dart';
import 'package:the_paragliding_app/utils/database_reset_helper.dart';
import 'helpers/test_helpers.dart';

/// A launch and the PGE pin for it, ~600m apart - inside the local search
/// radius but outside the 500m the API is asked for.
const launchLat = 47.09675;
const launchLon = 11.323366;
const pinLat = 47.1019;
const pinLon = 11.3243;

Future<void> seedPgeSite(String name) async {
  final db = await DatabaseHelper.instance.database;
  await PgeSitesDatabaseService.instance.initializeTables();
  await db.insert('pge_sites', {
    'id': 9001,
    'name': name,
    'latitude': pinLat,
    'longitude': pinLon,
    'altitude': 2000,
    'country': 'at',
  });
}

Future<int> insertUnknownSiteWithFlight({
  String name = 'Unknown 1',
  double? latitude,
  double? longitude,
}) async {
  final lat = latitude ?? launchLat;
  final lon = longitude ?? launchLon;
  final db = await DatabaseHelper.instance.database;
  final siteId = await db.insert('sites', {
    'name': name,
    'latitude': lat,
    'longitude': lon,
  });
  await db.insert('flights', {
    'date': '2026-01-01',
    'launch_time': '10:00',
    'landing_time': '11:00',
    'duration': 60,
    'launch_site_id': siteId,
    'launch_latitude': lat,
    'launch_longitude': lon,
  });
  return siteId;
}

void main() {
  setUpAll(() async {
    await TestHelpers.initializeDatabaseForTesting();
  });

  setUp(() async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('flights');
    await db.delete('sites');
    await PgeSitesDatabaseService.instance.initializeTables();
    await db.delete('pge_sites');
    // Offline: these tests must never depend on the network
    SiteMatchingService.instance.setApiEnabled(false);
    await SiteMatchingService.instance.reload();
  });

  tearDown(() {
    SiteMatchingService.instance.setApiEnabled(true);
    ParaglidingEarthApi.debugSetOfflineMode(offline: false);
  });

  group('local-first site matching', () {
    test('matches a site that exists only in the local PGE database', () async {
      await seedPgeSite('Neustift - Elfer');

      final match = await SiteMatchingService.instance.findNearestSite(
        launchLat,
        launchLon,
        maxDistance: SiteMatchingService.localSiteSearchRadius,
      );

      expect(match, isNotNull);
      expect(match!.name, 'Neustift - Elfer');
    });

    test('returns null when the nearest local site is too far away', () async {
      await seedPgeSite('Somewhere Else');
      final db = await DatabaseHelper.instance.database;
      await db.update('pge_sites', {'latitude': pinLat + 0.5}); // ~55km north

      final match = await SiteMatchingService.instance.findNearestSite(
        launchLat,
        launchLon,
      );

      expect(match, isNull);
    });
  });

  group('rematchUnknownSites', () {
    test('gives the flight its real site name', () async {
      await seedPgeSite('Neustift - Elfer');
      await insertUnknownSiteWithFlight();

      final result = await DatabaseResetHelper.rematchUnknownSites();

      expect(result['success'], isTrue);
      expect(result['sites_matched'], 1);
      expect(result['flights_moved'], 1);

      final db = await DatabaseHelper.instance.database;
      final flights = await db.rawQuery(
          'SELECT s.name FROM flights f JOIN sites s ON f.launch_site_id = s.id');
      expect(flights.single['name'], 'Neustift - Elfer');
      expect(await db.query('sites', where: "name LIKE 'Unknown%'"), isEmpty);
    });

    test('merges into the real site when it already exists', () async {
      await seedPgeSite('Neustift - Elfer');
      final db = await DatabaseHelper.instance.database;
      final realId = await db.insert('sites', {
        'name': 'Neustift - Elfer',
        'latitude': pinLat,
        'longitude': pinLon,
        'catalog_site_id': 9001,
      });
      final unknownId = await insertUnknownSiteWithFlight();

      final result = await DatabaseResetHelper.rematchUnknownSites();

      expect(result['sites_matched'], 1);
      expect(result['flights_moved'], 1);
      expect(await db.query('sites', where: 'id = ?', whereArgs: [unknownId]),
          isEmpty,
          reason: 'the emptied Unknown row should be removed, not duplicated');

      final flights = await db.query('flights');
      expect(flights.single['launch_site_id'], realId);
    });

    test('leaves flights alone when no site is nearby', () async {
      final unknownId = await insertUnknownSiteWithFlight();

      final result = await DatabaseResetHelper.rematchUnknownSites();

      expect(result['success'], isTrue);
      expect(result['sites_matched'], 0);

      final db = await DatabaseHelper.instance.database;
      expect(await db.query('sites', where: 'id = ?', whereArgs: [unknownId]),
          hasLength(1));
    });

    test('skips a launch recorded at 0,0', () async {
      await seedPgeSite('Neustift - Elfer');
      final db = await DatabaseHelper.instance.database;
      final siteId = await db.insert('sites', {
        'name': 'Unknown 1',
        'latitude': 0.0,
        'longitude': 0.0,
      });

      final result = await DatabaseResetHelper.rematchUnknownSites();

      expect(result['sites_matched'], 0);
      expect(await db.query('sites', where: 'id = ?', whereArgs: [siteId]),
          hasLength(1));
    });

    // The tests above populate the matching cache in setUp, *before* inserting
    // their Unknown rows, so the cache never contains a placeholder. The real
    // app runs a long-lived singleton that has every existing Unknown site
    // cached, which is the state these two reproduce.

    test('does not match an Unknown site against itself', () async {
      final siteId = await insertUnknownSiteWithFlight();
      // Cache loaded AFTER the row exists - as in the running app
      await SiteMatchingService.instance.reload();

      final result = await DatabaseResetHelper.rematchUnknownSites();

      expect(result['sites_matched'], 0,
          reason: 'a placeholder is not a real identity to match against');

      final db = await DatabaseHelper.instance.database;
      final site = (await db.query('sites', where: 'id = ?', whereArgs: [siteId])).single;
      expect(site['name'], 'Unknown 1');
      expect(site['catalog_site_id'], isNull,
          reason: 'a flight-log row id must never be written as a PGE site id');
    });

    test('does not merge one Unknown site into another', () async {
      // Unknown 2 is cached; Unknown 1 is created afterwards, so the cache is
      // stale in exactly the way a mid-session import leaves it.
      final farId = await insertUnknownSiteWithFlight(
        name: 'Unknown 2',
        latitude: launchLat + 0.009, // ~1km away, inside the 2km search radius
      );
      await SiteMatchingService.instance.reload();
      final nearId = await insertUnknownSiteWithFlight();

      await DatabaseResetHelper.rematchUnknownSites();

      final db = await DatabaseHelper.instance.database;
      expect(await db.query('sites', where: 'id = ?', whereArgs: [nearId]),
          hasLength(1),
          reason: 'two distinct launches must not be commingled');
      expect(await db.query('sites', where: 'id = ?', whereArgs: [farId]),
          hasLength(1));

      final near = await db.query('flights', where: 'launch_site_id = ?', whereArgs: [nearId]);
      final far = await db.query('flights', where: 'launch_site_id = ?', whereArgs: [farId]);
      expect(near, hasLength(1), reason: 'each site keeps its own flight');
      expect(far, hasLength(1));
    });

    test('reports nothing to do on a clean log', () async {
      final result = await DatabaseResetHelper.rematchUnknownSites();

      expect(result['success'], isTrue);
      expect(result['sites_checked'], 0);
    });
  });

  group('API offline breaker', () {
    test('skips requests while the cooldown is running', () {
      ParaglidingEarthApi.debugSetOfflineMode(
          offline: true, enteredAt: DateTime.now());

      expect(ParaglidingEarthApi.debugShouldSkipRequest(), isTrue);
    });

    test('lets a request through once the cooldown has elapsed', () {
      ParaglidingEarthApi.debugSetOfflineMode(
        offline: true,
        enteredAt: DateTime.now()
            .subtract(ParaglidingEarthApi.offlineModeCooldown * 2),
      );

      expect(ParaglidingEarthApi.debugShouldSkipRequest(), isFalse,
          reason: 'the breaker must reopen - it used to latch for the session');
    });

    test('does not skip when online', () {
      ParaglidingEarthApi.debugSetOfflineMode(offline: false);

      expect(ParaglidingEarthApi.debugShouldSkipRequest(), isFalse);
    });
  });
}

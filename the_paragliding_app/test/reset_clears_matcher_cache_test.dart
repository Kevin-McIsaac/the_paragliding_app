import 'package:flutter_test/flutter_test.dart';
import 'package:the_paragliding_app/data/datasources/database_helper.dart';
import 'package:the_paragliding_app/data/models/site.dart';
import 'package:the_paragliding_app/services/database_service.dart';
import 'package:the_paragliding_app/services/site_matching_service.dart';
import 'package:the_paragliding_app/utils/database_reset_helper.dart';

import 'helpers/test_helpers.dart';

/// Covers wiping the database also clearing the matcher's in-memory cache.
///
/// [SiteMatchingService] caches the flight log, and deleting rows does not
/// touch that cache. The flight-log tier is consulted first, so a stale cache
/// keeps answering with sites that no longer exist: a recreate-from-IGC run
/// then names its sites after the database it just deleted. Observed in a real
/// run - the first flight of a "fresh" import matched "Stanwell Park" at 10m,
/// a name only the old database held, while the catalogue query beside it
/// correctly returned the two rows that were actually there.
///
/// **The API is disabled throughout.** Without that these tests pass for the
/// wrong reason: after the reset the network tier answers with a PGE name that
/// also is not the catalogue's, so the assertion goes green while the stale
/// cache is still there. That mistake sent an earlier round of this
/// investigation down the wrong path entirely.
void main() {
  const borahWest = (lat: -30.6792, lon: 150.6086);

  late bool apiWasEnabled;

  setUpAll(() async {
    await TestHelpers.initializeDatabaseForTesting();
  });

  setUp(() async {
    await DatabaseHelper.instance.close();
    await DatabaseHelper.instance.database;
    apiWasEnabled = SiteMatchingService.instance.isApiEnabled;
    SiteMatchingService.instance.setApiEnabled(false);
    await SiteMatchingService.instance.reload();
  });

  tearDown(() async {
    SiteMatchingService.instance.setApiEnabled(apiWasEnabled);
    await DatabaseHelper.instance.close();
  });

  /// Seed a flown site under a name the catalogue does not use, and get it
  /// into the matcher's cache the way an import would.
  Future<void> seedStaleSite() async {
    final siteId = await DatabaseService.instance.insertSite(Site(
      name: 'Manilla, Mt Borah (NSW)',
      latitude: borahWest.lat,
      longitude: borahWest.lon,
    ));

    final db = await DatabaseHelper.instance.database;
    await db.insert('flights', {
      'date': '2026-08-09',
      'launch_time': '10:00',
      'landing_time': '11:00',
      'duration': 3600,
      'launch_site_id': siteId,
      'launch_latitude': borahWest.lat,
      'launch_longitude': borahWest.lon,
    });

    await SiteMatchingService.instance.reload();

    // Guard the fixture: if the matcher cannot see it, the assertions below
    // prove nothing.
    final cached = await SiteMatchingService.instance
        .findNearestSite(borahWest.lat, borahWest.lon, preferredType: 'launch');
    expect(cached?.name, 'Manilla, Mt Borah (NSW)',
        reason: 'the stale site must be in the cache before it can go stale');
  }

  test('resetDatabase drops the cached flight log', () async {
    await seedStaleSite();

    await DatabaseResetHelper.resetDatabase();

    final match = await SiteMatchingService.instance
        .findNearestSite(borahWest.lat, borahWest.lon, preferredType: 'launch');

    expect(match, isNull,
        reason: 'the site was deleted, and with the API off there is nothing '
            'else to match - a hit here is the cache still answering, which '
            'names fresh imports after a database that no longer exists');
  });

  test('deleteFlightDataOnly drops the cached flight log', () async {
    await seedStaleSite();

    await DatabaseResetHelper.deleteFlightDataOnly();

    final match = await SiteMatchingService.instance
        .findNearestSite(borahWest.lat, borahWest.lon, preferredType: 'launch');

    expect(match, isNull);
  });
}

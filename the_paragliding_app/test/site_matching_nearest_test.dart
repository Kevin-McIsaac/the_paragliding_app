import 'package:flutter_test/flutter_test.dart';
import 'package:the_paragliding_app/data/datasources/database_helper.dart';
import 'package:the_paragliding_app/data/models/site.dart';
import 'package:the_paragliding_app/services/database_service.dart';
import 'package:the_paragliding_app/services/pge_sites_database_service.dart';
import 'package:the_paragliding_app/services/site_matching_service.dart';

import 'helpers/test_helpers.dart';

/// Covers [SiteMatchingService.findNearestSite] choosing the genuinely nearest
/// launch across both local sources.
///
/// The flight log used to short-circuit: any flown site within maxDistance
/// (500m by default) was returned without the catalogue being consulted. That
/// held while the catalogue had one pin per hill, but the federated catalogue
/// resolves individual launches. Mt Borah's four sit 180m to 1km apart, so a
/// flown site captured takeoffs from its neighbours - 17 flights across four
/// launches all landed on the west one.
///
/// Coordinates are the bundled catalogue's real values.
void main() {
  const west = (id: 9247, name: 'Manilla - Mt Borah - West launch', lat: -30.6792, lon: 150.6086);
  const east = (id: 11526, name: 'Manilla - Mt Borah - East launch', lat: -30.6793, lon: 150.6116);
  const northeast = (id: 11528, name: 'Manilla - Mt Borah - Northeast launch', lat: -30.6728, lon: 150.6156);

  setUpAll(() async {
    await TestHelpers.initializeDatabaseForTesting();
  });

  setUp(() async {
    await DatabaseHelper.instance.close();
    await DatabaseHelper.instance.database;
    await PgeSitesDatabaseService.instance.initializeTables();
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

  /// A flown site as an import leaves it: on the catalogue row's coordinates,
  /// linked to it, and with a flight attached.
  ///
  /// The flight matters - the matcher caches `getSitesUsedInFlights()`, so a
  /// site with no flights is invisible to it and the test would be measuring
  /// an empty cache rather than the tier it means to.
  Future<int> insertFlownSite(
      ({int id, String name, double lat, double lon}) site) async {
    final id = await DatabaseService.instance.insertSite(Site(
      name: site.name,
      latitude: site.lat,
      longitude: site.lon,
      catalogRef: 'pge:${site.id}',
    ));

    final db = await DatabaseHelper.instance.database;
    await db.insert('flights', {
      'date': '2026-08-08',
      'launch_time': '10:00',
      'landing_time': '11:00',
      'duration': 3600,
      'launch_site_id': id,
      'launch_latitude': site.lat,
      'launch_longitude': site.lon,
    });

    // The matcher reads a cached site list, so it has to be rebuilt after
    // inserting - exactly as the import path does.
    await SiteMatchingService.instance.reload();
    return id;
  }

  test('prefers a catalogue launch that is materially closer than a flown site',
      () async {
    await insertCatalogSite(west);
    await insertCatalogSite(east);
    await insertFlownSite(west);

    // Flight 49's real takeoff: 87m from east, 355m from west. Both are inside
    // the 500m radius where the flight log used to win outright.
    final match = await SiteMatchingService.instance
        .findNearestSite(-30.67878, 150.61228, preferredType: 'launch');

    expect(match, isNotNull);
    expect(match!.name, east.name,
        reason: 'east is 268m closer; the flown west site must not short-circuit');
  });

  test('keeps the flown site when it is the nearest launch', () async {
    await insertCatalogSite(west);
    await insertCatalogSite(east);
    final westSiteId = await insertFlownSite(west);

    // Flight 20's real takeoff: 15m from west.
    final match = await SiteMatchingService.instance
        .findNearestSite(-30.67912, 150.60873, preferredType: 'launch');

    expect(match, isNotNull);
    expect(match!.isFromLocalDb, isTrue,
        reason: 'the pilot\'s own site wins when it is genuinely nearest');
    expect(match.id, westSiteId);
  });

  test('keeps the flown site when the catalogue is only marginally closer',
      () async {
    await insertCatalogSite(west);
    await insertCatalogSite(east);
    await insertFlownSite(west);

    // Midway-ish: east is nearer, but by less than the override margin, so the
    // pilot's own site (and their name for it) must not flip on GPS scatter.
    const margin = SiteMatchingService.catalogueOverrideMarginMeters;
    expect(margin, 100);

    final match = await SiteMatchingService.instance
        .findNearestSite(-30.67925, 150.61026, preferredType: 'launch');

    expect(match, isNotNull);
    expect(match!.isFromLocalDb, isTrue,
        reason: 'below the $margin m margin the flown site is kept');
  });

  test('finds a launch the pilot has never flown', () async {
    await insertCatalogSite(west);
    await insertCatalogSite(northeast);
    await insertFlownSite(west);

    // Flight 47: 21m from northeast, 996m from west. Northeast has no flown
    // site at all, so only the catalogue can supply it.
    final match = await SiteMatchingService.instance
        .findNearestSite(-30.67262, 150.61567, preferredType: 'launch');

    expect(match, isNotNull);
    expect(match!.name, northeast.name);
    expect(match.isFromLocalDb, isFalse);
  });

  test('falls back to the catalogue when nothing has been flown', () async {
    await insertCatalogSite(west);

    final match = await SiteMatchingService.instance
        .findNearestSite(-30.67912, 150.60873, preferredType: 'launch');

    expect(match, isNotNull);
    expect(match!.name, west.name);
  });

  /// A landing 300m from the launch, which is closer than any real landing
  /// gets: measured over DHV the median launch-to-landing gap is 1.7km, so
  /// this is a deliberately hostile case, well inside the 2km the catalogue
  /// tier searches.
  Future<void> insertCatalogLanding(
      ({int id, String name, double lat, double lon}) at) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('pge_sites', {
      'id': at.id,
      'ref': 'pge:${at.id}-lz',
      'name': '${at.name} Landing',
      'latitude': at.lat,
      'longitude': at.lon,
      'altitude': 300,
      'country': 'au',
      'site_type': 'landing',
    });
  }

  group('landings never capture a launch', () {
    test('the nearest row wins only among launches', () async {
      await insertCatalogSite(west);
      // 300m north of the west launch - nearer to the takeoff fix below than
      // the launch itself.
      await insertCatalogLanding((
        id: 99001,
        name: 'Manilla - Mt Borah',
        lat: west.lat + 0.0027,
        lon: west.lon,
      ));

      final match = await SiteMatchingService.instance.findNearestSite(
        west.lat + 0.0025,
        west.lon,
        maxDistance: 2000,
        preferredType: 'launch',
      );

      expect(match, isNotNull);
      expect(match!.name, west.name,
          reason: 'a landing must never be offered as a launch, however close');
    });

    test('a catalogue with no site_type column still matches', () async {
      // Rows imported before the producer emitted site_type read as null, and
      // they are all launches. Filtering on the column alone would hide the
      // entire catalogue from an app that had not refreshed yet.
      await insertCatalogSite(west);

      final match = await SiteMatchingService.instance.findNearestSite(
        west.lat,
        west.lon,
        maxDistance: 500,
        preferredType: 'launch',
      );

      expect(match?.name, west.name);
    });
  });
}


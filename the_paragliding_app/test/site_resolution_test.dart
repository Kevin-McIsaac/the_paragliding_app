import 'package:flutter_test/flutter_test.dart';
import 'package:the_paragliding_app/data/datasources/database_helper.dart';
import 'package:the_paragliding_app/data/models/site.dart';
import 'package:the_paragliding_app/services/database_service.dart';

import 'helpers/test_helpers.dart';

/// Covers [DatabaseService.findOrCreateSite] resolving to the right site row.
///
/// This is the step that decides which row a flight is actually attached to,
/// and it used to defeat the matcher entirely: its first act was a coordinate
/// lookup with a 0.01 degree (~1.1km) tolerance returning the first row found.
/// Mt Borah's launches are 180m-1km apart, so a correctly matched east launch
/// came straight back as the *west* site row and the flight was filed there.
///
/// Coordinates are the bundled catalogue's real values.
void main() {
  const west = (ref: 'pge:4632', name: 'Manilla - Mt Borah - West launch', lat: -30.6792, lon: 150.6086);
  const east = (ref: 'ansg:136-21', name: 'Manilla - Mt Borah - East launch', lat: -30.6793, lon: 150.6116);

  setUpAll(() async {
    await TestHelpers.initializeDatabaseForTesting();
  });

  setUp(() async {
    await DatabaseHelper.instance.close();
    await DatabaseHelper.instance.database;
  });

  tearDown(() async {
    await DatabaseHelper.instance.close();
  });

  Future<int> insertSite(
    ({String ref, String name, double lat, double lon}) site, {
    String? catalogRef,
  }) {
    return DatabaseService.instance.insertSite(Site(
      name: site.name,
      latitude: site.lat,
      longitude: site.lon,
      catalogRef: catalogRef ?? site.ref,
    ));
  }

  test('does not collapse a neighbouring launch onto an existing site',
      () async {
    final westSiteId = await insertSite(west);

    // 287m away - the case that used to return the west row, because 287m is
    // well inside the old ~1.1km tolerance.
    final resolved = await DatabaseService.instance.findOrCreateSite(
      latitude: east.lat,
      longitude: east.lon,
      name: east.name,
      catalogRef: east.ref,
    );

    expect(resolved.id, isNot(westSiteId));
    expect(resolved.name, east.name);
    expect(resolved.catalogRef, east.ref);
  });

  test('reuses the site already linked to that catalogue launch', () async {
    final westSiteId = await insertSite(west);

    // Same launch, but a takeoff fix 60m off the pin. Identity should win, so
    // no second row for a launch the pilot already has.
    final resolved = await DatabaseService.instance.findOrCreateSite(
      latitude: west.lat + 0.0005,
      longitude: west.lon,
      name: west.name,
      catalogRef: west.ref,
    );

    expect(resolved.id, westSiteId);
    final db = await DatabaseHelper.instance.database;
    expect(await db.query('sites'), hasLength(1));
  });

  test('reuses a nearby unlinked site rather than duplicating it', () async {
    // A row from an older import, with no catalogue link - the coordinate
    // fallback is the only thing that can find it.
    final unlinkedId = await DatabaseService.instance.insertSite(Site(
      name: 'Mt Borah',
      latitude: west.lat,
      longitude: west.lon,
    ));

    final resolved = await DatabaseService.instance.findOrCreateSite(
      latitude: west.lat,
      longitude: west.lon,
      name: west.name,
      catalogRef: west.ref,
    );

    expect(resolved.id, unlinkedId);
    final db = await DatabaseHelper.instance.database;
    expect(await db.query('sites'), hasLength(1),
        reason: 'a second row here would show as a duplicate map pin, since '
            'marker dedup keys on catalog_ref');
  });

  test('picks the nearest when two sites are inside the radius', () async {
    // 50m and 90m from the query point; first-found would be arbitrary.
    final nearId = await DatabaseService.instance.insertSite(Site(
      name: 'Near', latitude: west.lat + 0.00045, longitude: west.lon));
    await DatabaseService.instance.insertSite(Site(
      name: 'Far', latitude: west.lat - 0.00081, longitude: west.lon));

    final resolved = await DatabaseService.instance
        .findOrCreateSite(latitude: west.lat, longitude: west.lon);

    expect(resolved.id, nearId);
  });

  test('creates a site when nothing is near', () async {
    await insertSite(west);

    final resolved = await DatabaseService.instance.findOrCreateSite(
      latitude: -31.853,
      longitude: 116.761,
      name: 'Mount Bakewell (top launches)',
      catalogRef: 'pge:9643',
    );

    expect(resolved.name, 'Mount Bakewell (top launches)');
    final db = await DatabaseHelper.instance.database;
    expect(await db.query('sites'), hasLength(2));
  });
}

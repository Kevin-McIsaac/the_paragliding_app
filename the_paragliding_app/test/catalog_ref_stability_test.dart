import 'package:flutter_test/flutter_test.dart';
import 'package:the_paragliding_app/data/datasources/database_helper.dart';
import 'package:the_paragliding_app/services/database_service.dart';
import 'package:the_paragliding_app/services/pge_sites_database_service.dart';

import 'helpers/test_helpers.dart';

/// A regenerated catalogue must not move a flown site to another launch.
///
/// This began as a probe of the opposite. The catalogue was keyed on a dense row
/// number that tracked its producer's file order, so one upstream insertion
/// shifted every id after it - and the relink that could have followed them ran
/// only on the federated changeover and early-returned forever after. Measured
/// against the real import path: a flown Mt Borah site kept id 17, which now
/// named a launch 800km away, and rendered alt 380m for 800m, wind [N] for [W],
/// the wrong guide's tab, and moved the pilot's favourite with it.
///
/// These now assert the fix - rows keyed on the contributing guide's own id, so
/// a rebuild that renumbers every row changes nothing a pilot can see. Revert
/// the v5 migration or the upsert in importSitesData and they go red again.
void main() {
  late dynamic db;

  // What the device imported first.
  List<Map<String, dynamic>> catalogueA() => [
        {
          'id': 17, 'name': 'Manilla - Mt Borah - West launch',
          'longitude': 150.6086, 'latitude': -30.6792, 'altitude': 800,
          'country': 'au', 'source': 'pge:4632;siteguide_au:136-40',
          'wind_w': 2,
        },
        {
          'id': 18, 'name': 'Bright - Mystic', 'longitude': 146.97,
          'latitude': -36.72, 'altitude': 380, 'country': 'au',
          'source': 'pge:5000', 'wind_n': 2,
        },
      ];

  /// The same two launches, regenerated after an upstream guide added a site
  /// earlier in the file. Every positional id has shifted; nothing about either
  /// launch has changed. This is the routine event the design has to absorb.
  List<Map<String, dynamic>> catalogueB() => [
        {
          'id': 17, 'name': 'Bright - Mystic', 'longitude': 146.97,
          'latitude': -36.72, 'altitude': 380, 'country': 'au',
          'source': 'pge:5000', 'wind_n': 2,
        },
        {
          'id': 18, 'name': 'Manilla - Mt Borah - West launch',
          'longitude': 150.6086, 'latitude': -30.6792, 'altitude': 800,
          'country': 'au', 'source': 'pge:4632;siteguide_au:136-40',
          'wind_w': 2,
        },
      ];

  setUp(() async {
    await TestHelpers.initializeDatabaseForTesting();
    await DatabaseHelper.instance.recreateDatabase();
    db = await DatabaseHelper.instance.database;
    await PgeSitesDatabaseService.instance.initializeTables();

    await db.insert('pge_sites', {
      'ref': 'pge:4632', 'name': 'Manilla, Mt Borah',
      'longitude': 150.6, 'latitude': -30.7, 'is_favorite': 1,
    });
    await db.insert('sites', {
      'id': 1, 'name': 'Mt Borah', 'latitude': -30.6792, 'longitude': 150.6086,
      'catalog_ref': 'pge:4632', 'created_at': DateTime.now().toIso8601String(),
    });
  });

  test('an import leaves the flown site on its own launch', () async {
    await PgeSitesDatabaseService.instance.importSitesData(rows: catalogueA());

    final site = (await db.query('sites', where: 'id = 1')).single;
    expect(site['catalog_ref'], 'pge:4632');
  });

  test('a regenerated catalogue does not repoint the flown site', () async {
    await PgeSitesDatabaseService.instance.importSitesData(rows: catalogueA());
    // Weeks later: sources changed, catalogue rebuilt, positional ids shifted.
    await PgeSitesDatabaseService.instance.importSitesData(rows: catalogueB());

    final site = (await db.query('sites', where: 'id = 1')).single;
    final pointsAt = (await db.query('pge_sites',
            where: 'ref = ?', whereArgs: [site['catalog_ref']]))
        .single;

    expect(site['catalog_ref'], 'pge:4632',
        reason: "the link is the guide's own id, so a rebuild cannot move it");
    expect(pointsAt['name'], 'Manilla - Mt Borah - West launch');
  });

  test("the production read path shows this launch's own guide data", () async {
    await PgeSitesDatabaseService.instance.importSitesData(rows: catalogueA());
    await PgeSitesDatabaseService.instance.importSitesData(rows: catalogueB());

    // The same JOIN the map and the site sheet use.
    final sites = await DatabaseService.instance.getLocalSitesWithPgeDataInBounds(
      north: -30.0, south: -31.0, east: 151.0, west: 150.0,
    );
    final borah = sites.firstWhere((s) => s.name == 'Mt Borah');

    expect(borah.altitude, 800, reason: 'Mt Borah is at 800m, Mystic at 380m');
    expect(borah.windDirections, ['W'], reason: 'Borah west launch faces W');
    expect(borah.sources.map((s) => s.provider), contains('siteguide_au'),
        reason: 'both guides describing this launch should still be listed');
  });

  test('favourites stay on the launch across a regeneration', () async {
    // This is the path production actually takes on every refresh - the pilot's
    // device is long past any one-time migration. The favourite is never deleted
    // and re-applied now; the upsert leaves the column alone.
    await PgeSitesDatabaseService.instance.importSitesData(rows: catalogueA());
    await PgeSitesDatabaseService.instance.importSitesData(rows: catalogueB());

    final favourites = await db.query('pge_sites', where: 'is_favorite = 1');
    expect(favourites.map((r) => r['name']),
        ['Manilla - Mt Borah - West launch']);
  });

  test('a withdrawn entry leaves the link dangling, and it self-heals',
      () async {
    await PgeSitesDatabaseService.instance.importSitesData(rows: catalogueA());

    // Mt Borah drops out of the catalogue entirely for one build.
    await PgeSitesDatabaseService.instance.importSitesData(
      rows: [catalogueB().first],
    );

    var site = (await db.query('sites', where: 'id = 1')).single;
    expect(site['catalog_ref'], 'pge:4632',
        reason: 'the link is kept, not cleared - refs are never reused, so a '
            'dangling one is safe and can come back');

    var sites = await DatabaseService.instance.getLocalSitesWithPgeDataInBounds(
      north: -30.0, south: -31.0, east: 151.0, west: 150.0,
    );
    expect(sites.firstWhere((s) => s.name == 'Mt Borah').altitude, isNull,
        reason: 'no guide describes it, so there is no enrichment to show');

    // The guide restores it. Nothing asks the pilot to repair anything.
    await PgeSitesDatabaseService.instance.importSitesData(rows: catalogueB());

    sites = await DatabaseService.instance.getLocalSitesWithPgeDataInBounds(
      north: -30.0, south: -31.0, east: 151.0, west: 150.0,
    );
    expect(sites.firstWhere((s) => s.name == 'Mt Borah').altitude, 800);
  });
}

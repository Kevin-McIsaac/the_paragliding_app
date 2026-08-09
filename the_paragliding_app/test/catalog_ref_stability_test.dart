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
          'country': 'au', 'source': 'pge:4632;ansg:136-40',
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
          'country': 'au', 'source': 'pge:4632;ansg:136-40',
          'wind_w': 2,
        },
      ];

  /// A launch only the Australian guide describes, alongside the two above so
  /// the fixtures in setUp are not disturbed.
  List<Map<String, dynamic>> catalogueAnsgOnly() => [
        ...catalogueA(),
        {
          'id': 19, 'name': 'Corryong - Mt Elliot', 'longitude': 147.9,
          'latitude': -36.19, 'altitude': 500, 'country': 'au',
          'source': 'ansg:106-28', 'wind_n': 2,
        },
      ];

  /// The same launch after ParaglidingEarth starts describing it too. The
  /// producer emits a second, higher-precedence token; nothing about the launch
  /// itself has changed.
  List<Map<String, dynamic>> catalogueAnsgPlusPge() => [
        ...catalogueA(),
        {
          'id': 19, 'name': 'Corryong - Mt Elliot', 'longitude': 147.9,
          'latitude': -36.19, 'altitude': 500, 'country': 'au',
          'source': 'ansg:106-28;pge:7001', 'wind_n': 2,
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
    expect(borah.sources.map((s) => s.provider), contains('ansg'),
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

  test('a launch that gains a higher-precedence guide keeps its key', () async {
    // CatalogRef.fromSource returns the *highest-precedence* token, so deriving
    // the key afresh on every import renamed a row the day a second guide began
    // describing it - ansg:106-28 becoming pge:7001. A rename is a delete plus
    // an insert: the favourite went with the deleted row, and the flown site's
    // link pointed at a key the producer will never emit again, so unlike a
    // withdrawal it could not self-heal. Drop the `held` lookup in
    // importSitesData and this goes red.
    await PgeSitesDatabaseService.instance.importSitesData(
        rows: catalogueAnsgOnly());
    await db.update('pge_sites', {'is_favorite': 1},
        where: 'ref = ?', whereArgs: ['ansg:106-28']);
    await db.insert('sites', {
      'id': 2, 'name': 'Corryong', 'latitude': -36.19, 'longitude': 147.9,
      'catalog_ref': 'ansg:106-28',
      'created_at': DateTime.now().toIso8601String(),
    });

    await PgeSitesDatabaseService.instance.importSitesData(
        rows: catalogueAnsgPlusPge());

    final site = (await db.query('sites', where: 'id = 2')).single;
    expect(site['catalog_ref'], 'ansg:106-28',
        reason: 'a row already keyed is not re-keyed by precedence');

    final kept = (await db.query('pge_sites',
            where: 'ref = ?', whereArgs: ['ansg:106-28']))
        .single;
    expect(kept['is_favorite'], 1, reason: 'the favourite must survive');
    expect(
        await db.query('pge_sites', where: 'ref = ?', whereArgs: ['pge:7001']),
        isEmpty,
        reason: 'the row was updated in place, not replaced under a new key');
  });

  test('two entries merging into one carry the favourite and the link',
      () async {
    // The residual case: both keys are already in the database, so one of them
    // genuinely has to go. It is still not a withdrawal - the surviving row
    // names the old key in its own `source` - so the favourite and the flown
    // site follow it across rather than being dropped.
    await PgeSitesDatabaseService.instance.importSitesData(rows: [
      ...catalogueAnsgOnly(),
      {
        'id': 20, 'name': 'Corryong (PGE)', 'longitude': 147.9,
        'latitude': -36.19, 'altitude': 500, 'country': 'au',
        'source': 'pge:7001', 'wind_n': 2,
      },
    ]);
    await db.update('pge_sites', {'is_favorite': 1},
        where: 'ref = ?', whereArgs: ['pge:7001']);
    await db.insert('sites', {
      'id': 2, 'name': 'Corryong', 'latitude': -36.19, 'longitude': 147.9,
      'catalog_ref': 'pge:7001',
      'created_at': DateTime.now().toIso8601String(),
    });

    // The producer works out they are one launch and emits a single row.
    await PgeSitesDatabaseService.instance.importSitesData(
        rows: catalogueAnsgPlusPge());

    final site = (await db.query('sites', where: 'id = 2')).single;
    expect(site['catalog_ref'], 'ansg:106-28',
        reason: 'the link follows the launch onto the surviving key');

    final survivor = (await db.query('pge_sites',
            where: 'ref = ?', whereArgs: ['ansg:106-28']))
        .single;
    expect(survivor['is_favorite'], 1,
        reason: 'the favourite was on the absorbed row and must not be lost');
  });

  test('the catalogue tab can read the row a flown site is linked to', () async {
    // getSiteByRef selected `cc.country_name`, which country_codes does not have
    // - its columns are (code, name), and every sibling query in that file uses
    // COALESCE(cc.name, s.country). So it threw `no such column` for every flown
    // site carrying a catalog_ref, and site_details_screen calls it with no
    // catchError, so the wind/altitude/guide tab silently never populated.
    await PgeSitesDatabaseService.instance.importSitesData(rows: catalogueA());

    final site =
        await PgeSitesDatabaseService.instance.getSiteByRef('pge:4632');

    expect(site, isNotNull, reason: 'the query must not throw');
    expect(site!.name, 'Manilla - Mt Borah - West launch');
    expect(site.altitude, 800);
  });
}

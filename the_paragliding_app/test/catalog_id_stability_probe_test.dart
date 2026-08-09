import 'package:flutter_test/flutter_test.dart';
import 'package:the_paragliding_app/data/datasources/database_helper.dart';
import 'package:the_paragliding_app/services/database_service.dart';
import 'package:the_paragliding_app/services/pge_sites_database_service.dart';

import 'helpers/test_helpers.dart';

/// Probe: what a *regenerated* catalogue does to an already-federated install.
///
/// The relink only runs on the generation change. Once a device is on
/// generation 2, every later refresh takes the early return and leaves
/// sites.catalog_site_id exactly as it was - while pge_sites is deleted and
/// re-inserted under whatever ids the new CSV carries.
void main() {
  late dynamic db;

  // Catalogue A: what the device imported first.
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

  /// Catalogue B: same two launches, regenerated after an upstream guide added
  /// a site earlier in the file. Ids are positional, so both shifted by one.
  /// Nothing about either launch changed.
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

    // Pre-federation state: the flown site points at a PGE id, and the user
    // has favourited that launch.
    await db.insert('pge_sites', {
      'id': 4632, 'name': 'Manilla, Mt Borah',
      'longitude': 150.6, 'latitude': -30.7, 'is_favorite': 1,
    });
    await db.insert('sites', {
      'id': 1, 'name': 'Mt Borah', 'latitude': -30.6792, 'longitude': 150.6086,
      'catalog_site_id': 4632, 'created_at': DateTime.now().toIso8601String(),
    });
  });

  test('the generation-2 relink lands the flown site on the right launch',
      () async {
    await PgeSitesDatabaseService.instance.importSitesData(rows: catalogueA());

    final site = (await db.query('sites', where: 'id = 1')).single;
    expect(site['catalog_site_id'], 17);
  });

  test('a regenerated catalogue silently repoints the flown site', () async {
    await PgeSitesDatabaseService.instance.importSitesData(rows: catalogueA());
    // Weeks later: sources changed, CSV rebuilt, ids shifted.
    await PgeSitesDatabaseService.instance.importSitesData(rows: catalogueB());

    final site = (await db.query('sites', where: 'id = 1')).single;
    final pointsAt = (await db.query('pge_sites',
            where: 'id = ?', whereArgs: [site['catalog_site_id']]))
        .single;

    // ignore: avoid_print
    print('PROBE link=${site['catalog_site_id']} now names "${pointsAt['name']}" '
        '(source ${pointsAt['source']}, alt ${pointsAt['altitude']})');

    expect(site['catalog_site_id'], 18,
        reason: 'should follow pge:4632, which moved to id 18');
  });

  test('the production read path shows the wrong guide data for a flown site',
      () async {
    await PgeSitesDatabaseService.instance.importSitesData(rows: catalogueA());
    await PgeSitesDatabaseService.instance.importSitesData(rows: catalogueB());

    // The same JOIN the map and site sheet use.
    final sites = await DatabaseService.instance.getLocalSitesWithPgeDataInBounds(
      north: -30.0, south: -31.0, east: 151.0, west: 150.0,
    );
    final borah = sites.firstWhere((s) => s.name == 'Mt Borah');

    // ignore: avoid_print
    print('PROBE Mt Borah renders alt=${borah.altitude} '
        'wind=${borah.windDirections} sources=${borah.sources}');

    expect(borah.altitude, 800, reason: 'Mt Borah is at 800m, Mystic at 380m');
    expect(borah.windDirections, ['W'], reason: 'Borah west launch faces W');
  });

  test('favourites follow the launch across a regeneration', () async {
    await PgeSitesDatabaseService.instance.importSitesData(rows: catalogueA());
    await PgeSitesDatabaseService.instance.importSitesData(rows: catalogueB());

    final favourites = await db.query('pge_sites', where: 'is_favorite = 1');
    // ignore: avoid_print
    print('PROBE favourite is now '
        '${favourites.map((r) => '${r['id']}:${r['name']}').toList()}');

    expect(favourites.map((r) => r['name']),
        ['Manilla - Mt Borah - West launch']);
  });
}

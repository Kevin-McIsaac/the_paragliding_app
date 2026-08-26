import 'package:flutter_test/flutter_test.dart';
import 'package:the_paragliding_app/data/datasources/database_helper.dart';
import 'package:the_paragliding_app/services/pge_sites_database_service.dart';
import 'package:the_paragliding_app/services/site_bounds_loader_v2.dart';

import 'helpers/test_helpers.dart';

/// Searching the Sites tab by name finds landings; the queries that pick a site
/// for the pilot still do not.
///
/// Both halves matter and they pull in opposite directions. Landings were
/// excluded from search only because `searchSitesByName` shares the class-wide
/// `launchesOnly` default, and that default exists for a real reason: #355
/// added it after a flight matched "Mt Borah Landing" instead of a takeoff, and
/// a wrong match writes itself into `sites.catalog_ref` permanently. So the
/// widening has to sit at the one caller that searches the map, not at the
/// constant every caller shares.
///
/// `searchSitesByName` had no coverage at all in either class before this.
void main() {
  setUpAll(() async {
    await TestHelpers.initializeDatabaseForTesting();
  });

  setUp(() async {
    await DatabaseHelper.instance.close();
    await DatabaseHelper.instance.database;
    await PgeSitesDatabaseService.instance.initializeTables();
  });

  tearDown(() async => DatabaseHelper.instance.close());

  /// The real Mt Borah rows: four takeoffs on one hill and the field below it,
  /// which is exactly the search a pilot types the hill's name for.
  Future<void> seedBorah() async {
    final db = await DatabaseHelper.instance.database;
    for (final row in [
      {'ref': 'pge:1', 'name': 'Manilla - Mt Borah - East launch',
        'site_type': 'launch', 'latitude': -30.6788, 'longitude': 150.6123},
      {'ref': 'pge:2', 'name': 'Manilla - Mt Borah - West launch',
        'site_type': 'launch', 'latitude': -30.6791, 'longitude': 150.6087},
      {'ref': 'pge:3', 'name': 'Manilla, Mt Borah (NSW) Landing',
        'site_type': 'landing', 'latitude': -30.6560, 'longitude': 150.6420},
    ]) {
      await db.insert('pge_sites', {...row, 'country': 'au'});
    }
  }

  test('a landing is found by the name of the hill it serves', () async {
    await seedBorah();

    final results =
        await SiteBoundsLoaderV2.instance.searchSitesByName('Borah');

    expect(
      results.map((s) => s.name),
      contains('Manilla, Mt Borah (NSW) Landing'),
      reason: 'the map draws this landing; a search over the map must find it',
    );
    expect(results, hasLength(3), reason: 'the launches are still there too');
  });

  test('the launches-only default is untouched, so matching cannot regress',
      () async {
    await seedBorah();

    // The same query, straight at the database service, is what the flight
    // matcher and the flyability screen take.
    final results = await PgeSitesDatabaseService.instance
        .searchSitesByName(query: 'Borah');

    expect(results.map((s) => s.siteType), everyElement('launch'));
    expect(results, hasLength(2));
  });

  test('a row that predates site_type is still a launch, not a landing',
      () async {
    // COALESCE in _siteTypeClause: an app that has not re-imported since the
    // producer added the column has null on every row, and they are all
    // launches. Widening the search must not start calling them landings.
    final db = await DatabaseHelper.instance.database;
    await db.insert('pge_sites', {
      'ref': 'pge:9', 'name': 'Old Borah row', 'country': 'au',
      'latitude': -30.6788, 'longitude': 150.6123,
    });

    final results =
        await SiteBoundsLoaderV2.instance.searchSitesByName('Borah');

    expect(results.single.siteType, 'launch');
  });
}

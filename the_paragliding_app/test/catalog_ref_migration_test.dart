import 'package:flutter_test/flutter_test.dart';
import 'package:the_paragliding_app/data/datasources/database_helper.dart';
import 'package:the_paragliding_app/services/pge_sites_database_service.dart';

import 'helpers/test_helpers.dart';

/// The v4 -> v5 conversion of `sites.catalog_site_id` into `sites.catalog_ref`.
///
/// Drives [DatabaseHelper.fillCatalogRefs] directly rather than restating its
/// SQL, so the test cannot drift from the migration it is checking.
///
/// The case that matters is the third one. A federated catalogue id is a row
/// number and overlaps ParaglidingEarth's id space, so synthesising `pge:<n>`
/// from one would attach the site to an unrelated launch - which is the exact
/// failure this whole change exists to end. Declining to guess costs the pilot
/// wind and altitude on one site; guessing wrong shows them another launch's.
void main() {
  late dynamic db;

  setUp(() async {
    await TestHelpers.initializeDatabaseForTesting();
    await DatabaseHelper.instance.recreateDatabase();
    db = await DatabaseHelper.instance.database;
    // pge_sites is created by the catalogue service, not by _onCreate.
    await PgeSitesDatabaseService.instance.initializeTables();

    // Recreate the v4 pre-state. A fresh v5 install has no catalog_site_id at
    // all, so without this there is nothing for the migration to convert.
    await db.execute('ALTER TABLE sites ADD COLUMN catalog_site_id INTEGER');
  });

  Future<void> insertSite(int id, String name, int? catalogSiteId) async {
    await db.insert('sites', {
      'id': id,
      'name': name,
      'latitude': -30.6792,
      'longitude': 150.6086,
      'catalog_site_id': catalogSiteId,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  test('resolves a federated link through the guide token', () async {
    await db.insert('pge_sites', {
      'id': 17, 'name': 'Mt Borah West', 'longitude': 150.6086,
      'latitude': -30.6792, 'source': 'pge:4632;ansg:136-40',
    });
    await insertSite(1, 'Mt Borah', 17);

    expect(await DatabaseHelper.fillCatalogRefs(db), 1);

    final site = (await db.query('sites', where: 'id = 1')).single;
    expect(site['catalog_ref'], 'pge:4632',
        reason: 'pge leads the precedence list');
  });

  test('treats a pre-federation link as the PGE id it really was', () async {
    // A database that never saw the federated catalogue: no source column
    // values, and the stored id genuinely is ParaglidingEarth's.
    await db.insert('pge_sites', {
      'id': 4632, 'name': 'Manilla, Mt Borah',
      'longitude': 150.6, 'latitude': -30.7,
    });
    await insertSite(1, 'Mt Borah', 4632);

    expect(await DatabaseHelper.fillCatalogRefs(db), 1);

    final site = (await db.query('sites', where: 'id = 1')).single;
    expect(site['catalog_ref'], 'pge:4632');
  });

  test('leaves a link null rather than guessing when the row is gone', () async {
    await insertSite(1, 'Gone Upstream', 99999);

    expect(await DatabaseHelper.fillCatalogRefs(db), 0);

    final site = (await db.query('sites', where: 'id = 1')).single;
    expect(site['catalog_ref'], isNull,
        reason: 'id 99999 could be any launch now; pge:99999 would be a guess');
  });

  test('keys a launch no guide but the national one describes', () async {
    await db.insert('pge_sites', {
      'id': 21, 'name': 'An Australian launch', 'longitude': 150.0,
      'latitude': -30.0, 'source': 'ansg:136-21',
    });
    await insertSite(1, 'Local hill', 21);

    expect(await DatabaseHelper.fillCatalogRefs(db), 1);

    final site = (await db.query('sites', where: 'id = 1')).single;
    expect(site['catalog_ref'], 'ansg:136-21');
  });

  test('is idempotent, so a re-run cannot rewrite a converted link', () async {
    await db.insert('pge_sites', {
      'id': 17, 'name': 'Mt Borah West', 'longitude': 150.6086,
      'latitude': -30.6792, 'source': 'pge:4632',
    });
    await insertSite(1, 'Mt Borah', 17);

    await DatabaseHelper.fillCatalogRefs(db);
    // Second pass: the old integer column still holds 17, which now means a
    // different launch. It must not be consulted again.
    expect(await DatabaseHelper.fillCatalogRefs(db), 0);

    final site = (await db.query('sites', where: 'id = 1')).single;
    expect(site['catalog_ref'], 'pge:4632');
  });

  test('a ref collision keeps the favourited row, not an arbitrary one',
      () async {
    // Code review caught this. A pre-federation install could hold one row per
    // guide for a single physical launch; both resolve to the same ref, so one
    // has to go before the unique index can exist. Choosing by id would have
    // taken the pilot's favourite with it, recorded only as an aggregate count.
    await db.insert('pge_sites', {
      'id': 10, 'name': 'Mt Borah (PGE copy)', 'longitude': 150.6086,
      'latitude': -30.6792, 'source': 'pge:4632', 'is_favorite': 0,
    });
    await db.insert('pge_sites', {
      'id': 11, 'name': 'Mt Borah (favourited copy)', 'longitude': 150.6086,
      'latitude': -30.6792, 'source': 'pge:4632', 'is_favorite': 1,
    });

    // initializeTables runs the backfill, which is where the collision is
    // resolved - and it must leave a table the unique index can be built on.
    await PgeSitesDatabaseService.instance.initializeTables();

    final rows = await db.query('pge_sites', where: "ref = 'pge:4632'");
    expect(rows, hasLength(1), reason: 'a duplicate ref blocks the unique index');
    expect(rows.single['is_favorite'], 1,
        reason: "the survivor must be the row the pilot marked");
    expect(rows.single['name'], 'Mt Borah (favourited copy)');
  });

  test('a fresh install has the new column and the new index', () async {
    // Asserted against sqlite_master rather than by asking the service, so a
    // convergence failure between _onCreate and _onUpgrade shows up here.
    final columns = (await db.rawQuery('PRAGMA table_info(sites)'))
        .map((c) => c['name'] as String)
        .toSet();
    expect(columns, contains('catalog_ref'));

    final indexes = (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'sites'",
    )).map((row) => row['name'] as String).toSet();
    expect(indexes, contains('idx_sites_catalog_ref'));
  });
}

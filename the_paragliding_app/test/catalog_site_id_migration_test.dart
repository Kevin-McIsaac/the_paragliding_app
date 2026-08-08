import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:the_paragliding_app/data/datasources/database_helper.dart';

import 'helpers/test_helpers.dart';

/// Covers the v3 -> v4 migration, which renames `sites.pge_site_id` to
/// `catalog_site_id` on every existing install.
///
/// This drives the real `openDatabase(version:, onUpgrade:)` path rather than
/// calling the migration directly, which is the whole point. Calling
/// `_onUpgrade` by hand - the shape `duration_backfill_test.dart` uses - proves
/// the SQL runs, but cannot prove sqflite then *records* the new version. If it
/// does not, the rename succeeds on first launch and the identical rename is
/// attempted again on the next one, against a column that no longer exists.
/// That throws, `_onUpgrade` rethrows, and the database fails to open: the app
/// is unusable and the user's flight log is unreachable.
///
/// A Pixel 9 was found in exactly that end state - `user_version` 3, yet
/// `catalog_site_id` and its index already present - which is what this test
/// exists to rule in or out. The reopen at the end is the assertion that
/// matters; everything before it is setup.
void main() {
  /// The v3 `sites` table as released in v1.0.6+18, reproduced verbatim.
  ///
  /// Duplicating schema in a test usually invites drift, but a shipped schema
  /// is frozen by definition - this is what is on users' phones, and it must
  /// never be updated to match current `_onCreate`. That is the state the
  /// migration has to cope with.
  const v3SitesTable = '''
      CREATE TABLE sites (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        altitude REAL,
        country TEXT,
        custom_name INTEGER DEFAULT 0,
        pge_site_id INTEGER,
        is_favorite INTEGER DEFAULT 0,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''';

  late String dbPath;
  String? previousOverride;

  setUp(() async {
    await TestHelpers.initializeDatabaseForTesting();
    previousOverride = DatabaseHelper.databasePathOverride;

    // A file, not `inMemoryDatabasePath`: an in-memory database is discarded on
    // close, and this test has to close one and open it again to see whether
    // the recorded version survived.
    dbPath = TestHelpers.fixturePath(
        'v3_upgrade_${DateTime.now().microsecondsSinceEpoch}.db');
    await deleteDatabase(dbPath);

    // Release the singleton's memoised connection before repointing it.
    await DatabaseHelper.instance.close();
    DatabaseHelper.databasePathOverride = dbPath;
  });

  tearDown(() async {
    await DatabaseHelper.instance.close();
    DatabaseHelper.databasePathOverride = previousOverride;
    await deleteDatabase(dbPath);
  });

  /// Build a pre-federation install: schema at v3, holding a linked site.
  Future<void> createV3Database({int pgeSiteId = 4632}) async {
    final db = await openDatabase(
      dbPath,
      version: 3,
      onCreate: (db, version) async {
        await db.execute(v3SitesTable);
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_sites_pge_site_id ON sites(pge_site_id)');
        await db.insert('sites', {
          'name': 'Mt Borah',
          'latitude': -30.6789,
          'longitude': 150.609,
          'pge_site_id': pgeSiteId,
          'created_at': DateTime.now().toIso8601String(),
        });
      },
    );

    // Guard the fixture itself: if this is not really a v3 database holding the
    // old column, the test below proves nothing.
    expect(await db.getVersion(), 3);
    final columns = await db.rawQuery('PRAGMA table_info(sites)');
    expect(columns.map((c) => c['name']), contains('pge_site_id'));
    await db.close();
  }

  Future<List<String>> sitesColumns(Database db) async =>
      (await db.rawQuery('PRAGMA table_info(sites)'))
          .map((c) => c['name'] as String)
          .toList();

  test('renames pge_site_id to catalog_site_id, keeping the link', () async {
    await createV3Database(pgeSiteId: 4632);

    final db = await DatabaseHelper.instance.database;

    final columns = await sitesColumns(db);
    expect(columns, contains('catalog_site_id'));
    expect(columns, isNot(contains('pge_site_id')),
        reason: 'the old name must be gone, not merely shadowed');

    final site = (await db.query('sites')).single;
    expect(site['catalog_site_id'], 4632,
        reason: 'the link must survive the rename, not be dropped');
    expect(site['name'], 'Mt Borah');
  });

  test('records the new version, so the migration is not attempted twice',
      () async {
    await createV3Database();

    final db = await DatabaseHelper.instance.database;
    expect(await db.getVersion(), DatabaseHelper.databaseVersion,
        reason: 'an unrecorded upgrade re-runs the rename on the next launch');
  });

  test('reopens cleanly after upgrading - the second launch', () async {
    await createV3Database(pgeSiteId: 4632);

    // First launch: performs the upgrade.
    await DatabaseHelper.instance.database;
    await DatabaseHelper.instance.close();

    // Second launch. This is the one that failed on the device: the rename is
    // attempted again against a column that is no longer there, and the open
    // throws rather than returning a usable database.
    final db = await DatabaseHelper.instance.database;

    expect(await db.getVersion(), DatabaseHelper.databaseVersion);
    expect(await sitesColumns(db), contains('catalog_site_id'));
    expect((await db.query('sites')).single['catalog_site_id'], 4632,
        reason: 'reopening must not disturb the migrated data');
  });

  test('upgrades a v3 database whose rename already ran', () async {
    // The exact state the Pixel was found in: the schema change had been
    // applied but the version still read 3. Whatever produced it, a migration
    // that cannot survive being re-entered turns it into an app that will not
    // open - so the rename has to be conditional on the old column existing.
    final seed = await openDatabase(
      dbPath,
      version: 3,
      onCreate: (db, version) async {
        await db.execute(v3SitesTable
            .replaceAll('pge_site_id INTEGER', 'catalog_site_id INTEGER'));
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_sites_catalog_site_id ON sites(catalog_site_id)');
      },
    );
    await seed.close();

    final db = await DatabaseHelper.instance.database;

    expect(await db.getVersion(), DatabaseHelper.databaseVersion);
    expect(await sitesColumns(db), contains('catalog_site_id'));
  });
}

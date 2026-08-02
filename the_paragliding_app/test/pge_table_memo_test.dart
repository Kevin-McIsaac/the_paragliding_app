import 'package:flutter_test/flutter_test.dart';
import 'package:the_paragliding_app/data/datasources/database_helper.dart';
import 'package:the_paragliding_app/services/app_initialization_service.dart';

import 'helpers/test_helpers.dart';

/// `pge_sites` and `pge_sites_metadata` are created by
/// `PgeSitesDatabaseService.initializeTables()`, not by `DatabaseHelper._onCreate`,
/// so a database recreate drops them. `ensureTables()` used to memoise "done" in a
/// bool that outlived the database it described, leaving it a no-op against a
/// database with no tables (#282).
void main() {
  setUpAll(TestHelpers.initializeDatabaseForTesting);

  Future<bool> tableExists(String name) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name = ?",
      [name],
    );
    return rows.isNotEmpty;
  }

  test('ensureTables recreates the PGE tables after a database recreate', () async {
    await AppInitializationService.instance.ensureTables();
    expect(await tableExists('pge_sites'), isTrue, reason: 'precondition');

    // Drops every table, including the PGE ones, and installs a new connection.
    await DatabaseHelper.instance.recreateDatabase();
    expect(await tableExists('pge_sites'), isFalse,
        reason: 'recreate should have dropped them');

    // Before the fix this returned the cached future and did nothing.
    await AppInitializationService.instance.ensureTables();

    // Asserted against sqlite_master rather than the service, so a service that
    // wrongly believes the tables exist cannot make this pass.
    expect(await tableExists('pge_sites'), isTrue);
    expect(await tableExists('pge_sites_metadata'), isTrue);
  });

  test('ensureTables stays a no-op while the connection is unchanged', () async {
    // Independent of the test above: that one leaves the singletons holding a
    // recreated database, and this must not inherit that state.
    await DatabaseHelper.instance.recreateDatabase();

    await AppInitializationService.instance.ensureTables();
    final first = await DatabaseHelper.instance.database;

    await AppInitializationService.instance.ensureTables();
    await AppInitializationService.instance.ensureTables();

    // Same connection throughout - the memo should have short-circuited rather
    // than re-running DDL on every call.
    expect(identical(await DatabaseHelper.instance.database, first), isTrue);
    expect(await tableExists('pge_sites'), isTrue);
  });

  // No test for initializeInBackground's memo. Its only observable effect is a
  // ~11k-row download and sync, which tests disable on purpose
  // (backgroundInitEnabled, flutter_test_config.dart) because the live path costs
  // ~60s and fails offline - #280's timeouts came from exactly that. Offline,
  // _initialize() fails and never stamps its memo, so a passing assertion cannot
  // distinguish "re-entered the work" from "returned early", which is the whole
  // question. An earlier draft asserted the flights table still existed: it
  // passed against the unfixed code too, which is worse than no test.
  //
  // The change there is the same one-line pattern proven by the two tests above.
}

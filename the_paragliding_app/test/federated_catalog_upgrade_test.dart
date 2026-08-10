import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_paragliding_app/data/datasources/database_helper.dart';
import 'package:the_paragliding_app/services/pge_sites_database_service.dart';
import 'package:the_paragliding_app/services/pge_sites_download_service.dart';

import 'helpers/test_helpers.dart';

/// Drives the *real* bundled catalogue through the *real* copy, parse and
/// import chain, on a database that already looks like a pre-federation
/// install.
///
/// The other test file uses hand-built rows to pin the relink rules. This one
/// exists because those rows cannot catch what only 11,672 real ones can: a
/// column index off by one, a quoted name containing a comma shifting every
/// field after it, or an id that does not survive the round trip. It is the
/// closest thing to launching the app that runs without a display.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDocs;

  setUpAll(() async {
    tempDocs = await Directory.systemTemp.createTemp('federated_catalog_');
    // path_provider has no implementation under flutter_test.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDocs.path,
    );
  });

  tearDownAll(() async => tempDocs.delete(recursive: true));

  setUp(() async {
    await TestHelpers.initializeDatabaseForTesting();
    await DatabaseHelper.instance.recreateDatabase();
    await PgeSitesDatabaseService.instance.initializeTables();
  });

  test('the bundled catalogue imports and upgrades a pre-federation database',
      () async {
    final db = await DatabaseHelper.instance.database;

    // An install carrying the previous catalogue: a flown site linked to
    // Manilla - Mt Borah, and favourited. The catalogue row is seeded without a
    // ref, as a pre-federation export left it, so initializeTables' backfill has
    // to key it from its id before any of this can resolve.
    await db.insert('pge_sites', {
      'id': 4632,
      'name': 'Manilla, Mt Borah (NSW)',
      'longitude': 150.609,
      'latitude': -30.6789,
      'is_favorite': 1,
    });
    await db.insert('sites', {
      'name': 'Mt Borah',
      'latitude': -30.6789,
      'longitude': 150.609,
      'catalog_ref': 'pge:4632',
      'created_at': DateTime.now().toIso8601String(),
    });

    // The real chain: copy the asset out of the bundle, parse it, import it.
    expect(await PgeSitesDownloadService.instance.downloadSitesData(), isTrue);
    expect(await PgeSitesDatabaseService.instance.importSitesData(), isTrue);

    final count = (await db.rawQuery('SELECT COUNT(*) c FROM pge_sites')).first['c'] as int;
    expect(count, greaterThan(11000), reason: 'whole catalogue should import');

    // Coordinates, not row counts. Longitude precedes latitude in the file,
    // so an off-by-one would still parse and still count 11,672 rows.
    final borah = (await db.rawQuery(
      "SELECT * FROM pge_sites WHERE source LIKE '%pge:4632%'",
    )).single;
    expect(borah['latitude'] as double, closeTo(-30.68, 0.05));
    expect(borah['longitude'] as double, closeTo(150.61, 0.05));
    expect(borah['country'], 'au');
    expect(borah['altitude'], isNotNull);

    // The link is untouched, and still resolves - the whole point of keying on
    // the guide's id. Importing 11,703 rows over the top rewrites nothing the
    // pilot owns.
    final site = (await db.query('sites', where: 'catalog_ref IS NOT NULL')).single;
    expect(site['catalog_ref'], 'pge:4632');
    expect(borah['ref'], 'pge:4632',
        reason: 'the imported row carries the same key the flown site holds');

    // And the favourite stayed on that launch, through a backfill and a full
    // catalogue import.
    final favourites = await db.query('pge_sites', where: 'is_favorite = 1');
    expect(favourites.map((r) => r['ref']), ['pge:4632']);
  });

  test('a launch no source but Site Guide has is present and flyable', () async {
    // The point of the whole exercise: 135 Australian launches had no PGE
    // entry, so the app could not show them at all.
    await PgeSitesDownloadService.instance.downloadSitesData();
    await PgeSitesDatabaseService.instance.importSitesData();

    final db = await DatabaseHelper.instance.database;
    final guideOnly = await db.rawQuery(
      // `ansg:` since the producer emits the guide's own acronym natively. This
      // read the old prefix while the rewrite existed to translate it; with the
      // rewrite gone, the asset and this query have to agree.
      "SELECT * FROM pge_sites WHERE source LIKE 'ansg:%' AND source NOT LIKE '%pge:%'",
    );

    expect(guideOnly.length, greaterThan(50));
    // Wind is what flyability runs on, and Site Guide publishes none - it is
    // parsed out of prose. If that broke, these sites would be dead weight.
    final withWind = guideOnly.where((r) => [
          'wind_n', 'wind_ne', 'wind_e', 'wind_se',
          'wind_s', 'wind_sw', 'wind_w', 'wind_nw',
        ].any((c) => (r[c] as int) > 0));
    expect(withWind.length / guideOnly.length, greaterThan(0.8));
  });

  test('parses every record despite line breaks inside guide prose', () async {
    // The old hand-rolled parser split the file on newlines before reading
    // fields, so a hard line break inside a closure notice tore a record in
    // two - 42 of 11,703. Reading with a real CSV parser fixes that, and
    // reading by column name means order no longer matters either.
    expect(await PgeSitesDownloadService.instance.downloadSitesData(), isTrue);
    expect(await PgeSitesDatabaseService.instance.importSitesData(), isTrue);

    final db = await DatabaseHelper.instance.database;
    final count = (await db.rawQuery('SELECT COUNT(*) c FROM pge_sites')).first['c'] as int;
    expect(count, greaterThan(11000));

    // A record whose text contains a newline must survive whole.
    final closed = await db.rawQuery(
      "SELECT name, closed FROM pge_sites WHERE closed IS NOT NULL AND closed != ''",
    );
    expect(closed.length, greaterThan(20),
        reason: 'closed sites are carried, not dropped');
    expect(closed.any((r) => (r['closed'] as String).contains('\n')), isTrue,
        reason: 'a multi-line notice should keep its line break');
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_paragliding_app/data/datasources/database_helper.dart';
import 'package:the_paragliding_app/services/pge_sites_database_service.dart';

import 'helpers/test_helpers.dart';

/// The federated catalogue replaced a PGE-only export with a different id
/// space and one changed column. Both are silent failure modes:
///
///  * longitude precedes latitude in the CSV, so a swapped pair parses
///    cleanly and puts every site in the wrong hemisphere;
///  * catalogue ids and PGE ids overlap, so a link remap that ran twice would
///    point flown sites at unrelated launches.
void main() {
  group('bundled catalogue asset', () {
    late List<CsvRow> rows;

    setUpAll(() {
      // Parsed properly, by column name. These tests used to split on commas
      // themselves, which is the very thing the app stopped doing - and they
      // broke the moment guide prose with quotes and line breaks arrived.
      final bytes = File('assets/data/world_sites_extracted.csv.gz').readAsBytesSync();
      rows = csv.decodeWithHeaders(utf8.decode(gzip.decode(bytes)));
    });

    String field(CsvRow row, String name) => (row[name] ?? '').toString();

    test('carries every column the app reads by name', () {
      expect(
        rows.first.headerMap.keys,
        containsAll([
          'id', 'name', 'longitude', 'latitude', 'altitude', 'country',
          'wind_n', 'wind_ne', 'wind_e', 'wind_se',
          'wind_s', 'wind_sw', 'wind_w', 'wind_nw',
          'source', 'closed',
        ]),
      );
    });

    test('coordinates land in the right hemisphere, not merely parse', () {
      // The app reads by name now, so a column reorder is harmless - but a
      // producer that swapped the *values* would still emit valid doubles,
      // which is what this catches.
      var southernAndEastern = 0;
      var northernAndWestern = 0;

      for (final row in rows) {
        final lon = double.tryParse(field(row, 'longitude'));
        final lat = double.tryParse(field(row, 'latitude'));
        if (lon == null || lat == null) continue;

        expect(lat, inInclusiveRange(-90, 90),
            reason: 'latitude out of range: ${field(row, 'name')}');
        expect(lon, inInclusiveRange(-180, 180));

        if (lat < -10 && lon > 100) southernAndEastern++;
        if (lat > 40 && lon < 0) northernAndWestern++;
      }

      // Australia/NZ and North America/western Europe must both be populated.
      // A lat/lng swap collapses one of these to zero.
      expect(southernAndEastern, greaterThan(100));
      expect(northernAndWestern, greaterThan(100));
    });

    test('carries altitude, country and source', () {
      final sample = rows.take(2000);
      expect(sample.where((r) => field(r, 'altitude').isNotEmpty).length, greaterThan(1000));
      expect(sample.where((r) => field(r, 'country').isNotEmpty).length, greaterThan(1000));
      expect(sample.where((r) => field(r, 'source').startsWith('pge:')).length,
          greaterThan(1000));
    });

    test('keeps closed sites, with the reason', () {
      // Dropping them left the other guides' entries for the same place on
      // the map with nothing to say the site was shut.
      final shut = rows.where((r) => field(r, 'closed').isNotEmpty);
      expect(shut.length, greaterThan(20));
      expect(shut.any((r) => field(r, 'closed').contains('\n')), isTrue,
          reason: 'a multi-line notice must survive as one record');
    });

    test('includes launches contributed only by a national guide', () {
      // The reason the federation exists: 135 Australian launches have no PGE
      // counterpart and were invisible before.
      final guideOnly = rows.where((r) =>
          field(r, 'source').contains('siteguide_au') &&
          !field(r, 'source').contains('pge:'));
      expect(guideOnly.length, greaterThan(50));
    });
  });

  group('relinking flown sites to the federated catalogue', () {
    late dynamic db;

    Future<void> seedGenerationOne() async {
      // A pre-federation database: catalogue ids are PGE ids, and a flown
      // site points at one of them.
      await db.insert('pge_sites', {
        'id': 4632, 'name': 'Manilla, Mt Borah', 'longitude': 150.6, 'latitude': -30.7,
        'is_favorite': 1,
      });
      await db.insert('sites', {
        'id': 1, 'name': 'Mt Borah', 'latitude': -30.7, 'longitude': 150.6,
        'catalog_site_id': 4632, 'created_at': DateTime.now().toIso8601String(),
      });
      await db.insert('sites', {
        'id': 2, 'name': 'Gone Upstream', 'latitude': 1.0, 'longitude': 1.0,
        'catalog_site_id': 99999, 'created_at': DateTime.now().toIso8601String(),
      });
    }

    List<Map<String, dynamic>> federatedRows() => [
          {
            'id': 17, 'name': 'Manilla - Mt Borah - West launch',
            'longitude': 150.6086, 'latitude': -30.6792, 'altitude': 800,
            'country': 'au', 'source': 'pge:4632;siteguide_au:136-40',
          },
          {
            'id': 4632, 'name': 'A different launch that happens to hold this id',
            'longitude': 6.7, 'latitude': 45.9, 'altitude': 1200,
            'country': 'fr', 'source': 'pge:20001',
          },
        ];

    setUp(() async {
      await TestHelpers.initializeDatabaseForTesting();
      await DatabaseHelper.instance.recreateDatabase();
      db = await DatabaseHelper.instance.database;
      await PgeSitesDatabaseService.instance.initializeTables();
      await seedGenerationOne();
    });

    test('rewrites a flown site link into the new id space', () async {
      await PgeSitesDatabaseService.instance.importSitesData(rows: federatedRows());

      final site = (await db.query('sites', where: 'id = 1')).single;
      expect(site['catalog_site_id'], 17,
          reason: 'should follow pge:4632 into the federated catalogue');
    });

    test('clears a link whose source disappeared rather than leaving it wrong', () async {
      // Site 2 pointed at PGE 99999, which no longer exists. Id 99999 could
      // later belong to something unrelated; showing that launch's wind and
      // altitude would be worse than showing none.
      await PgeSitesDatabaseService.instance.importSitesData(rows: federatedRows());

      final site = (await db.query('sites', where: 'id = 2')).single;
      expect(site['catalog_site_id'], isNull);
    });

    test('carries favourites across the id change', () async {
      await PgeSitesDatabaseService.instance.importSitesData(rows: federatedRows());

      final favourites = await db.query('pge_sites', where: 'is_favorite = 1');
      expect(favourites.map((r) => r['id']), [17]);
    });

    test('does not relink a second time, when ids no longer mean the same thing',
        () async {
      await PgeSitesDatabaseService.instance.importSitesData(rows: federatedRows());
      // A weekly refresh of the same catalogue. Site 1 now holds canonical id
      // 17; re-running the mapping would look 17 up as a PGE id and could
      // relink it to something unrelated.
      await PgeSitesDatabaseService.instance.importSitesData(rows: federatedRows());

      final site = (await db.query('sites', where: 'id = 1')).single;
      expect(site['catalog_site_id'], 17);
    });

    test('an ordinary refresh keeps favourites', () async {
      // Regression: the import deleted the table and re-inserted, silently
      // clearing every favourite on each refresh.
      await PgeSitesDatabaseService.instance.importSitesData(rows: federatedRows());
      await PgeSitesDatabaseService.instance.importSitesData(rows: federatedRows());

      final favourites = await db.query('pge_sites', where: 'is_favorite = 1');
      expect(favourites.map((r) => r['id']), [17]);
    });
  });

  group('renaming pge_site_id to catalog_site_id', () {
    // The column never held a ParaglidingEarth id once sites were federated;
    // it holds a catalogue id. The old name asserted otherwise at every call
    // site and twice caused a catalogue id to be handed to ParaglidingEarth
    // as its own, silently addressing an unrelated site.
    test('carries existing links across the rename', () async {
      await TestHelpers.initializeDatabaseForTesting();
      await DatabaseHelper.instance.recreateDatabase();
      final db = await DatabaseHelper.instance.database;

      await db.insert('sites', {
        'name': 'Mt Borah',
        'latitude': -30.6789,
        'longitude': 150.609,
        'catalog_site_id': 9247,
        'created_at': DateTime.now().toIso8601String(),
      });

      // A v3 database is renamed in place, so the value has to survive - the
      // link is what gives a flown site its wind and altitude.
      final site = (await db.query('sites', where: "name = 'Mt Borah'")).single;
      expect(site['catalog_site_id'], 9247);
    });

    test('the old column name is gone', () async {
      await TestHelpers.initializeDatabaseForTesting();
      await DatabaseHelper.instance.recreateDatabase();
      final db = await DatabaseHelper.instance.database;

      final columns = (await db.rawQuery('PRAGMA table_info(sites)'))
          .map((c) => c['name'] as String)
          .toSet();

      expect(columns, contains('catalog_site_id'));
      expect(columns, isNot(contains('pge_site_id')),
          reason: 'a fresh install should never create the misleading name');
    });
  });
}

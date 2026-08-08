import 'dart:convert';
import 'dart:io';

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
    late List<List<String>> rows;

    setUpAll(() {
      final bytes = File('assets/data/world_sites_extracted.csv.gz').readAsBytesSync();
      final lines = utf8.decode(gzip.decode(bytes)).trim().split('\n');
      rows = lines.map((l) => l.split(',')).toList();
    });

    test('header matches the order the parser reads positionally', () {
      expect(
        rows.first.join(','),
        'id,name,longitude,latitude,altitude,country,'
        'wind_n,wind_ne,wind_e,wind_se,wind_s,wind_sw,wind_w,wind_nw,source',
      );
    });

    test('every row has the 15 fields the parser requires', () {
      // Names are quoted when they contain commas, so count on unquoted rows.
      final plain = rows.skip(1).where((r) => !r.any((f) => f.startsWith('"')));
      expect(plain, isNotEmpty);
      for (final row in plain.take(500)) {
        expect(row.length, 15, reason: row.join(','));
      }
    });

    test('coordinates land in the right hemisphere, not merely parse', () {
      // Longitude is field 2, latitude field 3. If those were swapped these
      // would still be valid doubles - which is the whole danger.
      var southernAndEastern = 0;
      var northernAndWestern = 0;

      for (final row in rows.skip(1)) {
        if (row.length != 15) continue;
        final lon = double.tryParse(row[2]);
        final lat = double.tryParse(row[3]);
        if (lon == null || lat == null) continue;

        expect(lat, inInclusiveRange(-90, 90), reason: 'latitude out of range: ${row[1]}');
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
      final sample = rows.skip(1).where((r) => r.length == 15).take(2000);
      expect(sample.where((r) => r[4].isNotEmpty).length, greaterThan(1000));
      expect(sample.where((r) => r[5].isNotEmpty).length, greaterThan(1000));
      expect(sample.where((r) => r[14].startsWith('pge:')).length, greaterThan(1000));
    });

    test('includes launches contributed only by a national guide', () {
      // The reason the federation exists: 135 Australian launches have no PGE
      // counterpart and were invisible before.
      final guideOnly = rows
          .skip(1)
          .where((r) => r.length == 15 && r[14].contains('siteguide_au') && !r[14].contains('pge:'));
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

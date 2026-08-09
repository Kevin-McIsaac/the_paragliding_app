import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_paragliding_app/data/datasources/database_helper.dart';
import 'package:the_paragliding_app/utils/catalog_ref.dart';

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
      //
      // Matched on the raw prefix the producer currently writes, not the app's
      // normalised one - this reads the asset, so it must say what the file says.
      // When the pipeline switches to `ansg:` this needs both.
      final guideOnly = rows.where((r) =>
          (field(r, 'source').contains('siteguide_au:') ||
              field(r, 'source').contains('ansg:')) &&
          !field(r, 'source').contains('pge:'));
      expect(guideOnly.length, greaterThan(50));
    });
  });

  // The 'relinking flown sites' group that used to sit here is gone with the
  // machinery it covered. The catalogue is keyed on the contributing guide's own
  // id now, so there is no id space to remap and no generation to track: a
  // rebuild leaves every link valid by construction. Its coverage moved, and
  // grew, rather than being dropped:
  //
  //  * test/catalog_ref_migration_test.dart - the one-time v4 -> v5 conversion
  //    of the old integer links, including refusing to guess a ref for a row
  //    that is no longer in the catalogue;
  //  * test/catalog_ref_stability_test.dart - a regenerated catalogue with every
  //    positional id shifted, favourites across a refresh, and a withdrawn entry
  //    re-linking itself when the guide restores it.

  group('the catalogue key', () {
    setUp(() async {
      await TestHelpers.initializeDatabaseForTesting();
      await DatabaseHelper.instance.recreateDatabase();
    });

    test('a fresh install links on a ref, not a row number', () async {
      final db = await DatabaseHelper.instance.database;
      final columns = (await db.rawQuery('PRAGMA table_info(sites)'))
          .map((c) => c['name'] as String)
          .toSet();

      expect(columns, contains('catalog_ref'));
      expect(columns, isNot(contains('pge_site_id')),
          reason: 'a fresh install should never create the misleading name');
      expect(columns, isNot(contains('catalog_site_id')),
          reason: 'the positional-id column is a v4 relic; only the v4 -> v5 '
              'migration should ever see it');
    });

    test('holds the guide token it was given', () async {
      final db = await DatabaseHelper.instance.database;
      await db.insert('sites', {
        'name': 'Mt Borah',
        'latitude': -30.6789,
        'longitude': 150.609,
        'catalog_ref': 'pge:4632',
        'created_at': DateTime.now().toIso8601String(),
      });

      final site = (await db.query('sites', where: "name = 'Mt Borah'")).single;
      expect(site['catalog_ref'], 'pge:4632');
    });

    test('every row of the shipped catalogue yields a ref', () async {
      // If a row could not be keyed the import would silently skip it, so the
      // pilot would lose a launch. Checked against the real asset because the
      // producer is not in this repo and cannot be tested directly.
      final bytes =
          File('assets/data/world_sites_extracted.csv.gz').readAsBytesSync();
      final rows = csv.decodeWithHeaders(utf8.decode(gzip.decode(bytes)));

      final unkeyable = rows
          .where((row) => CatalogRef.fromSource((row['source'] ?? '').toString()) == null)
          .length;
      expect(unkeyable, 0);
    });

    test('prefers pge when a launch is described by two guides', () {
      expect(CatalogRef.fromSource('ansg:136-40;pge:4632'), 'pge:4632');
      expect(CatalogRef.fromSource('ansg:136-40'), 'ansg:136-40');
      expect(CatalogRef.fromSource(''), isNull);
    });

    test('rejects a token missing either half', () {
      // `pge:` names no launch, and keying rows on it would collide every id-less
      // token from that guide onto one row. Not reachable against today's
      // catalogue - but the point of this change is to stop assuming that.
      expect(CatalogRef.tokensOf('pge:'), isEmpty);
      expect(CatalogRef.tokensOf(':4632'), isEmpty);
      expect(CatalogRef.tokensOf('pge'), isEmpty);
      expect(CatalogRef.fromSource('pge:;ansg:136-40'), 'ansg:136-40',
          reason: 'a malformed token must not shadow a usable one');
    });

    test('normalises a provider the producer has since renamed', () {
      // The shipped catalogue still says siteguide_au; the prefix is now the
      // guide's own acronym, ansg (Australian National Site Guide). Normalising on read means the
      // app works against either, and only ever stores the current form - so
      // there is one prefix in the database however old the catalogue is.
      expect(CatalogRef.fromSource('siteguide_au:136-40'), 'ansg:136-40');
      expect(CatalogRef.tokensOf('pge:4632;siteguide_au:136-40'),
          ['pge:4632', 'ansg:136-40']);
      expect(CatalogRef.providerOf('ansg:136-40'), 'ansg');
    });

    test('a provider prefix survives a round trip through source', () {
      // Length is a matter of taste - pge is three, ansg four, ffvl will be four
      // - so this asserts the part that is not: a prefix containing either
      // delimiter would be torn apart when `source` is parsed back, and the ref
      // stored against it would never match again.
      for (final provider in CatalogRef.providerPrecedence) {
        expect(provider, provider.toLowerCase(),
            reason: 'refs are compared exactly, so case cannot vary');
        expect(provider, isNot(contains(':')));
        expect(provider, isNot(contains(';')));

        expect(CatalogRef.fromSource('$provider:123'), '$provider:123');
        expect(CatalogRef.tokensOf('$provider:123;other:9').first,
            '$provider:123');
      }
    });
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_paragliding_app/data/datasources/database_helper.dart';
import 'package:the_paragliding_app/data/models/guide.dart';
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

    setUpAll(() async {
      // Parsed properly, by column name. These tests used to split on commas
      // themselves, which is the very thing the app stopped doing - and they
      // broke the moment guide prose with quotes and line breaks arrived.
      final bytes = File('assets/data/world_sites_extracted.csv.gz').readAsBytesSync();
      rows = csv.decodeWithHeaders(utf8.decode(gzip.decode(bytes)));

      // The bundled registry, read the way the app reads it. Both halves of the
      // pair are assets here on purpose: these tests exist to catch the two
      // drifting from each other.
      TestWidgetsFlutterBinding.ensureInitialized();
      await Guides.load();
    });

    String field(CsvRow row, String name) => (row[name] ?? '').toString();

    test('names no guide this app cannot describe', () {
      // The same alarm this has always been, moved to the thing it now guards.
      //
      // It used to assert every provider was in `CatalogRef.providerPrecedence`
      // - one of three hand-written copies of one list, the others being
      // KEY_PRECEDENCE and APP_PRECEDENCE in the producer's Python. That copy
      // is gone: the app requires the producer's `ref` and no longer chooses a
      // key, so there is no ranking here to fall behind.
      //
      // What can still fall behind is the guide's *identity*. A provider the
      // registry has never heard of degrades to its bare key - a tab reading
      // `ffvl`, no link out, no attribution - which is survivable but not
      // something to ship unnoticed. `guides.json` comes from the producer, so
      // this fires when the bundled catalogue has a guide the bundled registry
      // does not.
      final providers = <String>{};
      for (final row in rows) {
        for (final token in CatalogRef.tokensOf(field(row, 'source'))) {
          final provider = CatalogRef.providerOf(token);
          if (provider != null) providers.add(provider);
        }
      }

      expect(providers, isNotEmpty, reason: 'a sweep over nothing is not coverage');
      expect(
        providers.where((p) => Guides.of(p) == null),
        isEmpty,
        reason: 'the bundled guides.json does not describe every guide the '
            'bundled catalogue names - run: dart run tool/refresh_bundled_catalogue.dart',
      );
    });

    test('every guide has an id in site_group to build its link from', () {
      // What makes one URL template per guide sufficient, and the property that
      // replaced chopping a `source` id at its first hyphen. A guide named in
      // `source` with no token in `site_group` would leave the app with no id
      // to address that guide's page with - see Guide.siteUrl.
      final orphaned = <String>[];
      for (final row in rows) {
        final groups = {
          for (final token in CatalogRef.tokensOf(field(row, 'site_group')))
            CatalogRef.providerOf(token),
        };
        for (final token in CatalogRef.tokensOf(field(row, 'source'))) {
          if (!groups.contains(CatalogRef.providerOf(token))) {
            orphaned.add('${field(row, 'ref')}: $token');
          }
        }
      }

      expect(orphaned, isEmpty);
    });

    test('a guide page is addressed by site, not by launch', () {
      // The bug this replaced: `id.split('-').first` on a `source` id, which
      // sent every PGE landing to `?site=<takeoff>-lz` and every Australian one
      // to `/sites/details/lz`. 4,828 of 19,759 links.
      //
      // Swept over the real asset rather than a fixture, because the shapes
      // that broke it are landing rows the producer synthesises - exactly what
      // a hand-built fixture would forget to include.
      final suspect = <String>[];
      for (final row in rows) {
        for (final token in CatalogRef.tokensOf(field(row, 'source'))) {
          final provider = CatalogRef.providerOf(token);
          final url = Guides.of(provider!)?.siteUrl(field(row, 'site_group'));
          if (url == null) continue;
          if (url.endsWith('-lz') || url.endsWith('/lz') || url.contains('=lz')) {
            suspect.add('${field(row, 'ref')} -> $url');
          }
        }
      }

      expect(suspect, isEmpty,
          reason: 'a launch suffix reached the URL; the id must come from '
              'site_group, not source');
    });

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
      final guideOnly = rows.where((r) =>
          field(r, 'source').contains('ansg:') &&
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

    test('does not choose between guides', () {
      // This used to assert `ansg:136-40;pge:4632` keyed on pge, from a
      // precedence list hand-copied from the producer's. Choosing is the
      // producer's job and its answer is in the `ref` column; a second opinion
      // here could only ever agree or re-key a launch, and a re-key takes the
      // pilot's favourite with it.
      //
      // What is left is for two backfills over rows stored before federation,
      // whose `source` holds one token. First valid token, no ranking.
      expect(CatalogRef.fromSource('ansg:136-40'), 'ansg:136-40');
      expect(CatalogRef.fromSource('pge:4632'), 'pge:4632');
      expect(CatalogRef.fromSource('ansg:136-40;pge:4632'), 'ansg:136-40',
          reason: 'first token, in the order given - not a preference');
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

    test('the producer emits a key on every row, naming one of its guides', () {
      // This used to assert the emitted ref equalled what the app's own
      // precedence would derive - two statements of one rule, asserted equal.
      // The app no longer has the second statement, so what matters now is that
      // the one authority answers on every row, and that its answer names a
      // guide the row actually lists: the key and the guide tabs both come from
      // this row, and a ref pointing outside `source` would key a launch to a
      // guide the page never shows.
      final rows = csv.decodeWithHeaders(utf8.decode(gzip.decode(
          File('assets/data/world_sites_extracted.csv.gz').readAsBytesSync())));

      expect(rows.first.headerMap.keys, contains('ref'),
          reason: 'the app requires this column and rejects a snapshot without it');

      var checked = 0;
      final orphaned = <String>[];
      for (final row in rows) {
        final emitted = (row['ref'] ?? '').toString();
        expect(emitted, isNotEmpty,
            reason: 'an unkeyed row is a launch the pilot silently loses');
        if (!CatalogRef.tokensOf((row['source'] ?? '').toString())
            .contains(emitted)) {
          orphaned.add(emitted);
        }
        checked++;
      }

      expect(orphaned, isEmpty,
          reason: 'ref must name a guide listed in the same row\'s source');
      expect(checked, greaterThan(11000),
          reason: 'a sweep over nothing reads as coverage');
    });

    test('the shipped catalogue uses the guide\'s current prefix', () {
      // The rewrite that used to map siteguide_au -> ansg on read is gone, so
      // the asset itself has to be native. If it is not, every Australian-only
      // launch keys on a token nothing matches and silently loses its wind and
      // altitude.
      final text = utf8.decode(gzip.decode(
          File('assets/data/world_sites_extracted.csv.gz').readAsBytesSync()));

      expect(text.contains('siteguide_au'), isFalse);
      expect(text.contains('ansg:'), isTrue);
    });

    test('a provider prefix survives a round trip through source', () {
      // Length is a matter of taste - pge is three, ansg four, ffvl will be four
      // - so this asserts the part that is not: a prefix containing either
      // delimiter would be torn apart when `source` is parsed back, and the ref
      // stored against it would never match again.
      for (final provider in Guides.all.map((g) => g.key)) {
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

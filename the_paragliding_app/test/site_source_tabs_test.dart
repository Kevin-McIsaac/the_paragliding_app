import 'package:flutter_test/flutter_test.dart';
import 'package:the_paragliding_app/data/datasources/database_helper.dart';
import 'package:the_paragliding_app/data/models/paragliding_site.dart';
import 'package:the_paragliding_app/services/pge_sites_database_service.dart';

import 'helpers/test_helpers.dart';

/// The site dialog's second tab used to be an unlabelled ⓘ holding
/// ParaglidingEarth data without saying so. A launch can now come from more
/// than one guide, and they disagree - on names, on ratings, sometimes on
/// position - so which one you are reading has to be visible.
void main() {
  ParaglidingSite site(String? source) => ParaglidingSite(
        name: 'Manilla - Mt Borah - West launch',
        latitude: -30.6792,
        longitude: 150.6086,
        siteType: 'launch',
        source: source,
      );

  group('parsing the source column', () {
    test('a merged launch yields one entry per guide, in order', () {
      expect(
        site('pge:4632;siteguide_au:136-20').sources,
        [(provider: 'pge', id: '4632'), (provider: 'siteguide_au', id: '136-20')],
      );
    });

    test('a single-source launch yields one entry', () {
      expect(site('pge:4632').sources, [(provider: 'pge', id: '4632')]);
    });

    test('a guide-only launch does not claim a PGE source', () {
      // The 135 Australian launches PGE has never had.
      final sources = site('siteguide_au:136-21').sources;
      expect(sources, [(provider: 'siteguide_au', id: '136-21')]);
      expect(sources.any((s) => s.provider == 'pge'), isFalse);
    });

    test('a catalogue predating source tracking yields nothing', () {
      // The dialog falls back to a single PGE tab rather than none.
      expect(site(null).sources, isEmpty);
      expect(site('').sources, isEmpty);
    });

    test('a malformed token is skipped rather than throwing', () {
      expect(site('pge:4632;garbage;siteguide_au:1-2').sources.length, 2);
    });

    test('an id containing a colon survives', () {
      expect(site('other:a:b').sources, [(provider: 'other', id: 'a:b')]);
    });
  });

  group('the id used to fetch ParaglidingEarth detail', () {
    // Regression: catalogue ids are no longer PGE ids. Passing one to
    // getSiteDetails matches nothing, and the API silently returns whichever
    // takeoff is first in the bounding box - the wrong launch exactly where
    // launches cluster.
    int? pgeIdOf(ParaglidingSite s) {
      for (final source in s.sources) {
        if (source.provider == 'pge') return int.tryParse(source.id);
      }
      return null;
    }

    test('is PGE own id, not the canonical one', () {
      final merged = ParaglidingSite(
        name: 'Manilla - Mt Borah - West launch',
        latitude: -30.6792,
        longitude: 150.6086,
        siteType: 'launch',
        id: 9247, // canonical
        source: 'pge:4632;siteguide_au:136-20',
      );

      expect(pgeIdOf(merged), 4632);
      expect(pgeIdOf(merged), isNot(merged.id));
    });

    test('is null when no guide here is PGE', () {
      expect(pgeIdOf(site('siteguide_au:136-21')), isNull);
    });
  });

  group('translating a catalogue id back to a guide id', () {
    // The bug this exists for: the dialog built
    // paraglidingearth.com/?site=<catalogue id>. Catalogue 9247 is Mt Borah
    // in the app and "Spitzbuhel - Siusi/Seis am Schlern" on PGE, so the
    // title link opened an unrelated site in another country. Nothing failed;
    // it just went somewhere wrong.
    setUp(() async {
      await TestHelpers.initializeDatabaseForTesting();
      await DatabaseHelper.instance.recreateDatabase();
      await PgeSitesDatabaseService.instance.initializeTables();
      final db = await DatabaseHelper.instance.database;
      await db.insert('pge_sites', {
        'id': 9247,
        'name': 'Manilla - Mt Borah - West launch',
        'longitude': 150.6086,
        'latitude': -30.6792,
        'source': 'pge:4632;siteguide_au:136-20',
      });
      await db.insert('pge_sites', {
        'id': 11526,
        'name': 'Manilla - Mt Borah - East launch',
        'longitude': 150.6116,
        'latitude': -30.6793,
        'source': 'siteguide_au:136-21',
      });
    });

    test('returns the guide id, not the catalogue id', () async {
      expect(
        await PgeSitesDatabaseService.instance.sourceIdFor(9247, 'pge'),
        '4632',
      );
    });

    test('returns null when that guide has no entry for the launch', () async {
      // Linking to PGE here would open whatever site 11526 happens to be.
      expect(
        await PgeSitesDatabaseService.instance.sourceIdFor(11526, 'pge'),
        isNull,
      );
    });

    test('finds a guide listed second', () async {
      expect(
        await PgeSitesDatabaseService.instance.sourceIdFor(9247, 'siteguide_au'),
        '136-20',
      );
    });

    test('returns null for a catalogue id that no longer exists', () async {
      expect(await PgeSitesDatabaseService.instance.sourceIdFor(999999, 'pge'), isNull);
    });
  });
}

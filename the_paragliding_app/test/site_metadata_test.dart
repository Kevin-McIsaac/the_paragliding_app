import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:the_paragliding_app/data/models/guide.dart';
import 'package:the_paragliding_app/data/models/paragliding_site.dart';
import 'package:the_paragliding_app/presentation/screens/site_details_screen.dart';
import 'package:the_paragliding_app/services/pge_sites_database_service.dart';
import 'package:the_paragliding_app/services/pge_sites_download_service.dart';

import 'helpers/test_helpers.dart';

/// What a pilot reads on a site page, checked against what the guides published.
///
/// A launch reaches the screen through four hands: the producer merges the
/// guides into one catalogue row, the download parses it, the import stores it,
/// and the dialog renders it. Every one of those has silently changed a site's
/// meaning before - longitude read as latitude, a wind column read as a boolean,
/// PGE's altitude overruling the producer's choice of DHV's on a merged launch.
/// None of it announces itself: a wrong altitude is a plausible number, and a
/// wrong wind direction sends a pilot to the wrong side of a hill.
///
/// So the subject here is the whole path, per source shape - PGE alone, DHV
/// alone, the Site Guide alone, and each of the two merges - measured against a
/// baseline built from the guides' own columns by
/// `tool/refresh_site_baseline.dart`, which shares no code with the app.
///
/// **What this cannot check.** The catalogue carries one name, one altitude and
/// one wind set per launch, whichever guide the producer picked; the guides it
/// did not pick are named in `source` but their values are gone by the time the
/// app sees the row. So "does the app show DHV's altitude" is not answerable
/// here, and is the producer's test to write. What is answerable, and is what
/// these assert, is that the app shows the catalogue's figures unchanged, and
/// says no more about their provenance than it can back.
void main() {
  const compass = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];

  /// A catalogue row in the producer's column order, so a fixture reads like
  /// the file the app actually downloads.
  String csvRow({
    required String ref,
    required String name,
    required String source,
    String siteType = 'launch',
    double longitude = 8.0,
    double latitude = 47.0,
    int? altitude,
    Map<String, int> wind = const {},
    String siteGroup = '',
    String primary = '',
  }) {
    final cells = [
      '1',
      ref,
      name,
      '$longitude',
      '$latitude',
      altitude?.toString() ?? '',
      'de',
      for (final d in compass) '${wind[d] ?? 0}',
      source,
      '', // closed
      siteType,
      '0', // tow
      siteGroup,
      '', // notes
      primary,
    ];
    return cells.join(',');
  }

  const header = 'id,ref,name,longitude,latitude,altitude,country,'
      'wind_n,wind_ne,wind_e,wind_se,wind_s,wind_sw,wind_w,wind_nw,'
      'source,closed,site_type,tow,site_group,notes,primary';

  String csvOf(List<String> rows) => '$header\n${rows.join('\n')}\n';

  /// Import a catalogue through the paths the app uses: the real parser, then
  /// the real import. Nothing here hand-writes a database row, because the
  /// parse and the import are two of the four hands under test.
  Future<void> importCatalogue(String csvText) async {
    await PgeSitesDatabaseService.instance.initializeTables();
    final snapshot = PgeSitesDownloadService.parseCsvContent(csvText);
    expect(snapshot.skipped, 0, reason: 'the fixture must parse completely');
    final imported =
        await PgeSitesDatabaseService.instance.importSitesData(rows: snapshot.rows);
    expect(imported, isTrue);
  }

  /// The baseline, read at declaration time.
  ///
  /// Synchronous and outside any setUp so the tests below can be *declared*
  /// from it - which is how a launch whose primary guide has no provenance line
  /// gets no test at all, rather than a test that returns early and reports
  /// itself green.
  final baseline = (jsonDecode(
    File('test/fixtures/site_metadata_baseline.json').readAsStringSync(),
  ) as Map<String, dynamic>)['launches'] as Map<String, dynamic>;

  setUpAll(() async {
    await TestHelpers.initializeDatabaseForTesting();
    // Guide labels, links and attribution come from the bundled registry the
    // producer publishes, so a page rendered without it shows raw `source`
    // prefixes - `dhv` where a pilot should read `DHV`. The app loads this at
    // startup; a test that renders the page has to do the same.
    await Guides.load();
  });

  // ===========================================================================
  // The mechanics, on rows written to make each step visible.
  // ===========================================================================
  // Nothing resets the table between these: a complete snapshot deletes every
  // row it does not list, so each import replaces the last. That is the import's
  // own behaviour, and leaning on it here is one more place it is exercised.
  group('the mechanics', () {
    test('a guide is carried into the row it names, whichever guides there are',
        () async {
      await importCatalogue(csvOf([
        csvRow(
          ref: 'pge:1',
          name: 'PGE alone',
          source: 'pge:1',
          altitude: 900,
          wind: const {'W': 1},
        ),
        csvRow(
          ref: 'dhv:2-startplatz',
          name: 'DHV alone',
          source: 'dhv:2-startplatz',
          altitude: 800,
          wind: const {'N': 1},
        ),
        csvRow(
          ref: 'pge:3',
          name: 'Merged',
          source: 'dhv:4-startplatz;pge:3',
          altitude: 700,
          wind: const {'S': 1},
        ),
      ]));

      final pge = await PgeSitesDatabaseService.instance.getSiteByRef('pge:1');
      final dhv = await PgeSitesDatabaseService.instance
          .getSiteByRef('dhv:2-startplatz');
      final merged = await PgeSitesDatabaseService.instance.getSiteByRef('pge:3');

      expect(pge!.sources, [(provider: 'pge', id: '1')]);
      expect(dhv!.sources, [(provider: 'dhv', id: '2-startplatz')]);
      // In the producer's order, not re-sorted: the order is what the tabs show.
      expect(merged!.sources, [
        (provider: 'dhv', id: '4-startplatz'),
        (provider: 'pge', id: '3'),
      ]);
      expect([pge.name, dhv.name, merged.name],
          ['PGE alone', 'DHV alone', 'Merged']);
      expect([pge.altitude, dhv.altitude, merged.altitude], [900, 800, 700]);
    });

    test('the guide whose record won survives the import', () async {
      // `source` says which guides describe a launch; `primary` says which one
      // supplied its name, wind and position. The site page can only attribute
      // the figures it shows if this reaches it.
      await importCatalogue(csvOf([
        csvRow(
          ref: 'pge:3',
          name: 'Named by DHV',
          source: 'dhv:4-startplatz;pge:3',
          primary: 'dhv',
        ),
        csvRow(ref: 'pge:5', name: 'PGE alone', source: 'pge:5', primary: 'pge'),
      ]));

      final merged = await PgeSitesDatabaseService.instance.getSiteByRef('pge:3');
      final alone = await PgeSitesDatabaseService.instance.getSiteByRef('pge:5');

      expect(merged!.primarySource, 'dhv');
      expect(alone!.primarySource, 'pge');
      expect(merged.catalogRef, 'pge:3',
          reason: 'the key is still the ref, which primary does not move');
    });

    test('a catalogue without the column leaves it unknown, not guessed',
        () async {
      // Every install until the producer's column reaches it. Defaulting to the
      // first source here would have the page attribute a launch to a guide
      // nobody said it came from - worse than saying nothing.
      final parsed = PgeSitesDownloadService.parseCsvContent(
        'ref,name,longitude,latitude,altitude,source,site_type\n'
        'pge:7,Older catalogue,8.0,47.0,900,dhv:8-x;pge:7,launch\n',
      );
      expect(parsed.skipped, 0);
      await PgeSitesDatabaseService.instance.initializeTables();
      await PgeSitesDatabaseService.instance.importSitesData(rows: parsed.rows);

      final site = await PgeSitesDatabaseService.instance.getSiteByRef('pge:7');
      expect(site!.primarySource, isNull);
      expect(site.sources, hasLength(2), reason: 'the guides are still known');
    });

    test('a wind cell is a rating, not a flag', () async {
      // The guides publish 0, 1 (good) and 2 (excellent). A 2 is a direction
      // you can launch in, and reading the column as `== 1` would silently
      // drop the *best* directions a site has - 13,139 cells of the published
      // catalogue are 2s, more than the 11,531 that are 1s.
      await importCatalogue(csvOf([
        csvRow(
          ref: 'pge:1',
          name: 'Rated',
          source: 'pge:1',
          wind: const {'NE': 2, 'E': 1, 'SE': 0},
        ),
      ]));

      final site = await PgeSitesDatabaseService.instance.getSiteByRef('pge:1');
      expect(site!.windDirections, ['NE', 'E']);
    });

    test('wind directions come back in compass order', () async {
      // Not the order the columns happen to sit in, and not alphabetical: the
      // dialog joins this list with commas and shows it as it stands, so "NE,
      // E, SE" has to read the way a pilot reads a compass.
      await importCatalogue(csvOf([
        csvRow(
          ref: 'pge:1',
          name: 'All round',
          source: 'pge:1',
          wind: {for (final d in compass) d: 1},
        ),
      ]));

      final site = await PgeSitesDatabaseService.instance.getSiteByRef('pge:1');
      expect(site!.windDirections, compass);
    });

    test('a site with no direction at all offers none', () async {
      // 3,914 launches and 5,882 landings in the published catalogue have no
      // wind column set. An empty list is what the dialog needs to suppress
      // the rose and the flyability verdict; a default direction here would
      // read as a checked answer.
      await importCatalogue(csvOf([
        csvRow(ref: 'pge:1', name: 'Unrated', source: 'pge:1'),
      ]));

      final site = await PgeSitesDatabaseService.instance.getSiteByRef('pge:1');
      expect(site!.windDirections, isEmpty);
    });

    test('a missing altitude stays missing', () async {
      // Not 0. A launch at sea level and a launch nobody measured are
      // different statements, and "0 m AMSL" is only one of them.
      await importCatalogue(csvOf([
        csvRow(ref: 'pge:1', name: 'Unmeasured', source: 'pge:1'),
      ]));

      final site = await PgeSitesDatabaseService.instance.getSiteByRef('pge:1');
      expect(site!.altitude, isNull);
    });

    test('a landing is found through the group it shares with its launch',
        () async {
      // Not by distance: a landing sits a median 1.7km from its launch, and a
      // neighbouring hill's field is often closer than your own. The tokens
      // cross providers, so a DHV-keyed landing has to be reachable from a
      // launch keyed under PGE.
      await importCatalogue(csvOf([
        csvRow(
          ref: 'pge:1',
          name: 'Launch',
          source: 'dhv:9-startplatz;pge:1',
          altitude: 1000,
          siteGroup: 'dhv:9;pge:1',
        ),
        csvRow(
          ref: 'dhv:9-landeplatz',
          name: 'Landing',
          source: 'dhv:9-landeplatz',
          siteType: 'landing',
          altitude: 400,
          siteGroup: 'dhv:9',
        ),
        csvRow(
          ref: 'dhv:99-landeplatz',
          name: 'Someone else’s landing',
          source: 'dhv:99-landeplatz',
          siteType: 'landing',
          altitude: 400,
          siteGroup: 'dhv:99',
          longitude: 8.0001,
          latitude: 47.0001, // nearer, and not this launch's
        ),
      ]));

      final launch =
          await PgeSitesDatabaseService.instance.getSiteByRef('pge:1');
      final landings =
          await PgeSitesDatabaseService.instance.getLandingsForSite(launch!);

      expect(landings.map((l) => l.name), ['Landing']);
      expect(heightAboveLanding(launch.altitude, landings.first.altitude), 600);
    });

    test('and the same group names the launches a landing serves', () async {
      // The join read the other way, which is what a landing's own page shows.
      // The relationship the guides publish is symmetric; the app used to be
      // able to walk it in one direction only, so a landing was reachable but
      // could not say what it was for.
      //
      // Same fixture shape as above: the landing is keyed under DHV and its
      // launch under PGE, so this crosses providers too.
      await importCatalogue(csvOf([
        csvRow(
          ref: 'pge:1',
          name: 'Launch',
          source: 'dhv:9-startplatz;pge:1',
          altitude: 1000,
          siteGroup: 'dhv:9;pge:1',
        ),
        csvRow(
          ref: 'dhv:9-landeplatz',
          name: 'Landing',
          source: 'dhv:9-landeplatz',
          siteType: 'landing',
          altitude: 400,
          siteGroup: 'dhv:9',
        ),
        csvRow(
          ref: 'pge:2',
          name: 'Someone else’s launch',
          source: 'pge:2',
          altitude: 900,
          siteGroup: 'pge:2',
          longitude: 8.0001,
          latitude: 47.0001, // nearer, and not this landing's
        ),
      ]));

      final landing = await PgeSitesDatabaseService.instance
          .getSiteByRef('dhv:9-landeplatz');
      final launches = await PgeSitesDatabaseService.instance
          .getLaunchesForLanding(landing!);

      expect(launches.map((l) => l.name), ['Launch'],
          reason: 'the nearer launch shares no group token with it');
    });

    test('a landing above its launch produces no height, rather than a negative',
        () {
      // Winch and flatland sites, and altitudes nobody filled in. "-401 m"
      // beside a launch reads as a bug in the app rather than a gap in the data.
      expect(heightAboveLanding(400, 800), isNull);
      expect(heightAboveLanding(400, 400), isNull);
      expect(heightAboveLanding(null, 400), isNull);
      expect(heightAboveLanding(400, null), isNull);
    });
  });

  // ===========================================================================
  // The baseline, on rows the producer actually published.
  // ===========================================================================
  group('the baseline', () {
    setUpAll(() async {
      await importCatalogue(
        File('test/fixtures/site_metadata_catalogue.csv').readAsStringSync(),
      );
    });

    test('the baseline covers every source shape the catalogue publishes', () {
      // A baseline that quietly lost a shape would keep passing while the shape
      // it covered went unchecked. The published catalogue has five.
      final shapes = <String>{};
      for (final entry in baseline.values) {
        final providers = [
          for (final source in (entry as Map)['sources'] as List)
            (source as Map)['provider'] as String,
        ]..sort();
        shapes.add(providers.join('+'));
      }

      expect(shapes, {'pge', 'dhv', 'ansg', 'dhv+pge', 'ansg+pge'});
    });

    for (final ref in const [
      'pge:10004',
      'dhv:1009-neuwied-rodenbach-startplatz',
      'ansg:138-251',
      'pge:10043',
      'pge:10170',
      'pge:11480',
    ]) {
      test('$ref reaches the model as the guides published it', () async {
        final expected = baseline[ref] as Map<String, dynamic>;
        final site = await PgeSitesDatabaseService.instance.getSiteByRef(ref);

        expect(site, isNotNull, reason: 'the fixture must contain $ref');
        expect(site!.name, expected['name']);
        expect(site.altitude, expected['altitude_m']);
        expect(site.windDirections, expected['wind']);
        expect(site.catalogRef, ref);
        // Which guide the name and wind just checked actually came from. Every
        // merged launch here is keyed under one guide and named by another -
        // Stauf is `pge:10043` with DHV's name - so a row that lost this would
        // still look entirely plausible.
        expect(site.primarySource, expected['primary']);
        expect(
          [for (final s in site.sources) '${s.provider}:${s.id}'],
          [
            for (final source in expected['sources'] as List)
              '${(source as Map)['provider']}:${source['id']}',
          ],
        );

        final landings =
            await PgeSitesDatabaseService.instance.getLandingsForSite(site);
        expect(
          landings.map((l) => l.catalogRef),
          [for (final l in expected['landings'] as List) (l as Map)['ref']],
          reason: 'nearest first - it decides which landing the height uses',
        );
        expect(
          heightAboveLanding(site.altitude, landings.first.altitude),
          expected['height_above_landing_m'],
        );
      });
    }
  });

  // ===========================================================================
  // What the pilot actually reads.
  // ===========================================================================
  group('the site page', () {
    // Resolved before any widget test runs. A `testWidgets` body executes in
    // fake async, so awaiting a real database read inside one deadlocks the
    // guarded pump machinery rather than returning a site.
    final sites = <String, ParaglidingSite>{};

    setUpAll(() async {
      await importCatalogue(
        File('test/fixtures/site_metadata_catalogue.csv').readAsStringSync(),
      );

      for (final ref in baseline.keys) {
        final site = await PgeSitesDatabaseService.instance.getSiteByRef(ref);
        expect(site, isNotNull, reason: 'the fixture must contain $ref');
        sites[ref] = site!;
      }
    });

    /// Pump the page, let its own database reads finish, and let its network
    /// fetches fail.
    ///
    /// The page loads its landings from the catalogue itself - that is the read
    /// the height above landing depends on - and real I/O does not advance on
    /// fake time, so it is drained inside `runAsync` before the frames that
    /// render it. Wind, forecast and the ParaglidingEarth lookup all fail in a
    /// test binding, which is the point: every figure asserted below then has
    /// to have come from the catalogue. pumpAndSettle is no use here - a
    /// progress indicator animates forever - so frames are pumped by hand.
    Future<void> pumpSite(WidgetTester tester, ParaglidingSite site) async {
      tester.view.physicalSize = const Size(411, 923);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        home: SiteDetailsScreen(
          paraglidingSite: site,
          maxWindSpeed: 25,
          cautionWindSpeed: 15,
        ),
      ));

      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );

      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    for (final ref in const [
      'pge:10004',
      'dhv:1009-neuwied-rodenbach-startplatz',
      'ansg:138-251',
      'pge:10043',
      'pge:10170',
      'pge:11480',
    ]) {
      testWidgets('$ref shows the name, altitude, drop and wind it was given',
          (tester) async {
        final expected = baseline[ref] as Map<String, dynamic>;
        await pumpSite(tester, sites[ref]!);

        expect(find.text(expected['name'] as String), findsWidgets);
        expect(find.text('${expected['altitude_m']} m AMSL'), findsOneWidget);
        expect(
          find.text('${expected['height_above_landing_m']} m'),
          findsOneWidget,
          reason: 'launch minus its nearest landing',
        );
        expect(
          find.text((expected['wind'] as List).join(', ')),
          findsWidgets,
        );
      });

      // Declared only where there is something to assert. The ParaglidingEarth
      // tab is the live lookup rather than a guide summary and carries no
      // provenance line, so a PGE-primary launch gets no test here instead of
      // one that returns early and reports itself green.
      final primary = (baseline[ref] as Map<String, dynamic>)['primary'];
      if (primary != null && primary != 'pge') {
        final label = switch (primary as String) {
          'ansg' => 'ANSG',
          'dhv' => 'DHV',
          final other => other,
        };
        final fullName = switch (primary) {
          'ansg' => 'Australian National Site Guide',
          'dhv' => 'DHV Geländedatenbank',
          final other => other,
        };

        testWidgets('$ref attributes its figures to $label', (tester) async {
          // The real thing, on published rows: the synthetic tests below cover
          // the three wordings, this checks the app picks the right one from a
          // catalogue nobody wrote for the test. Every merged launch in the
          // baseline is keyed under PGE and named by its national guide.
          await pumpSite(tester, sites[ref]!);
          await tester.tap(find.widgetWithText(Tab, label));
          for (var i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 200));
          }

          expect(
            find.textContaining('as $fullName records this'),
            findsOneWidget,
          );
        });
      }

      testWidgets('$ref names every guide behind it', (tester) async {
        final expected = baseline[ref] as Map<String, dynamic>;
        await pumpSite(tester, sites[ref]!);

        for (final source in expected['sources'] as List) {
          final label = switch ((source as Map)['provider'] as String) {
            'pge' => 'PGE',
            'ansg' => 'ANSG',
            'dhv' => 'DHV',
            final other => other,
          };
          expect(find.widgetWithText(Tab, label), findsOneWidget,
              reason: 'a guide that contributed this launch needs a tab');
        }
      });
    }

    testWidgets('a guide tab shows the catalogue figures', (tester) async {
      await pumpSite(tester, sites['pge:10043']!);

      await tester.tap(find.widgetWithText(Tab, 'DHV'));
      // Six frames, not one: the tab transition animates, and a single 400ms
      // pump left the body unbuilt and the assertions looking like a missing
      // altitude rather than a tab that had not finished sliding.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }

      expect(find.text('Stauf Startplatz Südost'), findsWidgets);
      expect(find.text('260 m'), findsOneWidget);
      expect(find.text('E, S, SW'), findsWidgets);
    });

    /// Open [ref]'s tab for [provider] and return the provenance line under the
    /// guide's name.
    Future<String> provenanceOn(
      WidgetTester tester,
      ParaglidingSite site,
      String label,
    ) async {
      await pumpSite(tester, site);
      await tester.tap(find.widgetWithText(Tab, label));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }

      // The line sits directly under the guide's full name in the tab body.
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .whereType<String>();
      return texts.firstWhere(
        (t) => t.contains('records this') || t.contains('the guides behind') ||
            t.contains('Also describes'),
        orElse: () => '<no provenance line>',
      );
    }

    ParaglidingSite merged({String? primary}) => ParaglidingSite(
          name: 'Stauf Startplatz Südost',
          latitude: 49.54949,
          longitude: 8.027519,
          altitude: 260,
          siteType: 'launch',
          windDirections: const ['E', 'S', 'SW'],
          source: 'dhv:146-stauf-startplatz-suedost;pge:10043',
          catalogRef: 'pge:10043',
          primarySource: primary,
        );

    testWidgets('the guide whose record won says so', (tester) async {
      // The whole point of the producer emitting `primary`. Before it, this tab
      // introduced the catalogue's figures as "this launch as DHV records it"
      // on every guide, backed by nothing.
      expect(
        await provenanceOn(tester, merged(primary: 'dhv'), 'DHV'),
        'The name, wind and position below are as DHV Geländedatenbank records '
        'this launch.',
      );
    });

    testWidgets('a guide that did not win points at the one that did',
        (tester) async {
      // A pilot reading the DHV tab on a launch ParaglidingEarth named has to
      // be told, or the tab reads as DHV's own record of the place.
      expect(
        await provenanceOn(tester, merged(primary: 'pge'), 'DHV'),
        'Also describes this launch. The name, wind and position below are as '
        'ParaglidingEarth records it - open DHV for its own.',
      );
    });

    testWidgets('a catalogue that never said claims nothing', (tester) async {
      // Every install until the producer's column reaches it, and every row of
      // an older bundled asset. Saying "we do not know" is the only honest
      // answer, and is what this shipped as before `primary` existed.
      expect(
        await provenanceOn(tester, merged(), 'DHV'),
        'One of the guides behind this launch. The catalogue does not say '
        'which of them its name, wind and position came from.',
      );
    });
  });

  // ===========================================================================
  // Whether the baseline still describes what the producer publishes.
  // ===========================================================================
  group('the published catalogue', () {
    test('still carries the pinned launches, unchanged', () async {
      // The widget tests above initialise the test binding, which installs an
      // HttpOverrides that answers every request with 400. A live check in the
      // same file has to step outside it, or it fails as "the catalogue served
      // 400" - which reads as an outage upstream rather than as the binding
      // doing exactly what it is there for.
      final overrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = overrides);

      final baseline = jsonDecode(
        File('test/fixtures/site_metadata_baseline.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final launches = baseline['launches'] as Map<String, dynamic>;

      final response =
          await http.get(Uri.parse(PgeSitesConfig.catalogUrl)).timeout(
                const Duration(seconds: 60),
              );
      expect(response.statusCode, 200);

      final snapshot = PgeSitesDownloadService.parseCsvContent(response.body);
      final byRef = {
        for (final row in snapshot.rows)
          if (row['ref'] != null) row['ref'] as String: row,
      };

      final moved = <String>[];
      launches.forEach((ref, expectedAny) {
        final expected = expectedAny as Map<String, dynamic>;
        final row = byRef[ref];
        if (row == null) {
          moved.add('$ref: withdrawn from the catalogue');
          return;
        }

        final wind = [
          for (final d in compass)
            if ((row['wind_${d.toLowerCase()}'] as int? ?? 0) > 0) d,
        ];
        if (row['name'] != expected['name']) {
          moved.add('$ref: name ${expected['name']} -> ${row['name']}');
        }
        if (row['altitude'] != expected['altitude_m']) {
          moved.add(
              '$ref: altitude ${expected['altitude_m']} -> ${row['altitude']}');
        }
        if (wind.join(',') != (expected['wind'] as List).join(',')) {
          moved.add('$ref: wind ${expected['wind']} -> $wind');
        }
        // A launch changing hands between guides is exactly the kind of quiet
        // move worth reviewing: the name and wind on the page change with it.
        if (row['primary'] != expected['primary']) {
          moved.add(
              '$ref: primary ${expected['primary']} -> ${row['primary']}');
        }
      });

      // Not a failure of the app - a signal that the baseline has aged out and
      // wants regenerating, deliberately, so the change is reviewed rather than
      // absorbed. Run: dart run tool/refresh_site_baseline.dart
      expect(
        moved,
        isEmpty,
        reason: 'the published catalogue has moved under the baseline; '
            'regenerate it with tool/refresh_site_baseline.dart',
      );
    }, tags: ['network']);
  });
}

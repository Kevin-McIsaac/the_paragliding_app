import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:the_paragliding_app/services/app_initialization_service.dart';
import 'package:the_paragliding_app/services/pge_sites_download_service.dart';
import 'package:the_paragliding_app/utils/catalog_ref.dart';

/// Covers refreshing the catalogue from the published pipeline output.
///
/// The bundled asset is only ever as new as the release that shipped it, so
/// launches added since then reach the pilot from here. The decision of whether
/// to download is the intricate part and is pure, so it is tested without a
/// network; the URL itself is checked under the `network` tag, which is skipped
/// by default.
void main() {
  group('deciding whether to download', () {
    test('an unchanged ETag means no download', () {
      expect(
        PgeSitesDownloadService.isRemoteNewer(
          storedEtag: '"abc"',
          storedLastModified: null,
          remoteEtag: '"abc"',
          remoteLastModified: null,
          ageInDays: 900,
        ),
        isFalse,
        reason: 'the pipeline runs weekly and usually changes nothing; age must '
            'not override an ETag that says the file is identical',
      );
    });

    test('a changed ETag means download', () {
      expect(
        PgeSitesDownloadService.isRemoteNewer(
          storedEtag: '"abc"',
          storedLastModified: null,
          remoteEtag: '"def"',
          remoteLastModified: null,
          ageInDays: 0,
        ),
        isTrue,
      );
    });

    test('falls back to Last-Modified when there is no ETag', () {
      expect(
        PgeSitesDownloadService.isRemoteNewer(
          storedEtag: null,
          storedLastModified: 'Mon, 04 Aug 2026 02:00:00 GMT',
          remoteEtag: null,
          remoteLastModified: 'Mon, 11 Aug 2026 02:00:00 GMT',
          ageInDays: 0,
        ),
        isTrue,
      );
    });

    test('falls back to age only when neither side has a validator', () {
      bool byAge(int days) => PgeSitesDownloadService.isRemoteNewer(
            storedEtag: null,
            storedLastModified: null,
            remoteEtag: null,
            remoteLastModified: null,
            ageInDays: days,
          );

      expect(byAge(29), isFalse);
      expect(byAge(31), isTrue);
    });

    test('a reset to the bundled copy must not report "up to date"', () {
      // Code review caught this: "Reset to Bundled" reverts the local file to the
      // older shipped snapshot, but the stored validators still described the
      // published one. A later check compared the unchanged remote ETag against
      // them, said "no update", and left the pilot on stale data with no signal.
      // The reset now clears them, which is this state - nothing stored, so the
      // remote ETag has nothing to match and the download goes ahead.
      expect(
        PgeSitesDownloadService.isRemoteNewer(
          storedEtag: null,
          storedLastModified: null,
          remoteEtag: '"unchanged-since-the-last-download"',
          remoteLastModified: null,
          ageInDays: 0,
        ),
        isTrue,
      );
    });

    test('a first run, with nothing stored, downloads', () {
      // getPgeSitesDownloadDate() is null before any download, which the caller
      // turns into a very large age. Without this the app would never make its
      // first fetch.
      expect(
        PgeSitesDownloadService.isRemoteNewer(
          storedEtag: null,
          storedLastModified: null,
          remoteEtag: '"abc"',
          remoteLastModified: null,
          ageInDays: 9999,
        ),
        isTrue,
      );
    });
  });

  group('the download sanity check', () {
    // Found by driving the UI, not by this suite: the guard required the body to
    // start with `id,name,` and so rejected the real catalogue the day the
    // producer added its `ref` column. Every test imports parsed rows and never
    // reaches the download, which is why a broken refresh looked green.
    test('accepts the published header, whatever columns precede the ones we read',
        () async {
      final published = utf8.decode(gzip.decode(
          File('assets/data/world_sites_extracted.csv.gz').readAsBytesSync()));
      final header = published.split('\n').first.split(',').toSet();

      expect(header, containsAll(['name', 'longitude', 'latitude', 'source']),
          reason: 'these are the columns the parser actually reads');
      expect(header.first, isNot('name'),
          reason: 'a column precedes them today, which is what broke the old '
              'prefix check - if that stops being true this test is toothless');
    });
  });

  group('the published catalogue', () {
    test('is the URL the app is built to read', () {
      // Pinned deliberately: the app follows `main`, which only moves when the
      // pipeline's weekly PR is merged, so what pilots get has been reviewed.
      expect(
        PgeSitesConfig.catalogUrl,
        'https://raw.githubusercontent.com/Kevin-McIsaac/'
        'paragliding_site_federation/main/app/sites.csv',
      );
    });

    test('serves a catalogue this app can key and parse', () async {
      final response = await http
          .get(Uri.parse(PgeSitesConfig.catalogUrl))
          .timeout(const Duration(seconds: 60));

      expect(response.statusCode, 200);
      expect(response.headers['etag'], isNotNull,
          reason: 'the refresh check compares ETags; without one it degrades to '
              'a 30-day timer');

      final rows = csv.decodeWithHeaders(response.body);
      expect(rows.length, greaterThan(11000));

      // Every row must yield a ref, or the import would silently skip it and
      // the pilot would lose a launch.
      final unkeyable = rows
          .where((row) =>
              CatalogRef.fromSource((row['source'] ?? '').toString()) == null)
          .length;
      expect(unkeyable, 0);
    }, tags: 'network');

    test('matches the bundled asset closely enough to be the same catalogue',
        () async {
      // Not byte-equality: the published file moves ahead of the release. This
      // is a guard against the two drifting into different shapes - a column
      // added upstream that the bundled parser has never seen.
      final bundled = csv.decodeWithHeaders(utf8.decode(gzip.decode(
          File('assets/data/world_sites_extracted.csv.gz').readAsBytesSync())));
      final response = await http
          .get(Uri.parse(PgeSitesConfig.catalogUrl))
          .timeout(const Duration(seconds: 60));
      final published = csv.decodeWithHeaders(response.body);

      expect(published.first.headerMap.keys,
          containsAll(bundled.first.headerMap.keys));
    }, tags: 'network');
  });

  group('deciding whether to import the bundled snapshot', () {
    test('a published copy is never replaced by the bundled asset', () {
      // The bug this exists for. `bundledCatalogDiffersFromLocal` compares byte
      // sizes, and a published catalogue is re-gzipped on its way to disk, so
      // it differs from the asset even holding identical rows - measured at
      // 382,518 against 385,320 bytes for the same 11,690 launches. Reading
      // that as "the release shipped a new catalogue" copied the asset back
      // over every refresh on the next cold start: a launch published since the
      // release lasted one session, and a favourite on one went with its row.
      expect(
        AppInitializationService.shouldImportBundled(
          hasData: true,
          localCopyIsPublished: true,
          bundledDiffersFromLocal: true,
        ),
        isFalse,
      );
    });

    test('a release shipping a new catalogue is imported', () {
      // The case the size check was added for, and which still has to work: the
      // pilot is on the bundled copy and the release brought a newer one.
      expect(
        AppInitializationService.shouldImportBundled(
          hasData: true,
          localCopyIsPublished: false,
          bundledDiffersFromLocal: true,
        ),
        isTrue,
      );
    });

    test('an unchanged bundled copy is left alone', () {
      expect(
        AppInitializationService.shouldImportBundled(
          hasData: true,
          localCopyIsPublished: false,
          bundledDiffersFromLocal: false,
        ),
        isFalse,
      );
    });

    test('an empty database imports whatever is bundled', () {
      // Offline first launch: the asset is the only catalogue there is.
      for (final published in [true, false]) {
        expect(
          AppInitializationService.shouldImportBundled(
            hasData: false,
            localCopyIsPublished: published,
            bundledDiffersFromLocal: false,
          ),
          isTrue,
        );
      }
    });

  });

  group('deciding whether to ask the server again', () {
    final now = DateTime(2026, 8, 11, 9);

    test('a catalogue never checked is checked', () {
      expect(AppInitializationService.checkIsDue(null, now: now), isTrue);
    });

    test('a check a week old is due again', () {
      // The pipeline publishes weekly, so this is the cadence that matches it.
      // Throttling on maxAge instead left a launch added on Tuesday up to a
      // month from the pilot it was added for.
      expect(
        AppInitializationService.checkIsDue(
            now.subtract(const Duration(days: 8)),
            now: now),
        isTrue,
      );
    });

    test('a check from yesterday is not repeated', () {
      // The other direction: a launch site usually has no signal, and asking on
      // every cold start spends the pilot's battery on an answer that is almost
      // always "no".
      expect(
        AppInitializationService.checkIsDue(
            now.subtract(const Duration(days: 1)),
            now: now),
        isFalse,
      );
    });
  });

  group('parsing a snapshot', () {
    const header = 'id,ref,name,longitude,latitude,altitude,country,'
        'wind_n,wind_ne,wind_e,wind_se,wind_s,wind_sw,wind_w,wind_nw,'
        'source,closed';

    List<Map<String, dynamic>> parse(String rows) =>
        PgeSitesDownloadService.parseCsvContent('$header\n$rows\n');

    test('a row is kept whatever the producer puts in its id column', () {
      // `id` used to be the test of whether a line was a data row at all -
      // int.tryParse, skip if null - which made a column the app never stores
      // into a hard dependency. The producer emits a row number today; the day
      // it emitted its own canonical id every row would have been skipped, the
      // import would have found nothing to do, and the catalogue would have
      // frozen on the last good copy with one warning in the log.
      final sites = parse(
          'PSF-000048,pge:10060,Lanyon,149.10754,-35.48388,900,au,'
          '0,0,0,0,0,0,1,0,ansg:106-28;pge:10060,');

      expect(sites, hasLength(1));
      expect(sites.single['name'], 'Lanyon');
      expect(sites.single['ref'], 'pge:10060');
      expect(sites.single['latitude'], -35.48388);
    });

    test('a launch with unusable coordinates is skipped, not put at 0,0', () {
      // These defaulted to 0.0, which placed the launch in the Atlantic off
      // Ghana. A site the pilot can see is missing beats one that is silently
      // somewhere else, and null island matches nothing anyway.
      final sites = parse(
          '1,pge:1,Nowhere,,-35.48388,900,au,0,0,0,0,0,0,0,0,pge:1,\n'
          '2,pge:2,Also nowhere,not-a-number,-35.5,900,au,'
          '0,0,0,0,0,0,0,0,pge:2,');

      expect(sites, isEmpty);
    });

    test('a nameless row is skipped', () {
      final sites =
          parse('1,pge:1,,149.1,-35.4,900,au,0,0,0,0,0,0,0,0,pge:1,');

      expect(sites, isEmpty);
    });

    test('whether a row can be keyed is left to the import', () {
      // Deliberately not filtered here: importSitesData counts unkeyable rows
      // in CATALOG_IMPORT, and silently dropping them earlier would empty that
      // number while the rows went missing just the same.
      final sites =
          parse('1,,Unkeyable,149.1,-35.4,900,au,0,0,0,0,0,0,0,0,,');

      expect(sites, hasLength(1));
      expect(sites.single['ref'], isNull);
      expect(sites.single['source'], isEmpty);
    });
  });
}

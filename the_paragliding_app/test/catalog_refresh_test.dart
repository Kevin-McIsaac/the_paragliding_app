import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
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
}

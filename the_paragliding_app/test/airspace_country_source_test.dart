import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:the_paragliding_app/services/airspace_country_service.dart';

/// Airspace loading broke because OpenAIP moved their public export bucket, not
/// because any app code was wrong. The old GCS bucket was switched to Requester
/// Pays (openAIP/openaip#468) and every anonymous download started returning
/// HTTP 400 UserProjectMissing, so no country could be downloaded and the map
/// showed no airspace.
///
/// Two tests, deliberately split:
///
///  * the offline one guards against the URL being reverted or "tidied" back to
///    the dead bucket, and runs in the default suite;
///  * the network one is the only kind of test that can catch the bucket moving
///    *again* - the code stays correct while the host stops serving. It is
///    tagged `network` and skipped by default:
///        flutter test --tags network --run-skipped
void main() {
  group('airspace country export URL', () {
    test('is built from the live OpenAIP export bucket', () {
      final url = AirspaceCountryService.countryDataUrl('AU');

      expect(
        url,
        'https://storage.openaip.net/openaip-system-exports/au_asp.geojson',
      );

      // The specific failure this file exists to prevent. The old bucket still
      // resolves and still answers - with HTTP 400 for everyone - so pointing
      // back at it fails at runtime, not at build time.
      expect(
        url,
        isNot(contains('storage.googleapis.com')),
        reason:
            'The GCS export bucket is Requester Pays since 2026-07-23 and '
            'returns 400 UserProjectMissing to anonymous clients.',
      );
    });

    test('lower-cases the country code to match the published filenames', () {
      // availableCountries keys are upper case ('AU'); the files are not.
      expect(
        AirspaceCountryService.countryDataUrl('NZ'),
        endsWith('/nz_asp.geojson'),
      );
      expect(
        AirspaceCountryService.countryDataUrl('gb'),
        endsWith('/gb_asp.geojson'),
      );
    });
  });

  // The refresh check exists so a country that has not changed is not
  // re-downloaded - 13 MB for Australia. Getting this wrong is quiet in both
  // directions: too eager burns the user's data and OpenAIP's egress budget,
  // too lazy leaves stale airspace on the map, which is safety data.
  group('isRemoteNewer', () {
    const anEtag = '"fd64da8f00b7dea96f5b16640be501f8"';
    const anotherEtag = '"514b4f4cfb4d511f9a7f86874061ee94-3"';
    const aDate = 'Thu, 06 Aug 2026 01:09:06 GMT';
    const laterDate = 'Fri, 07 Aug 2026 02:11:00 GMT';

    bool check({
      String? storedEtag,
      String? storedLastModified,
      String? remoteEtag,
      String? remoteLastModified,
      int ageInDays = 0,
    }) => AirspaceCountryService.isRemoteNewer(
      storedEtag: storedEtag,
      storedLastModified: storedLastModified,
      remoteEtag: remoteEtag,
      remoteLastModified: remoteLastModified,
      ageInDays: ageInDays,
    );

    test('matching ETag means no update', () {
      expect(check(storedEtag: anEtag, remoteEtag: anEtag), isFalse);
    });

    test('different ETag means an update', () {
      expect(check(storedEtag: anEtag, remoteEtag: anotherEtag), isTrue);
    });

    test('ETag wins over Last-Modified when both are available', () {
      // The daily rebuild moves Last-Modified even when the airspace is
      // byte-identical, so trusting the date would re-download every day.
      expect(
        check(
          storedEtag: anEtag,
          remoteEtag: anEtag,
          storedLastModified: aDate,
          remoteLastModified: laterDate,
        ),
        isFalse,
      );
    });

    test('falls back to Last-Modified when no ETag is comparable', () {
      expect(
        check(storedLastModified: aDate, remoteLastModified: aDate),
        isFalse,
      );
      expect(
        check(storedLastModified: aDate, remoteLastModified: laterDate),
        isTrue,
      );
    });

    test('falls back to age when neither validator is comparable', () {
      // Data stored before validators were recorded, or a server that stops
      // sending them.
      expect(check(ageInDays: 3), isFalse);
      expect(check(ageInDays: 31), isTrue);
    });

    test('a validator on only one side is not treated as a match', () {
      // Comparing something against nothing must not silently mean "unchanged".
      expect(check(remoteEtag: anEtag, ageInDays: 31), isTrue);
      expect(check(storedEtag: anEtag, ageInDays: 31), isTrue);
      expect(check(remoteEtag: anEtag, ageInDays: 1), isFalse);
    });
  });

  group('airspace country export bucket', () {
    test(
      'serves parseable GeoJSON in the shape the overlay expects',
      () async {
        // NZ is the smallest of the supported countries (~1.7 MB).
        final url = AirspaceCountryService.countryDataUrl('NZ');
        final response = await http
            .get(Uri.parse(url))
            .timeout(const Duration(minutes: 2));

        expect(
          response.statusCode,
          200,
          reason:
              'Export bucket did not serve $url. If this is 400 with '
              'UserProjectMissing, the bucket has been locked down again - see '
              'openAIP/openaip#468 and #469.',
        );

        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        expect(decoded['type'], 'FeatureCollection');

        final features = decoded['features'] as List<dynamic>;
        expect(features, isNotEmpty);

        // The fields the airspace overlay actually reads. A file that parses
        // but has lost these would render nothing, which looks identical to
        // the outage this test is guarding against.
        final properties =
            (features.first as Map<String, dynamic>)['properties']
                as Map<String, dynamic>;
        expect(
          properties.keys,
          containsAll(<String>[
            'name',
            'type',
            'icaoClass',
            'upperLimit',
            'lowerLimit',
          ]),
        );

        final geometry =
            (features.first as Map<String, dynamic>)['geometry']
                as Map<String, dynamic>;
        expect(geometry['type'], 'Polygon');
      },
      tags: ['network'],
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}

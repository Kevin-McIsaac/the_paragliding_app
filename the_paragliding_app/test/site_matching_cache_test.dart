import 'package:flutter_test/flutter_test.dart';
import 'package:the_paragliding_app/data/models/site.dart';
import 'package:the_paragliding_app/services/site_matching_service.dart';
import 'helpers/test_helpers.dart';

void main() {
  group('SiteMatchingService.cacheSite', () {
    late SiteMatchingService service;

    setUpAll(() async {
      await TestHelpers.initializeDatabaseForTesting();
    });

    setUp(() async {
      service = SiteMatchingService.instance;
      // API off: a cache miss returns null instead of reaching the network, so
      // these tests stay offline and deterministic
      service.setApiEnabled(false);
      await service.reload();
    });

    tearDown(() => service.setApiEnabled(true));

    test('a cached site is found locally afterwards', () async {
      const launchLat = 46.5;
      const launchLon = 8.0;

      expect(await service.findNearestSite(launchLat, launchLon), isNull,
          reason: 'nothing cached yet');

      service.cacheSite(Site(
        id: 1,
        name: 'Test Launch',
        latitude: launchLat,
        longitude: launchLon,
        altitude: 1500,
      ));

      final match = await service.findNearestSite(launchLat, launchLon);

      expect(match, isNotNull);
      expect(match!.name, 'Test Launch');
    });

    test('a nearby launch matches the cached site within 500m', () async {
      service.cacheSite(Site(
        id: 2,
        name: 'Nearby Launch',
        latitude: 46.5,
        longitude: 8.0,
      ));

      // ~200m north
      final match = await service.findNearestSite(46.5018, 8.0);

      expect(match?.name, 'Nearby Launch');
    });

    test('a distant launch does not match', () async {
      service.cacheSite(Site(
        id: 3,
        name: 'Far Launch',
        latitude: 46.5,
        longitude: 8.0,
      ));

      // ~5km away
      final match = await service.findNearestSite(46.545, 8.0);

      expect(match, isNull);
    });

    test('caching the same site twice does not duplicate it', () {
      final before = service.siteCount;
      final site = Site(
        id: 4,
        name: 'Repeat Launch',
        latitude: 47.0,
        longitude: 9.0,
      );

      service.cacheSite(site);
      service.cacheSite(site);

      expect(service.siteCount, before + 1);
    });
  });
}

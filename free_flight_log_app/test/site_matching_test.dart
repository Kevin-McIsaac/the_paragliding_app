import 'package:flutter_test/flutter_test.dart';
import 'package:free_flight_log_app/services/site_matching_service.dart';

void main() {
  group('Site Matching Service Tests', () {
    late SiteMatchingService siteMatchingService;

    setUpAll(() async {
      siteMatchingService = SiteMatchingService.instance;
      await siteMatchingService.initialize();
    });

    test('Should initialize and load sites', () {
      expect(siteMatchingService.isReady, isTrue);
      expect(siteMatchingService.siteCount, greaterThan(0));
    });

    test('Should find Interlaken site near Beatenberg coordinates', () {
      // Coordinates near Interlaken - Beatenberg (from sample data)
      final site = siteMatchingService.findNearestLaunchSite(46.6945, 7.9867);
      
      expect(site, isNotNull);
      expect(site!.name, equals('Interlaken - Beatenberg'));
      expect(site.country, equals('Switzerland'));
      expect(site.siteType, equals('launch'));
    });

    test('Should find landing site near Interlaken', () {
      // Coordinates near Interlaken Landing Field
      final site = siteMatchingService.findNearestLandingSite(46.6774, 7.8636);
      
      expect(site, isNotNull);
      expect(site!.name, equals('Interlaken Landing Field'));
      expect(site.siteType, equals('landing'));
    });

    test('Should return null for coordinates far from any site', () {
      // Coordinates in the middle of the ocean
      final site = siteMatchingService.findNearestSite(0.0, 0.0, maxDistance: 100);
      
      expect(site, isNull);
    });

    test('Should search sites by name', () {
      final results = siteMatchingService.searchByName('Interlaken');
      
      expect(results, isNotEmpty);
      expect(results.first.name.toLowerCase(), contains('interlaken'));
    });

    test('Should get site name suggestion with coordinates fallback', () {
      // Test with known site coordinates
      final knownSiteName = siteMatchingService.getSiteNameSuggestion(
        46.6945, 7.9867,
        prefix: 'Launch',
        siteType: 'launch',
      );
      expect(knownSiteName, equals('Launch Interlaken - Beatenberg'));
      
      // Test with unknown coordinates (should fall back to coordinates)
      final unknownSiteName = siteMatchingService.getSiteNameSuggestion(
        0.0, 0.0,
        prefix: 'Launch',
        siteType: 'launch',
      );
      expect(unknownSiteName, contains('0.000°N 0.000°E'));
    });

    test('Should get statistics', () {
      final stats = siteMatchingService.getStatistics();
      
      expect(stats['total'], greaterThan(0));
      expect(stats['launch_sites'], greaterThan(0));
      expect(stats['countries'], greaterThan(0));
      expect(stats['top_countries'], isA<List>());
    });
  });
}
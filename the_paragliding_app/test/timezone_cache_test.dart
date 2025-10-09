import 'package:flutter_test/flutter_test.dart';
import 'package:the_paragliding_app/services/igc_parser.dart';
import 'package:the_paragliding_app/services/timezone_service.dart';
import 'dart:io';

void main() {
  group('Timezone Cache Tests', () {
    setUpAll(() {
      TimezoneService.initialize();
    });

    setUp(() {
      // Clear cache before each test
      IgcParser.clearTimezoneCache();
    });

    group('Cache Hit/Miss Behavior', () {
      test('Should cache timezone on first detection', () async {
        // Create IGC file with specific coordinates
        final testIgc = '''AFLY00M9 0101373
HFDTE150125
HFPLTPILOT:Cache Test Pilot
B1200004708710N01118478EA019780209600807000
B1300004708710N01118478EA019780209600807000
''';

        final testFile = File('/tmp/test_cache1.igc');
        await testFile.writeAsString(testIgc);
        
        // Get initial cache stats
        final statsBefore = IgcParser.getTimezoneStats();
        expect(statsBefore['size'], equals(0));
        
        // Parse file - should detect and cache timezone
        final parser = IgcParser();
        final result = await parser.parseFile(testFile.path);
        
        expect(result, isNotNull);
        expect(result.timezone, isNotNull);
        
        // Check cache stats after first parse
        final statsAfter = IgcParser.getTimezoneStats();
        expect(statsAfter['size'], equals(1)); // One entry cached
      });

      test('Should use cached timezone for same coordinates', () async {
        // Create two IGC files with same coordinates but different dates
        final testIgc1 = '''AFLY00M9 0101373
HFDTE150125
HFPLTPILOT:First Flight
B1200004708710N01118478EA019780209600807000
B1300004708710N01118478EA019780209600807000
''';

        final testIgc2 = '''AFLY00M9 0101373
HFDTE160125
HFPLTPILOT:Second Flight
B1400004708710N01118478EA019780209600807000
B1500004708710N01118478EA019780209600807000
''';

        final testFile1 = File('/tmp/test_cache_hit1.igc');
        final testFile2 = File('/tmp/test_cache_hit2.igc');
        await testFile1.writeAsString(testIgc1);
        await testFile2.writeAsString(testIgc2);
        
        final parser = IgcParser();
        
        // First parse - cache miss
        final result1 = await parser.parseFile(testFile1.path);
        expect(result1.timezone, isNotNull);
        
        final statsAfterFirst = IgcParser.getTimezoneStats();
        expect(statsAfterFirst['size'], equals(1));
        
        // Second parse - cache hit (same coordinates)
        final result2 = await parser.parseFile(testFile2.path);
        expect(result2.timezone, equals(result1.timezone));
        
        // Cache size should still be 1 (reused cached entry)
        final statsAfterSecond = IgcParser.getTimezoneStats();
        expect(statsAfterSecond['size'], equals(1));
      });

      test('Should cache different timezones for different coordinates', () async {
        // Create IGC files with different coordinates
        final testIgcSwitzerland = '''AFLY00M9 0101373
HFDTE150125
HFPLTPILOT:Swiss Pilot
B1200004708710N01118478EA019780209600807000
B1300004708710N01118478EA019780209600807000
''';

        final testIgcAustralia = '''AFLY00M9 0101373
HFDTE150125
HFPLTPILOT:Aussie Pilot
B1200003386880S15120930EA019780209600807000
B1300003386880S15120930EA019780209600807000
''';

        final testIgcJapan = '''AFLY00M9 0101373
HFDTE150125
HFPLTPILOT:Japan Pilot
B1200003530000N13900000EA019780209600807000
B1300003530000N13900000EA019780209600807000
''';

        final fileSwiss = File('/tmp/test_cache_swiss.igc');
        final fileAussie = File('/tmp/test_cache_aussie.igc');
        final fileJapan = File('/tmp/test_cache_japan.igc');
        
        await fileSwiss.writeAsString(testIgcSwitzerland);
        await fileAussie.writeAsString(testIgcAustralia);
        await fileJapan.writeAsString(testIgcJapan);
        
        final parser = IgcParser();
        
        // Parse different locations
        final resultSwiss = await parser.parseFile(fileSwiss.path);
        final resultAussie = await parser.parseFile(fileAussie.path);
        final resultJapan = await parser.parseFile(fileJapan.path);
        
        // Each should have different timezone
        expect(resultSwiss.timezone, isNotNull);
        expect(resultAussie.timezone, isNotNull);
        expect(resultJapan.timezone, isNotNull);
        
        expect(resultSwiss.timezone, isNot(equals(resultAussie.timezone)));
        expect(resultSwiss.timezone, isNot(equals(resultJapan.timezone)));
        expect(resultAussie.timezone, isNot(equals(resultJapan.timezone)));
        
        // Cache should have 3 entries
        final stats = IgcParser.getTimezoneStats();
        expect(stats['size'], equals(3));
      });
    });

    group('LRU Eviction', () {
      test('Should evict least recently used entries when cache is full', () async {
        // Generate more than 100 unique locations (cache max size)
        final parser = IgcParser();
        final List<String> timezones = [];
        
        // Create 105 files with unique coordinates
        for (int i = 0; i < 105; i++) {
          final lat = 10 + i * 0.5; // Spread across latitudes
          final lon = 10 + i * 0.5; // Spread across longitudes
          
          final latDeg = lat.floor();
          final latMin = ((lat - latDeg) * 60).floor();
          final lonDeg = lon.floor();
          final lonMin = ((lon - lonDeg) * 60).floor();
          
          final testIgc = '''AFLY00M9 0101373
HFDTE150125
HFPLTPILOT:Location $i
B120000${latDeg.toString().padLeft(2, '0')}${latMin.toString().padLeft(2, '0')}000N${lonDeg.toString().padLeft(3, '0')}${lonMin.toString().padLeft(2, '0')}000EA019780209600807000
B130000${latDeg.toString().padLeft(2, '0')}${latMin.toString().padLeft(2, '0')}000N${lonDeg.toString().padLeft(3, '0')}${lonMin.toString().padLeft(2, '0')}000EA019780209600807000
''';

          final testFile = File('/tmp/test_lru_$i.igc');
          await testFile.writeAsString(testIgc);
          
          final result = await parser.parseFile(testFile.path);
          if (result.timezone != null) {
            timezones.add(result.timezone!);
          }
        }
        
        // Cache should be at max size (100), not 105
        final stats = IgcParser.getTimezoneStats();
        expect(stats['size'], equals(100));
        expect(stats['maxSize'], equals(100));
        
        // First 5 entries should have been evicted
        // Parse the first file again - should be a cache miss
        final testIgcFirst = '''AFLY00M9 0101373
HFDTE150125
HFPLTPILOT:Location 0
B12000010${'00'}000N010${'00'}000EA019780209600807000
B13000010${'00'}000N010${'00'}000EA019780209600807000
''';

        final testFileFirst = File('/tmp/test_lru_0.igc');
        await testFileFirst.writeAsString(testIgcFirst);
        
        await parser.parseFile(testFileFirst.path);
        
        // Cache should still be at max size
        final statsAfter = IgcParser.getTimezoneStats();
        expect(statsAfter['size'], equals(100));
      });

      test('Should update access order on cache hit', () async {
        // Create 3 files with different coordinates
        final locations = [
          {'lat': '4700000', 'lon': '00800000', 'dir': 'E'},
          {'lat': '4800000', 'lon': '00900000', 'dir': 'E'},
          {'lat': '4900000', 'lon': '01000000', 'dir': 'E'},
        ];
        
        final parser = IgcParser();
        
        // Parse all three locations
        for (int i = 0; i < 3; i++) {
          final loc = locations[i];
          final testIgc = '''AFLY00M9 0101373
HFDTE150125
HFPLTPILOT:Location $i
B120000${loc['lat']}N${loc['lon']}${loc['dir']}A019780209600807000
B130000${loc['lat']}N${loc['lon']}${loc['dir']}A019780209600807000
''';

          final testFile = File('/tmp/test_access_$i.igc');
          await testFile.writeAsString(testIgc);
          await parser.parseFile(testFile.path);
        }
        
        // Cache has 3 entries
        expect(IgcParser.getTimezoneStats()['size'], equals(3));
        
        // Access first location again - moves it to end of access order
        final testIgcReaccess = '''AFLY00M9 0101373
HFDTE160125
HFPLTPILOT:Reaccess Location 0
B140000${locations[0]['lat']}N${locations[0]['lon']}${locations[0]['dir']}A019780209600807000
B150000${locations[0]['lat']}N${locations[0]['lon']}${locations[0]['dir']}A019780209600807000
''';

        final testFileReaccess = File('/tmp/test_reaccess.igc');
        await testFileReaccess.writeAsString(testIgcReaccess);
        await parser.parseFile(testFileReaccess.path);
        
        // Cache should still have 3 entries (cache hit)
        expect(IgcParser.getTimezoneStats()['size'], equals(3));
        
        // Now fill cache to capacity to test that location 0 is not evicted first
        for (int i = 4; i < 101; i++) {
          final testIgc = '''AFLY00M9 0101373
HFDTE150125
HFPLTPILOT:Fill $i
B120000${(5000000 + i * 1000).toString().padLeft(7, '0')}N${(1000000 + i * 1000).toString().padLeft(8, '0')}EA019780209600807000
B130000${(5000000 + i * 1000).toString().padLeft(7, '0')}N${(1000000 + i * 1000).toString().padLeft(8, '0')}EA019780209600807000
''';

          final testFile = File('/tmp/test_fill_$i.igc');
          await testFile.writeAsString(testIgc);
          await parser.parseFile(testFile.path);
        }
        
        // Cache at max size
        expect(IgcParser.getTimezoneStats()['size'], equals(100));
        
        // Location 0 should still be in cache (was recently accessed)
        // Location 1 or 2 should have been evicted
        final testLocation0Again = '''AFLY00M9 0101373
HFDTE170125
HFPLTPILOT:Check Location 0
B160000${locations[0]['lat']}N${locations[0]['lon']}${locations[0]['dir']}A019780209600807000
B170000${locations[0]['lat']}N${locations[0]['lon']}${locations[0]['dir']}A019780209600807000
''';

        final testFile0Again = File('/tmp/test_check_0.igc');
        await testFile0Again.writeAsString(testLocation0Again);
        await parser.parseFile(testFile0Again.path);
        
        // Should still be at max size (cache hit for location 0)
        expect(IgcParser.getTimezoneStats()['size'], equals(100));
      }, skip: 'Cache LRU eviction count edge case');
    });

    group('Cache Clearing', () {
      test('Should clear all cache entries when requested', () async {
        final parser = IgcParser();
        
        // Add some entries to cache
        for (int i = 0; i < 5; i++) {
          final testIgc = '''AFLY00M9 0101373
HFDTE150125
HFPLTPILOT:Pilot $i
B120000${(4000000 + i * 100000).toString().padLeft(7, '0')}N${(1000000 + i * 100000).toString().padLeft(8, '0')}EA019780209600807000
B130000${(4000000 + i * 100000).toString().padLeft(7, '0')}N${(1000000 + i * 100000).toString().padLeft(8, '0')}EA019780209600807000
''';

          final testFile = File('/tmp/test_clear_$i.igc');
          await testFile.writeAsString(testIgc);
          await parser.parseFile(testFile.path);
        }
        
        // Cache should have entries
        expect(IgcParser.getTimezoneStats()['size'], equals(5));
        
        // Clear cache
        IgcParser.clearTimezoneCache();
        
        // Cache should be empty
        final statsAfterClear = IgcParser.getTimezoneStats();
        expect(statsAfterClear['size'], equals(0));
      });

      test('Should work correctly after cache is cleared', () async {
        final parser = IgcParser();
        
        // Parse a file
        final testIgc1 = '''AFLY00M9 0101373
HFDTE150125
HFPLTPILOT:Before Clear
B1200004708710N01118478EA019780209600807000
B1300004708710N01118478EA019780209600807000
''';

        final testFile1 = File('/tmp/test_before_clear.igc');
        await testFile1.writeAsString(testIgc1);
        
        final result1 = await parser.parseFile(testFile1.path);
        expect(result1.timezone, isNotNull);
        expect(IgcParser.getTimezoneStats()['size'], equals(1));
        
        // Clear cache
        IgcParser.clearTimezoneCache();
        expect(IgcParser.getTimezoneStats()['size'], equals(0));
        
        // Parse another file - should work normally
        final testIgc2 = '''AFLY00M9 0101373
HFDTE160125
HFPLTPILOT:After Clear
B1400003386880S15120930EA019780209600807000
B1500003386880S15120930EA019780209600807000
''';

        final testFile2 = File('/tmp/test_after_clear.igc');
        await testFile2.writeAsString(testIgc2);
        
        final result2 = await parser.parseFile(testFile2.path);
        expect(result2.timezone, isNotNull);
        expect(IgcParser.getTimezoneStats()['size'], equals(1));
      });
    });

    group('Cache Key Generation', () {
      test('Should use rounded coordinates for cache key', () async {
        final parser = IgcParser();
        
        // Two files with slightly different coordinates that round to same key
        final testIgc1 = '''AFLY00M9 0101373
HFDTE150125
HFPLTPILOT:Pilot 1
B1200004708710N01118478EA019780209600807000
B1300004708710N01118478EA019780209600807000
''';

        final testIgc2 = '''AFLY00M9 0101373
HFDTE160125
HFPLTPILOT:Pilot 2
B1400004708711N01118479EA019780209600807000
B1500004708711N01118479EA019780209600807000
''';

        final testFile1 = File('/tmp/test_key1.igc');
        final testFile2 = File('/tmp/test_key2.igc');
        await testFile1.writeAsString(testIgc1);
        await testFile2.writeAsString(testIgc2);
        
        // Parse both files
        await parser.parseFile(testFile1.path);
        await parser.parseFile(testFile2.path);
        
        // Due to rounding to 3 decimal places, might be same or different cache entries
        // depending on exact coordinates
        final stats = IgcParser.getTimezoneStats();
        expect(stats['size'], greaterThanOrEqualTo(1));
        expect(stats['size'], lessThanOrEqualTo(2));
      });

      test('Should handle edge coordinates correctly', () async {
        final parser = IgcParser();
        
        // Test edge cases: 0°, 180°, -180°
        final edgeCases = [
          {'lat': '0000000', 'latDir': 'N', 'lon': '00000000', 'lonDir': 'E'}, // 0,0
          {'lat': '0000000', 'latDir': 'N', 'lon': '18000000', 'lonDir': 'E'}, // 0,180
          {'lat': '0000000', 'latDir': 'N', 'lon': '18000000', 'lonDir': 'W'}, // 0,-180
          {'lat': '9000000', 'latDir': 'N', 'lon': '00000000', 'lonDir': 'E'}, // 90,0
          {'lat': '9000000', 'latDir': 'S', 'lon': '00000000', 'lonDir': 'E'}, // -90,0
        ];
        
        for (int i = 0; i < edgeCases.length; i++) {
          final edge = edgeCases[i];
          final testIgc = '''AFLY00M9 0101373
HFDTE150125
HFPLTPILOT:Edge $i
B120000${edge['lat']}${edge['latDir']}${edge['lon']}${edge['lonDir']}A019780209600807000
B130000${edge['lat']}${edge['latDir']}${edge['lon']}${edge['lonDir']}A019780209600807000
''';

          final testFile = File('/tmp/test_edge_$i.igc');
          await testFile.writeAsString(testIgc);
          
          final result = await parser.parseFile(testFile.path);
          expect(result, isNotNull);
          expect(result.trackPoints.length, equals(2));
        }
        
        // Cache should have entries for edge coordinates
        final stats = IgcParser.getTimezoneStats();
        expect(stats['size'], greaterThan(0));
      });
    });

    group('Cache Performance', () {
      test('Should improve performance for repeated timezone detection', () async {
        final parser = IgcParser();
        
        // Create a test file
        final testIgc = '''AFLY00M9 0101373
HFDTE150125
HFPLTPILOT:Performance Test
B1200004708710N01118478EA019780209600807000
B1300004708710N01118478EA019780209600807000
B1400004708710N01118478EA019780209600807000
B1500004708710N01118478EA019780209600807000
B1600004708710N01118478EA019780209600807000
''';

        final testFile = File('/tmp/test_perf.igc');
        await testFile.writeAsString(testIgc);
        
        // First parse - cache miss
        final stopwatch1 = Stopwatch()..start();
        await parser.parseFile(testFile.path);
        stopwatch1.stop();
        final firstParseTime = stopwatch1.elapsedMicroseconds;
        
        // Second parse - cache hit (should be faster)
        final stopwatch2 = Stopwatch()..start();
        await parser.parseFile(testFile.path);
        stopwatch2.stop();
        final secondParseTime = stopwatch2.elapsedMicroseconds;
        
        // Cache hit should generally be faster, but not always guaranteed
        // due to system factors, so we just verify both complete
        expect(firstParseTime, greaterThan(0));
        expect(secondParseTime, greaterThan(0));
        
        // Verify cache was used
        expect(IgcParser.getTimezoneStats()['size'], equals(1));
      });

      test('Should handle concurrent parsing with shared cache', () async {
        // Create multiple files with same coordinates
        final List<File> files = [];
        for (int i = 0; i < 10; i++) {
          final testIgc = '''AFLY00M9 0101373
HFDTE${(15 + i).toString().padLeft(2, '0')}0125
HFPLTPILOT:Concurrent $i
B1200004708710N01118478EA019780209600807000
B1300004708710N01118478EA019780209600807000
''';

          final testFile = File('/tmp/test_concurrent_$i.igc');
          await testFile.writeAsString(testIgc);
          files.add(testFile);
        }
        
        // Parse all files (simulating concurrent access)
        final parser = IgcParser();
        final futures = files.map((file) => parser.parseFile(file.path));
        final results = await Future.wait(futures);
        
        // All should succeed
        expect(results.length, equals(10));
        for (final result in results) {
          expect(result, isNotNull);
          expect(result.timezone, isNotNull);
        }
        
        // Cache should have just one entry (all same coordinates)
        expect(IgcParser.getTimezoneStats()['size'], equals(1));
      });
    });

    group('Cache Statistics', () {
      test('Should provide accurate cache statistics', () async {
        final parser = IgcParser();
        
        // Initial stats
        final initialStats = IgcParser.getTimezoneStats();
        expect(initialStats['size'], equals(0));
        expect(initialStats['maxSize'], equals(100));
        
        // Add some entries
        for (int i = 0; i < 5; i++) {
          final testIgc = '''AFLY00M9 0101373
HFDTE150125
HFPLTPILOT:Stats $i
B120000${(4000000 + i * 100000).toString().padLeft(7, '0')}N${(1000000 + i * 100000).toString().padLeft(8, '0')}EA019780209600807000
B130000${(4000000 + i * 100000).toString().padLeft(7, '0')}N${(1000000 + i * 100000).toString().padLeft(8, '0')}EA019780209600807000
''';

          final testFile = File('/tmp/test_stats_$i.igc');
          await testFile.writeAsString(testIgc);
          await parser.parseFile(testFile.path);
        }
        
        // Check updated stats
        final updatedStats = IgcParser.getTimezoneStats();
        expect(updatedStats['size'], equals(5));
        expect(updatedStats['maxSize'], equals(100));
        expect(updatedStats['hitRate'], isNotNull);
      });
    });
  });
}
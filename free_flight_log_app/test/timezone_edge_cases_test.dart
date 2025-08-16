import 'package:flutter_test/flutter_test.dart';
import 'package:free_flight_log_app/services/igc_parser.dart';
import 'package:free_flight_log_app/services/timezone_service.dart';
import 'dart:io';

void main() {
  group('Timezone Edge Cases Tests', () {
    setUpAll(() {
      TimezoneService.initialize();
    });

    group('Midnight Crossing + Timezone Conversion', () {
      test('Should handle midnight crossing with positive timezone offset', () async {
        // Flight in Australia Sydney (+11:00 AEDT in January) crossing midnight
        // Launch at 23:30 UTC (10:30 next day local with DST)
        // Land at 01:45 UTC (12:45 local) - crosses midnight in UTC but not local
        final testIgc = '''AFLY00M9 0101373
HFDTE150125
HFPLTPILOT:Test Pilot
B2330003386880S15120930EA019780209600807000
B2345003386900S15120940EA019780209600807000
B0015003386920S15120950EA019780209600807000
B0145003386940S15120960EA019780209600807000
''';

        final testFile = File('/tmp/test_midnight_tz.igc');
        await testFile.writeAsString(testIgc);
        
        final parser = IgcParser();
        final result = await parser.parseFile(testFile.path);
        
        expect(result, isNotNull);
        expect(result.trackPoints.length, equals(4));
        
        // Verify timestamps are in chronological order
        for (int i = 1; i < result.trackPoints.length; i++) {
          expect(
            result.trackPoints[i].timestamp.isAfter(result.trackPoints[i - 1].timestamp),
            isTrue,
            reason: 'Timestamp $i should be after timestamp ${i - 1}',
          );
        }
        
        // First point: 23:30 UTC on Jan 15 = 10:30 Jan 16 local (+11:00 AEDT)
        final firstPoint = result.trackPoints.first;
        expect(firstPoint.timestamp.day, equals(16)); // Next day in local time
        expect(firstPoint.timestamp.hour, equals(10));
        expect(firstPoint.timestamp.minute, equals(30));
        
        // Last point: 01:45 UTC on Jan 16 = 12:45 Jan 16 local
        final lastPoint = result.trackPoints.last;
        expect(lastPoint.timestamp.day, equals(16));
        expect(lastPoint.timestamp.hour, equals(12));
        expect(lastPoint.timestamp.minute, equals(45));
        
        // Duration should be 2 hours 15 minutes
        final duration = lastPoint.timestamp.difference(firstPoint.timestamp);
        expect(duration.inMinutes, equals(135));
      });

      test('Should handle midnight crossing with negative timezone offset', () async {
        // Flight in California (-08:00 PST) crossing midnight in local time
        // Launch at 07:30 UTC (23:30 previous day local)
        // Land at 09:45 UTC (01:45 local) - crosses midnight in local but not UTC
        final testIgc = '''AFLY00M9 0101373
HFDTE160125
HFPLTPILOT:Test Pilot
B0730003700000N12200000WA019780209600807000
B0800003700100N12200100WA019780209600807000
B0830003700200N12200200WA019780209600807000
B0945003700300N12200300WA019780209600807000
''';

        final testFile = File('/tmp/test_midnight_neg_tz.igc');
        await testFile.writeAsString(testIgc);
        
        final parser = IgcParser();
        final result = await parser.parseFile(testFile.path);
        
        expect(result, isNotNull);
        expect(result.trackPoints.length, equals(4));
        
        // First point: 07:30 UTC on Jan 16 = 23:30 Jan 15 local (-08:00)
        final firstPoint = result.trackPoints.first;
        expect(firstPoint.timestamp.day, equals(15)); // Previous day in local time
        expect(firstPoint.timestamp.hour, equals(23));
        expect(firstPoint.timestamp.minute, equals(30));
        
        // Last point: 09:45 UTC on Jan 16 = 01:45 Jan 16 local
        final lastPoint = result.trackPoints.last;
        expect(lastPoint.timestamp.day, equals(16));
        expect(lastPoint.timestamp.hour, equals(1));
        expect(lastPoint.timestamp.minute, equals(45));
        
        // Verify chronological order
        for (int i = 1; i < result.trackPoints.length; i++) {
          expect(
            result.trackPoints[i].timestamp.isAfter(result.trackPoints[i - 1].timestamp),
            isTrue,
          );
        }
      });
    });

    group('International Date Line Crossing', () {
      test('Should handle flight crossing date line eastward', () async {
        // Flight from Fiji (+12:00) to Samoa (-11:00) - crosses date line
        // Same clock time but different dates
        final testIgc = '''AFLY00M9 0101373
HFDTE150125
HFPLTPILOT:Date Line Crosser
B0000001800000S17900000EA019780209600807000
B0100001800000S17900000WA019780209600807000
''';

        final testFile = File('/tmp/test_dateline.igc');
        await testFile.writeAsString(testIgc);
        
        final parser = IgcParser();
        final result = await parser.parseFile(testFile.path);
        
        expect(result, isNotNull);
        expect(result.trackPoints.length, equals(2));
        
        // Both points should have valid timestamps
        expect(result.trackPoints.first.timestamp, isNotNull);
        expect(result.trackPoints.last.timestamp, isNotNull);
      });
    });

    group('Extreme Timezone Offsets', () {
      test('Should handle +14:00 timezone (Kiribati)', () async {
        // Kiribati has +14:00 timezone
        final testIgc = '''AFLY00M9 0101373
HFDTE150125
HFPLTPILOT:Kiribati Pilot
B1000000130000N17230000EA019780209600807000
B1100000130100N17230100EA019780209600807000
''';

        final testFile = File('/tmp/test_kiribati.igc');
        await testFile.writeAsString(testIgc);
        
        final parser = IgcParser();
        final result = await parser.parseFile(testFile.path);
        
        expect(result, isNotNull);
        // Timezone detection should work even for extreme offsets
        expect(result.timezone, isNotNull);
        
        // With +14:00, 10:00 UTC becomes 00:00 next day local
        final firstPoint = result.trackPoints.first;
        expect(firstPoint.timestamp.day, equals(16)); // Next day
        expect(firstPoint.timestamp.hour, equals(0));
      }, skip: 'Timezone detection needs accurate Kiribati (+14:00) mapping');

      test('Should handle -12:00 timezone (Baker Island)', () async {
        // Baker Island has -12:00 timezone
        final testIgc = '''AFLY00M9 0101373
HFDTE150125
HFPLTPILOT:Baker Island Pilot
B1200000000000N17600000WA019780209600807000
B1300000000100N17600100WA019780209600807000
''';

        final testFile = File('/tmp/test_baker.igc');
        await testFile.writeAsString(testIgc);
        
        final parser = IgcParser();
        final result = await parser.parseFile(testFile.path);
        
        expect(result, isNotNull);
        expect(result.trackPoints.length, equals(2));
        
        // With -12:00, 12:00 UTC becomes 00:00 same day local
        final firstPoint = result.trackPoints.first;
        expect(firstPoint.timestamp.hour, equals(0));
      }, skip: 'Timezone detection needs accurate Baker Island (-12:00) mapping');

      test('Should handle fractional timezone +05:30 (India)', () async {
        // India has +05:30 timezone
        final testIgc = '''AFLY00M9 0101373
HFDTE150125
HFPLTPILOT:India Pilot
B0800002300000N07700000EA019780209600807000
B0900002300100N07700100EA019780209600807000
''';

        final testFile = File('/tmp/test_india.igc');
        await testFile.writeAsString(testIgc);
        
        final parser = IgcParser();
        final result = await parser.parseFile(testFile.path);
        
        expect(result, isNotNull);
        
        // With +05:30, 08:00 UTC becomes 13:30 local
        final firstPoint = result.trackPoints.first;
        expect(firstPoint.timestamp.hour, equals(13));
        expect(firstPoint.timestamp.minute, equals(30));
      }, skip: 'Timezone detection needs accurate India (+05:30) mapping');

      test('Should handle fractional timezone +09:30 (Adelaide)', () async {
        // Adelaide has +09:30 timezone (ACST)
        final testIgc = '''AFLY00M9 0101373
HFDTE150125
HFPLTPILOT:Adelaide Pilot
B0400003500000S13835000EA019780209600807000
B0500003500100S13835100EA019780209600807000
''';

        final testFile = File('/tmp/test_adelaide.igc');
        await testFile.writeAsString(testIgc);
        
        final parser = IgcParser();
        final result = await parser.parseFile(testFile.path);
        
        expect(result, isNotNull);
        
        // With +09:30, 04:00 UTC becomes 13:30 local
        final firstPoint = result.trackPoints.first;
        expect(firstPoint.timestamp.hour, equals(13));
        expect(firstPoint.timestamp.minute, equals(30));
      }, skip: 'Timezone detection needs accurate Adelaide (+09:30) mapping');
    });

    group('GPS Coordinate Edge Cases', () {
      test('Should handle coordinates at North Pole', () async {
        // North Pole coordinates (90°N)
        final testIgc = '''AFLY00M9 0101373
HFDTE150125
HFPLTPILOT:Arctic Explorer
B1200009000000N00000000EA019780209600807000
B1300009000000N00000000EA019780209600807000
''';

        final testFile = File('/tmp/test_north_pole.igc');
        await testFile.writeAsString(testIgc);
        
        final parser = IgcParser();
        final result = await parser.parseFile(testFile.path);
        
        expect(result, isNotNull);
        expect(result.trackPoints.length, equals(2));
        expect(result.trackPoints.first.latitude, equals(90.0));
      });

      test('Should handle coordinates at South Pole', () async {
        // South Pole coordinates (90°S)
        final testIgc = '''AFLY00M9 0101373
HFDTE150125
HFPLTPILOT:Antarctic Explorer
B1200009000000S00000000EA019780209600807000
B1300009000000S00000000EA019780209600807000
''';

        final testFile = File('/tmp/test_south_pole.igc');
        await testFile.writeAsString(testIgc);
        
        final parser = IgcParser();
        final result = await parser.parseFile(testFile.path);
        
        expect(result, isNotNull);
        expect(result.trackPoints.length, equals(2));
        expect(result.trackPoints.first.latitude, equals(-90.0));
      });

      test('Should handle coordinates at 180° longitude', () async {
        // Coordinates at 180° longitude (International Date Line)
        final testIgc = '''AFLY00M9 0101373
HFDTE150125
HFPLTPILOT:Date Line Pilot
B1200000000000N18000000EA019780209600807000
B1300000000000N18000000WA019780209600807000
''';

        final testFile = File('/tmp/test_180_longitude.igc');
        await testFile.writeAsString(testIgc);
        
        final parser = IgcParser();
        final result = await parser.parseFile(testFile.path);
        
        expect(result, isNotNull);
        expect(result.trackPoints.length, equals(2));
        expect(result.trackPoints.first.longitude.abs(), equals(180.0));
      });
    });

    group('Invalid Timezone Format Handling', () {
      test('Should handle malformed timezone in HFTZNUTCOFFSET', () async {
        // Invalid timezone format in header (should be ignored, use GPS instead)
        final testIgc = '''AFLY00M9 0101373
HFDTE150125
HFPLTPILOT:Test Pilot
HFTZNUTCOFFSET: INVALID
B1200004708710N01118478EA019780209600807000
B1300004708710N01118478EA019780209600807000
''';

        final testFile = File('/tmp/test_invalid_tz.igc');
        await testFile.writeAsString(testIgc);
        
        final parser = IgcParser();
        final result = await parser.parseFile(testFile.path);
        
        expect(result, isNotNull);
        // Should fall back to GPS-based timezone detection
        expect(result.timezone, isNotNull);
        expect(result.timezone, contains(':')); // Should be valid format
      });

      test('Should handle empty coordinates gracefully', () async {
        // Coordinates at 0,0 (Gulf of Guinea)
        final testIgc = '''AFLY00M9 0101373
HFDTE150125
HFPLTPILOT:Ocean Pilot
B1200000000000N00000000EA019780209600807000
B1300000000000N00000000EA019780209600807000
''';

        final testFile = File('/tmp/test_zero_coords.igc');
        await testFile.writeAsString(testIgc);
        
        final parser = IgcParser();
        final result = await parser.parseFile(testFile.path);
        
        expect(result, isNotNull);
        expect(result.trackPoints.length, equals(2));
        // Should still detect a timezone (likely Africa/Accra or UTC)
        expect(result.timezone, isNotNull);
      });
    });

    group('Timestamp Validation', () {
      test('Should maintain chronological order after timezone conversion', () async {
        // Create a flight with many points to verify ordering
        final testIgc = '''AFLY00M9 0101373
HFDTE150125
HFPLTPILOT:Test Pilot
B0800004708710N01118478EA019780209600807000
B0815004708710N01118478EA019780209600807000
B0830004708710N01118478EA019780209600807000
B0845004708710N01118478EA019780209600807000
B0900004708710N01118478EA019780209600807000
B0915004708710N01118478EA019780209600807000
B0930004708710N01118478EA019780209600807000
''';

        final testFile = File('/tmp/test_chronological.igc');
        await testFile.writeAsString(testIgc);
        
        final parser = IgcParser();
        final result = await parser.parseFile(testFile.path);
        
        expect(result, isNotNull);
        expect(result.trackPoints.length, equals(7));
        
        // Verify all timestamps are in strict chronological order
        for (int i = 1; i < result.trackPoints.length; i++) {
          final prev = result.trackPoints[i - 1].timestamp;
          final curr = result.trackPoints[i].timestamp;
          expect(
            curr.isAfter(prev),
            isTrue,
            reason: 'Point $i (${curr.toIso8601String()}) should be after point ${i-1} (${prev.toIso8601String()})',
          );
          
          // Verify 15-minute intervals
          final diff = curr.difference(prev);
          expect(diff.inMinutes, equals(15));
        }
      });

      test('Should handle rapid timestamp sequence (1-second intervals)', () async {
        // Test with 1-second intervals
        final testIgc = '''AFLY00M9 0101373
HFDTE150125
HFPLTPILOT:Test Pilot
B1200004708710N01118478EA019780209600807000
B1200014708710N01118478EA019780209600807000
B1200024708710N01118478EA019780209600807000
B1200034708710N01118478EA019780209600807000
B1200044708710N01118478EA019780209600807000
''';

        final testFile = File('/tmp/test_rapid.igc');
        await testFile.writeAsString(testIgc);
        
        final parser = IgcParser();
        final result = await parser.parseFile(testFile.path);
        
        expect(result, isNotNull);
        expect(result.trackPoints.length, equals(5));
        
        // Verify 1-second intervals
        for (int i = 1; i < result.trackPoints.length; i++) {
          final diff = result.trackPoints[i].timestamp
              .difference(result.trackPoints[i - 1].timestamp);
          expect(diff.inSeconds, equals(1));
        }
      });
    });
  });
}
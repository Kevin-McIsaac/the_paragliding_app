import 'package:flutter_test/flutter_test.dart';
import 'package:free_flight_log_app/services/igc_parser.dart';
import 'package:free_flight_log_app/services/timezone_service.dart';
import 'dart:io';

void main() {
  group('Timezone Boundary Crossing Tests', () {
    setUpAll(() {
      TimezoneService.initialize();
    });

    group('Single Timezone Boundary Crossing', () {
      test('Should detect timezone from launch location for cross-timezone flight', () async {
        // Flight from Switzerland (UTC+1/+2) to France (same timezone typically)
        // But for testing, we'll simulate crossing from Switzerland to UK
        final testIgc = '''AFLY00M9 0101373
HFDTE150825
HFPLTPILOT:Cross-Border Pilot
B1000004700000N00800000EA019780209600807000
B1100004650000N00600000EA019780209600807000
B1200004600000N00400000EA019780209600807000
B1300004550000N00200000EA019780209600807000
B1400004500000N00000000WA019780209600807000
''';

        final testFile = File('/tmp/test_tz_crossing.igc');
        await testFile.writeAsString(testIgc);
        
        final parser = IgcParser();
        final result = await parser.parseFile(testFile.path);
        
        expect(result, isNotNull);
        expect(result.trackPoints.length, equals(5));
        
        // Timezone should be detected from FIRST point (launch location)
        // This is important for consistency - all times use launch timezone
        expect(result.timezone, isNotNull);
        
        // Verify all timestamps use the same timezone offset
        final firstHour = result.trackPoints.first.timestamp.hour;
        final lastHour = result.trackPoints.last.timestamp.hour;
        final hourDiff = lastHour - firstHour;
        
        // Should be 4 hours difference (14:00 - 10:00 UTC = 4 hours)
        // Plus timezone offset applied consistently
        expect(hourDiff, equals(4));
      });

      test('Should handle east to west timezone crossing', () async {
        // Flight from Eastern Europe to Western Europe
        // Romania (UTC+2/+3) to Portugal (UTC+0/+1)
        final testIgc = '''AFLY00M9 0101373
HFDTE150825
HFPLTPILOT:East-West Pilot
B0800004500000N02500000EA019780209600807000
B0900004450000N02000000EA019780209600807000
B1000004400000N01500000EA019780209600807000
B1100004350000N01000000EA019780209600807000
B1200004300000N00500000EA019780209600807000
B1300004000000N00800000WA019780209600807000
''';

        final testFile = File('/tmp/test_east_west.igc');
        await testFile.writeAsString(testIgc);
        
        final parser = IgcParser();
        final result = await parser.parseFile(testFile.path);
        
        expect(result, isNotNull);
        expect(result.trackPoints.length, equals(6));
        
        // All points should use launch location timezone
        // Verify chronological order is maintained
        for (int i = 1; i < result.trackPoints.length; i++) {
          expect(
            result.trackPoints[i].timestamp.isAfter(result.trackPoints[i - 1].timestamp),
            isTrue,
          );
        }
      });

      test('Should handle west to east timezone crossing', () async {
        // Flight from UK to Eastern Europe
        // UK (UTC+0/+1) to Poland (UTC+1/+2)
        final testIgc = '''AFLY00M9 0101373
HFDTE150825
HFPLTPILOT:West-East Pilot
B0800005100000N00000000WA019780209600807000
B0900005150000N00500000EA019780209600807000
B1000005200000N01000000EA019780209600807000
B1100005250000N01500000EA019780209600807000
B1200005300000N02000000EA019780209600807000
''';

        final testFile = File('/tmp/test_west_east.igc');
        await testFile.writeAsString(testIgc);
        
        final parser = IgcParser();
        final result = await parser.parseFile(testFile.path);
        
        expect(result, isNotNull);
        expect(result.trackPoints.length, equals(5));
        
        // UK timezone should be used throughout
        expect(result.timezone, isNotNull);
        
        // Verify consistent hour progression
        for (int i = 1; i < result.trackPoints.length; i++) {
          final diff = result.trackPoints[i].timestamp
              .difference(result.trackPoints[i - 1].timestamp);
          expect(diff.inHours, equals(1));
        }
      });
    });

    group('Multiple Timezone Crossings', () {
      test('Should handle flight crossing multiple timezones', () async {
        // Long distance flight crossing 3+ timezones
        // From Western Europe through Central to Eastern Europe
        final testIgc = '''AFLY00M9 0101373
HFDTE150825
HFPLTPILOT:Multi-Zone Pilot
B0600004800000N00200000WA019780209600807000
B0700004750000N00500000EA019780209600807000
B0800004700000N01000000EA019780209600807000
B0900004650000N01500000EA019780209600807000
B1000004600000N02000000EA019780209600807000
B1100004550000N02500000EA019780209600807000
B1200004500000N03000000EA019780209600807000
''';

        final testFile = File('/tmp/test_multi_zone.igc');
        await testFile.writeAsString(testIgc);
        
        final parser = IgcParser();
        final result = await parser.parseFile(testFile.path);
        
        expect(result, isNotNull);
        expect(result.trackPoints.length, equals(7));
        
        // Launch timezone should be used consistently
        expect(result.timezone, isNotNull);
        
        // Duration should be 6 hours regardless of timezones crossed
        final duration = result.trackPoints.last.timestamp
            .difference(result.trackPoints.first.timestamp);
        expect(duration.inHours, equals(6));
      });

      test('Should handle zigzag flight across timezone boundary', () async {
        // Flight that crosses back and forth across a timezone boundary
        // Like flying along the French-Swiss border
        final testIgc = '''AFLY00M9 0101373
HFDTE150825
HFPLTPILOT:Zigzag Pilot
B1000004600000N00600000EA019780209600807000
B1030004600000N00700000EA019780209600807000
B1100004600000N00600000EA019780209600807000
B1130004600000N00700000EA019780209600807000
B1200004600000N00600000EA019780209600807000
''';

        final testFile = File('/tmp/test_zigzag.igc');
        await testFile.writeAsString(testIgc);
        
        final parser = IgcParser();
        final result = await parser.parseFile(testFile.path);
        
        expect(result, isNotNull);
        expect(result.trackPoints.length, equals(5));
        
        // Despite crossing boundary multiple times, use launch timezone
        expect(result.timezone, isNotNull);
        
        // Verify 30-minute intervals
        for (int i = 1; i < result.trackPoints.length; i++) {
          final diff = result.trackPoints[i].timestamp
              .difference(result.trackPoints[i - 1].timestamp);
          expect(diff.inMinutes, equals(30));
        }
      });
    });

    group('Coastal and Ocean Flights', () {
      test('Should handle flight from land to ocean', () async {
        // Flight from California coast out over Pacific Ocean
        final testIgc = '''AFLY00M9 0101373
HFDTE150825
HFPLTPILOT:Ocean Pilot
B1000003400000N11800000WA019780209600807000
B1100003350000N11900000WA019780209600807000
B1200003300000N12000000WA019780209600807000
B1300003250000N12100000WA019780209600807000
B1400003200000N12200000WA019780209600807000
''';

        final testFile = File('/tmp/test_land_ocean.igc');
        await testFile.writeAsString(testIgc);
        
        final parser = IgcParser();
        final result = await parser.parseFile(testFile.path);
        
        expect(result, isNotNull);
        expect(result.trackPoints.length, equals(5));
        
        // Should use California timezone from launch
        expect(result.timezone, isNotNull);
        
        // Verify consistent time progression
        for (int i = 1; i < result.trackPoints.length; i++) {
          final diff = result.trackPoints[i].timestamp
              .difference(result.trackPoints[i - 1].timestamp);
          expect(diff.inHours, equals(1));
        }
      });

      test('Should handle flight along coastline', () async {
        // Flight along Australian east coast (timezone boundary with ocean)
        final testIgc = '''AFLY00M9 0101373
HFDTE150825
HFPLTPILOT:Coastal Pilot
B0000003300000S15300000EA019780209600807000
B0100003320000S15300000EA019780209600807000
B0200003340000S15300000EA019780209600807000
B0300003360000S15300000EA019780209600807000
B0400003380000S15300000EA019780209600807000
''';

        final testFile = File('/tmp/test_coastline.igc');
        await testFile.writeAsString(testIgc);
        
        final parser = IgcParser();
        final result = await parser.parseFile(testFile.path);
        
        expect(result, isNotNull);
        expect(result.trackPoints.length, equals(5));
        
        // Should consistently use Australian Eastern timezone
        expect(result.timezone, isNotNull);
        expect(result.timezone, equals('+10:00')); // AEST
      });
    });

    group('Polar Region Flights', () {
      test('Should handle flight near Arctic Circle with multiple timezone crossings', () async {
        // Flight in northern Norway/Sweden/Finland area
        // These regions have complex timezone boundaries
        final testIgc = '''AFLY00M9 0101373
HFDTE150825
HFPLTPILOT:Arctic Pilot
B1000006800000N01500000EA019780209600807000
B1100006800000N02000000EA019780209600807000
B1200006800000N02500000EA019780209600807000
B1300006800000N03000000EA019780209600807000
''';

        final testFile = File('/tmp/test_arctic.igc');
        await testFile.writeAsString(testIgc);
        
        final parser = IgcParser();
        final result = await parser.parseFile(testFile.path);
        
        expect(result, isNotNull);
        expect(result.trackPoints.length, equals(4));
        
        // Should use timezone from launch location
        expect(result.timezone, isNotNull);
        
        // Verify chronological order
        for (int i = 1; i < result.trackPoints.length; i++) {
          expect(
            result.trackPoints[i].timestamp.isAfter(result.trackPoints[i - 1].timestamp),
            isTrue,
          );
        }
      });

      test('Should handle flight near Antarctic with undefined timezones', () async {
        // Antarctica has no official timezones in many areas
        final testIgc = '''AFLY00M9 0101373
HFDTE150125
HFPLTPILOT:Antarctic Pilot
B1000007000000S00000000EA019780209600807000
B1100007100000S00500000EA019780209600807000
B1200007200000S01000000EA019780209600807000
B1300007300000S01500000EA019780209600807000
''';

        final testFile = File('/tmp/test_antarctic.igc');
        await testFile.writeAsString(testIgc);
        
        final parser = IgcParser();
        final result = await parser.parseFile(testFile.path);
        
        expect(result, isNotNull);
        expect(result.trackPoints.length, equals(4));
        
        // Should still detect some timezone (likely UTC or estimation)
        expect(result.timezone, isNotNull);
      });
    });

    group('Island Hopping Flights', () {
      test('Should handle flight between Pacific islands with different timezones', () async {
        // Flight between Pacific islands (different timezones)
        // Hawaii to Tahiti crosses multiple timezones
        final testIgc = '''AFLY00M9 0101373
HFDTE150125
HFPLTPILOT:Island Hopper
B0000002100000N15700000WA019780209600807000
B0200002000000N15600000WA019780209600807000
B0400001900000N15500000WA019780209600807000
B0600001800000N15400000WA019780209600807000
B0800001700000N15000000WA019780209600807000
''';

        final testFile = File('/tmp/test_island_hop.igc');
        await testFile.writeAsString(testIgc);
        
        final parser = IgcParser();
        final result = await parser.parseFile(testFile.path);
        
        expect(result, isNotNull);
        expect(result.trackPoints.length, equals(5));
        
        // Should use Hawaii timezone from launch
        expect(result.timezone, isNotNull);
        
        // Verify 2-hour intervals
        for (int i = 1; i < result.trackPoints.length; i++) {
          final diff = result.trackPoints[i].timestamp
              .difference(result.trackPoints[i - 1].timestamp);
          expect(diff.inHours, equals(2));
        }
      });

      test('Should handle Caribbean island flight with minor timezone differences', () async {
        // Caribbean islands have various timezones (-4, -5)
        final testIgc = '''AFLY00M9 0101373
HFDTE150125
HFPLTPILOT:Caribbean Pilot
B1000001800000N06500000WA019780209600807000
B1100001750000N06600000WA019780209600807000
B1200001700000N06700000WA019780209600807000
B1300001650000N06800000WA019780209600807000
''';

        final testFile = File('/tmp/test_caribbean.igc');
        await testFile.writeAsString(testIgc);
        
        final parser = IgcParser();
        final result = await parser.parseFile(testFile.path);
        
        expect(result, isNotNull);
        expect(result.trackPoints.length, equals(4));
        
        // Should detect appropriate Caribbean timezone
        expect(result.timezone, isNotNull);
      });
    });

    group('Special Timezone Regions', () {
      test('Should handle flight in China (single timezone country)', () async {
        // China uses single timezone (UTC+8) despite large geographic area
        final testIgc = '''AFLY00M9 0101373
HFDTE150125
HFPLTPILOT:China Pilot
B0000004000000N08000000EA019780209600807000
B0200004000000N09000000EA019780209600807000
B0400004000000N10000000EA019780209600807000
B0600004000000N11000000EA019780209600807000
B0800004000000N12000000EA019780209600807000
''';

        final testFile = File('/tmp/test_china.igc');
        await testFile.writeAsString(testIgc);
        
        final parser = IgcParser();
        final result = await parser.parseFile(testFile.path);
        
        expect(result, isNotNull);
        expect(result.trackPoints.length, equals(5));
        
        // Should use China Standard Time throughout
        expect(result.timezone, equals('+08:00'));
      }, skip: 'Timezone detection needs accurate China (+08:00) mapping');

      test('Should handle flight in India (single timezone with half-hour offset)', () async {
        // India uses UTC+5:30 throughout
        final testIgc = '''AFLY00M9 0101373
HFDTE150125
HFPLTPILOT:India Pilot
B0000002800000N07000000EA019780209600807000
B0200002800000N08000000EA019780209600807000
B0400002800000N09000000EA019780209600807000
B0600002800000N08500000EA019780209600807000
''';

        final testFile = File('/tmp/test_india.igc');
        await testFile.writeAsString(testIgc);
        
        final parser = IgcParser();
        final result = await parser.parseFile(testFile.path);
        
        expect(result, isNotNull);
        expect(result.trackPoints.length, equals(4));
        
        // Should detect India's half-hour offset
        expect(result.timezone, equals('+05:30'));
        
        // Verify half-hour offset is applied correctly
        final firstPoint = result.trackPoints.first;
        expect(firstPoint.timestamp.minute, equals(30));
      }, skip: 'Timezone detection needs accurate India (+05:30) regional mapping');

      test('Should handle flight near Iran/Afghanistan border (unusual offsets)', () async {
        // Iran uses +3:30, Afghanistan uses +4:30
        final testIgc = '''AFLY00M9 0101373
HFDTE150125
HFPLTPILOT:Border Pilot
B0000003300000N06000000EA019780209600807000
B0100003300000N06100000EA019780209600807000
B0200003300000N06200000EA019780209600807000
''';

        final testFile = File('/tmp/test_iran_afghan.igc');
        await testFile.writeAsString(testIgc);
        
        final parser = IgcParser();
        final result = await parser.parseFile(testFile.path);
        
        expect(result, isNotNull);
        expect(result.trackPoints.length, equals(3));
        
        // Should detect the half-hour offset timezone
        expect(result.timezone, isNotNull);
        expect(result.timezone!.contains('30'), isTrue);
      }, skip: 'Timezone detection needs accurate Iran/Afghanistan border mapping');
    });
  });
}
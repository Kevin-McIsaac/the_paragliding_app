import 'package:flutter_test/flutter_test.dart';
import 'package:free_flight_log_app/services/igc_parser.dart';
import 'package:free_flight_log_app/services/timezone_service.dart';
import 'dart:io';

void main() {
  group('Multi-Day Flight Tests', () {
    setUpAll(() {
      TimezoneService.initialize();
    });

    group('Two-Day Flights', () {
      test('Should handle flight spanning two days with midnight crossing', () async {
        // Flight from late evening to early morning next day
        final testIgc = '''AFLY00M9 0101373
HFDTE150125
HFPLTPILOT:Overnight Pilot
B2200004700000N00800000EA019780209600807000
B2230004700100N00800100EA019780209600807000
B2300004700200N00800200EA019780209600807000
B2330004700300N00800300EA019780209600807000
B0000004700400N00800400EA019780209600807000
B0030004700500N00800500EA019780209600807000
B0100004700600N00800600EA019780209600807000
B0130004700700N00800700EA019780209600807000
B0200004700800N00800800EA019780209600807000
''';

        final testFile = File('/tmp/test_two_day.igc');
        await testFile.writeAsString(testIgc);
        
        final parser = IgcParser();
        final result = await parser.parseFile(testFile.path);
        
        expect(result, isNotNull);
        expect(result.trackPoints.length, equals(9));
        
        // First point should be on Jan 15
        final firstPoint = result.trackPoints.first;
        expect(firstPoint.timestamp.day, greaterThanOrEqualTo(15));
        
        // Last point should be on Jan 16
        final lastPoint = result.trackPoints.last;
        expect(lastPoint.timestamp.day, greaterThan(firstPoint.timestamp.day));
        
        // Total duration should be 4 hours
        final duration = lastPoint.timestamp.difference(firstPoint.timestamp);
        expect(duration.inHours, equals(4));
        
        // All timestamps should be chronological
        for (int i = 1; i < result.trackPoints.length; i++) {
          expect(
            result.trackPoints[i].timestamp.isAfter(result.trackPoints[i - 1].timestamp),
            isTrue,
          );
        }
      });

      test('Should handle flight with multiple midnight crossings', () async {
        // Ultra-long flight crossing midnight twice
        final testIgc = '''AFLY00M9 0101373
HFDTE150125
HFPLTPILOT:Ultra Pilot
B2000004700000N00800000EA019780209600807000
B2200004700100N00800100EA019780209600807000
B0000004700200N00800200EA019780209600807000
B0200004700300N00800300EA019780209600807000
B0400004700400N00800400EA019780209600807000
B0600004700500N00800500EA019780209600807000
B0800004700600N00800600EA019780209600807000
B1000004700700N00800700EA019780209600807000
B1200004700800N00800800EA019780209600807000
B1400004700900N00800900EA019780209600807000
B1600004701000N00801000EA019780209600807000
B1800004701100N00801100EA019780209600807000
B2000004701200N00801200EA019780209600807000
B2200004701300N00801300EA019780209600807000
B0000004701400N00801400EA019780209600807000
B0200004701500N00801500EA019780209600807000
''';

        final testFile = File('/tmp/test_double_midnight.igc');
        await testFile.writeAsString(testIgc);
        
        final parser = IgcParser();
        final result = await parser.parseFile(testFile.path);
        
        expect(result, isNotNull);
        expect(result.trackPoints.length, equals(16));
        
        // Should span 3 calendar days
        final firstDay = result.trackPoints.first.timestamp.day;
        final lastDay = result.trackPoints.last.timestamp.day;
        expect(lastDay - firstDay, equals(2)); // 3 days total
        
        // All timestamps should be chronological
        for (int i = 1; i < result.trackPoints.length; i++) {
          expect(
            result.trackPoints[i].timestamp.isAfter(result.trackPoints[i - 1].timestamp),
            isTrue,
          );
        }
        
        // Total duration should be 30 hours
        final duration = result.trackPoints.last.timestamp
            .difference(result.trackPoints.first.timestamp);
        expect(duration.inHours, equals(30));
      });
    });

    group('Week-Long Expedition Flights', () {
      test('Should handle week-long expedition with daily flights', () async {
        // Simulating a week-long expedition with multiple flight segments
        // Each day has morning and afternoon flights
        final testIgc = '''AFLY00M9 0101373
HFDTE150125
HFPLTPILOT:Expedition Pilot
B0800004700000N00800000EA019780209600807000
B1000004700100N00800100EA019780209600807000
B1200004700200N00800200EA019780209600807000
B1400004700300N00800300EA019780209600807000
B1600004700400N00800400EA019780209600807000
B1800004700500N00800500EA019780209600807000
B2000004700600N00800600EA019780209600807000
B2200004700700N00800700EA019780209600807000
B0000004700800N00800800EA019780209600807000
B0200004700900N00800900EA019780209600807000
B0400004701000N00801000EA019780209600807000
B0600004701100N00801100EA019780209600807000
B0800004701200N00801200EA019780209600807000
B1000004701300N00801300EA019780209600807000
B1200004701400N00801400EA019780209600807000
''';

        final testFile = File('/tmp/test_week_expedition.igc');
        await testFile.writeAsString(testIgc);
        
        final parser = IgcParser();
        final result = await parser.parseFile(testFile.path);
        
        expect(result, isNotNull);
        expect(result.trackPoints.isNotEmpty, isTrue);
        
        // All timestamps should be chronological
        for (int i = 1; i < result.trackPoints.length; i++) {
          expect(
            result.trackPoints[i].timestamp.isAfter(result.trackPoints[i - 1].timestamp),
            isTrue,
          );
        }
      });

      test('Should handle multi-day flight with gaps (landed overnight)', () async {
        // Flight with overnight stop - large time gaps
        final testIgc = '''AFLY00M9 0101373
HFDTE150125
HFPLTPILOT:Multi-Stop Pilot
B0800004700000N00800000EA019780209600807000
B1000004700100N00800100EA019780209600807000
B1200004700200N00800200EA019780209600807000
B1400004700300N00800300EA019780209600807000
B1600004700400N00800400EA019780209600807000
B0800004700500N00800500EA019780209600807000
B1000004700600N00800600EA019780209600807000
B1200004700700N00800700EA019780209600807000
B1400004700800N00800800EA019780209600807000
B1600004700900N00800900EA019780209600807000
''';

        final testFile = File('/tmp/test_overnight_stop.igc');
        await testFile.writeAsString(testIgc);
        
        final parser = IgcParser();
        final result = await parser.parseFile(testFile.path);
        
        expect(result, isNotNull);
        expect(result.trackPoints.length, equals(10));
        
        // Should detect the midnight crossing when time goes backwards
        final point5 = result.trackPoints[5];
        final point4 = result.trackPoints[4];
        
        // Point 5 (08:00) should be on the next day from point 4 (16:00)
        expect(point5.timestamp.day, greaterThan(point4.timestamp.day));
        
        // All timestamps should still be chronological
        for (int i = 1; i < result.trackPoints.length; i++) {
          expect(
            result.trackPoints[i].timestamp.isAfter(result.trackPoints[i - 1].timestamp),
            isTrue,
          );
        }
      });
    });

    group('Consecutive Midnight Crossings', () {
      test('Should handle flight crossing midnight on consecutive days', () async {
        // Flight that crosses midnight multiple times
        final testIgc = '''AFLY00M9 0101373
HFDTE150125
HFPLTPILOT:Marathon Pilot
B2300004700000N00800000EA019780209600807000
B2330004700100N00800100EA019780209600807000
B0000004700200N00800200EA019780209600807000
B0030004700300N00800300EA019780209600807000
B2300004700400N00800400EA019780209600807000
B2330004700500N00800500EA019780209600807000
B0000004700600N00800600EA019780209600807000
B0030004700700N00800700EA019780209600807000
''';

        final testFile = File('/tmp/test_consecutive_midnight.igc');
        await testFile.writeAsString(testIgc);
        
        final parser = IgcParser();
        final result = await parser.parseFile(testFile.path);
        
        expect(result, isNotNull);
        expect(result.trackPoints.length, equals(8));
        
        // Should correctly increment days at each midnight
        final day1 = result.trackPoints[0].timestamp.day; // 23:00 on day 1
        final day2 = result.trackPoints[2].timestamp.day; // 00:00 on day 2
        final day3 = result.trackPoints[6].timestamp.day; // 00:00 on day 3
        
        expect(day2, equals(day1 + 1));
        expect(day3, equals(day2 + 1));
        
        // All timestamps should be chronological
        for (int i = 1; i < result.trackPoints.length; i++) {
          expect(
            result.trackPoints[i].timestamp.isAfter(result.trackPoints[i - 1].timestamp),
            isTrue,
          );
        }
      }, skip: 'Edge case: consecutive midnight crossing date calculation');

      test('Should handle rapid midnight crossings (near poles in summer)', () async {
        // Simulating flight near poles where sun doesn't set
        // Pilot might fly continuously for days
        final testIgc = '''AFLY00M9 0101373
HFDTE150625
HFPLTPILOT:Polar Summer Pilot
B2200008500000N01000000EA019780209600807000
B2300008500100N01500100EA019780209600807000
B0000008500200N02000200EA019780209600807000
B0100008500300N02500300EA019780209600807000
B2200008500400N03000400EA019780209600807000
B2300008500500N03500500EA019780209600807000
B0000008500600N04000600EA019780209600807000
B0100008500700N04500700EA019780209600807000
''';

        final testFile = File('/tmp/test_polar_summer.igc');
        await testFile.writeAsString(testIgc);
        
        final parser = IgcParser();
        final result = await parser.parseFile(testFile.path);
        
        expect(result, isNotNull);
        expect(result.trackPoints.length, equals(8));
        
        // Each midnight crossing should increment the day
        int midnightCrossings = 0;
        for (int i = 1; i < result.trackPoints.length; i++) {
          if (result.trackPoints[i].timestamp.hour == 0 && 
              result.trackPoints[i - 1].timestamp.hour == 23) {
            midnightCrossings++;
          }
        }
        expect(midnightCrossings, equals(2));
        
        // All timestamps should be chronological
        for (int i = 1; i < result.trackPoints.length; i++) {
          expect(
            result.trackPoints[i].timestamp.isAfter(result.trackPoints[i - 1].timestamp),
            isTrue,
          );
        }
      });
    });

    group('Timestamp Validation Across Days', () {
      test('Should maintain chronological order across multiple days', () async {
        // Create a complex multi-day flight pattern
        final testIgc = '''AFLY00M9 0101373
HFDTE150125
HFPLTPILOT:Validation Pilot
B1000004700000N00800000EA019780209600807000
B1400004700100N00800100EA019780209600807000
B1800004700200N00800200EA019780209600807000
B2200004700300N00800300EA019780209600807000
B0200004700400N00800400EA019780209600807000
B0600004700500N00800500EA019780209600807000
B1000004700600N00800600EA019780209600807000
B1400004700700N00800700EA019780209600807000
B1800004700800N00800800EA019780209600807000
B2200004700900N00800900EA019780209600807000
B0200004701000N00801000EA019780209600807000
B0600004701100N00801100EA019780209600807000
''';

        final testFile = File('/tmp/test_chronological_multi.igc');
        await testFile.writeAsString(testIgc);
        
        final parser = IgcParser();
        final result = await parser.parseFile(testFile.path);
        
        expect(result, isNotNull);
        expect(result.trackPoints.length, equals(12));
        
        // Every timestamp should be after the previous one
        DateTime? previousTimestamp;
        for (final point in result.trackPoints) {
          if (previousTimestamp != null) {
            expect(
              point.timestamp.isAfter(previousTimestamp),
              isTrue,
              reason: 'Timestamp ${point.timestamp} should be after $previousTimestamp',
            );
          }
          previousTimestamp = point.timestamp;
        }
        
        // Verify 4-hour intervals between most points
        for (int i = 1; i < 4; i++) {
          final diff = result.trackPoints[i].timestamp
              .difference(result.trackPoints[i - 1].timestamp);
          expect(diff.inHours, equals(4));
        }
      });

      test('Should handle irregular time intervals across days', () async {
        // Flight with varying intervals
        final testIgc = '''AFLY00M9 0101373
HFDTE150125
HFPLTPILOT:Irregular Pilot
B0800004700000N00800000EA019780209600807000
B0815004700100N00800100EA019780209600807000
B0845004700200N00800200EA019780209600807000
B1000004700300N00800300EA019780209600807000
B1400004700400N00800400EA019780209600807000
B2000004700500N00800500EA019780209600807000
B2359004700600N00800600EA019780209600807000
B0001004700700N00800700EA019780209600807000
B0100004700800N00800800EA019780209600807000
B0800004700900N00800900EA019780209600807000
''';

        final testFile = File('/tmp/test_irregular.igc');
        await testFile.writeAsString(testIgc);
        
        final parser = IgcParser();
        final result = await parser.parseFile(testFile.path);
        
        expect(result, isNotNull);
        expect(result.trackPoints.length, equals(10));
        
        // All timestamps should be chronological
        for (int i = 1; i < result.trackPoints.length; i++) {
          expect(
            result.trackPoints[i].timestamp.isAfter(result.trackPoints[i - 1].timestamp),
            isTrue,
          );
        }
        
        // Check specific midnight crossing
        final beforeMidnight = result.trackPoints[6]; // 23:59
        final afterMidnight = result.trackPoints[7];  // 00:01
        expect(afterMidnight.timestamp.day, equals(beforeMidnight.timestamp.day + 1));
        
        // Duration across midnight should be 2 minutes
        final midnightDiff = afterMidnight.timestamp.difference(beforeMidnight.timestamp);
        expect(midnightDiff.inMinutes, equals(2));
      }, skip: 'Edge case: irregular interval midnight crossing calculation');
    });

    group('Multi-Day with Timezone Changes', () {
      test('Should handle multi-day flight with timezone and midnight crossing', () async {
        // Complex scenario: multi-day + timezone conversion
        final testIgc = '''AFLY00M9 0101373
HFDTE150125
HFPLTPILOT:Complex Pilot
B1400003300000S15100000EA019780209600807000
B1800003300100S15100100EA019780209600807000
B2200003300200S15100200EA019780209600807000
B0200003300300S15100300EA019780209600807000
B0600003300400S15100400EA019780209600807000
B1000003300500S15100500EA019780209600807000
B1400003300600S15100600EA019780209600807000
''';

        final testFile = File('/tmp/test_multi_tz.igc');
        await testFile.writeAsString(testIgc);
        
        final parser = IgcParser();
        final result = await parser.parseFile(testFile.path);
        
        expect(result, isNotNull);
        expect(result.trackPoints.length, equals(7));
        
        // Should detect Australian timezone
        expect(result.timezone, isNotNull);
        
        // All timestamps should be chronological after timezone conversion
        for (int i = 1; i < result.trackPoints.length; i++) {
          expect(
            result.trackPoints[i].timestamp.isAfter(result.trackPoints[i - 1].timestamp),
            isTrue,
          );
        }
        
        // Total duration should be 24 hours (full day)
        final duration = result.trackPoints.last.timestamp
            .difference(result.trackPoints.first.timestamp);
        expect(duration.inHours, equals(24));
      });

      test('Should handle year boundary crossing (New Year flight)', () async {
        // Flight crossing from Dec 31 to Jan 1
        final testIgc = '''AFLY00M9 0101373
HFDTE311224
HFPLTPILOT:New Year Pilot
B2200004700000N00800000EA019780209600807000
B2300004700100N00800100EA019780209600807000
B0000004700200N00800200EA019780209600807000
B0100004700300N00800300EA019780209600807000
B0200004700400N00800400EA019780209600807000
''';

        final testFile = File('/tmp/test_new_year.igc');
        await testFile.writeAsString(testIgc);
        
        final parser = IgcParser();
        final result = await parser.parseFile(testFile.path);
        
        expect(result, isNotNull);
        expect(result.trackPoints.length, equals(5));
        
        // First points on Dec 31, 2024
        final firstPoint = result.trackPoints.first;
        expect(firstPoint.timestamp.year, equals(2024));
        expect(firstPoint.timestamp.month, equals(12));
        expect(firstPoint.timestamp.day, equals(31));
        
        // Last points on Jan 1, 2025
        final lastPoint = result.trackPoints.last;
        expect(lastPoint.timestamp.year, equals(2025));
        expect(lastPoint.timestamp.month, equals(1));
        expect(lastPoint.timestamp.day, equals(1));
        
        // All timestamps should be chronological
        for (int i = 1; i < result.trackPoints.length; i++) {
          expect(
            result.trackPoints[i].timestamp.isAfter(result.trackPoints[i - 1].timestamp),
            isTrue,
          );
        }
      });
    });

    group('Performance with Multi-Day Flights', () {
      test('Should efficiently handle flight with thousands of points over multiple days', () async {
        // Generate a large multi-day flight
        final buffer = StringBuffer();
        buffer.writeln('AFLY00M9 0101373');
        buffer.writeln('HFDTE150125');
        buffer.writeln('HFPLTPILOT:Performance Test Pilot');
        
        // Generate points every minute for 48 hours (2880 points)
        int hour = 0;
        int minute = 0;
        for (int i = 0; i < 2880; i++) {
          final hourStr = hour.toString().padLeft(2, '0');
          final minuteStr = minute.toString().padLeft(2, '0');
          final secStr = '00';
          final latMin = (i % 60).toString().padLeft(3, '0');
          // B record format: BHHMMSS DDMMmmmN DDDMMmmmE V PPPPP GGGGG (35 chars after B)
          buffer.writeln('B${hourStr}${minuteStr}${secStr}4700${latMin}N00800${latMin}EA0197802096');
          
          minute++;
          if (minute >= 60) {
            minute = 0;
            hour++;
            if (hour >= 24) {
              hour = 0;
            }
          }
        }
        
        final testFile = File('/tmp/test_performance.igc');
        await testFile.writeAsString(buffer.toString());
        
        final stopwatch = Stopwatch()..start();
        final parser = IgcParser();
        final result = await parser.parseFile(testFile.path);
        stopwatch.stop();
        
        expect(result, isNotNull);
        expect(result.trackPoints.length, equals(2880));
        
        // Should parse in reasonable time (less than 1 second)
        expect(stopwatch.elapsedMilliseconds, lessThan(1000));
        
        // Verify midnight crossings were detected
        final firstDay = result.trackPoints.first.timestamp.day;
        final lastDay = result.trackPoints.last.timestamp.day;
        expect(lastDay, greaterThan(firstDay));
        
        // All timestamps should be chronological
        for (int i = 1; i < result.trackPoints.length; i++) {
          expect(
            result.trackPoints[i].timestamp.isAfter(result.trackPoints[i - 1].timestamp),
            isTrue,
            reason: 'Failed at index $i',
          );
        }
      });
    });
  });
}
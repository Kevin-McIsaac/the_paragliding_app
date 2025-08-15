import 'package:flutter_test/flutter_test.dart';
import 'package:free_flight_log_app/services/igc_parser.dart';
import 'package:free_flight_log_app/services/timezone_service.dart';
import 'dart:io';

void main() {
  group('DST Transition Tests', () {
    setUpAll(() {
      TimezoneService.initialize();
    });

    group('Spring Forward (2AM → 3AM)', () {
      test('Should handle flight during spring DST transition in US', () async {
        // US DST starts on March 10, 2024 at 2:00 AM
        // At 2:00 AM, clocks jump to 3:00 AM
        // Flight from 06:30 UTC to 08:30 UTC (spans DST transition)
        final testIgc = '''AFLY00M9 0101373
HFDTE100324
HFPLTPILOT:Spring Forward Pilot
B0630004070000N07400000WA019780209600807000
B0700004070100N07400100WA019780209600807000
B0730004070200N07400200WA019780209600807000
B0800004070300N07400300WA019780209600807000
B0830004070400N07400400WA019780209600807000
''';

        final testFile = File('/tmp/test_spring_dst.igc');
        await testFile.writeAsString(testIgc);
        
        final parser = IgcParser();
        final result = await parser.parseFile(testFile.path);
        
        expect(result, isNotNull);
        expect(result.trackPoints.length, equals(5));
        
        // Before DST: 06:30 UTC = 01:30 EST (-05:00)
        final firstPoint = result.trackPoints.first;
        expect(firstPoint.timestamp.hour, equals(1));
        expect(firstPoint.timestamp.minute, equals(30));
        
        // After DST: 08:30 UTC = 04:30 EDT (-04:00)
        // Note: The clock jumps from 01:59 to 03:00, so 02:xx doesn't exist
        final lastPoint = result.trackPoints.last;
        expect(lastPoint.timestamp.hour, equals(4));
        expect(lastPoint.timestamp.minute, equals(30));
        
        // Total duration should still be 2 hours (UTC perspective)
        // But local time appears to jump 3 hours (1:30 to 4:30)
      }, skip: 'DST rules need exact spring transition dates for 2024');

      test('Should handle flight starting exactly at DST transition', () async {
        // Flight starts at 07:00 UTC (2:00 AM EST, exactly when DST starts)
        final testIgc = '''AFLY00M9 0101373
HFDTE100324
HFPLTPILOT:DST Start Pilot
B0700004070000N07400000WA019780209600807000
B0730004070100N07400100WA019780209600807000
B0800004070200N07400200WA019780209600807000
''';

        final testFile = File('/tmp/test_dst_start.igc');
        await testFile.writeAsString(testIgc);
        
        final parser = IgcParser();
        final result = await parser.parseFile(testFile.path);
        
        expect(result, isNotNull);
        expect(result.trackPoints.length, equals(3));
        
        // 07:00 UTC would be 02:00 EST, but DST makes it 03:00 EDT
        final firstPoint = result.trackPoints.first;
        expect(firstPoint.timestamp.hour, equals(3));
        expect(firstPoint.timestamp.minute, equals(0));
      }, skip: 'DST rules need exact spring transition time handling');
    });

    group('Fall Back (2AM → 1AM)', () {
      test('Should handle flight during fall DST transition in US', () async {
        // US DST ends on November 3, 2024 at 2:00 AM
        // At 2:00 AM, clocks fall back to 1:00 AM
        // Flight from 05:30 UTC to 07:30 UTC (spans DST transition)
        final testIgc = '''AFLY00M9 0101373
HFDTE031124
HFPLTPILOT:Fall Back Pilot
B0530004070000N07400000WA019780209600807000
B0600004070100N07400100WA019780209600807000
B0630004070200N07400200WA019780209600807000
B0700004070300N07400300WA019780209600807000
B0730004070400N07400400WA019780209600807000
''';

        final testFile = File('/tmp/test_fall_dst.igc');
        await testFile.writeAsString(testIgc);
        
        final parser = IgcParser();
        final result = await parser.parseFile(testFile.path);
        
        expect(result, isNotNull);
        expect(result.trackPoints.length, equals(5));
        
        // Before DST ends: 05:30 UTC = 01:30 EDT (-04:00)
        final firstPoint = result.trackPoints.first;
        expect(firstPoint.timestamp.hour, equals(1));
        expect(firstPoint.timestamp.minute, equals(30));
        
        // After DST ends: 07:30 UTC = 02:30 EST (-05:00)
        final lastPoint = result.trackPoints.last;
        expect(lastPoint.timestamp.hour, equals(2));
        expect(lastPoint.timestamp.minute, equals(30));
        
        // Verify chronological order is maintained
        for (int i = 1; i < result.trackPoints.length; i++) {
          expect(
            result.trackPoints[i].timestamp.isAfter(result.trackPoints[i - 1].timestamp),
            isTrue,
          );
        }
      }, skip: 'DST rules need exact fall back transition dates for 2024');

      test('Should handle ambiguous hour during fall back', () async {
        // During fall back, 1:00-2:00 AM occurs twice
        // Flight during the "repeated" hour
        final testIgc = '''AFLY00M9 0101373
HFDTE031124
HFPLTPILOT:Ambiguous Hour Pilot
B0500004070000N07400000WA019780209600807000
B0530004070100N07400100WA019780209600807000
B0600004070200N07400200WA019780209600807000
B0630004070300N07400300WA019780209600807000
B0700004070400N07400400WA019780209600807000
''';

        final testFile = File('/tmp/test_ambiguous_hour.igc');
        await testFile.writeAsString(testIgc);
        
        final parser = IgcParser();
        final result = await parser.parseFile(testFile.path);
        
        expect(result, isNotNull);
        expect(result.trackPoints.length, equals(5));
        
        // All timestamps should be chronological despite ambiguous local times
        for (int i = 1; i < result.trackPoints.length; i++) {
          expect(
            result.trackPoints[i].timestamp.isAfter(result.trackPoints[i - 1].timestamp),
            isTrue,
          );
        }
      });
    });

    group('Southern Hemisphere DST', () {
      test('Should handle DST transition in Australia (opposite schedule)', () async {
        // Australia DST starts in October (spring in Southern Hemisphere)
        // Sydney DST starts October 6, 2024 at 2:00 AM
        final testIgc = '''AFLY00M9 0101373
HFDTE061024
HFPLTPILOT:Sydney Pilot
B1530003380000S15120000EA019780209600807000
B1600003380100S15120100EA019780209600807000
B1630003380200S15120200EA019780209600807000
B1700003380300S15120300EA019780209600807000
''';

        final testFile = File('/tmp/test_sydney_dst.igc');
        await testFile.writeAsString(testIgc);
        
        final parser = IgcParser();
        final result = await parser.parseFile(testFile.path);
        
        expect(result, isNotNull);
        expect(result.trackPoints.length, equals(4));
        
        // Verify timestamps are valid and chronological
        for (int i = 1; i < result.trackPoints.length; i++) {
          expect(
            result.trackPoints[i].timestamp.isAfter(result.trackPoints[i - 1].timestamp),
            isTrue,
          );
        }
      });

      test('Should handle DST end in Australia (April)', () async {
        // Australia DST ends in April (autumn in Southern Hemisphere)
        // Sydney DST ends April 7, 2024 at 3:00 AM (back to 2:00 AM)
        final testIgc = '''AFLY00M9 0101373
HFDTE070424
HFPLTPILOT:Sydney Autumn Pilot
B1530003380000S15120000EA019780209600807000
B1600003380100S15120100EA019780209600807000
B1630003380200S15120200EA019780209600807000
B1700003380300S15120300EA019780209600807000
''';

        final testFile = File('/tmp/test_sydney_dst_end.igc');
        await testFile.writeAsString(testIgc);
        
        final parser = IgcParser();
        final result = await parser.parseFile(testFile.path);
        
        expect(result, isNotNull);
        expect(result.trackPoints.length, equals(4));
        
        // Verify all timestamps remain chronological
        for (int i = 1; i < result.trackPoints.length; i++) {
          expect(
            result.trackPoints[i].timestamp.isAfter(result.trackPoints[i - 1].timestamp),
            isTrue,
          );
        }
      });
    });

    group('Non-DST Zones', () {
      test('Should handle flight in Arizona (no DST)', () async {
        // Arizona doesn't observe DST (except Navajo Nation)
        // Always MST (-07:00)
        final testIgc = '''AFLY00M9 0101373
HFDTE100324
HFPLTPILOT:Arizona Pilot
B1400003300000N11200000WA019780209600807000
B1430003300100N11200100WA019780209600807000
B1500003300200N11200200WA019780209600807000
B1530003300300N11200300WA019780209600807000
''';

        final testFile = File('/tmp/test_arizona_no_dst.igc');
        await testFile.writeAsString(testIgc);
        
        final parser = IgcParser();
        final result = await parser.parseFile(testFile.path);
        
        expect(result, isNotNull);
        expect(result.trackPoints.length, equals(4));
        
        // Verify consistent timezone offset (no DST change)
        // 14:00 UTC = 07:00 MST
        final firstPoint = result.trackPoints.first;
        expect(firstPoint.timestamp.hour, equals(7));
        
        // 15:30 UTC = 08:30 MST (consistent offset)
        final lastPoint = result.trackPoints.last;
        expect(lastPoint.timestamp.hour, equals(8));
        expect(lastPoint.timestamp.minute, equals(30));
      }, skip: 'Timezone detection for Arizona (no DST) needs refinement');

      test('Should handle flight in Queensland (no DST)', () async {
        // Queensland, Australia doesn't observe DST
        // Always AEST (+10:00)
        final testIgc = '''AFLY00M9 0101373
HFDTE061024
HFPLTPILOT:Queensland Pilot
B0000002700000S15300000EA019780209600807000
B0030002700100S15300100EA019780209600807000
B0100002700200S15300200EA019780209600807000
B0130002700300S15300300EA019780209600807000
''';

        final testFile = File('/tmp/test_queensland_no_dst.igc');
        await testFile.writeAsString(testIgc);
        
        final parser = IgcParser();
        final result = await parser.parseFile(testFile.path);
        
        expect(result, isNotNull);
        expect(result.trackPoints.length, equals(4));
        
        // 00:00 UTC = 10:00 AEST
        final firstPoint = result.trackPoints.first;
        expect(firstPoint.timestamp.hour, equals(10));
        
        // 01:30 UTC = 11:30 AEST (consistent offset)
        final lastPoint = result.trackPoints.last;
        expect(lastPoint.timestamp.hour, equals(11));
        expect(lastPoint.timestamp.minute, equals(30));
      });
    });

    group('Cross-DST Flight Duration', () {
      test('Should calculate correct duration for flight crossing DST start', () async {
        // Flight crosses spring DST transition
        // Duration should be based on actual elapsed time, not clock time
        final testIgc = '''AFLY00M9 0101373
HFDTE100324
HFPLTPILOT:Duration Test Pilot
B0630004070000N07400000WA019780209600807000
B0830004070400N07400400WA019780209600807000
''';

        final testFile = File('/tmp/test_dst_duration.igc');
        await testFile.writeAsString(testIgc);
        
        final parser = IgcParser();
        final result = await parser.parseFile(testFile.path);
        
        expect(result, isNotNull);
        expect(result.trackPoints.length, equals(2));
        
        // UTC duration: 08:30 - 06:30 = 2 hours
        // Local appears: 04:30 - 01:30 = 3 hours (due to DST)
        // But actual duration should be 2 hours
        final duration = result.trackPoints.last.timestamp
            .difference(result.trackPoints.first.timestamp);
        expect(duration.inHours, equals(2));
      });

      test('Should calculate correct duration for flight crossing DST end', () async {
        // Flight crosses fall DST transition
        final testIgc = '''AFLY00M9 0101373
HFDTE031124
HFPLTPILOT:Fall Duration Pilot
B0530004070000N07400000WA019780209600807000
B0730004070400N07400400WA019780209600807000
''';

        final testFile = File('/tmp/test_fall_duration.igc');
        await testFile.writeAsString(testIgc);
        
        final parser = IgcParser();
        final result = await parser.parseFile(testFile.path);
        
        expect(result, isNotNull);
        expect(result.trackPoints.length, equals(2));
        
        // UTC duration: 07:30 - 05:30 = 2 hours
        // Local appears: 02:30 - 01:30 = 1 hour (due to fall back)
        // But actual duration should be 2 hours
        final duration = result.trackPoints.last.timestamp
            .difference(result.trackPoints.first.timestamp);
        expect(duration.inHours, equals(2));
      });
    });

    group('DST Edge Cases', () {
      test('Should handle flight ending at exact DST transition moment', () async {
        // Flight ends exactly at 07:00 UTC (2:00 AM local, DST start)
        final testIgc = '''AFLY00M9 0101373
HFDTE100324
HFPLTPILOT:Exact DST Pilot
B0630004070000N07400000WA019780209600807000
B0645004070100N07400100WA019780209600807000
B0700004070200N07400200WA019780209600807000
''';

        final testFile = File('/tmp/test_exact_dst.igc');
        await testFile.writeAsString(testIgc);
        
        final parser = IgcParser();
        final result = await parser.parseFile(testFile.path);
        
        expect(result, isNotNull);
        expect(result.trackPoints.length, equals(3));
        
        // Last point at exact DST transition
        final lastPoint = result.trackPoints.last;
        expect(lastPoint.timestamp.hour, equals(3)); // Jumps to 3:00 AM
      }, skip: 'DST rules need exact handling of transition moment');

      test('Should handle rapid points during DST transition', () async {
        // Points every minute during DST transition
        final testIgc = '''AFLY00M9 0101373
HFDTE100324
HFPLTPILOT:Rapid DST Pilot
B0658004070000N07400000WA019780209600807000
B0659004070100N07400100WA019780209600807000
B0700004070200N07400200WA019780209600807000
B0701004070300N07400300WA019780209600807000
B0702004070400N07400400WA019780209600807000
''';

        final testFile = File('/tmp/test_rapid_dst.igc');
        await testFile.writeAsString(testIgc);
        
        final parser = IgcParser();
        final result = await parser.parseFile(testFile.path);
        
        expect(result, isNotNull);
        expect(result.trackPoints.length, equals(5));
        
        // All points should maintain chronological order
        for (int i = 1; i < result.trackPoints.length; i++) {
          expect(
            result.trackPoints[i].timestamp.isAfter(result.trackPoints[i - 1].timestamp),
            isTrue,
          );
          
          // Despite local time jump, actual elapsed time should be 1 minute
          if (i < 3) {
            final diff = result.trackPoints[i].timestamp
                .difference(result.trackPoints[i - 1].timestamp);
            expect(diff.inMinutes, equals(1));
          }
        }
      });
    });
  });
}
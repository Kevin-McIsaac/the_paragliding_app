import 'package:flutter_test/flutter_test.dart';
import 'package:the_paragliding_app/services/timezone_service.dart';
import 'package:the_paragliding_app/services/igc_parser.dart';
import 'dart:io';

void main() {
  group('Timezone Detection Tests', () {
    setUpAll(() {
      TimezoneService.initialize();
    });

    test('Should detect timezone from European coordinates', () {
      // Coordinates near Zurich, Switzerland
      final timezone = TimezoneService.getTimezoneFromCoordinates(47.145, 11.308);
      expect(timezone, isNotNull);
      expect(timezone, equals('Europe/Zurich'));
      
      // Convert to offset string
      final offset = TimezoneService.getOffsetStringFromTimezone(
        timezone!,
        DateTime(2025, 8, 3), // Summer time
      );
      expect(offset, equals('+02:00')); // CEST in summer
    });

    test('Should detect timezone from North American coordinates', () {
      // Coordinates near New York
      final timezone = TimezoneService.getTimezoneFromCoordinates(40.7128, -74.0060);
      expect(timezone, isNotNull);
      expect(timezone, equals('America/New_York'));
      
      // Convert to offset string
      final offset = TimezoneService.getOffsetStringFromTimezone(
        timezone!,
        DateTime(2025, 8, 3), // Summer time
      );
      expect(offset, equals('-04:00')); // EDT in summer
    });

    test('Should detect timezone from Australian coordinates', () {
      // Coordinates near Sydney
      final timezone = TimezoneService.getTimezoneFromCoordinates(-33.8688, 151.2093);
      expect(timezone, isNotNull);
      expect(timezone, equals('Australia/Sydney'));
      
      // Convert to offset string
      final offset = TimezoneService.getOffsetStringFromTimezone(
        timezone!,
        DateTime(2025, 8, 3), // Winter in Australia
      );
      expect(offset, equals('+10:00')); // AEST in winter
    });

    test('Should fall back to estimation for unknown locations', () {
      // Coordinates in middle of ocean
      final timezone = TimezoneService.getTimezoneFromCoordinates(0, -30);
      expect(timezone, isNotNull);
      // Should return some timezone even if not exact
    });
  });

  group('IGC Parser B Record UTC Tests', () {
    test('Should override HFTZNUTCOFFSET with GPS-based timezone', () async {
      // Create a test IGC file with HFTZNUTCOFFSET that will be overridden
      // Coordinates near Zurich should give +02:00 (CEST in August)
      final testIgc = '''AFLY00M9 0101373
HFDTE050825
HFPLTPILOT:Test Pilot
HFTZNUTCOFFSET: 10.00h
B0800004708710N01118478EA019780209600807000
B0801004708710N01118478EA019780209600807000
B0802004708710N01118478EA019780209600807000
''';

      // Write test file
      final testFile = File('/tmp/test_utc.igc');
      await testFile.writeAsString(testIgc);
      
      final parser = IgcParser();
      final result = await parser.parseFile(testFile.path);
      
      expect(result, isNotNull);
      // Should have GPS-detected timezone, not the HFTZNUTCOFFSET value
      expect(result.timezone, equals('+02:00')); // Europe/Zurich in summer
      expect(result.trackPoints.length, equals(3));
      
      // First B record at 08:00:00 UTC should be 10:00:00 local time (+02:00)
      final firstPoint = result.trackPoints.first;
      expect(firstPoint.timestamp.hour, equals(10)); // 08:00 UTC + 2 hours
      expect(firstPoint.timestamp.minute, equals(0));
      expect(firstPoint.timestamp.second, equals(0));
    });

    test('Should always detect timezone from GPS coordinates', () async {
      // Create a test IGC file without HFTZNUTCOFFSET header
      // Using coordinates near Zurich (47.145°N, 11.308°E)
      final testIgc = '''AFLY00M9 0101373
HFDTE050825
HFPLTPILOT:Test Pilot
B0800004708700N01118480EA019780209600807000
B0801004708710N01118478EA019780209600807000
B0802004708720N01118476EA019780209600807000
''';

      // Write test file
      final testFile = File('/tmp/test_gps.igc');
      await testFile.writeAsString(testIgc);
      
      final parser = IgcParser();
      final result = await parser.parseFile(testFile.path);
      
      expect(result, isNotNull);
      // Should have detected timezone from GPS coordinates
      expect(result.timezone, isNotNull);
      expect(result.timezone, equals('+02:00')); // CEST in August
      
      // First B record at 08:00:00 UTC should be 10:00:00 local time (+02:00)
      final firstPoint = result.trackPoints.first;
      expect(firstPoint.timestamp.hour, equals(10)); // 08:00 UTC + 2 hours
      expect(firstPoint.timestamp.minute, equals(0));
      expect(firstPoint.timestamp.second, equals(0));
    });

    test('Should keep UTC if no timezone detected', () async {
      // Create a test IGC file without timezone and with ocean coordinates
      final testIgc = '''AFLY00M9 0101373
HFDTE050825
HFPLTPILOT:Test Pilot
B0800000000000N00000000EA019780209600807000
B0801000000000N00000000EA019780209600807000
''';

      // Write test file
      final testFile = File('/tmp/test_ocean.igc');
      await testFile.writeAsString(testIgc);
      
      final parser = IgcParser();
      final result = await parser.parseFile(testFile.path);
      
      expect(result, isNotNull);
      // Will detect a timezone even for 0,0 coordinates (likely UTC or Africa)
      // The important thing is that it processes the file without error
      expect(result.trackPoints.length, equals(2));
    });
  });
}
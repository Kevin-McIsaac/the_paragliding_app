import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_paragliding_app/services/igc_parser.dart';

void main() {
  const header = 'AFLY00M9 0101373\n'
      'HFDTE030616\n'
      'HFPLTPILOT:Test Pilot\n'
      'HFGTYGLIDERTYPE:Alpha 31\n';

  /// Valid B record at [time] (HHMMSS), near Sydney
  String bRecord(String time) =>
      'B${time}3413138S15100113EA0015500270';

  group('IgcParser B-record validation', () {
    final parser = IgcParser();

    test('keeps well-formed records', () {
      final file = parser.parseString(
        '$header${bRecord('034029')}\n${bRecord('034129')}\n${bRecord('034229')}\n',
      );

      expect(file.trackPoints, hasLength(3));
    });

    test('skips impossible hours rather than rolling into later days', () {
      // hour 80 and hour 99 - DateTime would silently roll these forward,
      // turning one flight into a track spanning days
      final file = parser.parseString(
        '$header${bRecord('034029')}\n'
        '${bRecord('800000')}\n'
        '${bRecord('990000')}\n'
        '${bRecord('034129')}\n',
      );

      expect(file.trackPoints, hasLength(2));
      final span = file.trackPoints.last.timestamp
          .difference(file.trackPoints.first.timestamp);
      expect(span.inHours, lessThan(24));
    });

    test('skips out-of-range minutes and seconds', () {
      final file = parser.parseString(
        '$header${bRecord('034029')}\n'
        '${bRecord('034129')}\n'
        '${bRecord('034229')}\n'
        '${bRecord('037029')}\n' // minute 70
        '${bRecord('034099')}\n' // second 99
        '\n',
      );

      expect(file.trackPoints, hasLength(3));
    });

    test('rejects a file where most records are malformed', () {
      expect(
        () => parser.parseString(
          '$header${bRecord('034029')}\n'
          '${bRecord('800000')}\n'
          '${bRecord('990000')}\n',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('parses the sample flight unchanged', () async {
      final sample = File('test_data/sample_flight.igc');
      expect(sample.existsSync(), isTrue,
          reason: 'sample fixture missing - test cannot verify a clean parse');

      final file = await parser.parseFile(sample.path);

      expect(file.trackPoints, isNotEmpty);
      final span = file.trackPoints.last.timestamp
          .difference(file.trackPoints.first.timestamp);
      expect(span.inHours, lessThan(24));
    });
  });
}

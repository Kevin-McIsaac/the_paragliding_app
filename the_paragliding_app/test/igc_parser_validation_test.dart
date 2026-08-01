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

  /// B record with explicit coordinate fields, for the out-of-range cases.
  /// [lat] is DDMMmmm, [lon] is DDDMMmmm - widths are fixed, so a bad value has
  /// to stay the same length as a good one.
  String bRecordAt(String time, {String lat = '3413138', String lon = '15100113'}) =>
      'B$time${lat}S${lon}EA0015500270';

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

    test('skips records with out-of-range coordinates', () {
      final file = parser.parseString(
        '$header${bRecord('034029')}\n'
        '${bRecord('034129')}\n'
        '${bRecord('034229')}\n'
        '${bRecordAt('034329', lat: '9913138')}\n' // latitude 99 degrees
        '${bRecordAt('034429', lon: '19900113')}\n' // longitude 199 degrees
        '\n',
      );

      expect(file.trackPoints, hasLength(3),
          reason: 'impossible coordinates must be dropped, not clamped');
    });

    test('accepts a flight that crosses midnight UTC', () {
      // The rollover path re-parses the record with an incremented date; the
      // range checks must not reject those records on the way through.
      final file = parser.parseString(
        '$header${bRecord('235800')}\n'
        '${bRecord('235900')}\n'
        '${bRecord('000100')}\n'
        '${bRecord('000200')}\n',
      );

      expect(file.trackPoints, hasLength(4));
      final span = file.trackPoints.last.timestamp
          .difference(file.trackPoints.first.timestamp);
      expect(span.inHours, lessThan(24));
      expect(file.trackPoints.last.timestamp
          .isAfter(file.trackPoints.first.timestamp), isTrue);
    });

    test('keeps a file sitting exactly at the 50% malformed threshold', () {
      // The rule is `malformed * 2 > total`, so exactly half must survive -
      // this pins the boundary against an accidental flip to >=.
      final file = parser.parseString(
        '$header${bRecord('034029')}\n'
        '${bRecord('034129')}\n'
        '${bRecord('800000')}\n'
        '${bRecord('990000')}\n',
      );

      expect(file.trackPoints, hasLength(2));
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

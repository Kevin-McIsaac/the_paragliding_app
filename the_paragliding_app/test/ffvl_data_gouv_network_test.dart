import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// The two files FFVL publishes on data.gouv.fr. The ids are stable and the
/// data.gouv.fr endpoint redirects to the current dated file.
const _balisesUrl =
    'https://www.data.gouv.fr/api/1/datasets/r/8d795154-9145-4ab2-99de-6768a36f31ea';
const _relevesUrl =
    'https://www.data.gouv.fr/api/1/datasets/r/047b2ab9-627f-4e5f-9d68-5b948433c61d';

void main() {
  test('the published FFVL files are still served and parseable', () async {
    // flutter_test answers every real request with a 400 unless the override
    // is lifted, which is exactly what a live check needs to opt out of.
    final overrides = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = overrides);

    const headers = {
      'Accept': 'application/json',
      'User-Agent': 'TheParaglidingApp/1.0',
    };

    final balisesResponse = await http.get(
      Uri.parse(_balisesUrl),
      headers: headers,
    );
    expect(balisesResponse.statusCode, 200);

    final decodedBalises = jsonDecode(balisesResponse.body);
    expect(decodedBalises, isA<List>());
    final beacons = (decodedBalises as List)
        .whereType<Map<String, dynamic>>()
        .toList();
    expect(beacons.length, greaterThan(500));

    final complete = beacons.where((beacon) {
      return beacon['idBalise'] != null &&
          beacon['nom'] != null &&
          beacon['latitude'] != null &&
          beacon['longitude'] != null;
    }).length;
    expect(complete / beacons.length, greaterThan(0.99));

    final readingsResponse = await http.get(
      Uri.parse(_relevesUrl),
      headers: headers,
    );
    expect(readingsResponse.statusCode, 200);

    final decodedReadings = jsonDecode(readingsResponse.body);
    expect(decodedReadings, isA<List>());
    final readings = (decodedReadings as List)
        .whereType<Map<String, dynamic>>()
        .toList();
    expect(readings.length, greaterThan(100));

    final dated = readings.where((reading) {
      final date = reading['date'];
      return reading['idbalise'] != null &&
          date is String &&
          DateTime.tryParse(date) != null;
    }).toList();
    expect(dated.length / readings.length, greaterThan(0.99));

    final beaconIds = beacons.map((beacon) => beacon['idBalise'].toString()).toSet();
    expect(
      dated.any((reading) => beaconIds.contains(reading['idbalise'].toString())),
      isTrue,
    );

    final now = DateTime.now();
    final fresh = dated.where((reading) {
      final date = DateTime.parse(reading['date'] as String).toUtc();
      return now.difference(date) < const Duration(hours: 2);
    }).length;
    expect(fresh / dated.length, greaterThan(0.9));
  }, tags: 'network');
}

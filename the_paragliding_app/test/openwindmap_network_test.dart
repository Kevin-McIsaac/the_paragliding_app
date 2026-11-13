import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// The public OpenWindMap Live API. The app fetches the global list because the
/// API has no area query. The single-station call is the endpoint the app reads
/// for complete metadata when a specific station is needed.
const _allUrl = 'https://api.openwindmap.org/v1/live-with-meta/all';
const _singleUrl = 'https://api.openwindmap.org/v1/live-with-meta';

void main() {
  test('the live OpenWindMap endpoints are served and parseable', () async {
    // flutter_test answers every real request with a 400 unless the override
    // is lifted, which is exactly what a live check needs to opt out of.
    final overrides = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = overrides);

    const headers = {
      'Accept': 'application/json',
      'User-Agent': 'TheParaglidingApp/1.0',
    };

    final response = await http.get(Uri.parse(_allUrl), headers: headers);
    expect(response.statusCode, 200);

    final decoded = jsonDecode(response.body);
    expect(decoded, isA<Map<String, dynamic>>());

    final data = (decoded as Map<String, dynamic>)['data'];
    expect(data, isA<List>());

    final stations = (data as List).whereType<Map<String, dynamic>>().toList();
    expect(stations.length, greaterThan(500));

    final complete = stations.where((station) {
      final meta = station['meta'];
      final location = station['location'];
      final measurements = station['measurements'];
      return station['id'] != null &&
          meta is Map<String, dynamic> &&
          meta['name'] != null &&
          location is Map<String, dynamic> &&
          location['latitude'] is num &&
          location['longitude'] is num &&
          measurements is Map<String, dynamic>;
    }).length;
    expect(complete / stations.length, greaterThan(0.9));

    final withWind = stations.where((station) {
      final status = station['status'];
      final measurements = station['measurements'];
      return status is Map<String, dynamic> &&
          status['state'] == 'on' &&
          measurements is Map<String, dynamic> &&
          measurements['wind_speed_avg'] is num &&
          measurements['wind_heading'] is num;
    }).toList();
    expect(withWind.length, greaterThan(300));

    for (final station in withWind.take(100)) {
      final measurements = station['measurements'] as Map<String, dynamic>;
      expect(
        measurements['wind_speed_avg'] as num,
        inInclusiveRange(0, 250),
      );
      expect(
        measurements['wind_heading'] as num,
        inInclusiveRange(0, 360),
      );
    }

    final firstId = stations.first['id'];
    expect(firstId, isNotNull);

    final singleResponse = await http.get(
      Uri.parse('$_singleUrl/$firstId'),
      headers: headers,
    );
    expect(singleResponse.statusCode, 200);

    final single = jsonDecode(singleResponse.body) as Map<String, dynamic>;
    final singleData = single['data'] as Map<String, dynamic>;
    expect(singleData['id'], firstId);
  }, tags: 'network');
}

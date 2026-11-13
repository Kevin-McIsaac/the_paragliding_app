import 'dart:async';
import 'dart:convert';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

import 'package:the_paragliding_app/data/models/weather_station_source.dart';
import 'package:the_paragliding_app/services/weather_providers/openwindmap_weather_provider.dart';
import 'package:the_paragliding_app/services/weather_providers/weather_station_provider_registry.dart';

/// A compact copy of the `live-with-meta/all` response. It keeps the fields
/// the provider reads and adds the cases the parser must survive: an offline
/// station, a station without a heading, and a station without a position.
String _responseJson({String? date}) {
  final now = DateTime.now().toUtc();
  final stamp =
      date ?? now.subtract(const Duration(minutes: 5)).toIso8601String();

  final data = <Map<String, dynamic>>[
    {
      'id': 1,
      'meta': {'name': 'Sauveterre'},
      'location': {
        'latitude': 43.456782,
        'longitude': 0.846358,
        'success': true,
      },
      'measurements': {
        'date': stamp,
        'wind_heading': 292.5,
        'wind_speed_avg': 12,
        'wind_speed_max': 21,
        'wind_speed_min': 6.5,
      },
      'status': {'state': 'on'},
    },
    {
      'id': 2,
      'meta': {'name': 'Pioupiou 61'},
      'location': {
        'latitude': 48.557058,
        'longitude': 7.515347,
        'success': true,
      },
      'measurements': {
        'date': stamp,
        'wind_heading': 180,
        'wind_speed_avg': 5,
        'wind_speed_max': 9,
        'wind_speed_min': 1,
      },
      'status': {'state': 'off'},
    },
    {
      'id': 3,
      'meta': {'name': 'No heading'},
      'location': {
        'latitude': 45.0,
        'longitude': 6.0,
        'success': true,
      },
      'measurements': {
        'date': stamp,
        'wind_heading': null,
        'wind_speed_avg': 3,
        'wind_speed_max': 4,
        'wind_speed_min': 1,
      },
      'status': {'state': 'on'},
    },
    {
      'id': 4,
      'meta': {'name': 'No location'},
      'location': {'latitude': null, 'longitude': null, 'success': false},
      'measurements': {'date': stamp},
      'status': {'state': 'on'},
    },
    {
      'id': 5,
      'meta': {'name': 'USA'},
      'location': {'latitude': 40.0, 'longitude': -100.0, 'success': true},
      'measurements': {
        'date': stamp,
        'wind_heading': 90,
        'wind_speed_avg': 10,
        'wind_speed_max': 15,
        'wind_speed_min': 5,
      },
      'status': {'state': 'on'},
    },
  ];

  return jsonEncode({'data': data});
}

MockClient _client({
  String? body,
  int status = 200,
  void Function(Uri)? onRequest,
}) {
  return MockClient((request) async {
    onRequest?.call(request.url);
    return http.Response(body ?? _responseJson(), status);
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late OpenWindMapWeatherProvider provider;

  final france = LatLngBounds(const LatLng(42, -5), const LatLng(51, 10));
  final usa = LatLngBounds(const LatLng(35, -110), const LatLng(45, -90));

  setUp(() {
    provider = OpenWindMapWeatherProvider.instance;
    provider.clearCache();
    // A test that forgets to install its own client gets empty data, not the
    // real network.
    provider.httpClientForTest = MockClient(
      (request) async => http.Response('unexpected request', 500),
    );
  });

  test('parses the global response and maps the metadata', () async {
    provider.httpClientForTest = _client();

    final stations = await provider.fetchStations(france);

    expect(stations.map((station) => station.id), ['1', '2', '3']);

    final sauveterre = stations.first;
    expect(sauveterre.name, 'Sauveterre');
    expect(sauveterre.latitude, closeTo(43.456782, 0.000001));
    expect(sauveterre.longitude, closeTo(0.846358, 0.000001));
    expect(sauveterre.source, WeatherStationSource.openWindMap);
    expect(sauveterre.observationType, 'Wind Station (OpenWindMap)');
    expect(sauveterre.dataUrl, 'https://www.openwindmap.org/windbird-1');
    expect(sauveterre.windData!.speedKmh, 12);
    expect(sauveterre.windData!.gustsKmh, 21);
    expect(sauveterre.windData!.directionDegrees, 292.5);
    expect(sauveterre.windData!.timestamp.isUtc, isTrue);

    final offline = stations.firstWhere((station) => station.id == '2');
    expect(offline.windData, isNull);

    final noHeading = stations.firstWhere((station) => station.id == '3');
    expect(noHeading.windData, isNull);

    // The station without a position is not dropped into the list.
    expect(stations.any((station) => station.id == '4'), isFalse);
  });

  test('filters the global list to the requested bounding box', () async {
    provider.httpClientForTest = _client();

    final stations = await provider.fetchStations(usa);

    expect(stations.map((station) => station.id), ['5']);
  });

  test('caches the list and refreshes when a TTL expires', () async {
    final requests = <Uri>[];
    provider.httpClientForTest = _client(onRequest: requests.add);

    await provider.fetchStations(france);
    expect(requests, hasLength(1));
    expect(requests.single.path, contains('live-with-meta/all'));

    requests.clear();
    await provider.fetchStations(france);
    expect(requests, isEmpty);

    requests.clear();
    provider.setCacheAgeForTest(measurementsAge: const Duration(minutes: 6));
    await provider.fetchStations(france);
    expect(requests, hasLength(1));

    requests.clear();
    provider.setCacheAgeForTest(stationListAge: const Duration(hours: 25));
    await provider.fetchStations(france);
    expect(requests, hasLength(1));
  });

  test('a failed refresh keeps the previous cache', () async {
    provider.httpClientForTest = _client();
    final first = await provider.fetchStations(france);
    expect(first, hasLength(3));

    provider.httpClientForTest =
        MockClient((request) async => http.Response('down', 500));
    provider.setCacheAgeForTest(measurementsAge: const Duration(minutes: 6));

    final second = await provider.fetchStations(france);

    expect(second, hasLength(3));
    expect(second.first.windData, isNotNull);
  });

  test('a non-200 response is an empty list', () async {
    provider.httpClientForTest = _client(status: 503);

    expect(await provider.fetchStations(france), isEmpty);
  });

  test('a malformed response is an empty list', () async {
    provider.httpClientForTest = _client(body: 'not json');

    expect(await provider.fetchStations(france), isEmpty);
  });

  test('two concurrent fetches share one request', () async {
    var requests = 0;
    final gate = Completer<void>();
    provider.httpClientForTest = MockClient((request) async {
      requests++;
      await gate.future;
      return http.Response(_responseJson(), 200);
    });

    final first = provider.fetchStations(france);
    final second = provider.fetchStations(france);
    gate.complete();

    final results = await Future.wait([first, second]);

    expect(requests, 1);
    expect(results[0], hasLength(3));
    expect(results[1], hasLength(3));
  });

  test('extracts the embedded wind by station key', () async {
    provider.httpClientForTest = _client();
    final stations = await provider.fetchStations(france);

    final wind = await provider.fetchWeatherData(stations);

    expect(wind, hasLength(1));
    expect(wind['openWindMap:1']!.speedKmh, 12);
    expect(wind['openWindMap:1']!.directionDegrees, 292.5);
  });

  test('reports its source and attribution', () async {
    expect(provider.source, WeatherStationSource.openWindMap);
    expect(provider.displayName, 'OpenWindMap');
    expect(provider.description, contains('global'));
    expect(provider.attributionName, contains('OpenWindMap'));
    expect(provider.attributionUrl, 'https://openwindmap.org/');
    expect(provider.cacheTTL, const Duration(minutes: 5));
    expect(provider.requiresApiKey, isFalse);
    expect(await provider.isConfigured(), isTrue);
  });

  test('is registered for the source', () {
    expect(
      WeatherStationProviderRegistry.getProvider(
        WeatherStationSource.openWindMap,
      ),
      same(provider),
    );
    expect(
      WeatherStationProviderRegistry.getAllSources(),
      contains(WeatherStationSource.openWindMap),
    );
  });
}

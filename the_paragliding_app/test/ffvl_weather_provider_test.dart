import 'dart:convert';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

import 'package:the_paragliding_app/data/models/weather_station_source.dart';
import 'package:the_paragliding_app/services/weather_providers/ffvl_weather_provider.dart';

/// Excerpts of the live data.gouv.fr files, keeping only the fields the
/// provider reads. The dates are generated around the test clock so the
/// two-hour freshness gate is deterministic.
const _balises = <Map<String, dynamic>>[
  {
    'idBalise': 10,
    'nom': 'Mont Jovet',
    'latitude': 45.4852981,
    'longitude': 6.63917016,
    'altitude': 2283,
    'departement': '73',
    'station_type': 'ADISON',
    'en_maintenance': 0,
  },
  {
    'idBalise': 11,
    'nom': 'Aiguebelette',
    'latitude': 45.60290146,
    'longitude': 5.80628014,
    'altitude': 1121,
    'departement': '73',
    'station_type': 'OPENWINDMAP',
    'en_maintenance': 0,
  },
  {
    'idBalise': 12,
    'nom': 'Maintenance integer',
    'latitude': 45.0,
    'longitude': 6.0,
    'station_type': 'ADISON',
    'en_maintenance': 1,
  },
  {
    'idBalise': 13,
    'nom': 'Maintenance string',
    'latitude': 45.1,
    'longitude': 6.1,
    'station_type': 'ADISON',
    'en_maintenance': '1',
  },
  {
    'idBalise': 14,
    'nom': 'No position',
    'longitude': 6.2,
    'station_type': 'ADISON',
    'en_maintenance': 0,
  },
  {
    'idBalise': 15,
    'nom': 'No department',
    'latitude': 45.2,
    'longitude': 6.2,
    'station_type': 'HOLFUY',
    'en_maintenance': 0,
  },
  {
    'idBalise': 16,
    'nom': 'Unknown department',
    'latitude': 45.3,
    'longitude': 6.3,
    'departement': '99',
    'station_type': 'SENCROP',
    'en_maintenance': 0,
  },
];

String _readingsJson({
  String? date,
  bool withDirection = true,
  bool includeOld = false,
}) {
  final now = DateTime.now().toUtc();
  final recent = date ??
      now.subtract(const Duration(minutes: 5)).toIso8601String();

  final readings = <Map<String, dynamic>>[
    {
      'idbalise': 10,
      'date': recent,
      'vitesseVentMoy': 30,
      'vitesseVentMax': 44,
      'directVentMoy': withDirection ? 246 : 0,
    },
    // No beacon has id 999. This must be ignored, not turned into a station.
    {
      'idbalise': 999,
      'date': recent,
      'vitesseVentMoy': 12,
      'directVentMoy': 90,
    },
  ];

  if (!withDirection) {
    readings.first.remove('directVentMoy');
  }

  if (includeOld) {
    readings.add({
      'idbalise': 11,
      'date': now.subtract(const Duration(hours: 3)).toIso8601String(),
      'vitesseVentMoy': 20,
      'directVentMoy': 180,
    });
  }

  return jsonEncode(readings);
}

MockClient _client({
  String? balises,
  String? readings,
  int balisesStatus = 200,
  int readingsStatus = 200,
  void Function(Uri)? onRequest,
}) {
  return MockClient((request) async {
    onRequest?.call(request.url);
    final isBalises = request.url.path.contains('8d795154');
    if (isBalises) {
      return http.Response(
        balises ?? jsonEncode(_balises),
        balisesStatus,
      );
    }
    return http.Response(
      readings ?? _readingsJson(),
      readingsStatus,
    );
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FfvlWeatherProvider provider;

  final france = LatLngBounds(const LatLng(42, -5), const LatLng(51, 10));
  final australia = LatLngBounds(const LatLng(-45, 110), const LatLng(-10, 155));

  setUp(() {
    provider = FfvlWeatherProvider.instance;
    provider.clearCache();
    // A test that forgets to install its own client gets empty data, not the
    // real network.
    provider.httpClientForTest =
        MockClient((request) async => http.Response('unexpected request', 500));
  });

  test('joins readings and maps the beacon metadata', () async {
    provider.httpClientForTest = _client();

    final stations = await provider.fetchStations(france);

    expect(
      stations.map((station) => station.id),
      ['ffvl_10', 'ffvl_11', 'ffvl_15', 'ffvl_16'],
    );

    final jovet = stations.firstWhere((station) => station.id == 'ffvl_10');
    expect(jovet.name, 'Mont Jovet (Savoie)');
    expect(jovet.latitude, closeTo(45.4852981, 0.000001));
    expect(jovet.longitude, closeTo(6.63917016, 0.000001));
    expect(jovet.elevation, 2283);
    expect(jovet.observationType, 'FFVL (ADISON)');
    expect(jovet.dataUrl,
        'https://www.balisemeteo.com/balise.php?idBalise=10');
    expect(jovet.windData!.speedKmh, 30);
    expect(jovet.windData!.gustsKmh, 44);
    expect(jovet.windData!.directionDegrees, 246);
    expect(jovet.windData!.timestamp.isUtc, isTrue);

    final openWindMap =
        stations.firstWhere((station) => station.id == 'ffvl_11');
    expect(openWindMap.name, 'Aiguebelette (Savoie)');
    expect(openWindMap.observationType, 'FFVL/OpenWindMap');
    expect(openWindMap.windData, isNull);

    final noDepartment =
        stations.firstWhere((station) => station.id == 'ffvl_15');
    expect(noDepartment.name, 'No department');
    expect(noDepartment.observationType, 'FFVL (HOLFUY)');

    final unknownDepartment =
        stations.firstWhere((station) => station.id == 'ffvl_16');
    expect(unknownDepartment.name, 'Unknown department (Dept 99)');
  });

  test('skips maintenance marked as an integer or a string', () async {
    provider.httpClientForTest = _client();

    final stations = await provider.fetchStations(france);
    final ids = stations.map((station) => station.id);

    expect(ids, isNot(contains('ffvl_12')));
    expect(ids, isNot(contains('ffvl_13')));
  });

  test('skips a beacon with no position', () async {
    provider.httpClientForTest = _client();

    final stations = await provider.fetchStations(france);

    expect(stations.map((station) => station.id), isNot(contains('ffvl_14')));
  });

  test('keeps a +01:00 timestamp as the same UTC instant', () async {
    final instant = DateTime.now().toUtc().subtract(const Duration(minutes: 5));
    final wallClock = instant.add(const Duration(hours: 1));
    final stamp =
        '${wallClock.toIso8601String().substring(0, 19)}+01:00';

    provider.httpClientForTest = _client(readings: _readingsJson(date: stamp));

    final stations = await provider.fetchStations(france);
    final wind = stations
        .firstWhere((station) => station.id == 'ffvl_10')
        .windData!;

    expect(wind.timestamp, DateTime.parse(stamp));
    expect(wind.timestamp.isUtc, isTrue);
  });

  test('a reading with no direction is no wind, not zero wind', () async {
    provider.httpClientForTest =
        _client(readings: _readingsJson(withDirection: false));

    final stations = await provider.fetchStations(france);
    final jovet = stations.firstWhere((station) => station.id == 'ffvl_10');

    expect(jovet.windData, isNull);
  });

  test('drops a reading older than two hours', () async {
    provider.httpClientForTest =
        _client(readings: _readingsJson(includeOld: true));

    final stations = await provider.fetchStations(france);

    expect(
      stations.firstWhere((station) => station.id == 'ffvl_10').windData,
      isNotNull,
    );
    expect(
      stations.firstWhere((station) => station.id == 'ffvl_11').windData,
      isNull,
    );
  });

  test('ignores an orphan reading', () async {
    provider.httpClientForTest = _client();

    final stations = await provider.fetchStations(france);

    expect(stations, hasLength(4));
    expect(stations.any((station) => station.id.contains('999')), isFalse);
  });

  test('loads the catalogue once, then refreshes only the readings', () async {
    final requests = <Uri>[];
    provider.httpClientForTest = _client(onRequest: requests.add);

    await provider.fetchStations(france);
    expect(requests, hasLength(2));
    expect(requests[0].path, contains('8d795154'));
    expect(requests[1].path, contains('047b2ab9'));

    requests.clear();
    provider.setCacheAgeForTest(measurementsAge: const Duration(minutes: 6));
    await provider.fetchStations(france);
    expect(requests, hasLength(1));
    expect(requests.single.path, contains('047b2ab9'));

    requests.clear();
    provider.setCacheAgeForTest(beaconListAge: const Duration(hours: 25));
    await provider.fetchStations(france);
    expect(requests, hasLength(2));
  });

  test('a failed readings refresh keeps the previous stations', () async {
    provider.httpClientForTest = _client();
    final first = await provider.fetchStations(france);
    expect(first.first.windData, isNotNull);

    var calls = 0;
    provider.httpClientForTest = MockClient((request) async {
      calls++;
      return http.Response('down', 500);
    });
    provider.setCacheAgeForTest(measurementsAge: const Duration(minutes: 6));

    final after = await provider.fetchStations(france);

    expect(calls, 1);
    expect(after, hasLength(first.length));
    expect(after.first.windData, isNotNull);
  });

  test('a failed beacon-list refresh keeps the old stations', () async {
    provider.httpClientForTest = _client();
    await provider.fetchStations(france);

    provider.httpClientForTest =
        MockClient((request) async => http.Response('down', 500));
    provider.setCacheAgeForTest(beaconListAge: const Duration(hours: 25));

    final after = await provider.fetchStations(france);

    expect(after, hasLength(4));
  });

  test('a 500 on the readings file still returns the beacons', () async {
    provider.httpClientForTest = _client(readingsStatus: 500);

    final stations = await provider.fetchStations(france);

    expect(stations, hasLength(4));
    expect(stations.every((station) => station.windData == null), isTrue);
  });

  test('a 404 on the beacon list returns no stations', () async {
    provider.httpClientForTest = _client(balisesStatus: 404);

    expect(await provider.fetchStations(france), isEmpty);
  });

  test('a second fetch inside both TTLs makes no request', () async {
    final requests = <Uri>[];
    provider.httpClientForTest = _client(onRequest: requests.add);

    await provider.fetchStations(france);
    requests.clear();
    await provider.fetchStations(france);

    expect(requests, isEmpty);
  });

  test('an outside-France view makes no request with a fresh cache', () async {
    final requests = <Uri>[];
    provider.httpClientForTest = _client(onRequest: requests.add);

    await provider.fetchStations(france);
    requests.clear();
    provider.setCacheAgeForTest(measurementsAge: const Duration(minutes: 6));

    final stations = await provider.fetchStations(australia);

    expect(stations, isEmpty);
    expect(requests, isEmpty);
  });

  test('is keyless and credits FFVL and data.gouv.fr', () async {
    expect(provider.source, WeatherStationSource.ffvl);
    expect(provider.requiresApiKey, isFalse);
    expect(await provider.isConfigured(), isTrue);
    expect(provider.attributionName, contains('FFVL'));
    expect(provider.attributionUrl, contains('data.gouv.fr/datasets/'));
  });

  test('fetchWeatherData extracts the embedded wind and makes no request',
      () async {
    final requests = <Uri>[];
    provider.httpClientForTest = _client(onRequest: requests.add);
    final stations = await provider.fetchStations(france);
    requests.clear();

    final data = await provider.fetchWeatherData(stations);

    expect(requests, isEmpty);
    expect(data.keys, ['ffvl:ffvl_10']);
    expect(data, hasLength(1));
  });
}

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:the_paragliding_app/data/models/weather_station.dart';
import 'package:the_paragliding_app/data/models/weather_station_source.dart';
import 'package:the_paragliding_app/data/models/wind_data.dart';
import 'package:the_paragliding_app/services/weather_providers/weather_station_provider.dart';
import 'package:the_paragliding_app/services/weather_station_service.dart';

/// A push-based provider's readings must survive as the result of
/// [WeatherStationService.getStationsInBounds].
///
/// WU PWS returns its cache answer from `fetchStations` immediately and delivers
/// the readings later through `onStationsUpdated`. `getStationsInBounds` used to
/// rebuild its return value purely from the `fetchStations` returns, discarding
/// every pushed reading - so the screen's terminal assignment replaced the wind
/// it had just been handed with the empty cache answer, and the markers hung on
/// "wind loading..." until the map was panned.
///
/// Seen live 2026-09-12 near Jenbach: `WU_PWS_READING_OK` for 9 of 10 stations,
/// the terminal push carrying 9 with wind, and then
/// `WU_PWS_WEATHER_EXTRACTED total_stations=9 stations_with_data=0` as the last
/// line of the log.
///
/// These tests drive the service itself with fake providers rather than
/// recomputing the selection, so the wiring is what is under test.
void main() {
  final bounds = LatLngBounds(
    const LatLng(47.0, 11.0),
    const LatLng(48.0, 12.5),
  );

  WeatherStation station(
    String id,
    double lat,
    double lon, {
    double? speed,
    WeatherStationSource source = WeatherStationSource.weatherUndergroundPws,
  }) =>
      WeatherStation(
        id: id,
        source: source,
        name: 'Station $id',
        latitude: lat,
        longitude: lon,
        windData: speed == null
            ? null
            : WindData(
                speedKmh: speed,
                directionDegrees: 270,
                gustsKmh: speed + 6,
                timestamp: DateTime.utc(2026, 9, 12, 14),
              ),
      );

  // Distinct positions on purpose: the service deduplicates stations within
  // 150 m, so co-located fakes would collapse into one and hide the wiring bug.
  WeatherStation a({double? speed}) => station('A', 47.30, 11.10, speed: speed);
  WeatherStation b({double? speed}) => station('B', 47.40, 11.20, speed: speed);

  group('a push-based provider', () {
    test('returns the pushed reading, not its empty cache answer', () async {
      final provider = _PushProvider(
        cacheAnswer: [a()],
        pushes: [_Push([a(speed: 19)], passComplete: true)],
      );

      final stations = await WeatherStationService.instance
          .getStationsInBounds(bounds, providersForTest: [provider]);

      expect(stations, hasLength(1));
      expect(stations.single.id, 'A');
      expect(stations.single.windData, isNotNull);
      expect(stations.single.windData!.speedKmh, 19);
    });

    test('merges intermediate deltas and lets the terminal push set the list',
        () async {
      final provider = _PushProvider(
        cacheAnswer: [a(), b()],
        pushes: [
          _Push([a(speed: 12)], passComplete: false),
          _Push([a(speed: 12), b(speed: 25)], passComplete: true),
        ],
      );

      final stations = await WeatherStationService.instance
          .getStationsInBounds(bounds, providersForTest: [provider]);

      final byId = {for (final s in stations) s.id: s};
      expect(byId.keys, containsAll(['A', 'B']));
      expect(byId['A']!.windData!.speedKmh, 12);
      expect(byId['B']!.windData!.speedKmh, 25);
    });

    test('drops a station the terminal push no longer lists', () async {
      final provider = _PushProvider(
        cacheAnswer: [a(), b()],
        pushes: [_Push([a(speed: 12)], passComplete: true)],
      );

      final stations = await WeatherStationService.instance
          .getStationsInBounds(bounds, providersForTest: [provider]);

      expect(stations, hasLength(1));
      expect(stations.single.id, 'A');
    });

    test('falls back to the cache answer when only deltas arrived', () async {
      // A pass superseded mid-flight can push a delta batch and never send its
      // terminal list. Trusting that partial accumulator would drop every
      // station the delta did not mention - one station instead of two.
      final provider = _PushProvider(
        cacheAnswer: [a(), b()],
        pushes: [_Push([a(speed: 12)], passComplete: false)],
      );

      final stations = await WeatherStationService.instance
          .getStationsInBounds(bounds, providersForTest: [provider]);

      expect(stations, hasLength(2));
      expect(
        stations.map((s) => s.id).toSet(),
        {'A', 'B'},
        reason: 'a delta-only pass must not shrink the result to the delta',
      );
    });
  });

  group('a blocking provider', () {
    test('still returns its own list', () async {
      final provider = _BlockingProvider([
        station('M',
            47.50, 11.50,
            speed: 30, source: WeatherStationSource.bom),
      ]);

      final stations = await WeatherStationService.instance
          .getStationsInBounds(bounds, providersForTest: [provider]);

      expect(stations, hasLength(1));
      expect(stations.single.id, 'M');
      expect(stations.single.windData!.speedKmh, 30);
    });

    test('is combined with a push-based provider in one fetch', () async {
      final push = _PushProvider(
        cacheAnswer: [a()],
        pushes: [_Push([a(speed: 19)], passComplete: true)],
      );
      final blocking = _BlockingProvider([
        station('M',
            47.50, 11.50,
            speed: 30, source: WeatherStationSource.bom),
      ]);

      final stations = await WeatherStationService.instance
          .getStationsInBounds(
            bounds,
            providersForTest: [push, blocking],
          );

      final byId = {for (final s in stations) s.id: s};
      expect(byId.keys, containsAll(['A', 'M']));
      expect(byId['A']!.windData!.speedKmh, 19);
      expect(byId['M']!.windData!.speedKmh, 30);
    });
  });

  test('progress pushes are still forwarded to the caller', () async {
    final provider = _PushProvider(
      cacheAnswer: [a()],
      pushes: [
        _Push([a(speed: 12)], passComplete: false),
        _Push([a(speed: 19)], passComplete: true),
      ],
    );
    final seen = <String>[];

    await WeatherStationService.instance.getStationsInBounds(
      bounds,
      providersForTest: [provider],
      onProgress: ({
        required source,
        required displayName,
        required success,
        required stationCount,
        required stations,
        bool passComplete = false,
      }) {
        seen.add('${source.name}:${stations.length}:$passComplete');
      },
    );

    expect(seen, contains('weatherUndergroundPws:1:false'));
    expect(seen, contains('weatherUndergroundPws:1:true'));
  });
}

/// One replayed progressive update: the stations, and whether it is the
/// provider's terminal full list.
class _Push {
  const _Push(this.stations, {required this.passComplete});

  final List<WeatherStation> stations;
  final bool passComplete;
}

/// The WU PWS shape: push updates from inside `fetchStations`, then return the
/// cache answer the provider started from.
class _PushProvider implements WeatherStationProvider {
  _PushProvider({required this.cacheAnswer, required this.pushes});

  final List<WeatherStation> cacheAnswer;
  final List<_Push> pushes;

  @override
  WeatherStationSource get source => WeatherStationSource.weatherUndergroundPws;

  @override
  bool get pushesProgressively => true;

  @override
  String get displayName => 'Fake push provider';

  @override
  String get description => 'test';

  @override
  String get attributionName => 'test';

  @override
  String get attributionUrl => 'https://example.test/';

  @override
  Duration get cacheTTL => const Duration(minutes: 10);

  @override
  bool get requiresApiKey => false;

  @override
  Future<bool> isConfigured() async => true;

  @override
  Future<void> warmCache() async {}

  @override
  void clearCache() {}

  @override
  Map<String, dynamic> getCacheStats() => const <String, dynamic>{};

  @override
  Future<List<WeatherStation>> fetchStations(
    LatLngBounds bounds, {
    Function()? onApiCallStart,
    void Function(List<WeatherStation> stations, {bool passComplete})?
        onStationsUpdated,
  }) async {
    onApiCallStart?.call();
    for (final push in pushes) {
      onStationsUpdated?.call(push.stations, passComplete: push.passComplete);
    }
    return cacheAnswer;
  }

  @override
  Future<Map<String, WindData>> fetchWeatherData(
    List<WeatherStation> stations,
  ) async =>
      {
        for (final s in stations)
          if (s.windData != null) s.key: s.windData!,
      };
}

/// A provider whose return value is its result.
class _BlockingProvider implements WeatherStationProvider {
  _BlockingProvider(this.result);

  final List<WeatherStation> result;

  @override
  WeatherStationSource get source => WeatherStationSource.bom;

  @override
  bool get pushesProgressively => false;

  @override
  String get displayName => 'Fake blocking provider';

  @override
  String get description => 'test';

  @override
  String get attributionName => 'test';

  @override
  String get attributionUrl => 'https://example.test/';

  @override
  Duration get cacheTTL => const Duration(minutes: 10);

  @override
  bool get requiresApiKey => false;

  @override
  Future<bool> isConfigured() async => true;

  @override
  Future<void> warmCache() async {}

  @override
  void clearCache() {}

  @override
  Map<String, dynamic> getCacheStats() => const <String, dynamic>{};

  @override
  Future<List<WeatherStation>> fetchStations(
    LatLngBounds bounds, {
    Function()? onApiCallStart,
    void Function(List<WeatherStation> stations, {bool passComplete})?
        onStationsUpdated,
  }) async =>
      result;

  @override
  Future<Map<String, WindData>> fetchWeatherData(
    List<WeatherStation> stations,
  ) async =>
      {
        for (final s in stations)
          if (s.windData != null) s.key: s.windData!,
      };
}

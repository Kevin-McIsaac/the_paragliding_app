import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:the_paragliding_app/data/models/wind_data.dart';
import 'package:the_paragliding_app/data/models/wind_forecast.dart';
import 'package:the_paragliding_app/services/weather_forecast_cache.dart';
import 'package:the_paragliding_app/services/weather_service.dart';

/// The hourly block Open-Meteo returns for one location, covering the times
/// every test requests.
String forecastJson() {
  final start = DateTime(2026, 11, 16);
  final times = List.generate(168, (i) => start.add(Duration(hours: i)).toIso8601String());
  return jsonEncode({
    'hourly': {
      'time': times,
      'wind_speed_10m': List.filled(168, 12.0),
      'wind_direction_10m': List.filled(168, 200.0),
      'wind_gusts_10m': List.filled(168, 20.0),
      'precipitation': List.filled(168, 0.0),
    },
  });
}

/// A batch response: one hourly object per requested location.
String batchJson(int locations) {
  final hourly = jsonDecode(forecastJson());
  return jsonEncode(List.filled(locations, hourly));
}

WindForecast forecast({DateTime? fetchedAt}) {
  final start = DateTime(2026, 11, 16);
  return WindForecast(
    latitude: 47.0,
    longitude: 11.0,
    speedsKmh: List.filled(168, 12.0),
    directionsDegs: List.filled(168, 200.0),
    gustsKmh: List.filled(168, 20.0),
    precipitationMm: List.filled(168, 0.0),
    timestamps: List.generate(168, (i) => start.add(Duration(hours: i))),
    fetchedAt: fetchedAt ?? DateTime.now(),
  );
}

void main() {
  late WeatherService service;
  late Directory cacheDirectory;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    cacheDirectory = await Directory.systemTemp.createTemp('weather_service_test');
    service = WeatherService.instance;
    service.resetForTests();
    // Never touch the developer's real weather_forecasts.json.
    service.debugDiskCache = WeatherForecastCache(directoryProvider: () async => cacheDirectory);
    service.retryBaseDelay = Duration.zero;
  });

  tearDown(() async {
    service.resetForTests();
    await cacheDirectory.delete(recursive: true);
  });

  test('retries a 429 and returns wind data', () async {
    var requests = 0;
    service.debugHttpClient = MockClient((request) async {
      requests++;
      if (requests == 1) {
        return http.Response(
          '{"reason":"Too many concurrent requests","error":true}',
          429,
          headers: {'retry-after': '0'},
        );
      }
      return http.Response(forecastJson(), 200);
    });

    final wind = await service.getWindData(47.0, 11.0, DateTime(2026, 11, 16, 12));

    expect(requests, 2);
    expect(wind, isA<WindData>());
  });

  test('does not wait when Retry-After exceeds the cap', () async {
    service.maxRetryAfter = Duration.zero;
    var requests = 0;
    service.debugHttpClient = MockClient((request) async {
      requests++;
      return http.Response(
        '{"reason":"Minutely API request limit exceeded."}',
        429,
        headers: {'retry-after': '42'},
      );
    });

    final wind = await service.getWindData(47.0, 11.0, DateTime(2026, 11, 16, 12));

    expect(requests, 1);
    expect(wind, isNull);
  });

  test('honours Retry-After before the second attempt', () async {
    var requests = 0;
    service.debugHttpClient = MockClient((request) async {
      requests++;
      if (requests == 1) {
        return http.Response('slow down', 429, headers: {'retry-after': '1'});
      }
      return http.Response(forecastJson(), 200);
    });

    final stopwatch = Stopwatch()..start();
    await service.getWindData(47.0, 11.0, DateTime(2026, 11, 16, 12));
    stopwatch.stop();

    expect(requests, 2);
    expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(900));
  });

  test('caps concurrent requests', () async {
    service.maxConcurrentRequests = 2;
    var inFlight = 0;
    var peak = 0;
    service.debugHttpClient = MockClient((request) async {
      inFlight++;
      if (inFlight > peak) peak = inFlight;
      await Future.delayed(const Duration(milliseconds: 20));
      inFlight--;
      return http.Response(forecastJson(), 200);
    });

    final results = await Future.wait([
      for (var i = 0; i < 6; i++)
        service.getWindData(46.0 + i * 0.1, 10.0, DateTime(2026, 11, 16, 12)),
    ]);

    expect(peak, lessThanOrEqualTo(2));
    expect(results.whereType<WindData>().length, 6);
  });

  test('a ten-site batch is one HTTP request', () async {
    var requests = 0;
    service.debugHttpClient = MockClient((request) async {
      requests++;
      // The comma-separated latitude parameter is how the batch is sent.
      expect(request.url.queryParameters['latitude']!.split(',').length, 10);
      return http.Response(batchJson(10), 200);
    });

    final locations = [
      for (var i = 0; i < 10; i++) LatLng(47.0 + i * 0.05, 11.0),
    ];
    final data = await service.getWindDataBatch(locations, DateTime(2026, 11, 16, 12));

    expect(requests, 1);
    expect(data.length, 10);
  });

  test('restores fresh forecasts from disk with no HTTP request', () async {
    final directory = await Directory.systemTemp.createTemp('weather_cache_restore');
    addTearDown(() => directory.delete(recursive: true));

    service.debugDiskCache = WeatherForecastCache(directoryProvider: () async => directory);
    service.debugHttpClient = MockClient((request) async => http.Response(forecastJson(), 200));
    await service.getWindData(47.0, 11.0, DateTime(2026, 11, 16, 12));
    await service.flushDiskSave();

    // A fresh launch: memory is gone, the file is not.
    service.resetForTests();
    service.debugDiskCache = WeatherForecastCache(directoryProvider: () async => directory);
    var requests = 0;
    service.debugHttpClient = MockClient((request) async {
      requests++;
      return http.Response('should not be called', 500);
    });

    final cached = await service.getCachedForecast(47.0, 11.0);
    final wind = await service.getWindData(47.0, 11.0, DateTime(2026, 11, 16, 12));

    expect(cached, isNotNull);
    expect(wind, isNotNull);
    expect(requests, 0);
  });

  group('WeatherForecastCache', () {
    late Directory directory;
    late WeatherForecastCache cache;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('weather_cache');
      cache = WeatherForecastCache(directoryProvider: () async => directory);
    });

    tearDown(() => directory.delete(recursive: true));

    test('round-trips a forecast', () async {
      final original = forecast(fetchedAt: DateTime.now());
      await cache.save({'k': original});

      final loaded = await cache.load();

      expect(loaded.keys, ['k']);
      expect(loaded['k']!.speedsKmh, original.speedsKmh);
      expect(loaded['k']!.timestamps.length, original.timestamps.length);
    });

    test('drops entries older than the TTL', () async {
      await cache.save({'old': forecast(fetchedAt: DateTime.now().subtract(const Duration(hours: 2)))});

      expect(await cache.load(), isEmpty);
    });

    test('returns an empty map for a corrupt file', () async {
      await File('${directory.path}/${WeatherForecastCache.fileName}').writeAsString('not json');

      expect(await cache.load(), isEmpty);
    });
  });
}

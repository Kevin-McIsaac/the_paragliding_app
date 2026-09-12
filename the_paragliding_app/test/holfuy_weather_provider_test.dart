import 'dart:convert';
import 'dart:io';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:the_paragliding_app/data/models/holfuy_reading.dart';
import 'package:the_paragliding_app/data/models/holfuy_station_catalogue.dart';
import 'package:the_paragliding_app/data/models/weather_station_source.dart';
import 'package:the_paragliding_app/services/holfuy_stations_download_service.dart';
import 'package:the_paragliding_app/services/weather_providers/holfuy_weather_provider.dart';
import 'package:the_paragliding_app/services/weather_providers/weather_station_provider_registry.dart';
import 'package:the_paragliding_app/services/weather_station_service.dart';

/// Excerpts of the live Holfuy widget page (station 142, verified 2026-09-12).
/// Only the tokens the parser reads are kept; the values are what the real page
/// served, including the `km\/h` escaping inside the page's own JSON.
const _kmhPage = r'''
var units =JSON.parse('{"speed":"km\/h","temp":"C","height":"m"}');
<span id="j_speed">19</span>
<span id="j_gust" title="wind gust" class="act_data_gust">25</span>
var owind=[[13,248],[15,266],[20,281],[19,275]];
<span id="act_date"><b>113</b> sec. ago</span>
''';

const _msPage = r'''
var units =JSON.parse('{"speed":"m\/s","temp":"C","height":"m"}');
<span id="j_speed">3.6</span>
<span id="j_gust" title="wind gust" class="act_data_gust">6.1</span>
var owind=[[4.2,266],[5.6,281],[5.3,275],[6.4,266]];
<span id="act_date"><b>36</b> sec. ago</span>
''';

const _offlinePage = r'''
var units =JSON.parse('{"speed":"km\/h","temp":"C","height":"m"}');
<span id="j_speed">-</span>
var owind=[[0,0]];
<span id="act_date"><b>9</b> sec. ago</span>
''';

/// The real offline widget page (station 156, FlyStanwell, AU, 2026-09-12).
/// Solar station, flat battery: no readings at all, but the page says why.
const _offlineBatteryPage = r'''
<html>
<title>Holfuy Weather Widget - FlyStanwell</title>
<script>
var stattr = {"id":156,"short_name":"Stwl","country":"AU","style":"W"};
var units =JSON.parse('{"speed":"km\/h","temp":"C","height":"m"}');
</script>
<body>
<div style="background: rgba(255,255,255,0.5); font-size: 0.8em;">
<b>Battery is empty!</b> Waiting for Sun... 
<br>Last update:2026-Sep-10 13:55:53 AEST						<br> Thanks for your understanding!
</div>
</body>
</html>
''';

const _noWindHistoryPage = r'''
var units =JSON.parse('{"speed":"km\/h","temp":"C","height":"m"}');
<span id="j_speed">12</span>
<span id="j_gust">20</span>
<span id="act_date"><b>5</b> sec. ago</span>
''';

String _catalogueJson() => jsonEncode({
      'generated_utc': '2026-09-12T00:18:24Z',
      'source': 'holfuy',
      'attribution': 'Holfuy',
      'attribution_url': 'https://holfuy.com/',
      'licence': 'used with permission',
      'stations': [
        {
          'id': '142',
          'name': 'THPK Ersfjord',
          'lat': 69.70017,
          'lon': 18.63842,
          'alt': 130,
          'country': 'NO',
          'url': 'https://holfuy.com/en/weather/142',
        },
        {
          'id': '351',
          'name': 'Elorrio-Udalaitz',
          'lat': 43.099772,
          'lon': -2.533773,
          'alt': 700,
          'country': 'ES',
          'url': 'https://holfuy.com/en/weather/351',
        },
        {
          'id': '1222',
          'name': 'Pointy Knob',
          'lat': 39.002045,
          'lon': -79.467939,
          'country': 'US',
          'url': 'https://holfuy.com/en/weather/1222',
        },
      ],
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final download = HolfuyStationsDownloadService.instance;
  // Resolved inside setUp, not here: the provider builds an http.Client on
  // construction, and flutter_test's HTTP overrides only exist inside a test
  // zone.
  late HolfuyWeatherProvider provider;

  late Directory tempDir;

  final world = LatLngBounds(const LatLng(-90, -180), const LatLng(90, 180));
  final norway = LatLngBounds(const LatLng(58, 4), const LatLng(72, 32));

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    provider = HolfuyWeatherProvider.instance;
    provider.clearCacheForTest();

    tempDir = Directory.systemTemp.createTempSync('holfuy_provider_test');
    download.directoryOverrideForTest = tempDir.path;
    download.bundledLoaderForTest = () async => _catalogueJson();
  });

  tearDown(() {
    download.directoryOverrideForTest = null;
    download.bundledLoaderForTest = null;
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  // --- reading parse ---------------------------------------------------------

  group('parseReadingHtml', () {
    test('reads km/h, and degrees from the wind history', () {
      final now = DateTime.utc(2026, 9, 12, 12, 0, 0);

      final wind = HolfuyWeatherProvider.parseReadingHtml(_kmhPage, now: now)!;

      expect(wind.speedKmh, 19.0);
      expect(wind.gustsKmh, 25.0);
      // The last owind pair, not the cardinal "W" the page also renders.
      expect(wind.directionDegrees, 275.0);
      expect(wind.timestamp, now.subtract(const Duration(seconds: 113)));
    });

    test('refuses an m/s page instead of reporting a 3.6x error', () {
      // If su=km/h is ever not honoured the numbers are m/s. 3.6 would look
      // like a plausible wind speed, so this must fail loudly, not convert.
      expect(HolfuyWeatherProvider.parseReadingHtml(_msPage), isNull);
    });

    test('an offline station is no reading, not a zero reading', () {
      expect(HolfuyWeatherProvider.parseReadingHtml(_offlinePage), isNull);
    });

    test('no direction means no reading, rather than a guessed one', () {
      expect(
        HolfuyWeatherProvider.parseReadingHtml(_noWindHistoryPage),
        isNull,
      );
    });

    test('a flat-battery page reports the station\'s own reason', () {
      final reading = HolfuyWeatherProvider.parseReading(_offlineBatteryPage);

      expect(reading.status, HolfuyReadingStatus.offline);
      expect(reading.hasWind, isFalse);
      expect(reading.offlineReason, contains('Battery is empty!'));
      expect(reading.offlineReason, contains('Waiting for Sun'));
      expect(reading.lastUpdate, '2026-Sep-10 13:55:53 AEST');
    });

    test('a page with no reading and no explanation is a failure, not offline', () {
      // A contract mismatch (or a truncated page) must not be dressed up as
      // "the station is offline" - that is a wrong statement about the world.
      final reading = HolfuyWeatherProvider.parseReading(_noWindHistoryPage);

      expect(reading.status, HolfuyReadingStatus.unavailable);
      expect(reading.offlineReason, isNull);
    });

    test('a good page reads as ok, and an m/s page as unavailable', () {
      expect(
        HolfuyWeatherProvider.parseReading(_kmhPage).status,
        HolfuyReadingStatus.ok,
      );
      expect(
        HolfuyWeatherProvider.parseReading(_msPage).status,
        HolfuyReadingStatus.unavailable,
      );
    });
  });

  // --- the map layer is free -------------------------------------------------

  group('positions', () {
    test('fetchStations filters to bounds and issues no HTTP request', () async {
      var requests = 0;
      provider.httpClientForTest = MockClient((request) async {
        requests++;
        return http.Response('should not be called', 500);
      });

      final stations = await provider.fetchStations(norway);

      expect(stations.map((s) => s.id), ['142']);
      expect(stations.single.source, WeatherStationSource.holfuy);
      expect(stations.single.observationType, 'Holfuy launch station');
      expect(stations.single.elevation, 130);
      expect(requests, 0);
    });

    test('fetchWeatherData never fans out to one request per station', () async {
      var requests = 0;
      provider.httpClientForTest = MockClient((request) async {
        requests++;
        return http.Response(_kmhPage, 200);
      });

      final stations = await provider.fetchStations(world);
      expect(stations, hasLength(3));

      // The service calls this with every visible station. For Holfuy it must
      // be cached-only, or one pan scrapes hundreds of stations.
      final data = await provider.fetchWeatherData(stations);
      expect(data, isEmpty);
      expect(requests, 0);

      await provider.requestReading('142');
      expect(requests, 1);

      final after = await provider.fetchWeatherData(stations);
      expect(after.keys, contains('holfuy:142'));
      expect(after, hasLength(1));
    });
  });

  // --- the on-tap path -------------------------------------------------------

  group('requestReading', () {
    test('shares one request between concurrent taps, then caches', () async {
      var requests = 0;
      provider.httpClientForTest = MockClient((request) async {
        requests++;
        return http.Response(_kmhPage, 200);
      });

      final results = await Future.wait([
        provider.requestReading('142'),
        provider.requestReading('142'),
      ]);

      expect(results.every((r) => r.wind?.speedKmh == 19.0), isTrue);
      expect(requests, 1);

      await provider.requestReading('142');
      expect(requests, 1, reason: 'still within the reading cache TTL');
    });

    test('asks for km/h explicitly and names the station', () async {
      Uri? seen;
      provider.httpClientForTest = MockClient((request) async {
        seen = request.url;
        return http.Response(_kmhPage, 200);
      });

      await provider.requestReading('351');

      expect(seen!.host, 'widget.holfuy.com');
      expect(seen!.queryParameters['station'], '351');
      expect(seen!.queryParameters['su'], 'km/h');
    });

    test('paces requests to different stations', () async {
      var requests = 0;
      provider.httpClientForTest = MockClient((request) async {
        requests++;
        return http.Response(_kmhPage, 200);
      });

      final stopwatch = Stopwatch()..start();
      await provider.requestReading('142');
      await provider.requestReading('351');
      stopwatch.stop();

      expect(requests, 2);
      expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(900));
    });

    test('an HTTP failure is unavailable, not an exception', () async {
      provider.httpClientForTest = MockClient(
        (request) async => http.Response('gateway error', 502),
      );

      final reading = await provider.requestReading('142');

      expect(reading.status, HolfuyReadingStatus.unavailable);
      expect(reading.hasWind, isFalse);
    });

    test('an offline station keeps its reason through the whole tap path', () async {
      provider.httpClientForTest = MockClient(
        (request) async => http.Response(_offlineBatteryPage, 200),
      );

      final reading = await provider.requestReading('156');

      expect(reading.status, HolfuyReadingStatus.offline);
      expect(reading.offlineReason, contains('Battery is empty!'));
      expect(reading.lastUpdate, '2026-Sep-10 13:55:53 AEST');
    });
  });

  // --- wiring ----------------------------------------------------------------

  test('is registered for the holfuy source', () {
    expect(
      WeatherStationProviderRegistry.getProvider(WeatherStationSource.holfuy),
      HolfuyWeatherProvider.instance,
    );
    expect(
      WeatherStationProviderRegistry.getAllSources(),
      contains(WeatherStationSource.holfuy),
    );
  });

  test('the filter toggle round-trips through preferences', () async {
    expect(
      await WeatherStationService.isProviderEnabled(WeatherStationSource.holfuy),
      isTrue,
    );

    await WeatherStationService.setProviderEnabled(
        WeatherStationSource.holfuy, false);

    expect(
      await WeatherStationService.isProviderEnabled(WeatherStationSource.holfuy),
      isFalse,
    );
  });

  // --- the published file, live ----------------------------------------------

  test('the published station file is still served and parseable', () async {
    // flutter_test answers every real request with a 400 unless the override is
    // lifted, which is exactly what a live check needs to opt out of.
    final overrides = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = overrides);

    final response =
        await http.get(Uri.parse(HolfuyStationsConfig.catalogUrl));

    expect(response.statusCode, 200);
    final catalogue = HolfuyStationCatalogue.parse(response.body);
    expect(catalogue.stations.length, greaterThan(1000));

    final station142 =
        catalogue.stations.firstWhere((s) => s.id == '142');
    expect(station142.name, 'THPK Ersfjord');
    expect(station142.latitude, closeTo(69.70017, 0.001));
    expect(station142.longitude, closeTo(18.63842, 0.001));
  }, tags: 'network');
}

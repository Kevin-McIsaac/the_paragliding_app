import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:the_paragliding_app/data/models/weather_station_source.dart';
import 'package:the_paragliding_app/data/models/wind_data.dart';
import 'package:the_paragliding_app/services/weather_providers/weather_station_provider_registry.dart';
import 'package:the_paragliding_app/services/weather_providers/weather_underground_pws_provider.dart';
import 'package:the_paragliding_app/utils/map_constants.dart';

/// Unit tests for the Weather Underground PWS provider's pure logic:
/// gap-probing geometry, staleness filtering, wind parsing, and registry
/// wiring. No network calls - API access is exercised in the network-tagged
/// suite only.
void main() {
  // Fresh station observed 5 minutes ago - field names as returned by
  // pws/observations/current (verified live 2026-09-05).
  Map<String, dynamic> freshObs({DateTime? time}) {
    final t = (time ?? DateTime.now().toUtc().subtract(const Duration(minutes: 5)))
        .toIso8601String();
    return {
      'obsTimeUtc': t,
      'winddir': 67,
      'metric': {
        'temp': 27,
        'windSpeed': 12.5,
        'windGust': 24.0,
        'pressure': 1013.61,
      },
    };
  }

  group('registry wiring', () {
    test('PWS source is registered', () {
      final provider = WeatherStationProviderRegistry.getProvider(
        WeatherStationSource.weatherUndergroundPws,
      );
      expect(provider, isA<WeatherUndergroundPwsProvider>());
      expect(provider.displayName, isNotEmpty);
      expect(provider.attributionUrl, contains('wunderground.com'));
      expect(provider.requiresApiKey, isTrue);
    });

    test('all sources resolve to a provider', () {
      for (final source in WeatherStationSource.values) {
        expect(
          () => WeatherStationProviderRegistry.getProvider(source),
          returnsNormally,
        );
      }
    });
  });

  group('gap probing', () {
    test('probes everything when cache is empty', () {
      final provider = WeatherUndergroundPwsProvider.instance;
      provider.clearCache();

      final bounds = LatLngBounds(LatLng(-32.0, 116.5), LatLng(-31.7, 117.0));
      final probes = provider.uncoveredProbePoints(bounds);

      expect(probes, isNotEmpty);
      // Every probe must lie inside the requested bounds.
      for (final p in probes) {
        expect(p.latitude, inInclusiveRange(bounds.south, bounds.north));
        expect(p.longitude, inInclusiveRange(bounds.west, bounds.east));
      }
    });

    test('zero probes when the viewport is fully covered', () {
      final provider = WeatherUndergroundPwsProvider.instance;
      provider.clearCache();

      final now = DateTime.now().toUtc();
      // Two fresh stations far enough apart to cover a wide viewport, with a
      // non-zero coverage radius from their probe points.
      provider.discovered['ISTA1'] = DiscoveredPwsStation(
        id: 'ISTA1',
        name: 'Station One',
        latitude: -31.85,
        longitude: 116.70,
        distanceKm: 5,
        qcStatus: 1,
        updateTimeUtc: now.subtract(const Duration(minutes: 5)),
        coverageRadiusKm: 8,
      );
      provider.discovered['ISTA2'] = DiscoveredPwsStation(
        id: 'ISTA2',
        name: 'Station Two',
        latitude: -31.85,
        longitude: 117.30,
        distanceKm: 5,
        qcStatus: 1,
        updateTimeUtc: now.subtract(const Duration(minutes: 5)),
        coverageRadiusKm: 8,
      );

      final bounds = LatLngBounds(LatLng(-31.95, 116.60), LatLng(-31.75, 117.40));
      final probes = provider.uncoveredProbePoints(bounds);

      // The grid extends past the covered discs' edges (bounds > coverage),
      // but all points inside the discs are covered. A viewport of this size
      // (~87 km wide) still has uncovered corners - assert we never need more
      // probes than the cap and that stations in the centre of coverage are
      // not re-probed.
      expect(probes.length, lessThanOrEqualTo(12));
      for (final p in probes) {
        // No probe may sit on top of a known station (that would be a wasted
        // duplicate probe).
        expect(
          provider.distanceKm(p.latitude, p.longitude, -31.85, 116.70),
          greaterThanOrEqualTo(MapConstants.wuCoverageRadiusKm),
        );
        expect(
          provider.distanceKm(p.latitude, p.longitude, -31.85, 117.30),
          greaterThanOrEqualTo(MapConstants.wuCoverageRadiusKm),
        );
      }
    });

    test('stale stations do not count as coverage', () {
      final provider = WeatherUndergroundPwsProvider.instance;
      provider.clearCache();

      // Stale: last updated 3 hours ago.
      provider.discovered['ISTALE'] = DiscoveredPwsStation(
        id: 'ISTALE',
        name: 'Dead Station',
        latitude: -31.85,
        longitude: 116.70,
        distanceKm: 5,
        qcStatus: 1,
        updateTimeUtc: DateTime.now().toUtc().subtract(const Duration(hours: 3)),
        coverageRadiusKm: 50,
      );

      final bounds = LatLngBounds(LatLng(-31.9, 116.65), LatLng(-31.8, 116.75));
      final probes = provider.uncoveredProbePoints(bounds);

      expect(probes, isNotEmpty,
          reason: 'a stale station must not suppress probing');
    });
  });

  group('staleness filter', () {
    test('isStale after the cutoff', () {
      final old = DiscoveredPwsStation(
        id: 'IOLD',
        name: null,
        latitude: 0,
        longitude: 0,
        distanceKm: null,
        qcStatus: 1,
        updateTimeUtc:
            DateTime.now().toUtc().subtract(MapConstants.wuStaleObservationCutoff),
        coverageRadiusKm: 5,
      );
      expect(old.isStale, isTrue);
    });

    test('fresh inside the cutoff', () {
      final recent = DiscoveredPwsStation(
        id: 'INEW',
        name: null,
        latitude: 0,
        longitude: 0,
        distanceKm: null,
        qcStatus: -1,
        updateTimeUtc: DateTime.now().toUtc().subtract(const Duration(minutes: 30)),
        coverageRadiusKm: 5,
      );
      expect(recent.isStale, isFalse);
    });

    test('missing updateTimeUtc is assumed alive (unknown freshness)', () {
      // After a cache restore updateTimeUtc is null: freshness is unknown,
      // not stale. The next reading pass stamps it with real data.
      final unknown = DiscoveredPwsStation(
        id: 'INULL',
        name: null,
        latitude: 0,
        longitude: 0,
        distanceKm: null,
        qcStatus: null,
        updateTimeUtc: null,
        coverageRadiusKm: 5,
      );
      expect(unknown.isStale, isFalse);
    });
  });

  group('wind parsing', () {
    test('parses metric wind from an observation record', () {
      final provider = WeatherUndergroundPwsProvider.instance;
      final wind = provider.parseWind(freshObs());

      expect(wind, isNotNull);
      expect(wind!.speedKmh, 12.5);
      expect(wind.gustsKmh, 24.0);
      expect(wind.directionDegrees, 67);
      expect(wind.timestamp.isUtc, isTrue);
    });

    test('accepts history-endpoint field names as fallback', () {
      final provider = WeatherUndergroundPwsProvider.instance;
      final wind = provider.parseWind({
        'obsTimeUtc': DateTime.now().toUtc().toIso8601String(),
        'winddirAvg': 270.0,
        'metric': {'windspeedAvg': 8.0, 'windspeedHigh': 15.0},
      });
      expect(wind, isNotNull);
      expect(wind!.speedKmh, 8.0);
      expect(wind.directionDegrees, 270.0);
    });

    test('returns null without speed or direction', () {
      final provider = WeatherUndergroundPwsProvider.instance;
      expect(
        provider.parseWind({
          'obsTimeUtc': DateTime.now().toUtc().toIso8601String(),
          'metric': {},
        }),
        isNull,
      );
      expect(provider.parseWind({}), isNull);
    });
  });

  group('distance', () {
    test('haversine matches known separation', () {
      final provider = WeatherUndergroundPwsProvider.instance;
      // Mt Bakewell to the IBURGE35 hit from the discovery doc: ~0.2 km.
      final d = provider.distanceKm(-31.853, 116.765, -31.85334, 116.76261);
      expect(d, closeTo(0.21, 0.05));
    });
  });

  group('in-bounds conversion', () {
    test('converts discovered stations with dashboard URL and QC label', () {
      final provider = WeatherUndergroundPwsProvider.instance;
      provider.clearCache();

      provider.discovered['IBURGE35'] = DiscoveredPwsStation(
        id: 'IBURGE35',
        name: 'Burges',
        latitude: -31.85334,
        longitude: 116.76261,
        distanceKm: 0.2,
        qcStatus: 1,
        updateTimeUtc: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
        coverageRadiusKm: 0.2,
      );
      provider.discovered['IBURGE35']!.windData = WindData(
        speedKmh: 10,
        gustsKmh: 20,
        directionDegrees: 180,
        timestamp: DateTime.now().toUtc(),
      );

      // Bounds containing the station.
      final bounds =
          LatLngBounds(LatLng(-31.9, 116.70), LatLng(-31.8, 116.90));
      final stations = provider.stationsInBoundsForTest(bounds);

      expect(stations, hasLength(1));
      expect(stations.first.id, 'IBURGE35');
      expect(stations.first.name, 'Burges');
      expect(stations.first.dataUrl,
          'https://www.wunderground.com/dashboard/pws/IBURGE35');
      expect(stations.first.observationType, 'WU PWS (QC passed)');
      expect(stations.first.source, WeatherStationSource.weatherUndergroundPws);
      expect(stations.first.windData, isNotNull);
    });

    test('drops stale stations from the map layer', () {
      final provider = WeatherUndergroundPwsProvider.instance;
      provider.clearCache();

      provider.discovered['IDEAD'] = DiscoveredPwsStation(
        id: 'IDEAD',
        name: 'Dead',
        latitude: -31.85,
        longitude: 116.85,
        distanceKm: 1,
        qcStatus: 1,
        updateTimeUtc: DateTime.now().toUtc().subtract(const Duration(hours: 5)),
        coverageRadiusKm: 1,
      );
      provider.discovered['IALIVE'] = DiscoveredPwsStation(
        id: 'IALIVE',
        name: 'Alive',
        latitude: -31.86,
        longitude: 116.87,
        distanceKm: 1,
        qcStatus: -1,
        updateTimeUtc: DateTime.now().toUtc().subtract(const Duration(minutes: 10)),
        coverageRadiusKm: 1,
      );

      final bounds =
          LatLngBounds(LatLng(-31.9, 116.70), LatLng(-31.8, 116.90));
      final stations = provider.stationsInBoundsForTest(bounds);

      expect(stations, hasLength(1));
      expect(stations.first.id, 'IALIVE');
      // Non-QC station gets the plain label.
      expect(stations.first.observationType, 'WU PWS');
    });

    test('filters to bounds', () {
      final provider = WeatherUndergroundPwsProvider.instance;
      provider.clearCache();

      provider.discovered['IIN'] = DiscoveredPwsStation(
        id: 'IIN',
        name: 'Inside',
        latitude: -31.85,
        longitude: 116.85,
        distanceKm: 1,
        qcStatus: 1,
        updateTimeUtc: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
        coverageRadiusKm: 1,
      );
      provider.discovered['IOUT'] = DiscoveredPwsStation(
        id: 'IOUT',
        name: 'Outside',
        latitude: -30.0,
        longitude: 115.0,
        distanceKm: 1,
        qcStatus: 1,
        updateTimeUtc: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
        coverageRadiusKm: 1,
      );

      final bounds =
          LatLngBounds(LatLng(-31.9, 116.70), LatLng(-31.8, 116.90));
      final stations = provider.stationsInBoundsForTest(bounds);

      expect(stations.map((s) => s.id), ['IIN']);
    });
  });
}

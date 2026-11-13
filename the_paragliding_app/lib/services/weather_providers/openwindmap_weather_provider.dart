import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../data/models/weather_station.dart';
import '../../data/models/weather_station_source.dart';
import '../../data/models/wind_data.dart';
import '../../utils/map_constants.dart';
import '../logging_service.dart';
import 'weather_station_provider.dart';

/// OpenWindMap weather station provider from api.openwindmap.org.
///
/// The network has no area query and no discovery endpoint. It publishes one
/// global list, so the app fetches the whole list and filters it in memory -
/// the same global-cache strategy the old Pioupiou provider used.
///
/// - Station positions are cached for 24 hours.
/// - Measurements are cached for 5 minutes. The API asks for no more than one
///   update per 60 seconds, so this cache is well inside the limit.
///
/// Wind speeds are already in km/h. A measurement is a 4-minute average before
/// `measurements.date`. The `status.state` field gates the reading: an `off`
/// station is still shown at its last known position, but without wind.
class OpenWindMapWeatherProvider implements WeatherStationProvider {
  static final OpenWindMapWeatherProvider instance =
      OpenWindMapWeatherProvider._();
  OpenWindMapWeatherProvider._();

  static const String _baseUrl = 'https://api.openwindmap.org/v1';
  static const Duration _requestTimeout = Duration(seconds: 30);
  static const String _userAgent = 'TheParaglidingApp/1.0';

  http.Client _httpClient = http.Client();

  @visibleForTesting
  set httpClientForTest(http.Client client) => _httpClient = client;

  /// Global cache entry (single entry for all stations).
  _GlobalCacheEntry? _globalCache;

  /// Pending global request to prevent duplicate API calls.
  Future<List<WeatherStation>>? _pendingGlobalRequest;

  @override
  WeatherStationSource get source => WeatherStationSource.openWindMap;

  /// This provider answers with a complete list, so its return value is its
  /// result - see [WeatherStationProvider.pushesProgressively].
  @override
  bool get pushesProgressively => false;

  @override
  String get displayName => 'OpenWindMap';

  @override
  String get description => 'Community wind stations (global)';

  @override
  String get attributionName => 'OpenWindMap Contributors';

  @override
  String get attributionUrl => 'https://openwindmap.org/';

  @override
  Duration get cacheTTL => MapConstants.openWindMapMeasurementsCacheTTL;

  @override
  bool get requiresApiKey => false;

  @override
  Future<bool> isConfigured() async => true;

  @override
  Future<List<WeatherStation>> fetchStations(
    LatLngBounds bounds, {
    Function()? onApiCallStart,
    void Function(List<WeatherStation> stations, {bool passComplete})?
        onStationsUpdated,
    LatLng? focusPoint,
    void Function(String message)? onError,
  }) async {
    try {
      // Early exit: the cached station list does not cover this view.
      if (_globalCache != null && !_globalCache!.stationListExpired) {
        if (!_boundsOverlap(bounds, _globalCache!.bounds)) {
          LoggingService.structured('OPENWINDMAP_BBOX_NO_OVERLAP', {
            'requested':
                '${bounds.south},${bounds.west},${bounds.north},${bounds.east}',
            'cached': '${_globalCache!.bounds.south},${_globalCache!.bounds.west},'
                '${_globalCache!.bounds.north},${_globalCache!.bounds.east}',
          });
          return [];
        }
      }

      if (_globalCache != null && !_globalCache!.stationListExpired) {
        // No stations in this view: do not spend a request on a refresh.
        final hasStationsInView = _globalCache!.stations.any(
          (s) => bounds.contains(LatLng(s.latitude, s.longitude)),
        );

        if (!hasStationsInView) {
          LoggingService.structured('OPENWINDMAP_NO_STATIONS_IN_VIEW', {
            'bounds':
                '${bounds.south},${bounds.west},${bounds.north},${bounds.east}',
            'cached_bbox':
                '${_globalCache!.bounds.south},${_globalCache!.bounds.west},'
                '${_globalCache!.bounds.north},${_globalCache!.bounds.east}',
            'total_cached_stations': _globalCache!.stations.length,
          });
          return [];
        }

        if (_globalCache!.measurementsExpired) {
          LoggingService.info('OpenWindMap measurements expired, refreshing');
          onApiCallStart?.call();
          await _refreshMeasurements();
        } else {
          LoggingService.structured('OPENWINDMAP_CACHE_HIT', {
            'total_stations': _globalCache!.stations.length,
            'station_list_age_min': DateTime.now()
                .difference(_globalCache!.stationListTimestamp)
                .inMinutes,
            'measurements_age_min': DateTime.now()
                .difference(_globalCache!.measurementsTimestamp)
                .inMinutes,
          });
        }

        return _filterStationsToBounds(_globalCache!.stations, bounds);
      }

      // No valid cache - join a pending request or start one.
      if (_pendingGlobalRequest != null) {
        LoggingService.info('Waiting for pending OpenWindMap global request');
        await _pendingGlobalRequest;
        if (_globalCache == null) return [];
        return _filterStationsToBounds(_globalCache!.stations, bounds);
      }

      onApiCallStart?.call();
      _pendingGlobalRequest = _fetchAllStations();
      try {
        await _pendingGlobalRequest;
        if (_globalCache == null) return [];
        return _filterStationsToBounds(_globalCache!.stations, bounds);
      } finally {
        _pendingGlobalRequest = null;
      }
    } catch (e, stackTrace) {
      LoggingService.error(
          'Failed to fetch OpenWindMap stations', e, stackTrace);
      return [];
    }
  }

  @override
  Future<void> warmCache() async {
    // A fully fresh cache needs no warm-up.
    if (_globalCache != null &&
        !_globalCache!.stationListExpired &&
        !_globalCache!.measurementsExpired) {
      return;
    }
    await fetchStations(LatLngBounds(LatLng(-90, -180), LatLng(90, 180)));
  }

  @override
  Future<Map<String, WindData>> fetchWeatherData(
    List<WeatherStation> stations,
  ) async {
    if (stations.isEmpty) return {};

    // OpenWindMap stations already have wind data embedded.
    final result = <String, WindData>{};
    for (final station in stations) {
      final wind = station.windData;
      if (wind != null) result[station.key] = wind;
    }

    LoggingService.structured('OPENWINDMAP_WEATHER_EXTRACTED', {
      'total_stations': stations.length,
      'stations_with_data': result.length,
    });

    return result;
  }

  @override
  void clearCache() {
    _globalCache = null;
    _pendingGlobalRequest = null;
    LoggingService.info('OpenWindMap global cache cleared');
  }

  /// Shift the cache timestamps back in tests, so the TTL paths run without
  /// waiting for the clock.
  @visibleForTesting
  void setCacheAgeForTest({
    Duration? stationListAge,
    Duration? measurementsAge,
  }) {
    final cache = _globalCache;
    if (cache == null) return;
    final now = DateTime.now();
    _globalCache = _GlobalCacheEntry(
      stations: cache.stations,
      stationListTimestamp: stationListAge == null
          ? cache.stationListTimestamp
          : now.subtract(stationListAge),
      measurementsTimestamp: measurementsAge == null
          ? cache.measurementsTimestamp
          : now.subtract(measurementsAge),
      bounds: cache.bounds,
    );
  }

  @override
  Map<String, dynamic> getCacheStats() {
    if (_globalCache == null) {
      return {
        'cached': false,
        'total_stations': 0,
      };
    }

    final stationAge =
        DateTime.now().difference(_globalCache!.stationListTimestamp);
    final measurementAge =
        DateTime.now().difference(_globalCache!.measurementsTimestamp);

    return {
      'cached': true,
      'total_stations': _globalCache!.stations.length,
      'stations_with_data':
          _globalCache!.stations.where((s) => s.windData != null).length,
      'station_list_age_minutes': stationAge.inMinutes,
      'measurements_age_minutes': measurementAge.inMinutes,
      'station_list_expired': _globalCache!.stationListExpired,
      'measurements_expired': _globalCache!.measurementsExpired,
    };
  }

  /// Fetch the global station list with complete metadata.
  Future<List<WeatherStation>> _fetchAllStations() async {
    try {
      final stopwatch = Stopwatch()..start();
      final url = Uri.parse('$_baseUrl/live-with-meta/all');

      LoggingService.structured('OPENWINDMAP_REQUEST_START', {
        'url': url.toString(),
        'strategy': 'fetch_all_global',
      });

      final response = await _httpClient.get(
        url,
        headers: {
          'Accept': 'application/json',
          'User-Agent': _userAgent,
        },
      ).timeout(
        _requestTimeout,
        onTimeout: () {
          stopwatch.stop();
          LoggingService.structured('OPENWINDMAP_TIMEOUT', {
            'url': url.toString(),
            'duration_ms': stopwatch.elapsedMilliseconds,
            'timeout_seconds': _requestTimeout.inSeconds,
          });
          return http.Response('{"error": "Request timeout"}', 408);
        },
      );

      stopwatch.stop();

      LoggingService.structured('OPENWINDMAP_RESPONSE_RECEIVED', {
        'status_code': response.statusCode,
        'duration_ms': stopwatch.elapsedMilliseconds,
        'content_length': response.body.length,
      });

      if (response.statusCode != 200) {
        LoggingService.structured('OPENWINDMAP_HTTP_ERROR', {
          'status_code': response.statusCode,
          'response_body': response.body.substring(
            0,
            response.body.length > 500 ? 500 : response.body.length,
          ),
          'duration_ms': stopwatch.elapsedMilliseconds,
        });
        return [];
      }

      final networkTime = stopwatch.elapsedMilliseconds;
      final parseStopwatch = Stopwatch()..start();
      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic>) {
        LoggingService.structured('OPENWINDMAP_MALFORMED_RESPONSE', {
          'body_type': decoded.runtimeType.toString(),
        });
        return [];
      }

      final dataList = decoded['data'];
      if (dataList is! List) {
        LoggingService.structured('OPENWINDMAP_MALFORMED_RESPONSE', {
          'data_type': dataList.runtimeType.toString(),
        });
        return [];
      }

      final stations = <WeatherStation>[];
      for (final stationJson in dataList) {
        if (stationJson is! Map<String, dynamic>) continue;
        try {
          final station = _parseStation(stationJson);
          if (station != null) stations.add(station);
        } catch (e) {
          LoggingService.error('Failed to parse OpenWindMap station', e);
        }
      }

      parseStopwatch.stop();

      LoggingService.performance(
        'OpenWindMap parsing',
        Duration(milliseconds: parseStopwatch.elapsedMilliseconds),
        '${stations.length} stations parsed',
      );

      final cachedBounds = _calculateBoundsFromStations(stations);
      final now = DateTime.now();
      _globalCache = _GlobalCacheEntry(
        stations: stations,
        stationListTimestamp: now,
        measurementsTimestamp: now,
        bounds: cachedBounds,
      );

      LoggingService.structured('OPENWINDMAP_STATIONS_SUCCESS', {
        'station_count': stations.length,
        'stations_with_data': stations.where((s) => s.windData != null).length,
        'network_ms': networkTime,
        'parse_ms': parseStopwatch.elapsedMilliseconds,
        'total_ms': stopwatch.elapsedMilliseconds,
      });

      return stations;
    } catch (e, stackTrace) {
      LoggingService.structured('OPENWINDMAP_REQUEST_FAILED', {
        'error_type': e.runtimeType.toString(),
        'error_message': e.toString(),
      });
      LoggingService.error(
          'Failed to fetch OpenWindMap stations', e, stackTrace);
      return [];
    }
  }

  /// Refresh measurements and keep the station-list age.
  Future<void> _refreshMeasurements() async {
    final previousStationListTimestamp = _globalCache?.stationListTimestamp;
    try {
      final stations = await _fetchAllStations();
      if (stations.isNotEmpty && _globalCache != null) {
        final refreshedBounds = _calculateBoundsFromStations(stations);
        _globalCache = _GlobalCacheEntry(
          stations: stations,
          // A measurements refresh must not make a day-old station list look
          // new.
          stationListTimestamp: previousStationListTimestamp ??
              _globalCache!.stationListTimestamp,
          measurementsTimestamp: DateTime.now(),
          bounds: refreshedBounds,
        );

        LoggingService.structured('OPENWINDMAP_MEASUREMENTS_REFRESHED', {
          'station_count': stations.length,
          'stations_with_data': stations.where((s) => s.windData != null).length,
        });
      }
    } catch (e, stackTrace) {
      LoggingService.error(
          'Failed to refresh OpenWindMap measurements', e, stackTrace);
    }
  }

  /// Parse one station object from the global response.
  WeatherStation? _parseStation(Map<String, dynamic> json) {
    try {
      final id = json['id'];
      final location = json['location'];
      final meta = json['meta'];
      final measurements = json['measurements'];
      final status = json['status'];

      if (id == null || location is! Map<String, dynamic>) {
        return null;
      }

      final latitude = location['latitude'];
      final longitude = location['longitude'];
      if (latitude is! num || longitude is! num) {
        return null;
      }

      final state = status is Map<String, dynamic> ? status['state'] : null;
      final isOnline = state == 'on';

      WindData? windData;
      if (isOnline && measurements is Map<String, dynamic>) {
        final speed = measurements['wind_speed_avg'];
        final heading = measurements['wind_heading'];
        final maxSpeed = measurements['wind_speed_max'];
        final date = measurements['date'];

        if (speed is num && heading is num) {
          windData = WindData(
            speedKmh: speed.toDouble(),
            gustsKmh: maxSpeed is num ? maxSpeed.toDouble() : null,
            directionDegrees: heading.toDouble(),
            timestamp:
                date is String ? DateTime.parse(date) : DateTime.now().toUtc(),
          );
        }
      }

      return WeatherStation(
        id: id.toString(),
        source: WeatherStationSource.openWindMap,
        name: meta is Map<String, dynamic> ? meta['name'] as String? : null,
        latitude: latitude.toDouble(),
        longitude: longitude.toDouble(),
        windData: windData,
        observationType: 'Wind Station (OpenWindMap)',
        dataUrl: 'https://www.openwindmap.org/windbird-$id',
      );
    } catch (e) {
      LoggingService.error('Error parsing OpenWindMap station', e);
      return null;
    }
  }

  /// Filter stations to those within the requested bounding box.
  List<WeatherStation> _filterStationsToBounds(
    List<WeatherStation> stations,
    LatLngBounds bounds,
  ) {
    final filtered = stations.where((station) {
      return bounds.contains(LatLng(station.latitude, station.longitude));
    }).toList();

    LoggingService.structured('OPENWINDMAP_BBOX_FILTER', {
      'total_stations': stations.length,
      'filtered_count': filtered.length,
      'bounds': '${bounds.south},${bounds.west},${bounds.north},${bounds.east}',
    });

    return filtered;
  }

  /// Calculate a bounding box from a list of stations.
  LatLngBounds _calculateBoundsFromStations(List<WeatherStation> stations) {
    if (stations.isEmpty) {
      return LatLngBounds(LatLng(0, 0), LatLng(0, 0));
    }

    double minLat = stations.first.latitude;
    double maxLat = stations.first.latitude;
    double minLon = stations.first.longitude;
    double maxLon = stations.first.longitude;

    for (final station in stations) {
      if (station.latitude < minLat) minLat = station.latitude;
      if (station.latitude > maxLat) maxLat = station.latitude;
      if (station.longitude < minLon) minLon = station.longitude;
      if (station.longitude > maxLon) maxLon = station.longitude;
    }

    return LatLngBounds(
      LatLng(minLat, minLon), // Southwest corner
      LatLng(maxLat, maxLon), // Northeast corner
    );
  }

  /// Check whether two bounding boxes overlap.
  bool _boundsOverlap(LatLngBounds a, LatLngBounds b) {
    return !(a.east < b.west ||
        a.west > b.east ||
        a.north < b.south ||
        a.south > b.north);
  }
}

/// Global cache entry with dual timestamp tracking.
class _GlobalCacheEntry {
  final List<WeatherStation> stations;
  final DateTime stationListTimestamp;
  final DateTime measurementsTimestamp;
  final LatLngBounds bounds;

  _GlobalCacheEntry({
    required this.stations,
    required this.stationListTimestamp,
    required this.measurementsTimestamp,
    required this.bounds,
  });

  bool get stationListExpired {
    return DateTime.now().difference(stationListTimestamp) >
        MapConstants.openWindMapStationListCacheTTL;
  }

  bool get measurementsExpired {
    return DateTime.now().difference(measurementsTimestamp) >
        MapConstants.openWindMapMeasurementsCacheTTL;
  }
}

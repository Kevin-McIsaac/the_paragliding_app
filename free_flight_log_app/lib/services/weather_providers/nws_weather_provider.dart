import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../data/models/weather_station.dart';
import '../../data/models/weather_station_source.dart';
import '../../data/models/wind_data.dart';
import '../../utils/map_constants.dart';
import '../logging_service.dart';
import 'weather_station_provider.dart';

/// National Weather Service (NWS) weather station provider
/// Provides real-time weather observations from api.weather.gov
///
/// IMPORTANT: This provider only works for locations within the United States.
/// International locations will return 0 stations.
///
/// Free, no API key required
class NwsWeatherProvider implements WeatherStationProvider {
  static final NwsWeatherProvider instance = NwsWeatherProvider._();
  NwsWeatherProvider._();

  static const String _baseUrl = 'https://api.weather.gov';

  /// Cache for station lists: "bbox_key" -> {stations, timestamp}
  final Map<String, _StationCacheEntry> _stationCache = {};

  /// Cache for pending requests
  final Map<String, Future<List<WeatherStation>>> _pendingStationRequests = {};

  @override
  WeatherStationSource get source => WeatherStationSource.nws;

  @override
  String get displayName => 'NWS Observations (US only)';

  @override
  String get description => 'US National Weather Service stations';

  @override
  String get attributionName => 'US National Weather Service';

  @override
  String get attributionUrl => 'https://www.weather.gov/';

  @override
  Duration get cacheTTL => MapConstants.weatherStationCacheTTL;

  @override
  bool get requiresApiKey => false;

  @override
  Future<bool> isConfigured() async {
    // NWS doesn't require configuration
    return true;
  }

  @override
  Future<List<WeatherStation>> fetchStations(LatLngBounds bounds) async {
    // Generate cache key
    final cacheKey = _getBoundsCacheKey(bounds);

    // Check cache
    final cached = _stationCache[cacheKey];
    if (cached != null && !cached.isExpired) {
      LoggingService.info('NWS station cache hit for $cacheKey (${cached.stations.length} stations)');
      return cached.stations;
    }

    // Check if request pending
    if (_pendingStationRequests.containsKey(cacheKey)) {
      LoggingService.info('Waiting for pending NWS station request: $cacheKey');
      return _pendingStationRequests[cacheKey]!;
    }

    // Create new request
    final future = _fetchStationsInBounds(bounds, cacheKey);
    _pendingStationRequests[cacheKey] = future;

    try {
      final result = await future;
      return result;
    } finally {
      _pendingStationRequests.remove(cacheKey);
    }
  }

  @override
  Future<Map<String, WindData>> fetchWeatherData(
    List<WeatherStation> stations,
  ) async {
    if (stations.isEmpty) return {};

    // NWS stations fetch latest observations individually
    final Map<String, WindData> result = {};

    // Fetch observations for stations in parallel (limit to avoid overwhelming API)
    final futures = <Future<void>>[];

    for (final station in stations) {
      futures.add(_fetchStationObservation(station).then((windData) {
        if (windData != null) {
          result[station.key] = windData;
        }
      }));
    }

    await Future.wait(futures);

    LoggingService.structured('NWS_WEATHER_EXTRACTED', {
      'total_stations': stations.length,
      'stations_with_data': result.length,
    });

    return result;
  }

  @override
  void clearCache() {
    _stationCache.clear();
    LoggingService.info('NWS station cache cleared');
  }

  @override
  Map<String, dynamic> getCacheStats() {
    final validEntries = _stationCache.values.where((e) => !e.isExpired).length;
    final totalStations = _stationCache.values
        .where((e) => !e.isExpired)
        .fold<int>(0, (sum, entry) => sum + entry.stations.length);

    return {
      'total_cache_entries': _stationCache.length,
      'valid_cache_entries': validEntries,
      'total_cached_stations': totalStations,
      'pending_requests': _pendingStationRequests.length,
    };
  }

  /// Fetch NWS stations within bounds
  Future<List<WeatherStation>> _fetchStationsInBounds(
    LatLngBounds bounds,
    String cacheKey,
  ) async {
    try {
      final stopwatch = Stopwatch()..start();

      // NWS doesn't support bbox query, so we fetch all stations and filter
      final url = Uri.parse('$_baseUrl/stations?limit=500');

      LoggingService.structured('NWS_REQUEST_START', {
        'bounds': '${bounds.south},${bounds.west},${bounds.north},${bounds.east}',
        'url': url.toString(),
        'cache_key': cacheKey,
      });

      final response = await http.get(
        url,
        headers: {
          'Accept': 'application/geo+json',
          'User-Agent': 'FreeFlightLog/1.0',
        },
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          stopwatch.stop();
          LoggingService.structured('NWS_TIMEOUT', {
            'duration_ms': stopwatch.elapsedMilliseconds,
            'timeout_seconds': 30,
          });
          return http.Response('{"error": "Request timeout"}', 408);
        },
      );

      stopwatch.stop();

      LoggingService.structured('NWS_RESPONSE_RECEIVED', {
        'status_code': response.statusCode,
        'duration_ms': stopwatch.elapsedMilliseconds,
        'content_length': response.body.length,
      });

      if (response.statusCode == 200) {
        final networkTime = stopwatch.elapsedMilliseconds;

        // Parse GeoJSON response
        final parseStopwatch = Stopwatch()..start();
        final responseData = jsonDecode(response.body) as Map<String, dynamic>;
        final features = responseData['features'] as List?;

        if (features == null) {
          LoggingService.info('NWS: No features in response');
          _stationCache[cacheKey] = _StationCacheEntry(
            stations: [],
            timestamp: DateTime.now(),
          );
          return [];
        }

        final List<WeatherStation> allStations = [];
        for (final feature in features) {
          try {
            final station = _parseNwsStation(feature as Map<String, dynamic>);
            if (station != null) {
              allStations.add(station);
            }
          } catch (e) {
            LoggingService.error('Failed to parse NWS station', e);
          }
        }

        // Filter stations within bounds
        final stationsInBounds = allStations.where((station) {
          return bounds.contains(LatLng(station.latitude, station.longitude));
        }).toList();

        parseStopwatch.stop();

        LoggingService.performance(
          'NWS parsing',
          Duration(milliseconds: parseStopwatch.elapsedMilliseconds),
          '${stationsInBounds.length} stations in bounds (${allStations.length} total)',
        );

        // Cache the filtered results
        _stationCache[cacheKey] = _StationCacheEntry(
          stations: stationsInBounds,
          timestamp: DateTime.now(),
        );

        LoggingService.structured('NWS_STATIONS_SUCCESS', {
          'station_count': stationsInBounds.length,
          'total_fetched': allStations.length,
          'network_ms': networkTime,
          'parse_ms': parseStopwatch.elapsedMilliseconds,
          'cache_key': cacheKey,
        });

        return stationsInBounds;
      } else if (response.statusCode == 408) {
        // Request timeout
        return [];
      } else {
        LoggingService.structured('NWS_HTTP_ERROR', {
          'status_code': response.statusCode,
          'response_body': response.body.substring(0, response.body.length > 500 ? 500 : response.body.length),
        });
        return [];
      }
    } catch (e, stackTrace) {
      LoggingService.structured('NWS_REQUEST_FAILED', {
        'error_type': e.runtimeType.toString(),
        'error_message': e.toString(),
        'cache_key': cacheKey,
      });
      LoggingService.error('Failed to fetch NWS stations', e, stackTrace);
      return [];
    }
  }

  /// Parse NWS GeoJSON station feature
  WeatherStation? _parseNwsStation(Map<String, dynamic> feature) {
    try {
      final properties = feature['properties'] as Map<String, dynamic>?;
      final geometry = feature['geometry'] as Map<String, dynamic>?;

      if (properties == null || geometry == null) return null;

      final stationId = properties['stationIdentifier'] as String?;
      if (stationId == null) return null;

      final coordinates = geometry['coordinates'] as List?;
      if (coordinates == null || coordinates.length < 2) return null;

      final longitude = (coordinates[0] as num).toDouble();
      final latitude = (coordinates[1] as num).toDouble();

      // Extract elevation
      double? elevation;
      final elevData = properties['elevation'] as Map<String, dynamic>?;
      if (elevData != null) {
        elevation = (elevData['value'] as num?)?.toDouble();
      }

      return WeatherStation(
        id: stationId,
        source: WeatherStationSource.nws,
        name: properties['name'] as String?,
        latitude: latitude,
        longitude: longitude,
        elevation: elevation,
        windData: null, // Fetched separately
      );
    } catch (e) {
      LoggingService.error('Error parsing NWS station', e);
      return null;
    }
  }

  /// Fetch latest observation for a station
  Future<WindData?> _fetchStationObservation(WeatherStation station) async {
    try {
      final url = Uri.parse('$_baseUrl/stations/${station.id}/observations/latest');

      final response = await http.get(
        url,
        headers: {
          'Accept': 'application/geo+json',
          'User-Agent': 'FreeFlightLog/1.0',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final properties = data['properties'] as Map<String, dynamic>?;

        if (properties == null) return null;

        // Extract wind data
        final windSpeed = properties['windSpeed'] as Map<String, dynamic>?;
        final windDirection = properties['windDirection'] as Map<String, dynamic>?;
        final windGust = properties['windGust'] as Map<String, dynamic>?;
        final timestamp = properties['timestamp'] as String?;

        if (windSpeed == null || windDirection == null || timestamp == null) {
          LoggingService.structured('NWS_OBSERVATION_MISSING_DATA', {
            'station_id': station.id,
            'has_wind_speed': windSpeed != null,
            'has_wind_direction': windDirection != null,
            'has_timestamp': timestamp != null,
          });
          return null;
        }

        final speedValue = windSpeed['value'] as num?;
        final directionValue = windDirection['value'] as num?;

        if (speedValue == null || directionValue == null) {
          LoggingService.structured('NWS_OBSERVATION_NULL_VALUES', {
            'station_id': station.id,
            'speed_value': speedValue,
            'direction_value': directionValue,
          });
          return null;
        }

        final gustValue = windGust?['value'] as num?;

        LoggingService.structured('NWS_OBSERVATION_SUCCESS', {
          'station_id': station.id,
          'speed_kmh': speedValue.toDouble(),
          'direction_deg': directionValue.toDouble(),
          'gust_kmh': gustValue?.toDouble(),
        });

        return WindData(
          speedKmh: speedValue.toDouble(),
          directionDegrees: directionValue.toDouble(),
          gustsKmh: gustValue?.toDouble(),
          timestamp: DateTime.parse(timestamp),
        );
      }

      return null;
    } catch (e) {
      LoggingService.structured('NWS_OBSERVATION_ERROR', {
        'station_id': station.id,
        'station_name': station.name,
        'error': e.toString(),
      });
      return null;
    }
  }

  /// Generate cache key from bounding box
  String _getBoundsCacheKey(LatLngBounds bounds) {
    // Round to 0.1 degrees for reasonable cache granularity
    final west = (bounds.west * 10).round() / 10;
    final south = (bounds.south * 10).round() / 10;
    final east = (bounds.east * 10).round() / 10;
    final north = (bounds.north * 10).round() / 10;

    return '$west,$south,$east,$north';
  }
}

/// Cache entry for station lists with expiration
class _StationCacheEntry {
  final List<WeatherStation> stations;
  final DateTime timestamp;

  _StationCacheEntry({
    required this.stations,
    required this.timestamp,
  });

  bool get isExpired {
    return DateTime.now().difference(timestamp) > MapConstants.stationListCacheTTL;
  }
}

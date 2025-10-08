import 'dart:convert';
import 'dart:math';
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
/// International locations will return 0 stations quickly (no timeout).
///
/// Uses bbox-containment caching strategy:
/// - Station lists cached for 24 hours (stations don't move)
/// - Observations cached for 10 minutes (update frequency varies 1-60min)
/// - Reuses cached data across zoom/pan operations
///
/// Free, no API key required
class NwsWeatherProvider implements WeatherStationProvider {
  static final NwsWeatherProvider instance = NwsWeatherProvider._();
  NwsWeatherProvider._();

  static const String _baseUrl = 'https://api.weather.gov';

  /// Cache for station lists: "bbox_key" -> {stations, bounds, timestamp}
  /// Stores bbox containing all stations from grid point lookup
  final Map<String, _StationCacheEntry> _stationCache = {};

  /// Cache for individual station observations: "station_id" -> {windData, timestamp}
  final Map<String, _ObservationCacheEntry> _observationCache = {};

  /// Pending station list requests to prevent duplicate API calls
  final Map<String, Future<List<WeatherStation>>> _pendingStationRequests = {};

  /// Pending observation requests to prevent duplicate API calls
  final Map<String, Future<WindData?>> _pendingObservationRequests = {};

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
  Duration get cacheTTL => MapConstants.nwsObservationCacheTTL;

  @override
  bool get requiresApiKey => false;

  @override
  Future<bool> isConfigured() async {
    // NWS doesn't require configuration
    return true;
  }

  @override
  Future<List<WeatherStation>> fetchStations(LatLngBounds bounds) async {
    // Generate cache key from rounded bounds
    final cacheKey = _getBoundsCacheKey(bounds);

    // Step 1: Check exact cache match
    final cached = _stationCache[cacheKey];
    if (cached != null && !cached.isExpired) {
      LoggingService.structured('NWS_CACHE_HIT', {
        'cache_key': cacheKey,
        'stations': cached.stations.length,
      });
      return cached.stations;
    }

    // Step 2: Check if any cached bbox contains requested bbox
    final containingCache = _findContainingCache(bounds);
    if (containingCache != null) {
      // Filter cached stations to requested bbox
      final filtered = containingCache.stations.where((station) {
        return bounds.contains(LatLng(station.latitude, station.longitude));
      }).toList();

      LoggingService.structured('NWS_CACHE_SUBSET', {
        'cached_total': containingCache.stations.length,
        'filtered_count': filtered.length,
        'cached_bbox': _boundsToString(containingCache.bounds),
        'requested_bbox': _boundsToString(bounds),
      });

      return filtered;
    }

    // Step 3: Check if request is already pending
    if (_pendingStationRequests.containsKey(cacheKey)) {
      LoggingService.info('Waiting for pending NWS station request: $cacheKey');
      return _pendingStationRequests[cacheKey]!;
    }

    // Step 4: Fetch from API
    final future = _fetchStationsFromGrid(bounds, cacheKey);
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

    // Fetch observations in parallel with per-station caching
    final Map<String, WindData> result = {};
    final futures = <Future<void>>[];

    for (final station in stations) {
      futures.add(_fetchStationObservation(station).then((windData) {
        if (windData != null) {
          result[station.key] = windData;
        }
      }));
    }

    await Future.wait(futures);

    LoggingService.structured('NWS_WEATHER_FETCHED', {
      'total_stations': stations.length,
      'stations_with_data': result.length,
    });

    return result;
  }

  @override
  void clearCache() {
    _stationCache.clear();
    _observationCache.clear();
    LoggingService.info('NWS cache cleared (stations and observations)');
  }

  @override
  Map<String, dynamic> getCacheStats() {
    final validStationEntries = _stationCache.values.where((e) => !e.isExpired).length;
    final totalStations = _stationCache.values
        .where((e) => !e.isExpired)
        .fold<int>(0, (sum, entry) => sum + entry.stations.length);

    final validObservationEntries = _observationCache.values.where((e) => !e.isExpired).length;

    return {
      'station_cache_entries': _stationCache.length,
      'valid_station_entries': validStationEntries,
      'total_cached_stations': totalStations,
      'observation_cache_entries': _observationCache.length,
      'valid_observation_entries': validObservationEntries,
      'pending_station_requests': _pendingStationRequests.length,
      'pending_observation_requests': _pendingObservationRequests.length,
    };
  }

  /// Fetch stations from NWS grid point lookup
  Future<List<WeatherStation>> _fetchStationsFromGrid(
    LatLngBounds requestedBounds,
    String cacheKey,
  ) async {
    try {
      // Calculate bbox center for grid point lookup
      final centerLat = (requestedBounds.north + requestedBounds.south) / 2;
      final centerLon = (requestedBounds.east + requestedBounds.west) / 2;

      LoggingService.structured('NWS_CACHE_MISS', {
        'cache_key': cacheKey,
        'center_lat': centerLat.toStringAsFixed(4),
        'center_lon': centerLon.toStringAsFixed(4),
      });

      // NWS API Step 1: Get grid stations URL from point
      final gridUrl = await _getGridStationsUrl(centerLat, centerLon);
      if (gridUrl == null) {
        // Non-US location (404 from /points endpoint)
        return [];
      }

      // NWS API Step 2: Fetch all stations for this grid (~50 stations)
      final allStations = await _fetchGridStations(gridUrl);
      if (allStations.isEmpty) {
        return [];
      }

      // Calculate bbox that contains all returned stations
      final containingBbox = _calculateContainingBbox(allStations);

      // Cache with expanded bbox
      _stationCache[cacheKey] = _StationCacheEntry(
        stations: allStations,
        bounds: containingBbox,
        timestamp: DateTime.now(),
      );

      // Filter to requested bbox
      final filtered = allStations.where((station) {
        return requestedBounds.contains(LatLng(station.latitude, station.longitude));
      }).toList();

      LoggingService.structured('NWS_GRID_FETCHED', {
        'total_stations': allStations.length,
        'in_bbox': filtered.length,
        'cached_bbox': _boundsToString(containingBbox),
        'requested_bbox': _boundsToString(requestedBounds),
      });

      return filtered;
    } catch (e, stackTrace) {
      LoggingService.error('Failed to fetch NWS stations from grid', e, stackTrace);
      return [];
    }
  }

  /// Get observationStations URL from NWS /points endpoint
  /// Returns null if location is outside US (404 response)
  Future<String?> _getGridStationsUrl(double lat, double lon) async {
    try {
      final stopwatch = Stopwatch()..start();
      final url = Uri.parse('$_baseUrl/points/${lat.toStringAsFixed(4)},${lon.toStringAsFixed(4)}');

      LoggingService.structured('NWS_POINT_REQUEST', {
        'lat': lat.toStringAsFixed(4),
        'lon': lon.toStringAsFixed(4),
      });

      final response = await http.get(
        url,
        headers: {
          'Accept': 'application/geo+json',
          'User-Agent': 'FreeFlightLog/1.0',
        },
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          LoggingService.structured('NWS_POINT_TIMEOUT', {
            'lat': lat,
            'lon': lon,
          });
          return http.Response('{"error": "Timeout"}', 408);
        },
      );

      stopwatch.stop();

      if (response.statusCode == 404) {
        // Location outside US coverage
        LoggingService.structured('NWS_NON_US_LOCATION', {
          'lat': lat,
          'lon': lon,
          'duration_ms': stopwatch.elapsedMilliseconds,
        });
        return null;
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final properties = data['properties'] as Map<String, dynamic>?;
        final gridUrl = properties?['observationStations'] as String?;

        LoggingService.structured('NWS_POINT_SUCCESS', {
          'grid_url': gridUrl,
          'duration_ms': stopwatch.elapsedMilliseconds,
        });

        return gridUrl;
      }

      LoggingService.structured('NWS_POINT_ERROR', {
        'status_code': response.statusCode,
        'response': response.body.substring(0, min(200, response.body.length)),
      });
      return null;
    } catch (e, stackTrace) {
      LoggingService.error('Failed to get NWS grid URL', e, stackTrace);
      return null;
    }
  }

  /// Fetch station list from NWS gridpoints stations endpoint
  Future<List<WeatherStation>> _fetchGridStations(String gridUrl) async {
    try {
      final stopwatch = Stopwatch()..start();
      final url = Uri.parse(gridUrl);

      LoggingService.structured('NWS_GRID_REQUEST', {
        'grid_url': gridUrl,
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
          LoggingService.structured('NWS_GRID_TIMEOUT', {
            'grid_url': gridUrl,
          });
          return http.Response('{"error": "Timeout"}', 408);
        },
      );

      stopwatch.stop();

      if (response.statusCode != 200) {
        LoggingService.structured('NWS_GRID_ERROR', {
          'status_code': response.statusCode,
          'response': response.body.substring(0, min(200, response.body.length)),
        });
        return [];
      }

      // Parse GeoJSON response
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final features = data['features'] as List?;

      if (features == null || features.isEmpty) {
        LoggingService.info('NWS: No stations in grid response');
        return [];
      }

      final List<WeatherStation> stations = [];
      for (final feature in features) {
        try {
          final station = _parseNwsStation(feature as Map<String, dynamic>);
          if (station != null) {
            stations.add(station);
          }
        } catch (e) {
          LoggingService.error('Failed to parse NWS station', e);
        }
      }

      LoggingService.structured('NWS_GRID_SUCCESS', {
        'total_stations': stations.length,
        'duration_ms': stopwatch.elapsedMilliseconds,
      });

      return stations;
    } catch (e, stackTrace) {
      LoggingService.error('Failed to fetch NWS grid stations', e, stackTrace);
      return [];
    }
  }

  /// Parse NWS GeoJSON station feature into WeatherStation
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

      // Extract elevation if available
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
        observationType: WeatherStation.inferObservationType(stationId),
      );
    } catch (e) {
      LoggingService.error('Error parsing NWS station', e);
      return null;
    }
  }

  /// Fetch observation for a single station with caching
  Future<WindData?> _fetchStationObservation(WeatherStation station) async {
    // Check observation cache (10-minute TTL)
    final cached = _observationCache[station.id];
    if (cached != null && !cached.isExpired) {
      LoggingService.structured('NWS_OBSERVATION_CACHE_HIT', {
        'station_id': station.id,
      });
      return cached.windData;
    }

    // Check if request is already pending
    if (_pendingObservationRequests.containsKey(station.id)) {
      return _pendingObservationRequests[station.id]!;
    }

    // Create new request
    final future = _fetchObservationFromApi(station.id);
    _pendingObservationRequests[station.id] = future;

    try {
      final windData = await future;

      // Cache successful fetch
      if (windData != null) {
        _observationCache[station.id] = _ObservationCacheEntry(
          windData: windData,
          timestamp: DateTime.now(),
        );
      }

      return windData;
    } finally {
      _pendingObservationRequests.remove(station.id);
    }
  }

  /// Fetch latest observation from NWS API
  Future<WindData?> _fetchObservationFromApi(String stationId) async {
    try {
      final url = Uri.parse('$_baseUrl/stations/$stationId/observations/latest');

      LoggingService.structured('NWS_OBSERVATION_REQUEST', {
        'station_id': stationId,
      });

      final response = await http.get(
        url,
        headers: {
          'Accept': 'application/geo+json',
          'User-Agent': 'FreeFlightLog/1.0',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        LoggingService.structured('NWS_OBSERVATION_ERROR', {
          'station_id': stationId,
          'status_code': response.statusCode,
        });
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final properties = data['properties'] as Map<String, dynamic>?;

      if (properties == null) {
        LoggingService.structured('NWS_OBSERVATION_NO_PROPERTIES', {
          'station_id': stationId,
        });
        return null;
      }

      // Extract wind data
      final windSpeed = properties['windSpeed'] as Map<String, dynamic>?;
      final windDirection = properties['windDirection'] as Map<String, dynamic>?;
      final windGust = properties['windGust'] as Map<String, dynamic>?;
      final timestamp = properties['timestamp'] as String?;

      if (windSpeed == null || windDirection == null || timestamp == null) {
        LoggingService.structured('NWS_OBSERVATION_MISSING_DATA', {
          'station_id': stationId,
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
          'station_id': stationId,
          'speed_value': speedValue,
          'direction_value': directionValue,
        });
        return null;
      }

      final gustValue = windGust?['value'] as num?;

      // NWS API returns wind speed already in km/h (unitCode: "wmoUnit:km_h-1")
      final speedKmh = speedValue.toDouble();
      final gustKmh = gustValue?.toDouble();

      LoggingService.structured('NWS_OBSERVATION_SUCCESS', {
        'station_id': stationId,
        'wind_kmh': speedKmh.toStringAsFixed(1),
        'dir_deg': directionValue.toDouble().toStringAsFixed(0),
        'gusts_kmh': gustKmh?.toStringAsFixed(1),
      });

      return WindData(
        speedKmh: speedKmh,
        directionDegrees: directionValue.toDouble(),
        gustsKmh: gustKmh,
        timestamp: DateTime.parse(timestamp),
      );
    } catch (e) {
      LoggingService.structured('NWS_OBSERVATION_FAILED', {
        'station_id': stationId,
        'error': e.toString(),
      });
      return null;
    }
  }

  /// Find cached entry whose bounds contain the requested bounds
  _StationCacheEntry? _findContainingCache(LatLngBounds requestedBounds) {
    for (final entry in _stationCache.values) {
      if (!entry.isExpired && _boundsContains(entry.bounds, requestedBounds)) {
        return entry;
      }
    }
    return null;
  }

  /// Check if container bounds fully contain the contained bounds
  bool _boundsContains(LatLngBounds container, LatLngBounds contained) {
    return container.north >= contained.north &&
           container.south <= contained.south &&
           container.east >= contained.east &&
           container.west <= contained.west;
  }

  /// Calculate bbox that contains all stations
  LatLngBounds _calculateContainingBbox(List<WeatherStation> stations) {
    if (stations.isEmpty) {
      return LatLngBounds(LatLng(0, 0), LatLng(0, 0));
    }

    double north = stations.first.latitude;
    double south = stations.first.latitude;
    double east = stations.first.longitude;
    double west = stations.first.longitude;

    for (final station in stations) {
      north = max(north, station.latitude);
      south = min(south, station.latitude);
      east = max(east, station.longitude);
      west = min(west, station.longitude);
    }

    return LatLngBounds(LatLng(south, west), LatLng(north, east));
  }

  /// Generate cache key from bounding box (rounded to 0.1 degrees)
  String _getBoundsCacheKey(LatLngBounds bounds) {
    final west = (bounds.west * 10).round() / 10;
    final south = (bounds.south * 10).round() / 10;
    final east = (bounds.east * 10).round() / 10;
    final north = (bounds.north * 10).round() / 10;

    return '$west,$south,$east,$north';
  }

  /// Convert bounds to string for logging
  String _boundsToString(LatLngBounds bounds) {
    return '${bounds.south.toStringAsFixed(2)},${bounds.west.toStringAsFixed(2)},'
           '${bounds.north.toStringAsFixed(2)},${bounds.east.toStringAsFixed(2)}';
  }
}

/// Cache entry for station lists with bbox and expiration
class _StationCacheEntry {
  final List<WeatherStation> stations;
  final LatLngBounds bounds; // Bbox containing all stations
  final DateTime timestamp;

  _StationCacheEntry({
    required this.stations,
    required this.bounds,
    required this.timestamp,
  });

  bool get isExpired {
    return DateTime.now().difference(timestamp) > MapConstants.nwsStationListCacheTTL;
  }
}

/// Cache entry for individual station observations with expiration
class _ObservationCacheEntry {
  final WindData windData;
  final DateTime timestamp;

  _ObservationCacheEntry({
    required this.windData,
    required this.timestamp,
  });

  bool get isExpired {
    return DateTime.now().difference(timestamp) > MapConstants.nwsObservationCacheTTL;
  }
}

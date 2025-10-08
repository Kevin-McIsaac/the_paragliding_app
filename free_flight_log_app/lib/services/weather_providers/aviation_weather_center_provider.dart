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

/// Aviation Weather Center provider from aviationweather.gov
/// Provides airport weather stations with real-time observations in METAR format
class AviationWeatherCenterProvider implements WeatherStationProvider {
  static final AviationWeatherCenterProvider instance = AviationWeatherCenterProvider._();
  AviationWeatherCenterProvider._();

  /// Conversion factor: knots to km/h
  static const double knotsToKmh = 1.852;

  /// Cache for station lists: "bbox_key" -> {stations, timestamp}
  final Map<String, _StationCacheEntry> _stationCache = {};

  /// Cache for pending station list requests to prevent duplicate API calls
  final Map<String, Future<List<WeatherStation>>> _pendingStationRequests = {};

  @override
  WeatherStationSource get source => WeatherStationSource.awcMetar;

  @override
  String get displayName => 'Aviation Weather Center';

  @override
  String get description => 'Airport weather (METAR format)';

  @override
  String get attributionName => 'Aviation Weather Center';

  @override
  String get attributionUrl => 'https://aviationweather.gov/';

  @override
  Duration get cacheTTL => MapConstants.weatherStationCacheTTL;

  @override
  bool get requiresApiKey => false;

  @override
  Future<bool> isConfigured() async {
    // Aviation Weather Center doesn't require configuration
    return true;
  }

  @override
  Future<List<WeatherStation>> fetchStations(LatLngBounds bounds) async {
    // Generate cache key from bounds
    final cacheKey = _getBoundsCacheKey(bounds);

    // Check exact cache match first
    final cached = _stationCache[cacheKey];
    if (cached != null && !cached.isExpired) {
      LoggingService.info('AWC_METAR station cache hit for $cacheKey (${cached.stations.length} stations)');
      return cached.stations;
    }

    // Check if any cached bbox contains the requested bbox
    final containingCache = _findContainingCache(bounds);
    if (containingCache != null) {
      final filteredStations = containingCache.stations.where((station) {
        return bounds.contains(LatLng(station.latitude, station.longitude));
      }).toList();

      LoggingService.structured('AWC_METAR_CACHE_SUBSET', {
        'cache_key': cacheKey,
        'cached_total': containingCache.stations.length,
        'filtered_count': filteredStations.length,
      });

      return filteredStations;
    }

    // Check if request is already pending
    if (_pendingStationRequests.containsKey(cacheKey)) {
      LoggingService.info('Waiting for pending AWC_METAR station request: $cacheKey');
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

    // Aviation Weather Center stations already have wind data embedded from the API response
    // Just extract it and map by station key
    final Map<String, WindData> result = {};
    for (final station in stations) {
      if (station.windData != null) {
        result[station.key] = station.windData!;
      }
    }

    LoggingService.structured('AWC_METAR_WEATHER_EXTRACTED', {
      'total_stations': stations.length,
      'stations_with_data': result.length,
    });

    return result;
  }

  @override
  void clearCache() {
    _stationCache.clear();
    LoggingService.info('AWC_METAR station cache cleared');
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

  /// Fetch Aviation Weather Center stations from aviationweather.gov
  /// Returns stations with embedded wind data in METAR format
  Future<List<WeatherStation>> _fetchStationsInBounds(
    LatLngBounds bounds,
    String cacheKey,
  ) async {
    try {
      final stopwatch = Stopwatch()..start();

      // Build bbox string: minLat,minLon,maxLat,maxLon
      final bbox = '${bounds.south.toStringAsFixed(2)},${bounds.west.toStringAsFixed(2)},'
                   '${bounds.north.toStringAsFixed(2)},${bounds.east.toStringAsFixed(2)}';

      // Build Aviation Weather Center METAR API URL
      final url = Uri.parse(
        'https://aviationweather.gov/api/data/metar?bbox=$bbox&format=json',
      );

      LoggingService.structured('AWC_METAR_REQUEST_START', {
        'bbox': bbox,
        'url': url.toString(),
        'cache_key': cacheKey,
      });

      // Make API request with appropriate headers
      final response = await http.get(
        url,
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'FreeFlightLog/1.0',
        },
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          stopwatch.stop();
          LoggingService.structured('AWC_METAR_TIMEOUT', {
            'bbox': bbox,
            'duration_ms': stopwatch.elapsedMilliseconds,
            'timeout_seconds': 30,
          });
          return http.Response('{"error": "Request timeout"}', 408);
        },
      );

      stopwatch.stop();

      LoggingService.structured('AWC_METAR_RESPONSE_RECEIVED', {
        'status_code': response.statusCode,
        'duration_ms': stopwatch.elapsedMilliseconds,
        'content_length': response.body.length,
        'bbox': bbox,
      });

      if (response.statusCode == 200) {
        final networkTime = stopwatch.elapsedMilliseconds;

        // Start parse timing
        final parseStopwatch = Stopwatch()..start();
        final List<dynamic> stationList = jsonDecode(response.body) as List;
        final List<WeatherStation> stations = [];

        for (final stationJson in stationList) {
          try {
            final station = _parseMetarStation(stationJson as Map<String, dynamic>);
            if (station != null) {
              stations.add(station);
            }
          } catch (e) {
            LoggingService.error('Failed to parse AWC_METAR station', e);
          }
        }

        parseStopwatch.stop();

        LoggingService.performance(
          'AWC_METAR parsing',
          Duration(milliseconds: parseStopwatch.elapsedMilliseconds),
          '${stations.length} stations parsed',
        );

        // Cache the results
        _stationCache[cacheKey] = _StationCacheEntry(
          stations: stations,
          timestamp: DateTime.now(),
        );

        LoggingService.structured('AWC_METAR_STATIONS_SUCCESS', {
          'station_count': stations.length,
          'network_ms': networkTime,
          'parse_ms': parseStopwatch.elapsedMilliseconds,
          'total_ms': stopwatch.elapsedMilliseconds,
          'cache_key': cacheKey,
        });

        return stations;
      } else if (response.statusCode == 204) {
        // 204 No Content - no stations in this region
        LoggingService.structured('AWC_METAR_NO_DATA', {
          'bbox': bbox,
          'duration_ms': stopwatch.elapsedMilliseconds,
        });

        // Cache empty result
        _stationCache[cacheKey] = _StationCacheEntry(
          stations: [],
          timestamp: DateTime.now(),
        );

        return [];
      } else if (response.statusCode == 408) {
        // Request timeout
        return [];
      } else {
        LoggingService.structured('AWC_METAR_HTTP_ERROR', {
          'status_code': response.statusCode,
          'bbox': bbox,
          'response_body': response.body.substring(0, response.body.length > 500 ? 500 : response.body.length),
          'duration_ms': stopwatch.elapsedMilliseconds,
        });
        return [];
      }
    } catch (e, stackTrace) {
      LoggingService.structured('AWC_METAR_REQUEST_FAILED', {
        'error_type': e.runtimeType.toString(),
        'error_message': e.toString(),
        'bbox': '${bounds.south.toStringAsFixed(2)},${bounds.west.toStringAsFixed(2)},${bounds.north.toStringAsFixed(2)},${bounds.east.toStringAsFixed(2)}',
        'cache_key': cacheKey,
      });
      LoggingService.error('Failed to fetch AWC_METAR stations', e, stackTrace);
      return [];
    }
  }

  /// Parse an Aviation Weather Center METAR station JSON object into a WeatherStation
  WeatherStation? _parseMetarStation(Map<String, dynamic> json) {
    try {
      final icaoId = json['icaoId'] as String?;
      final lat = json['lat'] as num?;
      final lon = json['lon'] as num?;

      if (icaoId == null || lat == null || lon == null) {
        return null;
      }

      // Extract wind data
      WindData? windData;
      final wdirRaw = json['wdir'];  // Can be int or String ("VRB" for variable)
      final wspd = json['wspd'] as int?;
      final wgst = json['wgst'] as int?;
      final reportTime = json['reportTime'] as String?;

      // Parse wind direction - can be int or "VRB" for variable winds
      int? wdir;
      if (wdirRaw is int) {
        wdir = wdirRaw;
      } else if (wdirRaw is String && wdirRaw != 'VRB') {
        // Try parsing string as int (some APIs return string numbers)
        wdir = int.tryParse(wdirRaw);
      }
      // If VRB or null, wdir remains null and wind data won't be created

      if (wdir != null && wspd != null) {
        // Convert from knots to km/h
        final windSpeedKmh = wspd * knotsToKmh;
        final windGustsKmh = wgst != null ? wgst * knotsToKmh : null;

        windData = WindData(
          speedKmh: windSpeedKmh,
          directionDegrees: wdir.toDouble(),
          gustsKmh: windGustsKmh,
          timestamp: reportTime != null
              ? DateTime.parse(reportTime)
              : DateTime.now(),
        );
      }

      return WeatherStation(
        id: icaoId,
        source: WeatherStationSource.awcMetar,
        name: json['name'] as String?,
        latitude: lat.toDouble(),
        longitude: lon.toDouble(),
        elevation: json['elev'] != null ? (json['elev'] as num).toDouble() : null,
        windData: windData,
        observationType: 'Airport (METAR)',
      );
    } catch (e) {
      LoggingService.error('Error parsing AWC_METAR station', e);
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

  /// Find a cached entry whose bounds contain the requested bounds
  _StationCacheEntry? _findContainingCache(LatLngBounds requestedBounds) {
    for (final entry in _stationCache.entries) {
      if (entry.value.isExpired) continue;

      final parts = entry.key.split(',');
      if (parts.length != 4) continue;

      try {
        final cachedWest = double.parse(parts[0]);
        final cachedSouth = double.parse(parts[1]);
        final cachedEast = double.parse(parts[2]);
        final cachedNorth = double.parse(parts[3]);

        if (cachedWest <= requestedBounds.west &&
            cachedSouth <= requestedBounds.south &&
            cachedEast >= requestedBounds.east &&
            cachedNorth >= requestedBounds.north) {
          return entry.value;
        }
      } catch (e) {
        continue;
      }
    }
    return null;
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

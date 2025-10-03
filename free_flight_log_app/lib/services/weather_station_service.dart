import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../data/models/weather_station.dart';
import '../data/models/wind_data.dart';
import '../utils/map_constants.dart';
import 'logging_service.dart';

/// Service for fetching METAR weather stations from aviationweather.gov
/// Provides actual meteorological stations with real-time wind data
class WeatherStationService {
  static final WeatherStationService instance = WeatherStationService._();
  WeatherStationService._();

  /// Conversion factor: knots to km/h
  static const double knotsToKmh = 1.852;

  /// Cache for station lists: "bbox_key" -> {stations, timestamp}
  final Map<String, _StationCacheEntry> _stationCache = {};

  /// Cache for pending station list requests to prevent duplicate API calls
  final Map<String, Future<List<WeatherStation>>> _pendingStationRequests = {};

  /// Get weather stations in a bounding box
  Future<List<WeatherStation>> getStationsInBounds(LatLngBounds bounds) async {
    // Generate cache key from bounds
    final cacheKey = _getBoundsCacheKey(bounds);

    // Check cache first
    final cached = _stationCache[cacheKey];
    if (cached != null && !cached.isExpired) {
      LoggingService.info('Weather station cache hit for $cacheKey (${cached.stations.length} stations)');
      return cached.stations;
    }

    // Check if request is already pending
    if (_pendingStationRequests.containsKey(cacheKey)) {
      LoggingService.info('Waiting for pending station request: $cacheKey');
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

  /// Fetch METAR stations from aviationweather.gov
  /// Returns stations with embedded wind data
  Future<List<WeatherStation>> _fetchStationsInBounds(
    LatLngBounds bounds,
    String cacheKey,
  ) async {
    try {
      final stopwatch = Stopwatch()..start();

      // Build bbox string: minLat,minLon,maxLat,maxLon
      final bbox = '${bounds.south.toStringAsFixed(2)},${bounds.west.toStringAsFixed(2)},'
                   '${bounds.north.toStringAsFixed(2)},${bounds.east.toStringAsFixed(2)}';

      LoggingService.structured('METAR_STATIONS_REQUEST', {
        'bbox': bbox,
      });

      // Build METAR API URL
      final url = Uri.parse(
        'https://aviationweather.gov/api/data/metar?bbox=$bbox&format=json',
      );

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
          LoggingService.error('METAR API timeout after 30s');
          throw TimeoutException('METAR API request timed out');
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> stationList = jsonDecode(response.body) as List;
        final List<WeatherStation> stations = [];

        for (final stationJson in stationList) {
          try {
            final station = _parseMetarStation(stationJson as Map<String, dynamic>);
            if (station != null) {
              stations.add(station);
            }
          } catch (e) {
            LoggingService.error('Failed to parse METAR station', e);
          }
        }

        stopwatch.stop();

        // Cache the results
        _stationCache[cacheKey] = _StationCacheEntry(
          stations: stations,
          timestamp: DateTime.now(),
        );

        LoggingService.structured('METAR_STATIONS_SUCCESS', {
          'station_count': stations.length,
          'duration_ms': stopwatch.elapsedMilliseconds,
          'cache_key': cacheKey,
        });

        return stations;
      } else {
        LoggingService.error('METAR API error: ${response.statusCode} - ${response.body}');
        return [];
      }
    } catch (e, stackTrace) {
      LoggingService.error('Failed to fetch METAR stations', e, stackTrace);
      return [];
    }
  }

  /// Parse a METAR station JSON object into a WeatherStation
  WeatherStation? _parseMetarStation(Map<String, dynamic> json) {
    try {
      final icaoId = json['icaoId'] as String?;
      final lat = json['lat'] as num?;
      final lon = json['lon'] as num?;

      if (icaoId == null || lat == null || lon == null) {
        return null; // Skip stations without required fields
      }

      // Extract wind data
      WindData? windData;
      final wdir = json['wdir'] as int?;
      final wspd = json['wspd'] as int?;
      final wgst = json['wgst'] as int?; // Wind gusts (optional)
      final reportTime = json['reportTime'] as String?;

      if (wdir != null && wspd != null) {
        // Convert wind speed from knots to km/h
        final windSpeedKmh = wspd * knotsToKmh;

        // Use actual gusts if available, otherwise estimate
        final windGustsKmh = wgst != null
            ? wgst * knotsToKmh
            : windSpeedKmh * 1.2; // Estimate gusts as 20% higher if not reported

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
        name: json['name'] as String?,
        latitude: lat.toDouble(),
        longitude: lon.toDouble(),
        elevation: json['elev'] != null ? (json['elev'] as num).toDouble() : null,
        windData: windData,
      );
    } catch (e) {
      LoggingService.error('Error parsing METAR station', e);
      return null;
    }
  }

  /// Get weather data for a list of stations
  /// Since METAR data comes with wind embedded, this just extracts it
  Future<Map<String, WindData>> getWeatherForStations(
    List<WeatherStation> stations,
    DateTime dateTime, // Ignored for METAR - always uses current data
  ) async {
    if (stations.isEmpty) return {};

    // METAR stations already have wind data embedded from the API response
    // Just extract it and map by station ID
    final Map<String, WindData> result = {};
    for (final station in stations) {
      if (station.windData != null) {
        result[station.id] = station.windData!;
      }
    }

    LoggingService.structured('METAR_WEATHER_EXTRACTED', {
      'total_stations': stations.length,
      'stations_with_data': result.length,
    });

    return result;
  }

  /// Generate cache key from bounding box (rounded to reduce cache entries)
  String _getBoundsCacheKey(LatLngBounds bounds) {
    // Round to 0.1 degrees (~10km) for reasonable cache granularity
    final west = (bounds.west * 10).round() / 10;
    final south = (bounds.south * 10).round() / 10;
    final east = (bounds.east * 10).round() / 10;
    final north = (bounds.north * 10).round() / 10;

    return '$west,$south,$east,$north';
  }

  /// Clear all caches (useful for testing or memory management)
  void clearCache() {
    _stationCache.clear();
    LoggingService.info('Weather station cache cleared');
  }

  /// Get cache statistics for debugging
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

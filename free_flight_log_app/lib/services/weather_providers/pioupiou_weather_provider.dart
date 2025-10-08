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

/// Pioupiou/OpenWindMap weather station provider from api.pioupiou.fr
/// Provides community wind stations with global coverage (~1000 stations)
///
/// Uses global caching strategy optimized for small network:
/// - Fetches ALL stations once (instead of per-bbox like METAR/NWS)
/// - Station list cached for 24 hours (locations don't change)
/// - Measurements cached for 20 minutes (wind data updates frequently)
/// - Filters cached data to bbox in-memory (instant pan/zoom)
///
/// Wind data is already in km/h (no conversion needed)
/// Measurements represent 4-minute averages before timestamp
class PioupiouWeatherProvider implements WeatherStationProvider {
  static final PioupiouWeatherProvider instance = PioupiouWeatherProvider._();
  PioupiouWeatherProvider._();

  // Note: Pioupiou API does not support HTTPS, must use HTTP
  static const String _baseUrl = 'http://api.pioupiou.fr/v1';

  /// Global cache entry (single entry for all stations)
  _GlobalCacheEntry? _globalCache;

  /// Pending global request to prevent duplicate API calls
  Future<List<WeatherStation>>? _pendingGlobalRequest;

  @override
  WeatherStationSource get source => WeatherStationSource.pioupiou;

  @override
  String get displayName => 'Pioupiou (OpenWindMap)';

  @override
  String get description => 'Community wind stations (global)';

  @override
  String get attributionName => 'OpenWindMap Contributors';

  @override
  String get attributionUrl => 'https://www.openwindmap.org/';

  @override
  Duration get cacheTTL => MapConstants.pioupiouMeasurementsCacheTTL;

  @override
  bool get requiresApiKey => false;

  @override
  Future<bool> isConfigured() async {
    // Pioupiou doesn't require configuration
    return true;
  }

  @override
  Future<List<WeatherStation>> fetchStations(LatLngBounds bounds) async {
    try {
      // Step 1: Check if station list cache is valid (<24hr)
      if (_globalCache != null && !_globalCache!.stationListExpired) {
        // Step 2: Check if measurements are stale (>20min)
        if (_globalCache!.measurementsExpired) {
          LoggingService.info('Pioupiou measurements expired, refreshing');
          await _refreshMeasurements();
        } else {
          LoggingService.structured('PIOUPIOU_CACHE_HIT', {
            'total_stations': _globalCache!.stations.length,
            'station_list_age_min': DateTime.now()
                .difference(_globalCache!.stationListTimestamp)
                .inMinutes,
            'measurements_age_min': DateTime.now()
                .difference(_globalCache!.measurementsTimestamp)
                .inMinutes,
          });
        }

        // Step 3: Filter to bbox and return
        return _filterStationsToBounds(_globalCache!.stations, bounds);
      }

      // Step 4: No valid cache - fetch everything from API
      if (_pendingGlobalRequest != null) {
        LoggingService.info('Waiting for pending Pioupiou global request');
        await _pendingGlobalRequest;
        return _filterStationsToBounds(_globalCache!.stations, bounds);
      }

      // Fetch all stations
      _pendingGlobalRequest = _fetchAllStations();
      try {
        await _pendingGlobalRequest;
        if (_globalCache == null) {
          return []; // Failed to fetch
        }
        return _filterStationsToBounds(_globalCache!.stations, bounds);
      } finally {
        _pendingGlobalRequest = null;
      }
    } catch (e, stackTrace) {
      LoggingService.error('Failed to fetch Pioupiou stations', e, stackTrace);
      return [];
    }
  }

  @override
  Future<Map<String, WindData>> fetchWeatherData(
    List<WeatherStation> stations,
  ) async {
    if (stations.isEmpty) return {};

    // Pioupiou stations already have wind data embedded (like METAR)
    // Just extract it and map by station key
    final Map<String, WindData> result = {};
    for (final station in stations) {
      if (station.windData != null) {
        result[station.key] = station.windData!;
      }
    }

    LoggingService.structured('PIOUPIOU_WEATHER_EXTRACTED', {
      'total_stations': stations.length,
      'stations_with_data': result.length,
    });

    return result;
  }

  @override
  void clearCache() {
    _globalCache = null;
    _pendingGlobalRequest = null;
    LoggingService.info('Pioupiou global cache cleared');
  }

  @override
  Map<String, dynamic> getCacheStats() {
    if (_globalCache == null) {
      return {
        'cached': false,
        'total_stations': 0,
      };
    }

    final stationAge = DateTime.now().difference(_globalCache!.stationListTimestamp);
    final measurementAge = DateTime.now().difference(_globalCache!.measurementsTimestamp);

    return {
      'cached': true,
      'total_stations': _globalCache!.stations.length,
      'stations_with_data': _globalCache!.stations.where((s) => s.windData != null).length,
      'station_list_age_minutes': stationAge.inMinutes,
      'measurements_age_minutes': measurementAge.inMinutes,
      'station_list_expired': _globalCache!.stationListExpired,
      'measurements_expired': _globalCache!.measurementsExpired,
    };
  }

  /// Fetch all stations from Pioupiou API
  /// Endpoint returns ~1000 stations globally with embedded measurements
  Future<List<WeatherStation>> _fetchAllStations() async {
    try {
      final stopwatch = Stopwatch()..start();

      final url = Uri.parse('$_baseUrl/live-with-meta/all');

      LoggingService.structured('PIOUPIOU_REQUEST_START', {
        'url': url.toString(),
        'strategy': 'fetch_all_global',
      });

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
          LoggingService.structured('PIOUPIOU_TIMEOUT', {
            'url': url.toString(),
            'duration_ms': stopwatch.elapsedMilliseconds,
            'timeout_seconds': 30,
          });
          return http.Response('{"error": "Request timeout"}', 408);
        },
      );

      stopwatch.stop();

      LoggingService.structured('PIOUPIOU_RESPONSE_RECEIVED', {
        'status_code': response.statusCode,
        'duration_ms': stopwatch.elapsedMilliseconds,
        'content_length': response.body.length,
      });

      if (response.statusCode == 200) {
        final networkTime = stopwatch.elapsedMilliseconds;

        // Parse response
        final parseStopwatch = Stopwatch()..start();
        final Map<String, dynamic> responseJson = jsonDecode(response.body);
        final List<dynamic> dataList = responseJson['data'] as List? ?? [];
        final List<WeatherStation> stations = [];

        for (final stationJson in dataList) {
          try {
            final station = _parsePioupiouStation(stationJson as Map<String, dynamic>);
            if (station != null) {
              stations.add(station);
            }
          } catch (e) {
            LoggingService.error('Failed to parse Pioupiou station', e);
          }
        }

        parseStopwatch.stop();

        LoggingService.performance(
          'Pioupiou parsing',
          Duration(milliseconds: parseStopwatch.elapsedMilliseconds),
          '${stations.length} stations parsed',
        );

        // Cache the results with current timestamps
        final now = DateTime.now();
        _globalCache = _GlobalCacheEntry(
          stations: stations,
          stationListTimestamp: now,
          measurementsTimestamp: now,
        );

        LoggingService.structured('PIOUPIOU_STATIONS_SUCCESS', {
          'station_count': stations.length,
          'stations_with_data': stations.where((s) => s.windData != null).length,
          'network_ms': networkTime,
          'parse_ms': parseStopwatch.elapsedMilliseconds,
          'total_ms': stopwatch.elapsedMilliseconds,
        });

        return stations;
      } else if (response.statusCode == 408) {
        // Request timeout
        return [];
      } else {
        LoggingService.structured('PIOUPIOU_HTTP_ERROR', {
          'status_code': response.statusCode,
          'response_body': response.body.substring(
            0,
            response.body.length > 500 ? 500 : response.body.length,
          ),
          'duration_ms': stopwatch.elapsedMilliseconds,
        });
        return [];
      }
    } catch (e, stackTrace) {
      LoggingService.structured('PIOUPIOU_REQUEST_FAILED', {
        'error_type': e.runtimeType.toString(),
        'error_message': e.toString(),
      });
      LoggingService.error('Failed to fetch Pioupiou stations', e, stackTrace);
      return [];
    }
  }

  /// Refresh measurements while keeping station list cache
  /// Re-fetches all stations but only updates measurements timestamp
  Future<void> _refreshMeasurements() async {
    try {
      final stations = await _fetchAllStations();
      if (stations.isNotEmpty && _globalCache != null) {
        // Update only measurements timestamp, keep original station list timestamp
        _globalCache = _GlobalCacheEntry(
          stations: stations,
          stationListTimestamp: _globalCache!.stationListTimestamp,
          measurementsTimestamp: DateTime.now(),
        );

        LoggingService.structured('PIOUPIOU_MEASUREMENTS_REFRESHED', {
          'station_count': stations.length,
          'stations_with_data': stations.where((s) => s.windData != null).length,
        });
      }
    } catch (e, stackTrace) {
      LoggingService.error('Failed to refresh Pioupiou measurements', e, stackTrace);
    }
  }

  /// Parse a Pioupiou station JSON object into a WeatherStation
  WeatherStation? _parsePioupiouStation(Map<String, dynamic> json) {
    try {
      final id = json['id'];
      final location = json['location'] as Map<String, dynamic>?;
      final meta = json['meta'] as Map<String, dynamic>?;
      final measurements = json['measurements'] as Map<String, dynamic>?;
      final status = json['status'] as Map<String, dynamic>?;

      if (id == null || location == null) {
        return null; // Skip stations without required fields
      }

      final latitude = location['latitude'] as num?;
      final longitude = location['longitude'] as num?;

      if (latitude == null || longitude == null) {
        return null;
      }

      // Check if station is online
      final state = status?['state'] as String?;
      final isOnline = state == 'on';

      // Extract wind data (only if station is online and measurements exist)
      WindData? windData;
      if (isOnline && measurements != null) {
        final windSpeedAvg = measurements['wind_speed_avg'] as num?;
        final windSpeedMax = measurements['wind_speed_max'] as num?;
        final windHeading = measurements['wind_heading'] as num?;
        final measurementDate = measurements['date'] as String?;

        // Wind data is valid if we have both speed and direction
        if (windSpeedAvg != null && windHeading != null) {
          // Wind speeds already in km/h - use directly
          windData = WindData(
            speedKmh: windSpeedAvg.toDouble(),
            gustsKmh: windSpeedMax?.toDouble(), // Can be null
            directionDegrees: windHeading.toDouble(),
            timestamp: measurementDate != null
                ? DateTime.parse(measurementDate)
                : DateTime.now(),
          );
        }
      }

      return WeatherStation(
        id: id.toString(),
        source: WeatherStationSource.pioupiou,
        name: meta?['name'] as String?,
        latitude: latitude.toDouble(),
        longitude: longitude.toDouble(),
        windData: windData,
        observationType: 'Wind Station (OpenWindMap)',
      );
    } catch (e) {
      LoggingService.error('Error parsing Pioupiou station', e);
      return null;
    }
  }

  /// Filter stations to those within requested bounding box
  List<WeatherStation> _filterStationsToBounds(
    List<WeatherStation> stations,
    LatLngBounds bounds,
  ) {
    final filtered = stations.where((station) {
      return bounds.contains(LatLng(station.latitude, station.longitude));
    }).toList();

    LoggingService.structured('PIOUPIOU_BBOX_FILTER', {
      'total_stations': stations.length,
      'filtered_count': filtered.length,
      'bounds': '${bounds.south},${bounds.west},${bounds.north},${bounds.east}',
    });

    return filtered;
  }
}

/// Global cache entry with dual timestamp tracking
/// Allows separate TTL for station list (24hr) and measurements (20min)
class _GlobalCacheEntry {
  final List<WeatherStation> stations;
  final DateTime stationListTimestamp;
  final DateTime measurementsTimestamp;

  _GlobalCacheEntry({
    required this.stations,
    required this.stationListTimestamp,
    required this.measurementsTimestamp,
  });

  bool get stationListExpired {
    return DateTime.now().difference(stationListTimestamp) >
        MapConstants.pioupiouStationListCacheTTL;
  }

  bool get measurementsExpired {
    return DateTime.now().difference(measurementsTimestamp) >
        MapConstants.pioupiouMeasurementsCacheTTL;
  }
}

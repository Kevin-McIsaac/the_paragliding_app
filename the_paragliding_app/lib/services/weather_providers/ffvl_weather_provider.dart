import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../data/models/weather_station.dart';
import '../../data/models/weather_station_source.dart';
import '../../data/models/wind_data.dart';
import '../../utils/map_constants.dart';
import '../logging_service.dart';
import '../api_keys.dart';
import 'weather_station_provider.dart';

/// FFVL (French Free Flight Federation) weather beacon provider from data.ffvl.fr
/// Provides weather beacons primarily in France and Europe (~650 beacons)
///
/// Uses global caching strategy optimized for small network:
/// - Fetches ALL beacons once (instead of per-bbox)
/// - Beacon list cached for 24 hours (locations don't change)
/// - Measurements cached for 5 minutes (FFVL updates every minute)
/// - Filters cached data to bbox in-memory (instant pan/zoom)
///
/// Wind data is already in km/h (no conversion needed)
class FfvlWeatherProvider implements WeatherStationProvider {
  static final FfvlWeatherProvider instance = FfvlWeatherProvider._();
  FfvlWeatherProvider._();

  // FFVL API endpoints (HTTPS with trailing slash)
  static const String _baseUrl = 'https://data.ffvl.fr/api/';

  /// Global cache entry (single entry for all beacons)
  _GlobalCacheEntry? _globalCache;

  /// Pending global request to prevent duplicate API calls
  Future<List<WeatherStation>>? _pendingGlobalRequest;

  @override
  WeatherStationSource get source => WeatherStationSource.ffvl;

  @override
  String get displayName => 'FFVL Beacons';

  @override
  String get description => 'French paragliding weather beacons';

  @override
  String get attributionName => 'FFVL (French Free Flight Federation)';

  @override
  String get attributionUrl => 'https://federation.ffvl.fr/';

  @override
  Duration get cacheTTL => MapConstants.ffvlMeasurementsCacheTTL;

  @override
  bool get requiresApiKey => true;

  @override
  Future<bool> isConfigured() async {
    // Check if API key is configured
    return ApiKeys.ffvlApiKey.isNotEmpty;
  }

  @override
  Future<List<WeatherStation>> fetchStations(LatLngBounds bounds) async {
    try {
      // Step 1: Check if beacon list cache is valid (<24hr)
      if (_globalCache != null && !_globalCache!.beaconListExpired) {
        // Step 2: Check if measurements are stale (>5min)
        if (_globalCache!.measurementsExpired) {
          LoggingService.info('FFVL measurements expired, refreshing');
          await _refreshMeasurements();
        } else {
          LoggingService.structured('FFVL_CACHE_HIT', {
            'total_beacons': _globalCache!.stations.length,
            'beacon_list_age_min': DateTime.now()
                .difference(_globalCache!.beaconListTimestamp)
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
        LoggingService.info('Waiting for pending FFVL global request');
        await _pendingGlobalRequest;
        // Check if the request succeeded and cache was populated
        if (_globalCache != null) {
          return _filterStationsToBounds(_globalCache!.stations, bounds);
        } else {
          // Request failed, return empty list
          LoggingService.warning('FFVL global request completed but cache is null');
          return [];
        }
      }

      // Fetch all beacons
      _pendingGlobalRequest = _fetchAllBeacons();
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
      LoggingService.error('Failed to fetch FFVL beacons', e, stackTrace);
      return [];
    }
  }

  @override
  Future<Map<String, WindData>> fetchWeatherData(
    List<WeatherStation> stations,
  ) async {
    if (stations.isEmpty) return {};

    // FFVL stations already have wind data embedded (like METAR and Pioupiou)
    // Just extract it and map by station key
    final Map<String, WindData> result = {};
    for (final station in stations) {
      if (station.windData != null) {
        result[station.key] = station.windData!;
      }
    }

    LoggingService.structured('FFVL_WEATHER_EXTRACTED', {
      'total_stations': stations.length,
      'stations_with_data': result.length,
    });

    return result;
  }

  @override
  void clearCache() {
    _globalCache = null;
    _pendingGlobalRequest = null;
    LoggingService.info('FFVL global cache cleared');
  }

  @override
  Map<String, dynamic> getCacheStats() {
    if (_globalCache == null) {
      return {
        'cached': false,
        'total_beacons': 0,
      };
    }

    final beaconAge = DateTime.now().difference(_globalCache!.beaconListTimestamp);
    final measurementAge = DateTime.now().difference(_globalCache!.measurementsTimestamp);

    return {
      'cached': true,
      'total_beacons': _globalCache!.stations.length,
      'beacons_with_data': _globalCache!.stations.where((s) => s.windData != null).length,
      'beacon_list_age_minutes': beaconAge.inMinutes,
      'measurements_age_minutes': measurementAge.inMinutes,
      'beacon_list_expired': _globalCache!.beaconListExpired,
      'measurements_expired': _globalCache!.measurementsExpired,
    };
  }

  /// Fetch all beacons from FFVL API
  /// Fetches both beacon list and measurements to get complete data
  Future<List<WeatherStation>> _fetchAllBeacons() async {
    try {
      final stopwatch = Stopwatch()..start();

      // Fetch beacon list first
      final apiKey = ApiKeys.ffvlApiKey;
      final beaconListUrl = Uri.parse(
        '$_baseUrl?base=balises&r=list&mode=json&key=$apiKey',
      );

      LoggingService.structured('FFVL_REQUEST_START', {
        'url': beaconListUrl.toString().replaceAll(apiKey, '***'),
        'strategy': 'fetch_all_global',
      });

      final beaconListResponse = await http.get(
        beaconListUrl,
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'TheParaglidingApp/1.0',
        },
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          stopwatch.stop();
          LoggingService.structured('FFVL_TIMEOUT', {
            'url': 'beacon_list',
            'duration_ms': stopwatch.elapsedMilliseconds,
            'timeout_seconds': 30,
          });
          return http.Response('{"error": "Request timeout"}', 408);
        },
      );

      if (beaconListResponse.statusCode != 200) {
        LoggingService.structured('FFVL_HTTP_ERROR', {
          'endpoint': 'beacon_list',
          'status_code': beaconListResponse.statusCode,
          'duration_ms': stopwatch.elapsedMilliseconds,
        });
        return [];
      }

      // Parse beacon list
      final List<dynamic> beaconList = jsonDecode(beaconListResponse.body);

      // Create a map for quick lookup
      final Map<String, Map<String, dynamic>> beaconMap = {};
      for (final beacon in beaconList) {
        final id = beacon['idBalise'] as String?;
        if (id != null) {
          beaconMap[id] = beacon as Map<String, dynamic>;
        }
      }

      // Fetch current measurements
      final measurementsUrl = Uri.parse(
        '$_baseUrl?base=balises&r=releves_meteo&key=$apiKey',
      );

      final measurementsResponse = await http.get(
        measurementsUrl,
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'TheParaglidingApp/1.0',
        },
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          LoggingService.structured('FFVL_TIMEOUT', {
            'url': 'measurements',
            'duration_ms': stopwatch.elapsedMilliseconds,
            'timeout_seconds': 30,
          });
          return http.Response('{"error": "Request timeout"}', 408);
        },
      );

      // Parse measurements response - it's a List not a Map
      Map<String, Map<String, dynamic>> measurementsMap = {};
      if (measurementsResponse.statusCode == 200) {
        final measurementsList = jsonDecode(measurementsResponse.body);
        if (measurementsList is List) {
          for (final measurement in measurementsList) {
            if (measurement is Map<String, dynamic>) {
              // Note: measurements API uses 'idbalise' (lowercase), not 'idBalise'
              final id = measurement['idbalise'] as String?;
              if (id != null) {
                measurementsMap[id] = measurement;
              }
            }
          }
        }
      }

      stopwatch.stop();

      LoggingService.structured('FFVL_MEASUREMENTS_PARSED', {
        'beacon_count': beaconMap.length,
        'measurement_count': measurementsMap.length,
      });

      // Parse and combine data
      final parseStopwatch = Stopwatch()..start();
      final List<WeatherStation> stations = [];

      for (final beaconData in beaconMap.values) {
        try {
          // Get fresh measurements if available
          Map<String, dynamic>? freshMeasurement;
          if (measurementsMap.isNotEmpty) {
            final beaconId = beaconData['idBalise'] as String;
            freshMeasurement = measurementsMap[beaconId];
          }

          final station = _parseFfvlBeacon(beaconData, freshMeasurement);
          if (station != null) {
            stations.add(station);
          }
        } catch (e) {
          LoggingService.error('Failed to parse FFVL beacon', e);
        }
      }

      parseStopwatch.stop();

      LoggingService.performance(
        'FFVL parsing',
        Duration(milliseconds: parseStopwatch.elapsedMilliseconds),
        '${stations.length} beacons parsed',
      );

      // Cache the results with current timestamps
      final now = DateTime.now();
      _globalCache = _GlobalCacheEntry(
        stations: stations,
        beaconListTimestamp: now,
        measurementsTimestamp: now,
      );

      LoggingService.structured('FFVL_BEACONS_SUCCESS', {
        'beacon_count': stations.length,
        'beacons_with_data': stations.where((s) => s.windData != null).length,
        'network_ms': stopwatch.elapsedMilliseconds - parseStopwatch.elapsedMilliseconds,
        'parse_ms': parseStopwatch.elapsedMilliseconds,
        'total_ms': stopwatch.elapsedMilliseconds,
      });

      return stations;
    } catch (e, stackTrace) {
      LoggingService.structured('FFVL_REQUEST_FAILED', {
        'error_type': e.runtimeType.toString(),
        'error_message': e.toString(),
      });
      LoggingService.error('Failed to fetch FFVL beacons', e, stackTrace);
      return [];
    }
  }

  /// Refresh measurements while keeping beacon list cache
  /// Re-fetches measurements but keeps the beacon list
  Future<void> _refreshMeasurements() async {
    try {
      // We need to re-fetch both endpoints since the beacon list API
      // also contains embedded measurements that we can use as fallback
      final beacons = await _fetchAllBeacons();
      if (beacons.isNotEmpty && _globalCache != null) {
        // Update only measurements timestamp, keep original beacon list timestamp
        _globalCache = _GlobalCacheEntry(
          stations: beacons,
          beaconListTimestamp: _globalCache!.beaconListTimestamp,
          measurementsTimestamp: DateTime.now(),
        );

        LoggingService.structured('FFVL_MEASUREMENTS_REFRESHED', {
          'beacon_count': beacons.length,
          'beacons_with_data': beacons.where((s) => s.windData != null).length,
        });
      }
    } catch (e, stackTrace) {
      LoggingService.error('Failed to refresh FFVL measurements', e, stackTrace);
    }
  }

  /// Parse a FFVL beacon JSON object into a WeatherStation
  WeatherStation? _parseFfvlBeacon(
    Map<String, dynamic> beaconData,
    Map<String, dynamic>? measurements,
  ) {
    try {
      final id = beaconData['idBalise'] as String?;
      final name = beaconData['nom'] as String?;
      final latitude = _parseDouble(beaconData['latitude']);
      final longitude = _parseDouble(beaconData['longitude']);
      final altitude = _parseDouble(beaconData['altitude']);

      if (id == null || latitude == null || longitude == null) {
        return null; // Skip beacons without required fields
      }

      // Check if beacon is in maintenance
      final inMaintenance = beaconData['en_maintenance'] == '1';
      if (inMaintenance) {
        LoggingService.debug('Skipping beacon in maintenance: $name');
        return null;
      }

      // Parse wind data - prefer fresh measurements over embedded data
      WindData? windData;

      if (measurements != null) {
        // Use fresh measurement data
        final windSpeedAvg = _parseDouble(measurements['vitesseVentMoy']);
        final windSpeedMax = _parseDouble(measurements['vitesseVentMax']);
        final windDirection = _parseDouble(measurements['directVentMoy']);
        final measurementDate = measurements['date'] as String?;

        if (windSpeedAvg != null && windDirection != null) {
          // Parse timestamp safely with fallback to current time
          DateTime timestamp = DateTime.now();
          if (measurementDate != null) {
            final parsed = DateTime.tryParse(measurementDate);
            if (parsed != null) {
              timestamp = parsed;
            } else {
              LoggingService.warning('Invalid measurement date format: $measurementDate');
            }
          }

          windData = WindData(
            speedKmh: windSpeedAvg,
            gustsKmh: windSpeedMax,
            directionDegrees: windDirection,
            timestamp: timestamp,
          );
        }
      } else {
        // Fallback to embedded data in beacon list
        final lastWindSpeed = _parseDouble(beaconData['last_wind_speed_avg']);
        final lastWindGust = _parseDouble(beaconData['last_wind_speed_max']);
        final lastWindDir = _parseDouble(beaconData['last_wind_dir']);
        final lastDataTimestamp = beaconData['last_data_timestamp'] as String?;

        // Check if data is fresh (less than 1 hour old)
        if (lastDataTimestamp != null && lastWindSpeed != null && lastWindDir != null) {
          final dataTime = DateTime.tryParse(lastDataTimestamp);
          if (dataTime != null) {
            final dataAge = DateTime.now().difference(dataTime);

            if (dataAge.inHours < 1) {
              windData = WindData(
                speedKmh: lastWindSpeed,
                gustsKmh: lastWindGust,
                directionDegrees: lastWindDir,
                timestamp: dataTime,
              );
            }
          } else {
            LoggingService.warning('Invalid beacon timestamp format: $lastDataTimestamp');
          }
        }
      }

      // Extract department/region info
      final department = beaconData['departement'] as String?;
      final stationType = beaconData['station_type'] as String? ?? 'FFVL';

      // Smart conditional display based on available metadata
      String? displayName;
      if (name != null && department != null) {
        final deptName = _getDepartmentName(department);
        if (deptName.isNotEmpty && !deptName.startsWith('Dept')) {
          // Full department name available
          displayName = '$name ($deptName)';
        } else if (department.isNotEmpty) {
          // Fallback to code if name not found
          displayName = '$name (Dept $department)';
        } else {
          // No department info
          displayName = name;
        }
      } else {
        displayName = name;
      }

      // Smart observation type based on station_type
      String observationType;
      if (stationType == 'PIOUPIOU') {
        observationType = 'FFVL/Pioupiou';
      } else if (stationType == 'OPENWINDMAP') {
        observationType = 'FFVL/OpenWindMap';
      } else if (stationType == 'FFVL') {
        observationType = 'FFVL';
      } else {
        observationType = 'FFVL ($stationType)';
      }

      // Extract URL from beacon data (use main beacon page)
      final beaconUrl = beaconData['url'] as String?;

      return WeatherStation(
        id: 'ffvl_$id',
        source: WeatherStationSource.ffvl,
        name: displayName,
        latitude: latitude,
        longitude: longitude,
        elevation: altitude,
        windData: windData,
        observationType: observationType,
        dataUrl: beaconUrl ?? 'https://www.balisemeteo.com/balise.php?idBalise=$id',
      );
    } catch (e) {
      LoggingService.error('Error parsing FFVL beacon', e);
      return null;
    }
  }

  /// Complete mapping of French department codes to full names
  static const Map<String, String> _frenchDepartments = {
    '01': 'Ain',
    '02': 'Aisne',
    '03': 'Allier',
    '04': 'Alpes-de-Haute-Provence',
    '05': 'Hautes-Alpes',
    '06': 'Alpes-Maritimes',
    '07': 'Ardèche',
    '08': 'Ardennes',
    '09': 'Ariège',
    '10': 'Aube',
    '11': 'Aude',
    '12': 'Aveyron',
    '13': 'Bouches-du-Rhône',
    '14': 'Calvados',
    '15': 'Cantal',
    '16': 'Charente',
    '17': 'Charente-Maritime',
    '18': 'Cher',
    '19': 'Corrèze',
    '2A': 'Corse-du-Sud',
    '2B': 'Haute-Corse',
    '21': 'Côte-d\'Or',
    '22': 'Côtes-d\'Armor',
    '23': 'Creuse',
    '24': 'Dordogne',
    '25': 'Doubs',
    '26': 'Drôme',
    '27': 'Eure',
    '28': 'Eure-et-Loir',
    '29': 'Finistère',
    '30': 'Gard',
    '31': 'Haute-Garonne',
    '32': 'Gers',
    '33': 'Gironde',
    '34': 'Hérault',
    '35': 'Ille-et-Vilaine',
    '36': 'Indre',
    '37': 'Indre-et-Loire',
    '38': 'Isère',
    '39': 'Jura',
    '40': 'Landes',
    '41': 'Loir-et-Cher',
    '42': 'Loire',
    '43': 'Haute-Loire',
    '44': 'Loire-Atlantique',
    '45': 'Loiret',
    '46': 'Lot',
    '47': 'Lot-et-Garonne',
    '48': 'Lozère',
    '49': 'Maine-et-Loire',
    '50': 'Manche',
    '51': 'Marne',
    '52': 'Haute-Marne',
    '53': 'Mayenne',
    '54': 'Meurthe-et-Moselle',
    '55': 'Meuse',
    '56': 'Morbihan',
    '57': 'Moselle',
    '58': 'Nièvre',
    '59': 'Nord',
    '60': 'Oise',
    '61': 'Orne',
    '62': 'Pas-de-Calais',
    '63': 'Puy-de-Dôme',
    '64': 'Pyrénées-Atlantiques',
    '65': 'Hautes-Pyrénées',
    '66': 'Pyrénées-Orientales',
    '67': 'Bas-Rhin',
    '68': 'Haut-Rhin',
    '69': 'Rhône',
    '70': 'Haute-Saône',
    '71': 'Saône-et-Loire',
    '72': 'Sarthe',
    '73': 'Savoie',
    '74': 'Haute-Savoie',
    '75': 'Paris',
    '76': 'Seine-Maritime',
    '77': 'Seine-et-Marne',
    '78': 'Yvelines',
    '79': 'Deux-Sèvres',
    '80': 'Somme',
    '81': 'Tarn',
    '82': 'Tarn-et-Garonne',
    '83': 'Var',
    '84': 'Vaucluse',
    '85': 'Vendée',
    '86': 'Vienne',
    '87': 'Haute-Vienne',
    '88': 'Vosges',
    '89': 'Yonne',
    '90': 'Territoire de Belfort',
    '91': 'Essonne',
    '92': 'Hauts-de-Seine',
    '93': 'Seine-Saint-Denis',
    '94': 'Val-de-Marne',
    '95': 'Val-d\'Oise',
    '971': 'Guadeloupe',
    '972': 'Martinique',
    '973': 'Guyane',
    '974': 'La Réunion',
    '975': 'Saint-Pierre-et-Miquelon',
    '976': 'Mayotte',
    '977': 'Saint-Barthélemy',
    '978': 'Saint-Martin',
    '984': 'Terre Adélaïe',
    '986': 'Wallis-et-Futuna',
    '987': 'Polynésie française',
    '988': 'Nouvelle-Calédonie',
    '989': 'Île de Clipperton',
  };

  /// Get full department name from code
  static String _getDepartmentName(String? code) {
    if (code == null || code.isEmpty) return '';

    // Try exact match first (handles 3-digit overseas territories)
    if (_frenchDepartments.containsKey(code)) {
      return _frenchDepartments[code]!;
    }

    // For metropolitan departments (1-2 digits), try with zero padding
    if (code.length <= 2) {
      final normalizedCode = code.padLeft(2, '0');
      if (_frenchDepartments.containsKey(normalizedCode)) {
        return _frenchDepartments[normalizedCode]!;
      }
    }

    // Return code if not found (shouldn't happen with complete map)
    return 'Dept $code';
  }

  /// Helper to parse various numeric formats from FFVL API
  double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) {
      if (value.isEmpty) return null;
      return double.tryParse(value);
    }
    return null;
  }

  /// Filter beacons to those within requested bounding box
  List<WeatherStation> _filterStationsToBounds(
    List<WeatherStation> stations,
    LatLngBounds bounds,
  ) {
    final filtered = stations.where((station) {
      return bounds.contains(LatLng(station.latitude, station.longitude));
    }).toList();

    LoggingService.structured('FFVL_BBOX_FILTER', {
      'total_beacons': stations.length,
      'filtered_count': filtered.length,
      'bounds': '${bounds.south},${bounds.west},${bounds.north},${bounds.east}',
    });

    return filtered;
  }
}

/// Global cache entry with dual timestamp tracking
/// Allows separate TTL for beacon list (24hr) and measurements (5min)
class _GlobalCacheEntry {
  final List<WeatherStation> stations;
  final DateTime beaconListTimestamp;
  final DateTime measurementsTimestamp;

  _GlobalCacheEntry({
    required this.stations,
    required this.beaconListTimestamp,
    required this.measurementsTimestamp,
  });

  bool get beaconListExpired {
    return DateTime.now().difference(beaconListTimestamp) >
        MapConstants.ffvlBeaconListCacheTTL;
  }

  bool get measurementsExpired {
    return DateTime.now().difference(measurementsTimestamp) >
        MapConstants.ffvlMeasurementsCacheTTL;
  }
}
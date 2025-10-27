import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:xml/xml.dart';
import '../../data/models/weather_station.dart';
import '../../data/models/weather_station_source.dart';
import '../../data/models/wind_data.dart';
import '../../utils/map_constants.dart';
import '../logging_service.dart';
import 'weather_station_provider.dart';

/// Bureau of Meteorology (BOM) weather station provider from reg.bom.gov.au
/// Provides Australian weather stations with real-time observations (~700 stations)
///
/// Uses state-based global caching strategy optimized for multi-file APIs:
/// - Australia divided into 7 states/territories (WA, NSW, VIC, QLD, SA, TAS, NT)
/// - Each state has separate XML file (~180-480 KB)
/// - Fetches only visible state(s) based on bounding box
/// - Station list cached per state for 24 hours (locations don't change)
/// - Observations cached per state for 10 minutes (BOM updates every 10 min)
/// - Filters cached data to bbox in-memory (instant pan/zoom within state)
///
/// Wind data is already in km/h (no conversion needed)
/// Observations update every 10 minutes at x:00, x:10, x:20, x:30, x:40, x:50
class BomWeatherProvider implements WeatherStationProvider {
  static final BomWeatherProvider instance = BomWeatherProvider._();
  BomWeatherProvider._();

  /// State cache entries (one per Australian state/territory)
  final Map<String, _StateCacheEntry> _stateCache = {};

  /// Pending state requests to prevent duplicate API calls
  final Map<String, Future<List<WeatherStation>>> _pendingStateRequests = {};

  @override
  WeatherStationSource get source => WeatherStationSource.bom;

  @override
  String get displayName => 'Bureau of Meteorology';

  @override
  String get description => 'Australian weather stations';

  @override
  String get attributionName => 'Australian Bureau of Meteorology';

  @override
  String get attributionUrl => 'http://www.bom.gov.au/';

  @override
  Duration get cacheTTL => MapConstants.bomObservationCacheTTL;

  @override
  bool get requiresApiKey => false;

  @override
  Future<bool> isConfigured() async {
    // BOM doesn't require configuration
    return true;
  }

  @override
  Future<List<WeatherStation>> fetchStations(LatLngBounds bounds) async {
    try {
      // Step 1: Determine which state(s) overlap with view bounds
      final overlappingStates = _determineOverlappingStates(bounds);

      if (overlappingStates.isEmpty) {
        LoggingService.structured('BOM_NO_STATES', {
          'bounds': _boundsToString(bounds),
        });
        return [];
      }

      LoggingService.structured('BOM_FETCH_START', {
        'states': overlappingStates.map((s) => s.code).toList(),
        'bounds': _boundsToString(bounds),
      });

      // Step 2: Fetch each overlapping state (in parallel if multiple)
      final futures = overlappingStates.map((state) => _fetchStateStations(state, bounds));
      final results = await Future.wait(futures);

      // Step 3: Combine all state results
      final allStations = <WeatherStation>[];
      for (final stateStations in results) {
        allStations.addAll(stateStations);
      }

      LoggingService.structured('BOM_FETCH_COMPLETE', {
        'states': overlappingStates.map((s) => s.code).toList(),
        'total_stations': allStations.length,
      });

      return allStations;
    } catch (e, stackTrace) {
      LoggingService.error('Failed to fetch BOM stations', e, stackTrace);
      return [];
    }
  }

  @override
  Future<Map<String, WindData>> fetchWeatherData(
    List<WeatherStation> stations,
  ) async {
    if (stations.isEmpty) return {};

    // BOM stations already have wind data embedded (like Pioupiou/FFVL)
    // Just extract it and map by station key
    final Map<String, WindData> result = {};
    for (final station in stations) {
      if (station.windData != null) {
        result[station.key] = station.windData!;
      }
    }

    LoggingService.structured('BOM_WEATHER_EXTRACTED', {
      'total_stations': stations.length,
      'stations_with_data': result.length,
    });

    return result;
  }

  @override
  void clearCache() {
    _stateCache.clear();
    _pendingStateRequests.clear();
    LoggingService.info('BOM state caches cleared');
  }

  @override
  Map<String, dynamic> getCacheStats() {
    final cachedStates = _stateCache.keys.toList();
    final totalStations = _stateCache.values
        .fold(0, (sum, entry) => sum + entry.stations.length);
    final stationsWithData = _stateCache.values
        .expand((entry) => entry.stations)
        .where((s) => s.windData != null)
        .length;

    return {
      'cached': _stateCache.isNotEmpty,
      'cached_states': cachedStates,
      'total_stations': totalStations,
      'stations_with_data': stationsWithData,
    };
  }

  /// Fetch stations for a specific state
  Future<List<WeatherStation>> _fetchStateStations(
    _BomState state,
    LatLngBounds requestBounds,
  ) async {
    try {
      // Check if we have a valid cache for this state
      final cached = _stateCache[state.code];

      // Step 1: Check if station list cache is valid (<24hr)
      if (cached != null && !cached.stationListExpired) {
        // Step 2: Check if observations are stale (>10min)
        if (cached.observationsExpired) {
          LoggingService.info('BOM ${state.code} observations expired, refreshing');
          await _refreshStateObservations(state);
        } else {
          LoggingService.structured('BOM_CACHE_HIT', {
            'state': state.code,
            'total_stations': cached.stations.length,
            'station_list_age_min': DateTime.now()
                .difference(cached.stationListTimestamp)
                .inMinutes,
            'observations_age_min': DateTime.now()
                .difference(cached.observationsTimestamp)
                .inMinutes,
          });
        }

        // Step 3: Filter cached stations to bbox
        final cachedEntry = _stateCache[state.code]!;
        return _filterStationsToBounds(cachedEntry.stations, requestBounds);
      }

      // Step 4: No valid cache - fetch state file from API
      if (_pendingStateRequests.containsKey(state.code)) {
        LoggingService.info('Waiting for pending BOM ${state.code} request');
        final stations = await _pendingStateRequests[state.code]!;
        return _filterStationsToBounds(stations, requestBounds);
      }

      // Fetch state file
      final future = _fetchStateFile(state);
      _pendingStateRequests[state.code] = future;

      try {
        final stations = await future;
        if (stations.isEmpty) {
          return []; // Failed to fetch
        }
        return _filterStationsToBounds(stations, requestBounds);
      } finally {
        _pendingStateRequests.remove(state.code);
      }
    } catch (e, stackTrace) {
      LoggingService.error('Failed to fetch BOM state ${state.code}', e, stackTrace);
      return [];
    }
  }

  /// Fetch and parse an entire state XML file from BOM
  Future<List<WeatherStation>> _fetchStateFile(_BomState state) async {
    try {
      final stopwatch = Stopwatch()..start();
      final url = state.url;

      LoggingService.structured('BOM_STATE_REQUEST_START', {
        'state': state.code,
        'product_id': state.productId,
        'url': url,
      });

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Accept': 'text/xml',
          'User-Agent': 'TheParaglidingApp/1.0',
        },
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          stopwatch.stop();
          LoggingService.structured('BOM_STATE_TIMEOUT', {
            'state': state.code,
            'duration_ms': stopwatch.elapsedMilliseconds,
            'timeout_seconds': 30,
          });
          return http.Response('{"error": "Request timeout"}', 408);
        },
      );

      stopwatch.stop();

      LoggingService.structured('BOM_STATE_RESPONSE', {
        'state': state.code,
        'status_code': response.statusCode,
        'duration_ms': stopwatch.elapsedMilliseconds,
        'content_length': response.body.length,
      });

      if (response.statusCode == 200) {
        final networkTime = stopwatch.elapsedMilliseconds;

        // Parse XML
        final parseStopwatch = Stopwatch()..start();
        final stations = _parseStateXml(response.body, state);
        parseStopwatch.stop();

        LoggingService.performance(
          'BOM ${state.code} parsing',
          Duration(milliseconds: parseStopwatch.elapsedMilliseconds),
          '${stations.length} stations parsed',
        );

        // Cache the results with current timestamps
        final now = DateTime.now();
        _stateCache[state.code] = _StateCacheEntry(
          stations: stations,
          stationListTimestamp: now,
          observationsTimestamp: now,
          stateCode: state.code,
          productId: state.productId,
        );

        LoggingService.structured('BOM_STATE_SUCCESS', {
          'state': state.code,
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
        LoggingService.structured('BOM_STATE_HTTP_ERROR', {
          'state': state.code,
          'status_code': response.statusCode,
          'response_preview': response.body.substring(
            0,
            response.body.length > 500 ? 500 : response.body.length,
          ),
          'duration_ms': stopwatch.elapsedMilliseconds,
        });
        return [];
      }
    } catch (e, stackTrace) {
      LoggingService.structured('BOM_STATE_REQUEST_FAILED', {
        'state': state.code,
        'error_type': e.runtimeType.toString(),
        'error_message': e.toString(),
      });
      LoggingService.error('Failed to fetch BOM state ${state.code}', e, stackTrace);
      return [];
    }
  }

  /// Refresh observations for a state while keeping station list cache
  Future<void> _refreshStateObservations(_BomState state) async {
    try {
      final stations = await _fetchStateFile(state);
      final cached = _stateCache[state.code];

      if (stations.isNotEmpty && cached != null) {
        // Update only observations timestamp, keep original station list timestamp
        _stateCache[state.code] = _StateCacheEntry(
          stations: stations,
          stationListTimestamp: cached.stationListTimestamp,
          observationsTimestamp: DateTime.now(),
          stateCode: state.code,
          productId: state.productId,
        );

        LoggingService.structured('BOM_OBSERVATIONS_REFRESHED', {
          'state': state.code,
          'station_count': stations.length,
          'stations_with_data': stations.where((s) => s.windData != null).length,
        });
      }
    } catch (e, stackTrace) {
      LoggingService.error(
        'Failed to refresh BOM ${state.code} observations',
        e,
        stackTrace,
      );
    }
  }

  /// Parse BOM XML file and extract weather stations
  List<WeatherStation> _parseStateXml(String xmlBody, _BomState state) {
    try {
      final document = XmlDocument.parse(xmlBody);
      final stations = <WeatherStation>[];

      // Extract issue time for logging
      final issueTimeUtc = document.findAllElements('issue-time-utc').firstOrNull?.innerText;

      // Parse each station element
      for (final stationNode in document.findAllElements('station')) {
        try {
          final station = _parseStationNode(stationNode, state);
          if (station != null && station.windData != null) {
            stations.add(station);
          }
        } catch (e) {
          // Log error but continue with other stations
          LoggingService.error(
            'BOM station parse error in ${state.code}',
            e,
            StackTrace.current,
          );
        }
      }

      LoggingService.structured('BOM_STATE_PARSE_SUCCESS', {
        'state': state.code,
        'stations_parsed': stations.length,
        'issue_time': issueTimeUtc,
      });

      return stations;
    } catch (e, stackTrace) {
      LoggingService.error('Failed to parse BOM XML for ${state.code}', e, stackTrace);
      return [];
    }
  }

  /// Parse a single station XML node into a WeatherStation
  WeatherStation? _parseStationNode(XmlElement stationNode, _BomState state) {
    try {
      // Extract station attributes
      final bomId = stationNode.getAttribute('bom-id');
      final name = stationNode.getAttribute('stn-name');
      final latStr = stationNode.getAttribute('lat');
      final lonStr = stationNode.getAttribute('lon');
      final heightStr = stationNode.getAttribute('stn-height');
      final type = stationNode.getAttribute('type'); // AWS or PAWS

      if (bomId == null || name == null || latStr == null || lonStr == null) {
        return null; // Skip stations without required attributes
      }

      final lat = double.tryParse(latStr);
      final lon = double.tryParse(lonStr);

      if (lat == null || lon == null) {
        return null;
      }

      final height = heightStr != null ? double.tryParse(heightStr) : null;

      // Find most recent observation period (index="0")
      final period = stationNode.findElements('period')
          .where((e) => e.getAttribute('index') == '0')
          .firstOrNull;

      if (period == null) {
        return null; // No observations available
      }

      // Extract observation time
      final timeUtc = period.getAttribute('time-utc');
      if (timeUtc == null) {
        return null;
      }

      final timestamp = DateTime.parse(timeUtc);

      // Extract wind elements from level[@index="0"] elements
      double? windSpeed, windDir, windGust, rainfall;

      for (final element in period.findAllElements('element')) {
        final elemType = element.getAttribute('type');
        final text = element.innerText;

        if (text.isEmpty) continue;

        switch (elemType) {
          case 'wind_spd_kmh':
            windSpeed = double.tryParse(text);
          case 'wind_dir_deg':
            windDir = double.tryParse(text);
          case 'gust_kmh':
            windGust = double.tryParse(text);
          case 'rainfall':
            rainfall = double.tryParse(text);
        }
      }

      // Only create station if we have wind data
      if (windSpeed == null && windDir == null) {
        return null;
      }

      // Create unique station ID with state prefix
      final stationId = '${state.code}:$bomId';

      // Determine observation type
      final observationType = type == 'PAWS'
          ? 'Portable AWS'
          : 'Automatic Weather Station';

      return WeatherStation(
        id: stationId,
        name: name,
        latitude: lat,
        longitude: lon,
        elevation: height,
        source: WeatherStationSource.bom,
        observationType: observationType,
        windData: WindData(
          speedKmh: windSpeed ?? 0,
          directionDegrees: windDir ?? 0,
          gustsKmh: windGust,
          precipitationMm: rainfall ?? 0,
          timestamp: timestamp,
        ),
      );
    } catch (e) {
      LoggingService.error('Error parsing BOM station node', e);
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

    LoggingService.structured('BOM_BBOX_FILTER', {
      'total_stations': stations.length,
      'filtered_count': filtered.length,
      'bounds': _boundsToString(bounds),
    });

    return filtered;
  }

  /// Determine which Australian state(s) overlap with the given bounding box
  List<_BomState> _determineOverlappingStates(LatLngBounds viewBounds) {
    final overlapping = <_BomState>[];

    for (final state in _australianStates) {
      if (_boundsOverlap(viewBounds, state.bounds)) {
        overlapping.add(state);
      }
    }

    // Fallback: if no overlap, find nearest state by center point
    if (overlapping.isEmpty) {
      final center = viewBounds.center;
      _BomState? nearest;
      double minDistance = double.infinity;

      for (final state in _australianStates) {
        final stateCenter = state.bounds.center;
        final distance = const Distance().distance(center, stateCenter);

        if (distance < minDistance) {
          minDistance = distance;
          nearest = state;
        }
      }

      if (nearest != null) {
        overlapping.add(nearest);
      }
    }

    return overlapping;
  }

  /// Check if two bounding boxes overlap
  bool _boundsOverlap(LatLngBounds a, LatLngBounds b) {
    return !(a.east < b.west || a.west > b.east ||
             a.north < b.south || a.south > b.north);
  }

  /// Convert bounds to string for logging
  String _boundsToString(LatLngBounds bounds) {
    return '${bounds.south},${bounds.west},${bounds.north},${bounds.east}';
  }
}

/// Australian state/territory definition with product ID and boundaries
class _BomState {
  final String code; // 'WA', 'NSW', etc.
  final String productId; // 'IDW60920', etc.
  final LatLngBounds bounds; // Approximate state boundary

  const _BomState({
    required this.code,
    required this.productId,
    required this.bounds,
  });

  /// BOM XML file URL
  String get url => 'http://reg.bom.gov.au/fwo/$productId.xml';
}

/// Australian states and territories with BOM product IDs
/// Boundaries are approximate for overlap detection
final List<_BomState> _australianStates = [
  _BomState(
    code: 'WA',
    productId: 'IDW60920',
    bounds: LatLngBounds(
      LatLng(-35.0, 113.0), // SW corner
      LatLng(-13.0, 129.0), // NE corner
    ),
  ),
  _BomState(
    code: 'NT',
    productId: 'IDD60920',
    bounds: LatLngBounds(
      LatLng(-26.0, 129.0),
      LatLng(-11.0, 138.0),
    ),
  ),
  _BomState(
    code: 'SA',
    productId: 'IDS60920',
    bounds: LatLngBounds(
      LatLng(-38.0, 129.0),
      LatLng(-26.0, 141.0),
    ),
  ),
  _BomState(
    code: 'QLD',
    productId: 'IDQ60920',
    bounds: LatLngBounds(
      LatLng(-29.0, 138.0),
      LatLng(-9.0, 154.0),
    ),
  ),
  _BomState(
    code: 'NSW',
    productId: 'IDN60920',
    bounds: LatLngBounds(
      LatLng(-38.0, 141.0),
      LatLng(-28.0, 154.0),
    ),
  ),
  _BomState(
    code: 'VIC',
    productId: 'IDV60920',
    bounds: LatLngBounds(
      LatLng(-39.0, 141.0),
      LatLng(-34.0, 150.0),
    ),
  ),
  _BomState(
    code: 'TAS',
    productId: 'IDT60920',
    bounds: LatLngBounds(
      LatLng(-44.0, 144.0),
      LatLng(-40.0, 149.0),
    ),
  ),
];

/// State cache entry with dual timestamp tracking
/// Allows separate TTL for station list (24hr) and observations (10min)
class _StateCacheEntry {
  final List<WeatherStation> stations;
  final DateTime stationListTimestamp;
  final DateTime observationsTimestamp;
  final String stateCode;
  final String productId;

  _StateCacheEntry({
    required this.stations,
    required this.stationListTimestamp,
    required this.observationsTimestamp,
    required this.stateCode,
    required this.productId,
  });

  bool get stationListExpired {
    return DateTime.now().difference(stationListTimestamp) >
        MapConstants.bomStationListCacheTTL;
  }

  bool get observationsExpired {
    return DateTime.now().difference(observationsTimestamp) >
        MapConstants.bomObservationCacheTTL;
  }
}

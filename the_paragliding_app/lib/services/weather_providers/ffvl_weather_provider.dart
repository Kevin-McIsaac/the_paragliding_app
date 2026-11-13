import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../data/models/weather_station.dart';
import '../../data/models/weather_station_source.dart';
import '../../data/models/wind_data.dart';
import '../../utils/map_constants.dart';
import '../logging_service.dart';
import 'weather_station_provider.dart';

/// FFVL (French Free Flight Federation) weather beacon provider from
/// data.gouv.fr.
///
/// The federation publishes two public files. No key is required.
/// - `balises.json`: the beacon list, published daily (about 237 KB).
/// - `releves.json`: the latest reading per beacon, published every 5 minutes
///   (about 33 KB).
///
/// The cache keeps the parsed beacon list and the derived stations separately,
/// so a reading refresh downloads only the 33 KB file. The dated static URLs
/// change on every publish and are served with a 30-day cache, so the provider
/// uses the stable resource-id URLs instead.
///
/// OpenWindMap beacons are in the list but have no readings in `releves.json`.
/// The OpenWindMap layer supplies those stations, and the service deduplicates
/// them within 150 m.
///
/// Wind data is already in km/h (no conversion needed).
class FfvlWeatherProvider implements WeatherStationProvider {
  static final FfvlWeatherProvider instance = FfvlWeatherProvider._();
  FfvlWeatherProvider._();

  // Stable data.gouv.fr resource ids. The 302 behind each id points at the
  // current dated file, so this never goes stale.
  static const String _balisesUrl =
      'https://www.data.gouv.fr/api/1/datasets/r/8d795154-9145-4ab2-99de-6768a36f31ea';
  static const String _relevesUrl =
      'https://www.data.gouv.fr/api/1/datasets/r/047b2ab9-627f-4e5f-9d68-5b948433c61d';
  static const String _stationUrl =
      'https://www.balisemeteo.com/balise.php?idBalise=';
  static const Duration _requestTimeout = Duration(seconds: 30);

  http.Client _httpClient = http.Client();

  @visibleForTesting
  set httpClientForTest(http.Client client) => _httpClient = client;

  /// Global cache entry (single entry for all beacons)
  _GlobalCacheEntry? _globalCache;

  /// Pending global request to prevent duplicate API calls
  Future<void>? _pendingCatalogue;
  Future<void>? _pendingReadings;

  @override
  WeatherStationSource get source => WeatherStationSource.ffvl;

  /// These providers answer with a complete list, so their return value is
  /// their result - see [WeatherStationProvider.pushesProgressively].
  @override
  bool get pushesProgressively => false;

  @override
  String get displayName => 'FFVL Beacons';

  @override
  String get description => 'French paragliding weather beacons (data.gouv.fr)';

  @override
  String get attributionName => 'FFVL (data.gouv.fr)';

  @override
  String get attributionUrl =>
      'https://www.data.gouv.fr/datasets/reseau-de-balises-meteo-de-la-ffvl-federation-francaise-de-vol-libre';

  @override
  Duration get cacheTTL => MapConstants.ffvlMeasurementsCacheTTL;

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
      final cache = _globalCache;

      // Early exit: the fresh catalogue does not cover this view.
      if (cache != null &&
          !cache.beaconListExpired &&
          !_boundsOverlap(bounds, cache.bounds)) {
        LoggingService.structured('FFVL_BBOX_NO_OVERLAP', {
          'requested':
              '${bounds.south},${bounds.west},${bounds.north},${bounds.east}',
          'cached':
              '${cache.bounds.south},${cache.bounds.west},'
              '${cache.bounds.north},${cache.bounds.east}',
        });
        return [];
      }

      if (cache == null || cache.beaconListExpired) {
        await _ensureCatalogue(onApiCallStart);
      } else if (cache.measurementsExpired) {
        final hasStationsInView = cache.stations.any(
          (s) => bounds.contains(LatLng(s.latitude, s.longitude)),
        );

        if (!hasStationsInView) {
          LoggingService.structured('FFVL_NO_STATIONS_IN_VIEW', {
            'bounds':
                '${bounds.south},${bounds.west},${bounds.north},${bounds.east}',
            'total_cached_stations': cache.stations.length,
          });
          return [];
        }

        await _ensureReadings(onApiCallStart);
      } else {
        LoggingService.structured('FFVL_CACHE_HIT', {
          'total_beacons': cache.stations.length,
          'beacon_list_age_min': DateTime.now()
              .difference(cache.beaconListTimestamp)
              .inMinutes,
          'measurements_age_min': DateTime.now()
              .difference(cache.measurementsTimestamp)
              .inMinutes,
        });
      }

      final current = _globalCache;
      if (current == null) return [];
      return _filterStationsToBounds(current.stations, bounds);
    } catch (e, stackTrace) {
      LoggingService.error('Failed to fetch FFVL beacons', e, stackTrace);
      return [];
    }
  }

  @override
  Future<void> warmCache() async {
    // Fully fresh cache - nothing to warm
    if (_globalCache != null &&
        !_globalCache!.beaconListExpired &&
        !_globalCache!.measurementsExpired) {
      return;
    }
    // A world bbox goes through the normal fetch/refresh path: it overlaps
    // any cached area, so a valid beacon list only refreshes readings
    // and an empty cache does the full global fetch.
    await fetchStations(LatLngBounds(LatLng(-90, -180), LatLng(90, 180)));
  }

  @override
  Future<Map<String, WindData>> fetchWeatherData(
    List<WeatherStation> stations,
  ) async {
    if (stations.isEmpty) return {};

    // FFVL stations already have wind data embedded (like METAR and OpenWindMap).
    // Just extract it and map by station key.
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
    _pendingCatalogue = null;
    _pendingReadings = null;
    LoggingService.info('FFVL global cache cleared');
  }

  @override
  Map<String, dynamic> getCacheStats() {
    final cache = _globalCache;
    if (cache == null) {
      return {
        'cached': false,
        'total_beacons': 0,
      };
    }

    final beaconAge = DateTime.now().difference(cache.beaconListTimestamp);
    final measurementAge = DateTime.now().difference(cache.measurementsTimestamp);

    return {
      'cached': true,
      'total_beacons': cache.beacons.length,
      'beacons_with_data': cache.stations.where((s) => s.windData != null).length,
      'beacon_list_age_minutes': beaconAge.inMinutes,
      'measurements_age_minutes': measurementAge.inMinutes,
      'beacon_list_expired': cache.beaconListExpired,
      'measurements_expired': cache.measurementsExpired,
    };
  }

  /// Test seam: rewrite the cache timestamps so the TTL paths can be exercised
  /// without waiting 5 minutes or 24 hours.
  @visibleForTesting
  void setCacheAgeForTest({
    Duration beaconListAge = Duration.zero,
    Duration measurementsAge = Duration.zero,
  }) {
    final cache = _globalCache;
    if (cache == null) return;
    final now = DateTime.now();
    _globalCache = _GlobalCacheEntry(
      beacons: cache.beacons,
      stations: cache.stations,
      beaconListTimestamp: now.subtract(beaconListAge),
      measurementsTimestamp: now.subtract(measurementsAge),
      bounds: cache.bounds,
    );
  }

  /// Load the beacon list and readings once, at most every 24 hours.
  Future<void> _ensureCatalogue(Function()? onApiCallStart) async {
    final pending = _pendingCatalogue;
    if (pending != null) {
      await pending;
      return;
    }

    onApiCallStart?.call();
    final future = _loadCatalogue();
    _pendingCatalogue = future;
    try {
      await future;
    } finally {
      _pendingCatalogue = null;
    }
  }

  /// Refresh only the readings, at most every 5 minutes.
  Future<void> _ensureReadings(Function()? onApiCallStart) async {
    final pending = _pendingReadings;
    if (pending != null) {
      await pending;
      return;
    }

    onApiCallStart?.call();
    final future = _refreshReadings();
    _pendingReadings = future;
    try {
      await future;
    } finally {
      _pendingReadings = null;
    }
  }

  Future<void> _loadCatalogue() async {
    final stopwatch = Stopwatch()..start();
    try {
      final balisesJson = await _fetchJson(_balisesUrl, 'balises');
      if (balisesJson == null) return; // keep any old cache

      final parsedBeacons = _parseBeacons(balisesJson);
      if (parsedBeacons.active.isEmpty) {
        LoggingService.warning('FFVL beacon list parsed to zero active beacons');
        return;
      }

      final readingsJson = await _fetchJson(_relevesUrl, 'releves');
      final parsedReadings = readingsJson == null
          ? const _ParsedReadings(<String, WindData>{}, 0)
          : _parseReadings(readingsJson, now: DateTime.now());

      final parseStopwatch = Stopwatch()..start();
      final stations = _buildStations(parsedBeacons.active, parsedReadings.winds);
      parseStopwatch.stop();

      LoggingService.performance(
        'FFVL parsing',
        Duration(milliseconds: parseStopwatch.elapsedMilliseconds),
        '${stations.length} beacons parsed',
      );

      final now = DateTime.now();
      _globalCache = _GlobalCacheEntry(
        beacons: parsedBeacons.active,
        stations: stations,
        beaconListTimestamp: now,
        measurementsTimestamp: readingsJson == null
            ? DateTime.fromMillisecondsSinceEpoch(0)
            : now,
        bounds: _calculateBoundsFromStations(stations),
      );

      final joined = parsedBeacons.active
          .where((beacon) => parsedReadings.winds.containsKey(beacon.id))
          .length;

      LoggingService.structured('FFVL_CATALOGUE_LOADED', {
        'raw': parsedBeacons.active.length +
            parsedBeacons.maintenance +
            parsedBeacons.invalid,
        'active': parsedBeacons.active.length,
        'maintenance': parsedBeacons.maintenance,
        'invalid': parsedBeacons.invalid,
        'readings': parsedReadings.winds.length,
        'joined': joined,
        'skipped': parsedReadings.skipped,
        'orphans': parsedReadings.winds.length - joined,
        'ms': stopwatch.elapsedMilliseconds,
      });
    } catch (e, stackTrace) {
      LoggingService.structured('FFVL_REQUEST_FAILED', {
        'error_type': e.runtimeType.toString(),
        'error_message': e.toString(),
      });
      LoggingService.error('Failed to load FFVL beacons', e, stackTrace);
    }
  }

  Future<void> _refreshReadings() async {
    final cache = _globalCache;
    if (cache == null) return;

    final stopwatch = Stopwatch()..start();
    try {
      final readingsJson = await _fetchJson(_relevesUrl, 'releves');
      if (readingsJson == null) return; // keep the old stations

      final parsed = _parseReadings(readingsJson, now: DateTime.now());
      final now = DateTime.now();

      _globalCache = _GlobalCacheEntry(
        beacons: cache.beacons,
        stations: _buildStations(cache.beacons, parsed.winds),
        beaconListTimestamp: cache.beaconListTimestamp,
        measurementsTimestamp: now,
        bounds: cache.bounds,
      );

      final joined = cache.beacons
          .where((beacon) => parsed.winds.containsKey(beacon.id))
          .length;

      LoggingService.structured('FFVL_READINGS_REFRESHED', {
        'readings': parsed.winds.length,
        'joined': joined,
        'skipped': parsed.skipped,
        'orphans': parsed.winds.length - joined,
        'ms': stopwatch.elapsedMilliseconds,
      });
    } catch (e, stackTrace) {
      LoggingService.structured('FFVL_READINGS_REFRESH_FAILED', {
        'error_type': e.runtimeType.toString(),
        'error_message': e.toString(),
      });
      LoggingService.error('Failed to refresh FFVL readings', e, stackTrace);
    }
  }

  /// Fetch one published file. Returns null on any failure, after logging it.
  Future<dynamic> _fetchJson(String url, String resource) async {
    final stopwatch = Stopwatch()..start();
    LoggingService.structured('FFVL_REQUEST_START', {
      'resource': resource,
      'url': url,
    });

    final response = await _httpClient.get(
      Uri.parse(url),
      headers: const {
        'Accept': 'application/json',
        'User-Agent': 'TheParaglidingApp/1.0',
      },
    ).timeout(
      _requestTimeout,
      onTimeout: () {
        stopwatch.stop();
        LoggingService.structured('FFVL_TIMEOUT', {
          'resource': resource,
          'duration_ms': stopwatch.elapsedMilliseconds,
          'timeout_seconds': _requestTimeout.inSeconds,
        });
        return http.Response('{"error": "Request timeout"}', 408);
      },
    );
    stopwatch.stop();

    if (response.statusCode == 404 || response.statusCode == 410) {
      LoggingService.structured('FFVL_RESOURCE_GONE', {
        'resource': resource,
        'status': response.statusCode,
        'url': url,
      });
      LoggingService.warning(
        'FFVL $resource resource is gone. Check the dataset page and the '
        'FFVL Dev Discord for a new resource id.',
      );
      return null;
    }

    if (response.statusCode != 200) {
      LoggingService.structured('FFVL_HTTP_ERROR', {
        'resource': resource,
        'status_code': response.statusCode,
        'duration_ms': stopwatch.elapsedMilliseconds,
      });
      return null;
    }

    try {
      return jsonDecode(response.body);
    } catch (e) {
      LoggingService.structured('FFVL_RESPONSE_INVALID', {
        'resource': resource,
        'error_type': e.runtimeType.toString(),
      });
      return null;
    }
  }

  _ParsedBeacons _parseBeacons(dynamic decoded) {
    if (decoded is! List) {
      return const _ParsedBeacons(<_Beacon>[], 0, 1);
    }

    final active = <_Beacon>[];
    var maintenance = 0;
    var invalid = 0;

    for (final raw in decoded) {
      if (raw is! Map<String, dynamic>) {
        invalid++;
        continue;
      }
      if (_isMaintenance(raw)) {
        maintenance++;
        continue;
      }
      final beacon = _parseBeacon(raw);
      if (beacon == null) {
        invalid++;
        continue;
      }
      active.add(beacon);
    }

    return _ParsedBeacons(active, maintenance, invalid);
  }

  bool _isMaintenance(Map<String, dynamic> json) {
    final value = json['en_maintenance'];
    return value == 1 || value == '1';
  }

  _Beacon? _parseBeacon(Map<String, dynamic> json) {
    try {
      final id = json['idBalise']?.toString();
      final latitude = _parseDouble(json['latitude']);
      final longitude = _parseDouble(json['longitude']);

      if (id == null || id.isEmpty || latitude == null || longitude == null) {
        return null;
      }

      return _Beacon(
        id: id,
        name: json['nom'] as String?,
        latitude: latitude,
        longitude: longitude,
        altitude: _parseDouble(json['altitude']),
        department: json['departement'] as String?,
        stationType: json['station_type'] as String? ?? 'FFVL',
      );
    } catch (e) {
      LoggingService.error('Error parsing FFVL beacon', e);
      return null;
    }
  }

  _ParsedReadings _parseReadings(dynamic decoded, {required DateTime now}) {
    if (decoded is! List) {
      return const _ParsedReadings(<String, WindData>{}, 0);
    }

    final winds = <String, WindData>{};
    var skipped = 0;

    for (final raw in decoded) {
      if (raw is! Map<String, dynamic>) {
        skipped++;
        continue;
      }
      final id = raw['idbalise']?.toString();
      if (id == null || id.isEmpty) {
        skipped++;
        continue;
      }
      final reading = _parseReading(raw, now: now);
      if (reading == null) {
        skipped++;
        continue;
      }
      winds[id] = reading;
    }

    return _ParsedReadings(winds, skipped);
  }

  WindData? _parseReading(
    Map<String, dynamic> json, {
    required DateTime now,
  }) {
    final speed = _parseDouble(json['vitesseVentMoy']);
    final direction = _parseDouble(json['directVentMoy']);
    final rawDate = json['date'];
    final date = rawDate is String ? DateTime.tryParse(rawDate)?.toUtc() : null;

    if (speed == null || direction == null || date == null) {
      return null;
    }

    // releves.json keeps the last reading of an offline beacon. Do not show a
    // month-old reading as today's wind.
    if (now.difference(date) > MapConstants.ffvlMeasurementMaxAge) {
      return null;
    }

    return WindData(
      speedKmh: speed,
      gustsKmh: _parseDouble(json['vitesseVentMax']),
      directionDegrees: direction,
      timestamp: date,
    );
  }

  List<WeatherStation> _buildStations(
    List<_Beacon> beacons,
    Map<String, WindData> winds,
  ) {
    return beacons.map((beacon) {
      return WeatherStation(
        id: 'ffvl_${beacon.id}',
        source: WeatherStationSource.ffvl,
        name: _displayName(beacon),
        latitude: beacon.latitude,
        longitude: beacon.longitude,
        elevation: beacon.altitude,
        windData: winds[beacon.id],
        observationType: _observationType(beacon.stationType),
        dataUrl: '$_stationUrl${beacon.id}',
      );
    }).toList();
  }

  static String? _displayName(_Beacon beacon) {
    final name = beacon.name;
    if (name == null) return null;

    final department = beacon.department;
    if (department == null || department.isEmpty) return name;

    final departmentName = _getDepartmentName(department);
    if (departmentName.isNotEmpty && !departmentName.startsWith('Dept')) {
      return '$name ($departmentName)';
    }
    return '$name (Dept $department)';
  }

  static String _observationType(String stationType) {
    switch (stationType) {
      case 'OPENWINDMAP':
        return 'FFVL/OpenWindMap';
      case 'FFVL':
        return 'FFVL';
      default:
        return 'FFVL ($stationType)';
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

  /// Helper to parse various numeric formats from the files
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

  /// Calculate bounding box from list of weather stations
  LatLngBounds _calculateBoundsFromStations(List<WeatherStation> stations) {
    if (stations.isEmpty) {
      // Return minimal bounds if no stations (shouldn't happen)
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

  /// Check if two bounding boxes overlap
  bool _boundsOverlap(LatLngBounds a, LatLngBounds b) {
    return !(a.east < b.west || a.west > b.east ||
             a.north < b.south || a.south > b.north);
  }
}

/// Parsed beacon metadata, kept so a reading refresh does not re-download or
/// re-parse `balises.json`.
class _Beacon {
  final String id;
  final String? name;
  final double latitude;
  final double longitude;
  final double? altitude;
  final String? department;
  final String stationType;

  const _Beacon({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.department,
    required this.stationType,
  });
}

class _ParsedBeacons {
  final List<_Beacon> active;
  final int maintenance;
  final int invalid;

  const _ParsedBeacons(this.active, this.maintenance, this.invalid);
}

class _ParsedReadings {
  final Map<String, WindData> winds;
  final int skipped;

  const _ParsedReadings(this.winds, this.skipped);
}

/// Global cache entry with dual timestamp tracking.
/// Allows separate TTL for the beacon list (24hr) and readings (5min).
class _GlobalCacheEntry {
  final List<_Beacon> beacons;
  final List<WeatherStation> stations;
  final DateTime beaconListTimestamp;
  final DateTime measurementsTimestamp;
  final LatLngBounds bounds; // Calculated bbox from station locations

  _GlobalCacheEntry({
    required this.beacons,
    required this.stations,
    required this.beaconListTimestamp,
    required this.measurementsTimestamp,
    required this.bounds,
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

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:latlong2/latlong.dart';

import '../../data/models/weather_station.dart';
import '../../data/models/weather_station_source.dart';
import '../../data/models/wind_data.dart';
import '../../utils/map_constants.dart';
import '../logging_service.dart';
import '../api_keys.dart';
import 'weather_station_provider.dart';

/// Weather Underground personal weather station (PWS) provider.
///
/// Data comes from The Weather Company API (api.weather.com). Unlike the other
/// providers there is no bbox listing: discovery uses
/// `v3/location/near?product=pws`, which takes a single geocode point and
/// returns the 10 nearest stations. To cover an arbitrary viewport with as few
/// API calls as possible this provider uses **gap probing** (see
/// docs/PWS_STATION_DISCOVERY.md):
///
/// - A persistent set of discovered stations is kept for the session.
/// - A viewport is "covered" when its sample points all lie within
///   [MapConstants.wuCoverageRadiusKm] of a known, fresh station - then zero
///   API calls are made and stations come straight from the cache.
/// - Otherwise only the uncovered sample points are probed and merged in.
///
/// Wind readings come from `pws/observations/current` (units=m → km/h
/// natively). Stations whose `updateTimeUtc` is older than
/// [MapConstants.wuStaleObservationCutoff] are dropped as dead.
///
/// Rate limits (1500/day, 30/min) are respected with a simple request
/// throttle; any failure degrades to an empty result for that call.
class WeatherUndergroundPwsProvider implements WeatherStationProvider {
  static final WeatherUndergroundPwsProvider instance =
      WeatherUndergroundPwsProvider._();
  WeatherUndergroundPwsProvider._();

  static const String _nearUrl = 'https://api.weather.com/v3/location/near';
  static const String _currentUrl =
      'https://api.weather.com/v2/pws/observations/current';

  /// Maximum probe points per viewport (world view worst case).
  static const int _maxProbesPerViewport = 12;

  /// Maximum reading refreshes per fetch pass - keeps a world-sized warm
  /// pass from eating the whole 30/minute rate limit.
  static const int _maxReadingsPerPass = 30;

  /// Up to this many in-bounds readings are fetched BLOCKING so wind arrives
  /// with the markers; beyond that the pass goes to the background.
  static const int _maxBlockingReadings = 12;

  /// Sample-point grid spacing as a fraction of the coverage radius so
  /// neighbouring probe discs overlap.
  static const double _probeSpacingFactor = 0.9;

  /// Minimum interval between API requests: 30/minute ≈ 2s, with margin.
  static const Duration _minRequestInterval = Duration(milliseconds: 2050);

  /// Persistent session cache of discovered stations by stationId.
  @visibleForTesting
  final Map<String, DiscoveredPwsStation> discovered = {};

  DateTime? _measurementsTimestamp;
  DateTime _lastRequestAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  WeatherStationSource get source => WeatherStationSource.weatherUndergroundPws;

  @override
  String get displayName => 'WU PWS';

  @override
  String get description => 'Weather Underground personal stations (global)';

  @override
  String get attributionName => 'Weather Underground';

  @override
  String get attributionUrl => 'https://www.wunderground.com/';

  @override
  Duration get cacheTTL => MapConstants.wuMeasurementsCacheTTL;

  @override
  bool get requiresApiKey => true;

  @override
  Future<bool> isConfigured() async {
    return ApiKeys.wundergroundApiKey.isNotEmpty;
  }

  /// Serialized fetch queue. Every caller runs its own bounded pass, one at a
  /// time - a simple chain beats the earlier shared-pass guard, which either
  /// duplicated work (no guard) or starved callers (a waiter returned the
  /// pending pass's answer, which was for different bounds and usually empty).
  ///
  /// The queue tail is the task future itself - NOT a separate Completer. An
  /// earlier version completed the caller's result via `return await` but left
  /// the Completer never-completed, so the next caller to chain onto it parked
  /// forever (seen live 2026-09-05: the Bakewell fetch queued behind the
  /// warm-up and never ran).
  Future<List<WeatherStation>>? _fetchQueue;

  /// Bumped on every fetch request; passes compare against this and abort
  /// when superseded so a navigation away doesn't keep spending rate limit.
  int _generation = 0;

  bool _cacheLoaded = false;

  @override
  Future<List<WeatherStation>> fetchStations(
    LatLngBounds bounds, {
    Function()? onApiCallStart,
  }) {
    return _enqueueFetch(bounds, onApiCallStart);
  }

  Future<List<WeatherStation>> _enqueueFetch(
    LatLngBounds bounds,
    Function()? onApiCallStart, {
    bool skipReadings = false,
  }) {
    final generation = ++_generation;
    final previous = _fetchQueue ??
        Future<List<WeatherStation>>.value(const []);
    final task = previous
        .catchError((_) => <WeatherStation>[])
        .then((_) async {
          await _loadPersistedCache();
          return _fetchWithProbes(
            bounds,
            onApiCallStart,
            skipReadings: skipReadings,
            generation: generation,
          );
        });
    _fetchQueue = task;
    return task;
  }

  Future<List<WeatherStation>> _fetchWithProbes(
    LatLngBounds bounds,
    Function()? onApiCallStart, {
    bool skipReadings = false,
    int generation = 0,
  }) async {
    try {
      final apiKey = ApiKeys.wundergroundApiKey;
      if (apiKey.isEmpty) {
        LoggingService.warning('WU PWS: no API key configured, skipping');
        return [];
      }

      bool superseded() => generation != _generation;

      // Probe only where the viewport isn't already covered by fresh
      // stations - zero API calls once an area has been explored.
      final probePoints = uncoveredProbePoints(bounds);
      if (probePoints.isNotEmpty) {
        onApiCallStart?.call();
        for (final point in probePoints) {
          if (superseded()) {
            // The user navigated away while this pass was queued or probing.
            // Finish with what the cache holds rather than spending more of
            // the rate limit on a view nobody is looking at.
            LoggingService.structured('WU_PWS_ABORTED', {
              'stage': 'probes',
              'probes_done': probePoints.indexOf(point),
              'probes_total': probePoints.length,
            });
            return _stationsInBounds(bounds);
          }
          await _probePoint(point, apiKey);
        }
        await _persistCacheNow();
      } else {
        LoggingService.structured('WU_PWS_CACHE_HIT', {
          'total_stations': _discoveredCount,
          'fresh_stations': _freshCount,
          'measurements_age_min': _measurementsTimestamp == null
              ? null
              : DateTime.now().difference(_measurementsTimestamp!).inMinutes,
        });
      }

      // Readings: block for them when the viewport has only a few stations
      // (wind arrives WITH the markers - "stations but all no data" is a
      // worse first impression than a slightly longer loading notification),
      // run them in the background for wide viewports where a blocking pass
      // would stall the map for a minute. Seen live 2026-09-05: blocking on
      // 30 readings made the first visit to a wide viewport take ~85s, and
      // backgrounding unconditionally delivered Bakewell's 7 stations with
      // no wind at all because nothing told the screen the readings landed.
      if (!skipReadings && !superseded()) {
        final pendingCount = _stationsNeedingReadings(bounds).length;
        if (pendingCount > 0 && pendingCount <= _maxBlockingReadings) {
          await _refreshReadings(apiKey, bounds, superseded);
        } else if (pendingCount > 0) {
          _scheduleReadingPass(apiKey, bounds);
        }
      }
      _measurementsTimestamp ??= DateTime.now();

      return _stationsInBounds(bounds);
    } catch (e, stackTrace) {
      LoggingService.error('Failed to fetch WU PWS stations', e, stackTrace);
      return [];
    }
  }

  /// Whether a background reading pass is running (prevents overlap).
  bool _readingsRunning = false;

  /// Stations in [bounds] whose readings are missing or past the TTL.
  List<DiscoveredPwsStation> _stationsNeedingReadings(LatLngBounds bounds) {
    final inBounds = discovered.values
        .where((s) =>
            !s.isStale &&
            bounds.contains(LatLng(s.latitude, s.longitude)))
        .toList();
    return inBounds.where((s) {
      final fetched = s.readingFetchedAt;
      if (fetched == null) return true;
      return DateTime.now().difference(fetched) >
          MapConstants.wuMeasurementsCacheTTL;
    }).toList();
  }

  /// Fire-and-forget reading pass. Only one runs at a time; a request while
  /// one is running is dropped - the stations needing refresh will be picked
  /// up by the next viewport pass, which re-checks ages anyway.
  void _scheduleReadingPass(String apiKey, LatLngBounds bounds) {
    if (_readingsRunning) {
      LoggingService.info('WU PWS reading pass already running, skipping');
      return;
    }
    final generationAtSchedule = _generation;
    _readingsRunning = true;
    unawaited(() async {
      try {
        await _refreshReadings(
          apiKey,
          bounds,
          () => generationAtSchedule != _generation,
        );
      } finally {
        _readingsRunning = false;
      }
    }());
  }

  @override
  Future<void> warmCache() async {
    // Deliberately a no-op, unlike the other providers: Pioupiou/FFVL have
    // global list endpoints where one warm call pre-loads everything, but WU
    // discovery is point-based - a world warm-up spends ~12 probe calls on
    // random grid points that may never be visited. Gap probing makes
    // on-demand discovery cheap, so the first real viewport fetch discovers
    // what it needs instead. This also stops the warm-up blocking the first
    // viewport pass in the fetch queue (seen live: ~23s head-of-line wait).
  }

  @override
  Future<Map<String, WindData>> fetchWeatherData(
    List<WeatherStation> stations,
  ) async {
    if (stations.isEmpty) return {};

    // Readings are attached during discovery (probes trigger a reading
    // refresh), so just extract them by station key - like FFVL.
    final Map<String, WindData> result = {};
    for (final station in stations) {
      if (station.windData != null) {
        result[station.key] = station.windData!;
      }
    }

    LoggingService.structured('WU_PWS_WEATHER_EXTRACTED', {
      'total_stations': stations.length,
      'stations_with_data': result.length,
    });

    return result;
  }

  @override
  void clearCache() {
    discovered.clear();
    _measurementsTimestamp = null;
    unawaited(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_cachePrefsKey);
      } catch (_) {}
    }());
    LoggingService.info('WU PWS cache cleared (incl. persisted)');
  }

  @override
  Map<String, dynamic> getCacheStats() {
    return {
      'cached': discovered.isNotEmpty,
      'total_stations': discovered.length,
      'fresh_stations': _freshCount,
      'stations_with_data':
          discovered.values.where((s) => s.windData != null).length,
      'measurements_age_minutes': _measurementsTimestamp == null
          ? null
          : DateTime.now().difference(_measurementsTimestamp!).inMinutes,
    };
  }

  // --- discovery internals -------------------------------------------------

  int get _discoveredCount => discovered.length;

  int get _freshCount =>
      discovered.values.where((s) => !s.isStale).length;

  /// Sample points covering [bounds], keeping only those not within the
  /// coverage radius of an already-known fresh station. An empty result means
  /// the viewport can be served entirely from the cache.
  @visibleForTesting
  List<LatLng> uncoveredProbePoints(LatLngBounds bounds) {
    final fresh = discovered.values
        .where((s) => !s.isStale && s.coverageRadiusKm > 0)
        .toList();

    final south = bounds.south;
    final north = bounds.north;
    final west = bounds.west;
    final east = bounds.east;

    final spacingDeg = _probeSpacingDeg();
    final latSteps = ((north - south) / spacingDeg).ceil().clamp(1, 3);
    final lonSteps = ((east - west) / spacingDeg).ceil().clamp(1, 4);

    final grid = <LatLng>[];
    for (int i = 0; i <= latSteps; i++) {
      for (int j = 0; j <= lonSteps; j++) {
        grid.add(LatLng(
          south + (north - south) * i / latSteps,
          west + (east - west) * j / lonSteps,
        ));
      }
    }

    final probes = grid.where((p) => !_isCovered(p, fresh)).toList();
    if (probes.length > _maxProbesPerViewport) {
      probes.removeRange(_maxProbesPerViewport, probes.length);
    }

    LoggingService.structured('WU_PWS_PROBE_PLAN', {
      'grid_points': grid.length,
      'uncovered_probes': probes.length,
      'known_stations': fresh.length,
    });
    return probes;
  }

  /// Grid spacing in degrees so probe discs overlap the coverage radius.
  /// Latitude only: longitude shrinkage at high latitudes only makes discs
  /// overlap *more*, never less.
  double _probeSpacingDeg() {
    const kmPerDegLat = 111.0;
    return MapConstants.wuCoverageRadiusKm * _probeSpacingFactor / kmPerDegLat;
  }

  bool _isCovered(LatLng point, List<DiscoveredPwsStation> fresh) {
    for (final station in fresh) {
      if (_distanceKm(point.latitude, point.longitude, station.latitude,
              station.longitude) <
          MapConstants.wuCoverageRadiusKm) {
        return true;
      }
    }
    return false;
  }

  /// Backing store for the discovered-station cache, so discovery survives  /// an app restart - station locations are a property of the world, not of
  /// the session. Without this every restart re-probed 12 points for an
  /// already-explored area (seen live 2026-09-05: a restart discarded 118
  /// known stations and re-probed 12 points at ~2s each).
  static const String _cachePrefsKey = 'wu_pws_discovered_stations_v1';

  Future<void> _loadPersistedCache() async {
    if (_cacheLoaded) return;
    _cacheLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cachePrefsKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      for (final entry in decoded) {
        if (entry is! Map<String, dynamic>) continue;
        final s = DiscoveredPwsStation.fromJson(entry);
        if (s != null) discovered.putIfAbsent(s.id, () => s);
      }
      LoggingService.structured('WU_PWS_CACHE_LOADED', {
        'stations': discovered.length,
      });
    } catch (e) {
      LoggingService.error('Failed to load WU PWS discovery cache', e);
    }
  }

  /// Persist after discovery changes. Immediate (not debounced): a hot
  /// restart or quick app kill never fired the old 5s debounce, so the
  /// freshly probed area was re-probed on the next start - the exact cost
  /// persistence exists to avoid.
  Future<void> _persistCacheNow() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Persist position + identity only - readings age out and are
      // re-fetched; staleness is judged at read time.
      final json =
          discovered.values.take(500).map((s) => s.toJson()).toList();
      await prefs.setString(_cachePrefsKey, jsonEncode(json));
      LoggingService.structured('WU_PWS_CACHE_PERSISTED', {
        'stations': json.length,
      });
    } catch (e) {
      LoggingService.error('Failed to persist WU PWS discovery cache', e);
    }
  }

  /// Probe one point via v3/location/near, merging results into the cache.
  Future<void> _probePoint(LatLng point, String apiKey) async {
    await _throttle();

    final stopwatch = Stopwatch()..start();
    final uri = Uri.parse(
      '$_nearUrl'
      '?geocode=${point.latitude.toStringAsFixed(4)},${point.longitude.toStringAsFixed(4)}'
      '&product=pws&format=json&apiKey=$apiKey',
    );

    LoggingService.structured('WU_PWS_REQUEST_START', {
      'url': _nearUrl,
      'geocode': '${point.latitude.toStringAsFixed(4)},${point.longitude.toStringAsFixed(4)}',
      'key': '***',
    });

    final http.Response response;
    try {
      response = await http.get(uri, headers: {
        'Accept': 'application/json',
        'User-Agent': 'TheParaglidingApp/1.0',
      }).timeout(const Duration(seconds: 30));
    } on TimeoutException {
      LoggingService.structured('WU_PWS_TIMEOUT', {
        'endpoint': 'location_near',
        'duration_ms': stopwatch.elapsedMilliseconds,
      });
      return;
    }

    if (response.statusCode != 200) {
      LoggingService.structured('WU_PWS_HTTP_ERROR', {
        'endpoint': 'location_near',
        'status_code': response.statusCode,
      });
      return;
    }

    final Map<String, dynamic>? decoded = _tryDecode(response.body);
    if (decoded == null) return;

    final location = decoded['location'];
    if (location is! Map<String, dynamic>) return;
    final ids = location['stationId'];
    if (ids is! List) return;

    int added = 0;
    for (int i = 0; i < ids.length; i++) {
      final id = ids[i]?.toString();
      final lat = _asDouble(_at(location['latitude'], i));
      final lon = _asDouble(_at(location['longitude'], i));
      if (id == null || lat == null || lon == null) continue;

      final distanceKm = _asDouble(_at(location['distanceKm'], i));
      final station = DiscoveredPwsStation(
        id: id,
        name: _at(location['stationName'], i)?.toString(),
        latitude: lat,
        longitude: lon,
        distanceKm: distanceKm,
        qcStatus: _asInt(_at(location['qcStatus'], i)),
        updateTimeUtc: _parseTime(_at(location['updateTimeUtc'], i)),
        coverageRadiusKm: distanceKm ?? 0,
      );

      if (!discovered.containsKey(id)) added++;
      discovered[id] = station;
    }

    LoggingService.structured('WU_PWS_PROBE_DONE', {
      'returned': ids.length,
      'new_stations': added,
      'total_stations': _discoveredCount,
      'duration_ms': stopwatch.elapsedMilliseconds,
    });
  }

  /// Fetch current observations for stations within [bounds] whose readings
  /// are missing or older than the measurements TTL.
  ///
  /// Runs ONCE per fetch pass, after all probes - not per probe. Re-scanning
  /// the whole cache after every probe made a pass take minutes (every call
  /// throttled to 30/min) and starved the map of stations. At most
  /// [_maxReadingsPerPass] stations are refreshed per pass so a world-sized
  /// warm pass can't hog the rate limit; stations that answered without data
  /// (HTTP 204) get their attempt stamped too, so they retry no more often
  /// than the TTL instead of on every pass.
  Future<void> _refreshReadings(
    String apiKey,
    LatLngBounds bounds,
    bool Function() superseded,
  ) async {
    final inBounds = discovered.values
        .where((s) =>
            !s.isStale &&
            bounds.contains(LatLng(s.latitude, s.longitude)))
        .toList();
    final needsReading = _stationsNeedingReadings(bounds);
    if (needsReading.length > _maxReadingsPerPass) {
      needsReading.removeRange(_maxReadingsPerPass, needsReading.length);
    }
    if (needsReading.isEmpty) return;

    LoggingService.structured('WU_PWS_READING_PASS', {
      'in_bounds': inBounds.length,
      'to_refresh': needsReading.length,
    });

    for (final station in needsReading) {
      if (superseded()) {
        LoggingService.structured('WU_PWS_ABORTED', {
          'stage': 'readings',
          'readings_done': needsReading.indexOf(station),
          'readings_total': needsReading.length,
        });
        return;
      }
      await _throttle();
      final stopwatch = Stopwatch()..start();
      try {
        final uri = Uri.parse(
          '$_currentUrl?stationId=${station.id}&format=json&units=m'
          '&apiKey=$apiKey',
        );
        final response = await http.get(uri, headers: {
          'Accept': 'application/json',
          'User-Agent': 'TheParaglidingApp/1.0',
        }).timeout(const Duration(seconds: 30));

        if (response.statusCode != 200) {
          LoggingService.structured('WU_PWS_HTTP_ERROR', {
            'endpoint': 'observations_current',
            'station_id': station.id,
            'status_code': response.statusCode,
          });
          // Stamp the attempt (204 = station silent) so it retries no more
          // often than the TTL instead of on every pass.
          station.readingFetchedAt = DateTime.now();
          continue;
        }

        final decoded = _tryDecode(response.body);
        if (decoded == null) continue;
        final obsList = decoded['observations'];
        if (obsList is! List || obsList.isEmpty) {
          station.readingFetchedAt = DateTime.now();
          continue;
        }
        final obs = obsList.first;
        if (obs is! Map<String, dynamic>) continue;

        // Stamp before parsing: a record without wind (temp-only PWS) must
        // not be re-fetched every pass either.
        station.readingFetchedAt = DateTime.now();
        // The observation's own time becomes the staleness anchor - this is
        // what lets a restored (unknown-freshness) station converge to real
        // staleness instead of staying "assumed alive" forever.
        station.updateTimeUtc ??= _parseTime(obs['obsTimeUtc']);
        final wind = _parseWind(obs);
        if (wind != null) {
          station.windData = wind;
        }
        LoggingService.structured('WU_PWS_READING_OK', {
          'station_id': station.id,
          'has_wind': wind != null,
          'duration_ms': stopwatch.elapsedMilliseconds,
        });
      } on TimeoutException {
        LoggingService.structured('WU_PWS_TIMEOUT', {
          'endpoint': 'observations_current',
          'station_id': station.id,
        });
      } catch (e) {
        LoggingService.error(
          'Failed to refresh WU PWS reading for ${station.id}',
          e,
        );
      }
    }
  }

  /// Parse wind from a pws/observations/current observation record.
  @visibleForTesting
  WindData? parseWind(Map<String, dynamic> obs) => _parseWind(obs);

  WindData? _parseWind(Map<String, dynamic> obs) {
    final metric = obs['metric'];
    // observations/current names: metric.windSpeed/windGust, top-level winddir.
    // (windspeedAvg/winddirAvg are the pws/history/all names - accepted as
    // fallbacks so a shared parser stays honest if reused.)
    final speed = metric is Map<String, dynamic>
        ? _asDouble(metric['windSpeed'] ?? metric['windspeedAvg'])
        : null;
    final gust = metric is Map<String, dynamic>
        ? _asDouble(metric['windGust'] ?? metric['windspeedHigh'])
        : null;
    final dir = _asDouble(obs['winddir'] ?? obs['winddirAvg']);
    if (speed == null || dir == null) return null;

    return WindData(
      speedKmh: speed,
      gustsKmh: gust,
      directionDegrees: dir,
      timestamp:
          _parseTime(obs['obsTimeUtc']) ?? DateTime.now().toUtc(),
    );
  }

  /// Convert discovered stations within bounds to [WeatherStation]s, dropping
  /// stale ones so the map never shows dead stations.
  List<WeatherStation> _stationsInBounds(LatLngBounds bounds) {    final stations = <WeatherStation>[];
    int staleCount = 0;

    for (final s in discovered.values) {
      if (s.isStale) {
        staleCount++;
        continue;
      }
      if (!bounds.contains(LatLng(s.latitude, s.longitude))) continue;

      stations.add(WeatherStation(
        id: s.id,
        source: source,
        name: s.name,
        latitude: s.latitude,
        longitude: s.longitude,
        windData: s.windData,
        observationType: s.qcStatus == 1 ? 'WU PWS (QC passed)' : 'WU PWS',
        dataUrl: 'https://www.wunderground.com/dashboard/pws/${s.id}',
      ));
    }

    LoggingService.structured('WU_PWS_BBOX_FILTER', {
      'total_stations': _discoveredCount,
      'stale_skipped': staleCount,
      'filtered_count': stations.length,
      'bounds':
          '${bounds.south},${bounds.west},${bounds.north},${bounds.east}',
    });

    return stations;
  }

  /// Test seam for [_stationsInBounds]: converts the current discovery cache
  /// to stations without any network access.
  @visibleForTesting
  List<WeatherStation> stationsInBoundsForTest(LatLngBounds bounds) =>
      _stationsInBounds(bounds);

  /// Wait so probe + reading calls together never exceed 30/minute.
  Future<void> _throttle() async {
    final now = DateTime.now();
    final elapsed = now.difference(_lastRequestAt);
    if (elapsed < _minRequestInterval) {
      await Future.delayed(_minRequestInterval - elapsed);
    }
    _lastRequestAt = DateTime.now();
  }

  static dynamic _at(dynamic list, int index) =>
      list is List && index < list.length ? list[index] : null;

  static double? _asDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static int? _asInt(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static DateTime? _parseTime(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  static Map<String, dynamic>? _tryDecode(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (e) {
      LoggingService.error('WU PWS: invalid JSON response', e);
      return null;
    }
  }

  /// Great-circle distance in km (haversine).
  @visibleForTesting
  double distanceKm(double lat1, double lon1, double lat2, double lon2) =>
      _distanceKm(lat1, lon1, lat2, lon2);

  double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLon = _degToRad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(lat1)) *
            math.cos(_degToRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return 2 * r * math.asin(math.sqrt(a));
  }

  double _degToRad(double deg) => deg * math.pi / 180.0;
}

/// A station learned from a v3/location/near response.
///
/// Mutable so wind readings can be refreshed in place without rebuilding the
/// cache map.
class DiscoveredPwsStation {
  final String id;
  final String? name;
  final double latitude;
  final double longitude;
  final double? distanceKm;
  final int? qcStatus;

  /// Distance from the probe point that discovered this station, reused as a
  /// rough "already covered" radius for gap probing.
  final double coverageRadiusKm;

  WindData? windData;
  DateTime? readingFetchedAt;

  /// Last known report time. Mutable: after a cache restore it is null
  /// (unknown, assumed alive) and the first successful reading sets it.
  DateTime? updateTimeUtc;

  DiscoveredPwsStation({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.distanceKm,
    required this.qcStatus,
    required this.updateTimeUtc,
    required this.coverageRadiusKm,
  });

  /// True when the station hasn't reported within the staleness cutoff -
  /// dead stations are dropped from the map.
  ///
  /// A null updateTimeUtc means freshness is UNKNOWN (fresh from a probe
  /// response that omitted it, or a cache restore) - assume alive and let the
  /// next reading pass stamp it. Treating unknown as stale made every
  /// restored station vanish from coverage AND from the map (seen live:
  /// 131 stations restored, PROBE_PLAN still reported known_stations=0).
  bool get isStale {
    final updated = updateTimeUtc;
    if (updated == null) return false;
    return DateTime.now().difference(updated) >
        MapConstants.wuStaleObservationCutoff;
  }

  /// Persisted form: identity + position only. Readings and timestamps are
  /// deliberately excluded - they age out and are re-fetched on demand.
  Map<String, dynamic> toJson() => {
        'id': id,
        if (name != null) 'name': name,
        'lat': latitude,
        'lon': longitude,
        'cov': coverageRadiusKm,
      };

  static DiscoveredPwsStation? fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString();
    final lat = (json['lat'] as num?)?.toDouble();
    final lon = (json['lon'] as num?)?.toDouble();
    if (id == null || id.isEmpty || lat == null || lon == null) return null;
    return DiscoveredPwsStation(
      id: id,
      name: json['name']?.toString(),
      latitude: lat,
      longitude: lon,
      distanceKm: null,
      qcStatus: null,
      updateTimeUtc: null, // unknown after restore; will refresh on fetch
      coverageRadiusKm: (json['cov'] as num?)?.toDouble() ?? 0,
    );
  }
}

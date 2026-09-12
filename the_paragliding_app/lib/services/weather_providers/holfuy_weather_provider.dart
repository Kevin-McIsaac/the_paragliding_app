import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../data/models/holfuy_reading.dart';
import '../../data/models/holfuy_station_catalogue.dart';
import '../../data/models/weather_station.dart';
import '../../data/models/weather_station_source.dart';
import '../../data/models/wind_data.dart';
import '../../utils/map_constants.dart';
import '../holfuy_stations_download_service.dart';
import '../logging_service.dart';
import 'weather_station_provider.dart';

/// Holfuy paragliding wind stations, as a map layer.
///
/// Holfuy publishes **no discovery endpoint**: not a WU-style "what is near
/// this point", and not a bulk list. Positions therefore come from the station
/// catalogue the federation builds and publishes, which the app fetches at
/// runtime and bundles as a fallback - see [HolfuyStationsDownloadService].
///
/// Readings are the deliberate exception to how every other provider here
/// works. Holfuy's official API is password-gated **per station** with a
/// documented ceiling of three, and its own monitor page politely refuses a
/// multi-station request by pointing at that API. So a live wind layer over
/// 1,537 stations is not a provider away: it is one request per station against
/// an operator who has said no.
///
/// The split that follows:
///
/// - **[fetchStations] is free.** It reads the local catalogue and issues no
///   Holfuy request at all.
/// - **[fetchWeatherData] never fans out.** The service calls it with every
///   station of this source, so it returns cached readings only. A pan across
///   the Alps must not become hundreds of scrapes.
/// - **[requestReading] is the whole live path**, and it runs only when a pilot
///   taps one station: single-flight, serialized, at least
///   [MapConstants.holfuyMinRequestInterval] apart, cached for
///   [MapConstants.holfuyReadingCacheTTL].
class HolfuyWeatherProvider implements WeatherStationProvider {
  static final HolfuyWeatherProvider instance = HolfuyWeatherProvider._();
  HolfuyWeatherProvider._();

  static const String widgetUrl = 'https://widget.holfuy.com/';
  static const Duration _timeout = Duration(seconds: 20);

  http.Client _httpClient = http.Client();

  @visibleForTesting
  set httpClientForTest(http.Client client) => _httpClient = client;

  /// Readings fetched this session, by station id, and when.
  final Map<String, WindData> _readings = {};
  final Map<String, DateTime> _readingFetchedAt = {};

  /// One in-flight request per station, so a double tap is one request.
  final Map<String, Future<HolfuyReading>> _pending = {};

  /// The serialization point: requests chain here so pacing holds across
  /// stations, not just within one.
  Future<void>? _queue;
  DateTime _lastRequestAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  WeatherStationSource get source => WeatherStationSource.holfuy;

  @override
  bool get pushesProgressively => false;

  @override
  String get displayName => 'Holfuy';

  @override
  String get description => 'Launch-site wind stations (worldwide)';

  @override
  String get attributionName => HolfuyStationCatalogue.defaultAttribution;

  @override
  String get attributionUrl => HolfuyStationCatalogue.defaultAttributionUrl;

  @override
  Duration get cacheTTL => MapConstants.holfuyReadingCacheTTL;

  @override
  bool get requiresApiKey => false;

  @override
  Future<bool> isConfigured() async => true;

  /// Refresh the published station file if it may have moved. This is the only
  /// startup network work, and it is a HEAD that almost always says "unchanged".
  @override
  Future<void> warmCache() async {
    await HolfuyStationsDownloadService.instance.ensureFresh();
  }

  /// Stations inside [bounds], from the local catalogue. No network.
  @override
  Future<List<WeatherStation>> fetchStations(
    LatLngBounds bounds, {
    Function()? onApiCallStart,
    void Function(List<WeatherStation> stations, {bool passComplete})?
        onStationsUpdated,
  }) async {
    try {
      final catalogue =
          await HolfuyStationsDownloadService.instance.loadCatalogue();

      if (!catalogue.isComplete) {
        LoggingService.structured('HOLFUY_CATALOGUE_INCOMPLETE', {
          'stations': catalogue.length,
          'skipped': catalogue.skipped,
        });
      }

      final inBounds = catalogue.stations
          .where((s) => bounds.contains(LatLng(s.latitude, s.longitude)))
          .map((s) => s.copyWith(windData: _cachedReading(s.id)))
          .toList();

      LoggingService.structured('HOLFUY_BBOX_FILTER', {
        'total_stations': catalogue.length,
        'filtered_count': inBounds.length,
        'bounds': '${bounds.south},${bounds.west},${bounds.north},${bounds.east}',
      });

      return inBounds;
    } catch (error, stackTrace) {
      LoggingService.error('Failed to load Holfuy stations', error, stackTrace);
      return [];
    }
  }

  /// Cached readings only - never a network call.
  ///
  /// [WeatherStationService] calls this with every station of a source after
  /// each viewport fetch. For every other provider that is a local map or a
  /// bounded API call; for Holfuy it must be a no-op fan-out, or one pan would
  /// scrape hundreds of stations and earn the block Holfuy's message is aimed
  /// at. Live wind arrives through [requestReading] instead.
  @override
  Future<Map<String, WindData>> fetchWeatherData(
    List<WeatherStation> stations,
  ) async {
    if (stations.isEmpty) return {};

    final result = <String, WindData>{};
    for (final station in stations) {
      final cached = station.windData ?? _cachedReading(station.id);
      if (cached != null) result[station.key] = cached;
    }

    LoggingService.structured('HOLFUY_WEATHER_EXTRACTED', {
      'total_stations': stations.length,
      'stations_with_data': result.length,
    });

    return result;
  }

  /// Fetch one station's current wind, on demand.
  ///
  /// A station whose reading is still fresh is answered from cache without a
  /// request. Concurrent taps for the same station share one request, and
  /// different stations are serialized behind the same pace.
  Future<HolfuyReading> requestReading(String stationId) {
    final cached = _cachedReading(stationId);
    if (cached != null) return Future.value(HolfuyReading.ok(cached));

    final pending = _pending[stationId];
    if (pending != null) return pending;

    final future = _enqueueReading(stationId);
    _pending[stationId] = future;
    unawaited(future.whenComplete(() {
      if (identical(_pending[stationId], future)) _pending.remove(stationId);
    }));
    return future;
  }

  WindData? _cachedReading(String stationId) {
    final wind = _readings[stationId];
    final at = _readingFetchedAt[stationId];
    if (wind == null || at == null) return null;
    if (DateTime.now().difference(at) > MapConstants.holfuyReadingCacheTTL) {
      return null;
    }
    return wind;
  }

  Future<HolfuyReading> _enqueueReading(String stationId) {
    final previous = _queue ?? Future<void>.value();
    final task = previous.catchError((_) {}).then((_) async {
      // Re-check inside the queue: another tap may have filled the cache while
      // this one waited its turn.
      final cached = _cachedReading(stationId);
      if (cached != null) return HolfuyReading.ok(cached);
      await _throttle();
      return _fetchReading(stationId);
    });
    _queue = task.then((_) {}, onError: (_) {});
    return task;
  }

  Future<HolfuyReading> _fetchReading(String stationId) async {
    final stopwatch = Stopwatch()..start();
    try {
      final uri = Uri.parse(
        '$widgetUrl?station=$stationId&mode=detailed&su=km/h',
      );
      final response = await _httpClient.get(uri, headers: {
        'Accept': 'text/html',
        'User-Agent': 'TheParaglidingApp/1.0',
      }).timeout(_timeout);

      if (response.statusCode != 200) {
        LoggingService.structured('HOLFUY_READING_HTTP_ERROR', {
          'station_id': stationId,
          'status_code': response.statusCode,
        });
        return const HolfuyReading.unavailable();
      }

      final reading = parseReading(response.body);
      final wind = reading.wind;

      if (wind != null) {
        _readings[stationId] = wind;
        _readingFetchedAt[stationId] = DateTime.now();
        LoggingService.structured('HOLFUY_READING_OK', {
          'station_id': stationId,
          'speed_kmh': wind.speedKmh,
          'direction_deg': wind.directionDegrees,
          'duration_ms': stopwatch.elapsedMilliseconds,
        });
      } else {
        // Deliberately not cached: a station that is flat today may be back
        // tomorrow, and tapping again is how a pilot finds out. Only a real
        // reading is worth remembering.
        LoggingService.structured(
          reading.status == HolfuyReadingStatus.offline
              ? 'HOLFUY_READING_OFFLINE'
              : 'HOLFUY_READING_UNAVAILABLE',
          {
            'station_id': stationId,
            'reason': reading.offlineReason,
            'last_update': reading.lastUpdate,
            'duration_ms': stopwatch.elapsedMilliseconds,
          },
        );
      }

      return reading;
    } catch (error, stackTrace) {
      LoggingService.error(
          'Failed to read Holfuy station $stationId', error, stackTrace);
      return const HolfuyReading.unavailable();
    }
  }

  /// Parse the monitor page's own HTML into a reading, an offline state, or a
  /// failure.
  ///
  /// The reading contract, verified against station 142
  /// (`?station=142&mode=detailed`):
  ///
  /// - `id="j_speed">19<` - current speed, **km/h** because the request pinned
  ///   `su=km/h`.
  /// - `id="j_gust">25<` - current gust, same unit.
  /// - `var owind=[[13,248],[15,266],[20,281],[19,275]];` - history as
  ///   `[speed, degrees]`; the last pair carries the direction in degrees.
  ///   `id="j_dir"` is only cardinal (`W`), which is not good enough to steer a
  ///   flyability calculation from.
  /// - `id="act_date"><b>113</b> sec. ago` - the reading's age.
  /// - `var units ={"speed":"km\/h",...}` - **asserted, not assumed**. If the
  ///   server did not honour `su=km/h`, the numbers are m/s and a 3.6x error
  ///   looks entirely plausible; this refuses rather than guesses.
  ///
  /// The order is load-bearing. A usable reading is accepted first, so a station
  /// that has come back online is never mislabelled. Only then does the
  /// station's *own* explanation count - "Battery is empty! Waiting for Sun..."
  /// is information, not a failure, and these solar stations spend a lot of
  /// time that way. What is left is a genuine contract mismatch.
  @visibleForTesting
  static HolfuyReading parseReading(String html, {DateTime? now}) {
    final wind = _windFromPage(html, now: now);
    if (wind != null) return HolfuyReading.ok(wind);

    final reason = _offlineReason(html);
    if (reason != null) {
      return HolfuyReading.offline(
        reason: reason,
        lastUpdate: _lastUpdateText(html),
      );
    }

    if (_declaredSpeedUnit(html) != 'km/h') {
      LoggingService.structured('HOLFUY_READING_UNIT_REJECTED', {
        'declared_unit': _declaredSpeedUnit(html) ?? 'missing',
      });
    }
    return const HolfuyReading.unavailable();
  }

  /// The wind reading alone, for callers that only care whether there is one.
  @visibleForTesting
  static WindData? parseReadingHtml(String html, {DateTime? now}) =>
      _windFromPage(html, now: now);

  static WindData? _windFromPage(String html, {DateTime? now}) {
    if (_declaredSpeedUnit(html) != 'km/h') return null;

    final speed = _spanDouble(html, _speedPattern);
    if (speed == null) return null; // offline, or no usable value

    final direction = _directionDegrees(html);
    if (direction == null) return null;

    final ageSeconds = _ageSeconds(html) ?? 0;
    final observedAt = (now ?? DateTime.now().toUtc())
        .toUtc()
        .subtract(Duration(seconds: ageSeconds));

    return WindData(
      speedKmh: speed,
      gustsKmh: _spanDouble(html, _gustPattern),
      directionDegrees: direction,
      timestamp: observedAt,
    );
  }

  static final RegExp _speedPattern = RegExp(r'id="j_speed"[^>]*>([^<]*)<');
  static final RegExp _gustPattern = RegExp(r'id="j_gust"[^>]*>([^<]*)<');
  static final RegExp _unitsPattern = RegExp(r'"speed"\s*:\s*"([^"]+)"');
  static final RegExp _owindPattern = RegExp(r'owind\s*=\s*(\[\[.*?\]\])');
  static final RegExp _pairPattern =
      RegExp(r'\[\s*([-0-9.]+)\s*,\s*([-0-9.]+)\s*\]');
  static final RegExp _agePattern =
      RegExp(r'id="act_date"[^>]*>\s*<b>(\d+)</b>');

  /// The unit the page says it is using, with JSON's `\/` unescaped.
  static String? _declaredSpeedUnit(String html) {
    final match = _unitsPattern.firstMatch(html);
    if (match == null) return null;
    return match.group(1)!.replaceAll(r'\', '');
  }

  static double? _spanDouble(String html, RegExp pattern) {
    final match = pattern.firstMatch(html);
    if (match == null) return null;
    final text = match.group(1)?.trim();
    if (text == null || text.isEmpty) return null;
    final value = double.tryParse(text);
    if (value == null || !value.isFinite) return null;
    return value;
  }

  /// The most recent direction in degrees, from the wind history array.
  static double? _directionDegrees(String html) {
    final arrayMatch = _owindPattern.firstMatch(html);
    if (arrayMatch == null) return null;
    final pairs = _pairPattern.allMatches(arrayMatch.group(1)!);
    if (pairs.isEmpty) return null;
    final last = pairs.last.group(2);
    if (last == null) return null;
    final value = double.tryParse(last);
    if (value == null || !value.isFinite) return null;
    if (value < 0 || value > 360) return null;
    return value;
  }

  static int? _ageSeconds(String html) {
    final match = _agePattern.firstMatch(html);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  static final RegExp _lastUpdatePattern = RegExp(
    r'Last update\s*:?\s*(\d{4}-[A-Za-z]{3}-\d{1,2}\s+\d{1,2}:\d{2}(?::\d{2})?(?:\s+[A-Z]{2,6})?)',
    caseSensitive: false,
  );

  /// Words that mean "this station is telling you why it is silent" rather than
  /// "the page did not parse".
  static const List<String> _offlineMarkers = [
    'battery',
    'offline',
    'not activated',
    'no connection',
  ];

  /// The station's own explanation for having no reading.
  ///
  /// Holfuy's widget server-renders this - the monitor page fills it in with
  /// JavaScript, which does not run here - e.g. "Battery is empty! Waiting for
  /// Sun... Last update:2026-Sep-10 13:55:53 AEST". The reason is the text
  /// before that timestamp.
  static String? _offlineReason(String html) {
    final text = _plainText(html);
    final lower = text.toLowerCase();
    if (!_offlineMarkers.any(lower.contains)) return null;

    var reason = text;
    final lastUpdateAt = lower.indexOf('last update');
    if (lastUpdateAt > 0) reason = text.substring(0, lastUpdateAt);
    reason = reason.trim();
    if (reason.isEmpty) reason = text.trim();
    if (reason.length > 160) reason = '${reason.substring(0, 157)}...';
    return reason.isEmpty ? null : reason;
  }

  /// The page's "Last update:" text, kept verbatim - it carries a timezone
  /// abbreviation (`AEST`) that `DateTime.parse` rejects, and showing Holfuy's
  /// own words beats a guessed conversion.
  static String? _lastUpdateText(String html) =>
      _lastUpdatePattern.firstMatch(_plainText(html))?.group(1)?.trim();

  /// Visible text: scripts, styles and tags removed, whitespace collapsed.
  static String _plainText(String html) {
    return html
        .replaceAll(
            RegExp(r'<script[^>]*>.*?</script>',
                dotAll: true, caseSensitive: false),
            ' ')
        .replaceAll(
            RegExp(r'<style[^>]*>.*?</style>',
                dotAll: true, caseSensitive: false),
            ' ')
        .replaceAll(
            RegExp(r'<title[^>]*>.*?</title>',
                dotAll: true, caseSensitive: false),
            ' ')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'&[a-z]+;', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<void> _throttle() async {
    final elapsed = DateTime.now().difference(_lastRequestAt);
    if (elapsed < MapConstants.holfuyMinRequestInterval) {
      await Future.delayed(MapConstants.holfuyMinRequestInterval - elapsed);
    }
    _lastRequestAt = DateTime.now();
  }

  /// Drop readings, keep the station catalogue - positions cost a download,
  /// readings are re-fetched on demand anyway.
  @override
  void clearCache() {
    final dropped = _readings.length;
    _readings.clear();
    _readingFetchedAt.clear();
    LoggingService.structured('HOLFUY_READINGS_CLEARED', {
      'readings': dropped,
    });
  }

  @visibleForTesting
  void clearCacheForTest() {
    _readings.clear();
    _readingFetchedAt.clear();
    _pending.clear();
    _queue = null;
    _lastRequestAt = DateTime.fromMillisecondsSinceEpoch(0);
  }

  @override
  Map<String, dynamic> getCacheStats() {
    return {
      'readings_cached': _readings.length,
      'requests_in_flight': _pending.length,
    };
  }
}

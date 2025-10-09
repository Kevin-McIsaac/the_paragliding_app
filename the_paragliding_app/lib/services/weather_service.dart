import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../data/models/wind_data.dart';
import '../utils/site_utils.dart';
import 'logging_service.dart';

/// Service for fetching weather data from Open-Meteo API
class WeatherService {
  static final WeatherService instance = WeatherService._();
  WeatherService._();

  /// Cache for wind data: "lat_lon_hour" -> WindData
  final Map<String, WindData> _cache = {};

  /// Cache for pending requests to prevent duplicate API calls
  final Map<String, Future<WindData?>> _pendingRequests = {};

  /// Cache for pending batch requests to prevent duplicate batch API calls
  final Map<String, Future<Map<String, WindData>>> _pendingBatchRequests = {};

  /// Maximum number of locations per batch request
  static const int maxBatchSize = 100;

  /// Get wind data for a specific location and time
  Future<WindData?> getWindData(
    double lat,
    double lon,
    DateTime dateTime,
  ) async {
    // Generate cache key
    final cacheKey = _getCacheKey(lat, lon, dateTime);

    // Check cache first
    if (_cache.containsKey(cacheKey)) {
      LoggingService.info('Weather cache hit for $cacheKey');
      return _cache[cacheKey];
    }

    // Check if request is already pending
    if (_pendingRequests.containsKey(cacheKey)) {
      LoggingService.info('Waiting for pending weather request: $cacheKey');
      return _pendingRequests[cacheKey];
    }

    // Create new request
    final future = _fetchWindData(lat, lon, dateTime, cacheKey);
    _pendingRequests[cacheKey] = future;

    try {
      final result = await future;
      return result;
    } finally {
      _pendingRequests.remove(cacheKey);
    }
  }

  /// Fetch wind data from Open-Meteo API
  Future<WindData?> _fetchWindData(
    double lat,
    double lon,
    DateTime dateTime,
    String cacheKey,
  ) async {
    try {
      LoggingService.info('Fetching weather data for $lat, $lon at ${dateTime.toIso8601String()}');

      // Build API URL
      final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$lat&longitude=$lon'
        '&hourly=wind_speed_10m,wind_direction_10m,wind_gusts_10m'
        '&wind_speed_unit=kmh'
        '&forecast_days=7'
        '&timezone=auto',
      );

      // Make API request
      final response = await http.get(url).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          LoggingService.error('Weather API timeout for $lat, $lon');
          throw TimeoutException('Weather API request timed out');
        },
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);

        // Parse hourly data
        final hourlyData = json['hourly'] as Map<String, dynamic>;
        final times = List<String>.from(hourlyData['time']);
        final windSpeeds = List<num>.from(hourlyData['wind_speed_10m']);
        final windDirections = List<num>.from(hourlyData['wind_direction_10m']);
        final windGusts = List<num>.from(hourlyData['wind_gusts_10m']);

        // Find the closest hour to requested time
        final index = _findClosestTimeIndex(times, dateTime);

        if (index >= 0 && index < times.length) {
          final windData = WindData(
            speedKmh: windSpeeds[index].toDouble(),
            directionDegrees: windDirections[index].toDouble(),
            gustsKmh: windGusts[index].toDouble(),
            timestamp: DateTime.parse(times[index]),
          );

          // Cache the result
          _cache[cacheKey] = windData;

          LoggingService.structured('WEATHER_DATA_FETCHED', {
            'lat': lat,
            'lon': lon,
            'time': dateTime.toIso8601String(),
            'wind_speed': windData.speedKmh,
            'wind_direction': windData.compassDirection,
            'wind_gusts': windData.gustsKmh,
          });

          return windData;
        }
      } else {
        LoggingService.error('Weather API error: ${response.statusCode} - ${response.body}');
      }
    } catch (e, stackTrace) {
      LoggingService.error('Failed to fetch weather data', e, stackTrace);
    }

    return null;
  }

  /// Find the index of the time closest to the target
  int _findClosestTimeIndex(List<String> times, DateTime target) {
    int closestIndex = -1;
    Duration closestDiff = const Duration(days: 365);

    for (int i = 0; i < times.length; i++) {
      final time = DateTime.parse(times[i]);
      final diff = time.difference(target).abs();

      if (diff < closestDiff) {
        closestDiff = diff;
        closestIndex = i;
      }

      // If we find an exact match or close enough (within 30 minutes), use it
      if (diff.inMinutes <= 30) {
        return i;
      }
    }

    return closestIndex;
  }

  /// Generate cache key based on location (1km grid) and hour
  String _getCacheKey(double lat, double lon, DateTime dateTime) {
    // Round to approximately 1km grid (0.01 degrees ≈ 1km)
    final gridLat = (lat * 100).round() / 100;
    final gridLon = (lon * 100).round() / 100;

    // Round to hour
    final hour = DateTime(
      dateTime.year,
      dateTime.month,
      dateTime.day,
      dateTime.hour,
    );

    return '${gridLat.toStringAsFixed(2)}_${gridLon.toStringAsFixed(2)}_${hour.toIso8601String()}';
  }

  /// Get wind data for multiple locations in a single batch API call
  /// Returns a map of "lat_lon" -> WindData for successfully fetched locations
  Future<Map<String, WindData>> getWindDataBatch(
    List<LatLng> locations,
    DateTime dateTime,
  ) async {
    if (locations.isEmpty) return {};

    // Limit batch size
    if (locations.length > maxBatchSize) {
      LoggingService.info('Batch size ${locations.length} exceeds max $maxBatchSize, splitting into chunks');

      // Split into chunks and process them
      final results = <String, WindData>{};
      for (int i = 0; i < locations.length; i += maxBatchSize) {
        final end = (i + maxBatchSize < locations.length) ? i + maxBatchSize : locations.length;
        final chunk = locations.sublist(i, end);
        final chunkResults = await getWindDataBatch(chunk, dateTime);
        results.addAll(chunkResults);
      }
      return results;
    }

    // Create batch key for deduplication
    final batchKey = _createBatchKey(locations, dateTime);

    // Check if batch request is already pending
    if (_pendingBatchRequests.containsKey(batchKey)) {
      LoggingService.info('Waiting for pending batch request: $batchKey');
      return _pendingBatchRequests[batchKey]!;
    }

    // Check cache first - separate cached from uncached locations
    final results = <String, WindData>{};
    final uncachedLocations = <LatLng>[];

    for (final location in locations) {
      final cacheKey = _getCacheKey(location.latitude, location.longitude, dateTime);
      if (_cache.containsKey(cacheKey)) {
        final locationKey = SiteUtils.createSiteKey(location.latitude, location.longitude);
        results[locationKey] = _cache[cacheKey]!;
      } else {
        uncachedLocations.add(location);
      }
    }

    // If all locations are cached, return immediately
    if (uncachedLocations.isEmpty) {
      LoggingService.structured('WEATHER_BATCH_CACHE_HIT', {
        'cached_count': results.length,
        'total_requested': locations.length,
      });
      return results;
    }

    // Fetch uncached locations
    final future = _fetchWindDataBatch(uncachedLocations, dateTime);
    _pendingBatchRequests[batchKey] = future;

    try {
      final batchResults = await future;
      results.addAll(batchResults);
      return results;
    } finally {
      _pendingBatchRequests.remove(batchKey);
    }
  }

  /// Fetch wind data for multiple locations from Open-Meteo batch API
  Future<Map<String, WindData>> _fetchWindDataBatch(
    List<LatLng> locations,
    DateTime dateTime,
  ) async {
    final results = <String, WindData>{};

    try {
      final stopwatch = Stopwatch()..start();

      // Build comma-separated latitude and longitude strings
      final latitudes = locations.map((loc) => loc.latitude.toStringAsFixed(4)).join(',');
      final longitudes = locations.map((loc) => loc.longitude.toStringAsFixed(4)).join(',');

      LoggingService.structured('WEATHER_BATCH_REQUEST', {
        'location_count': locations.length,
        'time': dateTime.toIso8601String(),
      });

      // Build API URL
      final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$latitudes&longitude=$longitudes'
        '&hourly=wind_speed_10m,wind_direction_10m,wind_gusts_10m'
        '&wind_speed_unit=kmh'
        '&forecast_days=7'
        '&timezone=auto',
      );

      // Make API request
      final response = await http.get(url).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          LoggingService.error('Weather batch API timeout for ${locations.length} locations');
          throw TimeoutException('Weather batch API request timed out');
        },
      );

      if (response.statusCode == 200) {
        // Open-Meteo returns different formats:
        // - Single location: Map<String, dynamic>
        // - Multiple locations: List<dynamic>
        // Normalize to always be a list
        final jsonBody = jsonDecode(response.body);
        final jsonArray = jsonBody is List ? jsonBody : [jsonBody];

        // Process each location's response
        for (int i = 0; i < jsonArray.length && i < locations.length; i++) {
          final locationData = jsonArray[i] as Map<String, dynamic>;
          final location = locations[i];

          // Parse hourly data
          final hourlyData = locationData['hourly'] as Map<String, dynamic>;
          final times = List<String>.from(hourlyData['time']);
          final windSpeeds = List<num>.from(hourlyData['wind_speed_10m']);
          final windDirections = List<num>.from(hourlyData['wind_direction_10m']);
          final windGusts = List<num>.from(hourlyData['wind_gusts_10m']);

          // Find the closest hour to requested time
          final index = _findClosestTimeIndex(times, dateTime);

          if (index >= 0 && index < times.length) {
            final windData = WindData(
              speedKmh: windSpeeds[index].toDouble(),
              directionDegrees: windDirections[index].toDouble(),
              gustsKmh: windGusts[index].toDouble(),
              timestamp: DateTime.parse(times[index]),
            );

            // Cache the result
            final cacheKey = _getCacheKey(location.latitude, location.longitude, dateTime);
            _cache[cacheKey] = windData;

            // Add to results using SiteUtils for consistent key format
            final locationKey = SiteUtils.createSiteKey(location.latitude, location.longitude);
            results[locationKey] = windData;
          }
        }

        stopwatch.stop();

        LoggingService.structured('WEATHER_BATCH_SUCCESS', {
          'requested_count': locations.length,
          'fetched_count': results.length,
          'duration_ms': stopwatch.elapsedMilliseconds,
        });
      } else {
        LoggingService.error('Weather batch API error: ${response.statusCode} - ${response.body}');
      }
    } catch (e, stackTrace) {
      LoggingService.error('Failed to fetch batch weather data', e, stackTrace);
    }

    return results;
  }

  /// Create a batch key for deduplication
  String _createBatchKey(List<LatLng> locations, DateTime dateTime) {
    final hour = DateTime(dateTime.year, dateTime.month, dateTime.day, dateTime.hour);
    final locationKeys = locations
        .map((loc) => '${(loc.latitude * 100).round()}_${(loc.longitude * 100).round()}')
        .toList()
      ..sort();
    return '${locationKeys.join('|')}_${hour.toIso8601String()}';
  }

  /// Clear the cache (useful for testing or memory management)
  void clearCache() {
    _cache.clear();
    LoggingService.info('Weather cache cleared');
  }

  /// Get cache statistics for debugging
  Map<String, dynamic> getCacheStats() {
    return {
      'size': _cache.length,
      'pending_requests': _pendingRequests.length,
      'keys': _cache.keys.toList(),
    };
  }
}
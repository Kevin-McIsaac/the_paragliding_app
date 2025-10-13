import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../data/models/wind_data.dart';
import '../data/models/wind_forecast.dart';
import '../utils/site_utils.dart';
import 'logging_service.dart';

/// Service for fetching weather data from Open-Meteo API
class WeatherService {
  static final WeatherService instance = WeatherService._();
  WeatherService._();

  /// Cache for 7-day wind forecasts: "lat_lon" -> WindForecast
  /// Changed from single-hour cache to full forecast cache for better efficiency
  final Map<String, WindForecast> _forecastCache = {};

  /// Cache for pending requests to prevent duplicate API calls
  final Map<String, Future<WindForecast?>> _pendingRequests = {};

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
    // Generate cache key (location-only, no time component)
    final cacheKey = _getLocationKey(lat, lon);

    // Check forecast cache first
    if (_forecastCache.containsKey(cacheKey)) {
      final forecast = _forecastCache[cacheKey]!;

      // Check if forecast is still fresh
      if (forecast.isFresh) {
        LoggingService.info('Weather forecast cache hit for $cacheKey');
        return forecast.getAtTime(dateTime);
      } else {
        // Forecast is stale, remove it
        LoggingService.info('Removing stale forecast for $cacheKey');
        _forecastCache.remove(cacheKey);
      }
    }

    // Check if request is already pending
    if (_pendingRequests.containsKey(cacheKey)) {
      LoggingService.info('Waiting for pending weather request: $cacheKey');
      final forecast = await _pendingRequests[cacheKey];
      return forecast?.getAtTime(dateTime);
    }

    // Create new request
    final future = _fetchWindForecast(lat, lon, cacheKey);
    _pendingRequests[cacheKey] = future;

    try {
      final forecast = await future;
      return forecast?.getAtTime(dateTime);
    } finally {
      _pendingRequests.remove(cacheKey);
    }
  }

  /// Fetch 7-day wind forecast from Open-Meteo API
  Future<WindForecast?> _fetchWindForecast(
    double lat,
    double lon,
    String cacheKey,
  ) async {
    try {
      LoggingService.info('Fetching 7-day weather forecast for $lat, $lon');

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

        // Parse full 7-day hourly forecast
        final hourlyData = json['hourly'] as Map<String, dynamic>;

        // Create forecast from API response
        final forecast = WindForecast.fromOpenMeteo(
          latitude: lat,
          longitude: lon,
          hourlyData: hourlyData,
        );

        // Cache the full forecast
        _forecastCache[cacheKey] = forecast;

        LoggingService.structured('WEATHER_FORECAST_FETCHED', {
          'lat': lat,
          'lon': lon,
          'hours_count': forecast.timestamps.length,
          'time_range': forecast.timeRange,
          'memory_bytes': forecast.approximateMemorySize,
        });

        return forecast;
      } else {
        LoggingService.error('Weather API error: ${response.statusCode} - ${response.body}');
      }
    } catch (e, stackTrace) {
      LoggingService.error('Failed to fetch weather forecast', e, stackTrace);
    }

    return null;
  }

  /// Generate cache key based on location only (no time component)
  /// Round to approximately 1km grid (0.01 degrees ≈ 1km)
  String _getLocationKey(double lat, double lon) {
    final gridLat = (lat * 100).round() / 100;
    final gridLon = (lon * 100).round() / 100;
    return '${gridLat.toStringAsFixed(2)}_${gridLon.toStringAsFixed(2)}';
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

    // Check forecast cache first - separate cached from uncached locations
    final results = <String, WindData>{};
    final uncachedLocations = <LatLng>[];

    for (final location in locations) {
      final cacheKey = _getLocationKey(location.latitude, location.longitude);

      // Check if we have a fresh forecast for this location
      if (_forecastCache.containsKey(cacheKey)) {
        final forecast = _forecastCache[cacheKey]!;

        if (forecast.isFresh) {
          // Get wind data at requested time from cached forecast
          final windData = forecast.getAtTime(dateTime);
          if (windData != null) {
            final locationKey = SiteUtils.createSiteKey(location.latitude, location.longitude);
            results[locationKey] = windData;
            continue; // Skip adding to uncached list
          }
        } else {
          // Forecast is stale, remove it
          _forecastCache.remove(cacheKey);
        }
      }

      uncachedLocations.add(location);
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
    final future = _fetchWindForecastBatch(uncachedLocations, dateTime);
    _pendingBatchRequests[batchKey] = future;

    try {
      final batchResults = await future;
      results.addAll(batchResults);
      return results;
    } finally {
      _pendingBatchRequests.remove(batchKey);
    }
  }

  /// Fetch 7-day wind forecasts for multiple locations from Open-Meteo batch API
  Future<Map<String, WindData>> _fetchWindForecastBatch(
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

          // Parse full 7-day hourly forecast
          final hourlyData = locationData['hourly'] as Map<String, dynamic>;

          // Create forecast from API response
          final forecast = WindForecast.fromOpenMeteo(
            latitude: location.latitude,
            longitude: location.longitude,
            hourlyData: hourlyData,
          );

          // Cache the full forecast
          final cacheKey = _getLocationKey(location.latitude, location.longitude);
          _forecastCache[cacheKey] = forecast;

          // Get wind data at requested time for immediate results
          final windData = forecast.getAtTime(dateTime);
          if (windData != null) {
            final locationKey = SiteUtils.createSiteKey(location.latitude, location.longitude);
            results[locationKey] = windData;
          }
        }

        stopwatch.stop();

        LoggingService.structured('WEATHER_BATCH_SUCCESS', {
          'requested_count': locations.length,
          'fetched_count': results.length,
          'duration_ms': stopwatch.elapsedMilliseconds,
          'forecasts_cached': _forecastCache.length,
        });
      } else {
        LoggingService.error('Weather batch API error: ${response.statusCode} - ${response.body}');
      }
    } catch (e, stackTrace) {
      LoggingService.error('Failed to fetch batch weather forecasts', e, stackTrace);
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

  /// Clear the forecast cache (useful for testing or memory management)
  void clearCache() {
    final clearedCount = _forecastCache.length;
    _forecastCache.clear();
    LoggingService.info('Weather forecast cache cleared: $clearedCount forecasts removed');
  }

  /// Get cache statistics for debugging
  Map<String, dynamic> getCacheStats() {
    // Calculate total memory usage
    int totalMemory = 0;
    int freshCount = 0;
    int staleCount = 0;

    for (final forecast in _forecastCache.values) {
      totalMemory += forecast.approximateMemorySize;
      if (forecast.isFresh) {
        freshCount++;
      } else {
        staleCount++;
      }
    }

    return {
      'forecast_count': _forecastCache.length,
      'fresh_forecasts': freshCount,
      'stale_forecasts': staleCount,
      'pending_requests': _pendingRequests.length,
      'pending_batch_requests': _pendingBatchRequests.length,
      'total_memory_bytes': totalMemory,
      'total_memory_kb': (totalMemory / 1024).toStringAsFixed(1),
      'keys': _forecastCache.keys.toList(),
    };
  }
}
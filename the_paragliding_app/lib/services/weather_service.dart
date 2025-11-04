import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../data/models/wind_data.dart';
import '../data/models/wind_forecast.dart';
import '../data/models/weather_model.dart';
import '../utils/site_utils.dart';
import '../utils/preferences_helper.dart';
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

  /// Cache for current weather model to avoid repeated SharedPreferences reads
  WeatherModel? _cachedModel;

  /// Maximum number of locations per batch request
  static const int maxBatchSize = 100;

  /// Get wind data for a specific location and time
  Future<WindData?> getWindData(
    double lat,
    double lon,
    DateTime dateTime,
  ) async {
    // Generate cache key (location + model, no time component)
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

  /// Get wind forecast for a specific location and specific model
  /// This allows fetching forecasts from different models for comparison
  Future<WindForecast?> getWindForecastForModel(
    double lat,
    double lon,
    WeatherModel model,
  ) async {
    // Generate cache key with specific model
    final gridLat = (lat * 100).round() / 100;
    final gridLon = (lon * 100).round() / 100;
    final cacheKey = '${gridLat.toStringAsFixed(2)}_${gridLon.toStringAsFixed(2)}_${model.apiValue}';

    // Check forecast cache first
    if (_forecastCache.containsKey(cacheKey)) {
      final forecast = _forecastCache[cacheKey]!;

      // Check if forecast is still fresh
      if (forecast.isFresh) {
        LoggingService.info('Weather forecast cache hit for $cacheKey (model: ${model.displayName})');
        return forecast;
      } else {
        // Forecast is stale, remove it
        LoggingService.info('Removing stale forecast for $cacheKey');
        _forecastCache.remove(cacheKey);
      }
    }

    // Check if request is already pending
    if (_pendingRequests.containsKey(cacheKey)) {
      LoggingService.info('Waiting for pending weather request: $cacheKey');
      return await _pendingRequests[cacheKey];
    }

    // Create new request with specific model
    final future = _fetchWindForecastForModel(lat, lon, cacheKey, model);
    _pendingRequests[cacheKey] = future;

    try {
      return await future;
    } finally {
      _pendingRequests.remove(cacheKey);
    }
  }

  /// Fetch forecasts for ALL weather models in a single API call
  /// Uses comma-separated models parameter - API returns single object with model-suffixed fields
  Future<Map<WeatherModel, WindForecast>> getAllModelForecasts(
    double lat,
    double lon,
  ) async {
    final results = <WeatherModel, WindForecast>{};

    // Check cache first for each model
    final gridLat = (lat * 100).round() / 100;
    final gridLon = (lon * 100).round() / 100;
    final uncachedModels = <WeatherModel>[];

    for (final model in WeatherModel.values) {
      final cacheKey = '${gridLat.toStringAsFixed(2)}_${gridLon.toStringAsFixed(2)}_${model.apiValue}';

      if (_forecastCache.containsKey(cacheKey)) {
        final forecast = _forecastCache[cacheKey]!;
        if (forecast.isFresh) {
          results[model] = forecast;
          continue;
        } else {
          _forecastCache.remove(cacheKey);
        }
      }

      uncachedModels.add(model);
    }

    // If all cached, return immediately
    if (uncachedModels.isEmpty) {
      LoggingService.info('All ${WeatherModel.values.length} models cached for $gridLat, $gridLon');
      return results;
    }

    // Fetch all uncached models in one API call
    final fetchedForecasts = await _fetchAllModelsInOneCall(lat, lon, uncachedModels);
    results.addAll(fetchedForecasts);

    LoggingService.structured('ALL_MODELS_SINGLE_CALL_SUCCESS', {
      'lat': lat,
      'lon': lon,
      'cached_count': WeatherModel.values.length - uncachedModels.length,
      'fetched_count': fetchedForecasts.length,
      'total_models': WeatherModel.values.length,
    });

    return results;
  }

  /// Fetch multiple models in a single API call using comma-separated models parameter
  /// API returns single object with model-suffixed fields (e.g., wind_speed_10m_gfs_seamless)
  Future<Map<WeatherModel, WindForecast>> _fetchAllModelsInOneCall(
    double lat,
    double lon,
    List<WeatherModel> models,
  ) async {
    final results = <WeatherModel, WindForecast>{};

    // Build comma-separated models string (excluding best_match since it doesn't need models param)
    final modelsWithParams = models.where((m) => m.apiParameter != null).toList();
    final modelParams = modelsWithParams.map((m) => m.apiParameter!).join(',');

    // Handle best_match separately (no models parameter needed)
    if (models.contains(WeatherModel.bestMatch)) {
      final forecast = await getWindForecastForModel(lat, lon, WeatherModel.bestMatch);
      if (forecast != null) {
        results[WeatherModel.bestMatch] = forecast;
      }
    }

    // If no models with parameters, return early
    if (modelParams.isEmpty) {
      return results;
    }

    LoggingService.info('Fetching ${modelsWithParams.length} models in single API call: $modelParams');

    // Build API URL with comma-separated models
    final urlString = 'https://api.open-meteo.com/v1/forecast'
        '?latitude=$lat&longitude=$lon'
        '&hourly=wind_speed_10m,wind_direction_10m,wind_gusts_10m,precipitation'
        '&wind_speed_unit=kmh'
        '&forecast_days=7'
        '&timezone=auto'
        '&models=$modelParams';

    final url = Uri.parse(urlString);

    final response = await http.get(url).timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        throw TimeoutException('Multi-model API request timed out');
      },
    );

    if (response.statusCode != 200) {
      throw Exception('API error: ${response.statusCode} - ${response.body}');
    }

    final jsonBody = jsonDecode(response.body) as Map<String, dynamic>;
    final hourlyData = jsonBody['hourly'] as Map<String, dynamic>;

    // API returns single object with model-suffixed fields
    // e.g., wind_speed_10m_gfs_seamless, wind_speed_10m_icon_seamless, etc.
    LoggingService.info('Multi-model response: single object with ${hourlyData.keys.length} fields');

    final gridLat = (lat * 100).round() / 100;
    final gridLon = (lon * 100).round() / 100;

    // Extract data for each model from the suffixed fields
    for (final model in modelsWithParams) {
      final modelSuffix = model.apiParameter!;

      // Extract model-specific hourly data by filtering suffixed fields
      final modelHourlyData = _extractModelData(hourlyData, modelSuffix);

      // Create forecast from extracted data
      final forecast = WindForecast.fromOpenMeteo(
        latitude: lat,
        longitude: lon,
        hourlyData: modelHourlyData,
      );

      results[model] = forecast;

      // Cache it
      final cacheKey = '${gridLat.toStringAsFixed(2)}_${gridLon.toStringAsFixed(2)}_${model.apiValue}';
      _forecastCache[cacheKey] = forecast;
    }

    return results;
  }

  /// Extract model-specific data from multi-model response
  /// Converts suffixed fields (wind_speed_10m_gfs_seamless) to standard fields (wind_speed_10m)
  Map<String, dynamic> _extractModelData(Map<String, dynamic> hourlyData, String modelSuffix) {
    return {
      'time': hourlyData['time'],
      'wind_speed_10m': hourlyData['wind_speed_10m_$modelSuffix'],
      'wind_direction_10m': hourlyData['wind_direction_10m_$modelSuffix'],
      'wind_gusts_10m': hourlyData['wind_gusts_10m_$modelSuffix'],
      'precipitation': hourlyData['precipitation_$modelSuffix'],
    };
  }

  /// Fetch 7-day wind forecast from Open-Meteo API
  Future<WindForecast?> _fetchWindForecast(
    double lat,
    double lon,
    String cacheKey,
  ) async {
    try {
      // Get current model
      final model = await getCurrentModel();
      final modelParam = model.apiParameter;

      LoggingService.info('Fetching 7-day weather forecast for $lat, $lon using model: ${model.displayName}');

      // Build API URL with optional models parameter
      var urlString = 'https://api.open-meteo.com/v1/forecast'
          '?latitude=$lat&longitude=$lon'
          '&hourly=wind_speed_10m,wind_direction_10m,wind_gusts_10m,precipitation'
          '&wind_speed_unit=kmh'
          '&forecast_days=7'
          '&timezone=auto';

      // Add models parameter if not using best match
      if (modelParam != null) {
        urlString += '&models=$modelParam';
      }

      final url = Uri.parse(urlString);

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

  /// Fetch 7-day wind forecast from Open-Meteo API for a specific model
  Future<WindForecast?> _fetchWindForecastForModel(
    double lat,
    double lon,
    String cacheKey,
    WeatherModel model,
  ) async {
    try {
      final modelParam = model.apiParameter;

      LoggingService.info('Fetching 7-day weather forecast for $lat, $lon using model: ${model.displayName}');

      // Build API URL with optional models parameter
      var urlString = 'https://api.open-meteo.com/v1/forecast'
          '?latitude=$lat&longitude=$lon'
          '&hourly=wind_speed_10m,wind_direction_10m,wind_gusts_10m,precipitation'
          '&wind_speed_unit=kmh'
          '&forecast_days=7'
          '&timezone=auto';

      // Add models parameter if not using best match
      if (modelParam != null) {
        urlString += '&models=$modelParam';
      }

      final url = Uri.parse(urlString);

      // Make API request
      final response = await http.get(url).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          LoggingService.error('Weather API timeout for $lat, $lon (model: ${model.displayName})');
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
          'model': model.displayName,
          'hours_count': forecast.timestamps.length,
          'time_range': forecast.timeRange,
          'memory_bytes': forecast.approximateMemorySize,
        });

        return forecast;
      } else {
        LoggingService.error('Weather API error for ${model.displayName}: ${response.statusCode} - ${response.body}');
      }
    } catch (e, stackTrace) {
      LoggingService.error('Failed to fetch weather forecast for ${model.displayName}', e, stackTrace);
    }

    return null;
  }

  /// Generate cache key based on location and model
  /// Round to approximately 1km grid (0.01 degrees ≈ 1km)
  /// Includes model to support separate caches per model
  /// Now synchronous - uses cached model instead of reading from SharedPreferences
  String _getLocationKey(double lat, double lon) {
    final gridLat = (lat * 100).round() / 100;
    final gridLon = (lon * 100).round() / 100;
    final modelApiValue = _cachedModel?.apiValue ?? 'best_match';
    return '${gridLat.toStringAsFixed(2)}_${gridLon.toStringAsFixed(2)}_$modelApiValue';
  }

  /// Get current weather model (with caching to avoid repeated SharedPreferences reads)
  Future<WeatherModel> getCurrentModel() async {
    if (_cachedModel != null) return _cachedModel!;
    final modelApiValue = await PreferencesHelper.getWeatherForecastModel();
    _cachedModel = WeatherModel.fromApiValue(modelApiValue);
    return _cachedModel!;
  }

  /// Get wind data for multiple locations in a single batch API call
  /// Returns a map of "lat_lon" -> WindData for successfully fetched locations
  /// Optional onApiCallStart callback is invoked when API call is actually made (not cached)
  Future<Map<String, WindData>> getWindDataBatch(
    List<LatLng> locations,
    DateTime dateTime, {
    Function()? onApiCallStart,
  }) async {
    if (locations.isEmpty) return {};

    // Limit batch size
    if (locations.length > maxBatchSize) {
      LoggingService.info('Batch size ${locations.length} exceeds max $maxBatchSize, splitting into chunks');

      // Split into chunks and process them
      final results = <String, WindData>{};
      for (int i = 0; i < locations.length; i += maxBatchSize) {
        final end = (i + maxBatchSize < locations.length) ? i + maxBatchSize : locations.length;
        final chunk = locations.sublist(i, end);
        final chunkResults = await getWindDataBatch(chunk, dateTime, onApiCallStart: onApiCallStart);
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

    // Notify that we're about to make an API call
    onApiCallStart?.call();

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

      // Get current model
      final model = await getCurrentModel();
      final modelParam = model.apiParameter;

      // Build comma-separated latitude and longitude strings
      final latitudes = locations.map((loc) => loc.latitude.toStringAsFixed(4)).join(',');
      final longitudes = locations.map((loc) => loc.longitude.toStringAsFixed(4)).join(',');

      LoggingService.structured('WEATHER_BATCH_REQUEST', {
        'location_count': locations.length,
        'time': dateTime.toIso8601String(),
        'model': model.displayName,
      });

      // Build API URL with optional models parameter
      var urlString = 'https://api.open-meteo.com/v1/forecast'
          '?latitude=$latitudes&longitude=$longitudes'
          '&hourly=wind_speed_10m,wind_direction_10m,wind_gusts_10m,precipitation'
          '&wind_speed_unit=kmh'
          '&forecast_days=7'
          '&timezone=auto';

      // Add models parameter if not using best match
      if (modelParam != null) {
        urlString += '&models=$modelParam';
      }

      final url = Uri.parse(urlString);

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
  /// Includes model to prevent collisions between different model requests
  String _createBatchKey(List<LatLng> locations, DateTime dateTime) {
    final hour = DateTime(dateTime.year, dateTime.month, dateTime.day, dateTime.hour);
    final locationKeys = locations
        .map((loc) => '${(loc.latitude * 100).round()}_${(loc.longitude * 100).round()}')
        .toList()
      ..sort();
    final modelApiValue = _cachedModel?.apiValue ?? 'best_match';
    return '${locationKeys.join('|')}_${hour.toIso8601String()}_$modelApiValue';
  }

  /// Get a cached forecast for a specific location
  /// Returns null if no forecast is cached or if the forecast is stale
  Future<WindForecast?> getCachedForecast(double lat, double lon) async {
    final cacheKey = _getLocationKey(lat, lon);
    if (_forecastCache.containsKey(cacheKey)) {
      final forecast = _forecastCache[cacheKey]!;
      if (forecast.isFresh) {
        return forecast;
      } else {
        // Remove stale forecast
        _forecastCache.remove(cacheKey);
      }
    }
    return null;
  }

  /// Check if an exception is retryable (transient network/server errors)
  bool _isRetryableError(dynamic error) {
    if (error is TimeoutException) return true;
    if (error is http.ClientException) return true;
    if (error is Exception) {
      final msg = error.toString().toLowerCase();
      return msg.contains('socket') ||
             msg.contains('connection') ||
             msg.contains('network');
    }
    return false;
  }

  /// Check if HTTP status code indicates a retryable error
  bool _isRetryableStatusCode(int statusCode) {
    return statusCode == 429 ||  // Rate limited - wait and retry
           statusCode == 503 ||  // Service unavailable - temporary
           statusCode == 504 ||  // Gateway timeout
           (statusCode >= 500 && statusCode < 600);  // Server errors
  }

  /// Retry an operation with exponential backoff for transient errors
  Future<T> _retryWithBackoff<T>(
    Future<T> Function() operation, {
    int maxRetries = 3,
    Duration initialDelay = const Duration(seconds: 1),
  }) async {
    int attempt = 0;
    Duration delay = initialDelay;

    while (true) {
      try {
        return await operation();
      } catch (error) {
        attempt++;

        // Check if we should retry
        final shouldRetry = attempt < maxRetries && _isRetryableError(error);

        if (!shouldRetry) {
          LoggingService.error(
            'Request failed after $attempt ${attempt == 1 ? "attempt" : "attempts"}',
            error,
            null,
          );
          rethrow;
        }

        // Log retry attempt
        LoggingService.structured('HTTP_RETRY', {
          'attempt': attempt,
          'max_retries': maxRetries,
          'delay_seconds': delay.inSeconds,
          'error_type': error.runtimeType.toString(),
        });

        // Wait with exponential backoff
        await Future.delayed(delay);
        delay *= 2;  // Double the delay for next attempt
      }
    }
  }

  /// Handle HTTP response errors with descriptive messages
  void _handleHttpError(int statusCode, String responseBody, String context) {
    String errorMessage;

    switch (statusCode) {
      case 400:
        errorMessage = 'Invalid request parameters';
        break;
      case 401:
        errorMessage = 'API authentication failed';
        break;
      case 403:
        errorMessage = 'API access forbidden';
        break;
      case 404:
        errorMessage = 'API endpoint not found';
        break;
      case 429:
        errorMessage = 'API rate limit exceeded - please wait before retrying';
        break;
      case 500:
        errorMessage = 'API server error';
        break;
      case 503:
        errorMessage = 'API service temporarily unavailable';
        break;
      case 504:
        errorMessage = 'API gateway timeout';
        break;
      default:
        errorMessage = 'HTTP error $statusCode';
    }

    LoggingService.structured('HTTP_ERROR', {
      'context': context,
      'status_code': statusCode,
      'error_message': errorMessage,
      'response_preview': responseBody.length > 200
          ? '${responseBody.substring(0, 200)}...'
          : responseBody,
    });

    throw Exception('$context: $errorMessage (HTTP $statusCode)');
  }

  /// Clear the forecast cache (useful for testing or memory management)
  /// Also clears the model cache to force re-reading preferences
  void clearCache() {
    final clearedCount = _forecastCache.length;
    _forecastCache.clear();
    _cachedModel = null;
    LoggingService.info('Weather forecast cache cleared: $clearedCount forecasts removed, model cache reset');
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
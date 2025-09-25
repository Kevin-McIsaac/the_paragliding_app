import 'dart:async';
import 'package:flutter_map/flutter_map.dart';
import '../data/models/flight.dart';
import 'site_bounds_loader_v2.dart';
import 'database_service.dart';
import 'logging_service.dart';

/// Result class for launch bounds loading
class LaunchBoundsLoadResult {
  final List<Flight> launches;
  final String boundsKey;
  final DateTime timestamp;

  LaunchBoundsLoadResult({
    required this.launches,
    required this.boundsKey,
    required this.timestamp,
  });
}

/// Centralized service for managing map bounds loading and caching
/// Eliminates duplicate bounds checking, debouncing, and loading logic
/// across all map widgets
class MapBoundsManager {
  static final MapBoundsManager instance = MapBoundsManager._();
  MapBoundsManager._();

  // Constants shared across all maps
  static const double boundsThreshold = 0.001; // ~100m change threshold
  static const int debounceDurationMs = 500; // Standardized debounce time
  static const int defaultSiteLimit = 50;

  // Debounce timers for each map context
  final Map<String, Timer?> _debounceTimers = {};
  final Map<String, Timer?> _launchDebounceTimers = {};

  // Last loaded bounds for each map context
  final Map<String, String> _lastLoadedBoundsKeys = {};
  final Map<String, String> _lastLoadedLaunchBoundsKeys = {};

  // Loading state for each map context
  final Map<String, bool> _loadingStates = {};
  final Map<String, bool> _launchLoadingStates = {};

  // Cache for loaded sites (bounds key -> result)
  final Map<String, SiteBoundsLoadResult> _cache = {};
  final Map<String, LaunchBoundsLoadResult> _launchCache = {};
  static const int _maxCacheSize = 10; // LRU cache size
  final List<String> _cacheKeys = []; // Track order for LRU
  final List<String> _launchCacheKeys = []; // Track order for launch cache LRU

  /// Check if bounds have changed significantly for a given context
  bool haveBoundsChangedSignificantly(
    String context,
    LatLngBounds newBounds,
    LatLngBounds? currentBounds,
  ) {
    if (currentBounds == null) return true;

    return (newBounds.north - currentBounds.north).abs() >= boundsThreshold ||
           (newBounds.south - currentBounds.south).abs() >= boundsThreshold ||
           (newBounds.east - currentBounds.east).abs() >= boundsThreshold ||
           (newBounds.west - currentBounds.west).abs() >= boundsThreshold;
  }

  /// Generate unique key for bounds
  String getBoundsKey(LatLngBounds bounds) {
    return '${bounds.north.toStringAsFixed(6)}_'
           '${bounds.south.toStringAsFixed(6)}_'
           '${bounds.east.toStringAsFixed(6)}_'
           '${bounds.west.toStringAsFixed(6)}';
  }

  /// Check if the same bounds are already loaded for a context
  bool areBoundsAlreadyLoaded(String context, LatLngBounds bounds) {
    final boundsKey = getBoundsKey(bounds);
    return _lastLoadedBoundsKeys[context] == boundsKey;
  }

  /// Check if currently loading for a context
  bool isLoading(String context) {
    return _loadingStates[context] ?? false;
  }

  /// Cancel any pending debounce timer for a context
  void cancelDebounce(String context) {
    _debounceTimers[context]?.cancel();
    _debounceTimers[context] = null;
  }

  /// Load sites for bounds with debouncing, caching, and deduplication
  /// Returns a Future that completes when sites are loaded
  Future<void> loadSitesForBoundsDebounced({
    required String context,
    required LatLngBounds bounds,
    required Function(SiteBoundsLoadResult) onLoaded,
    int siteLimit = defaultSiteLimit,
    bool includeFlightCounts = true,
  }) async {
    // Cancel any existing debounce timer
    cancelDebounce(context);

    // Set up new debounce timer
    final completer = Completer<void>();
    _debounceTimers[context] = Timer(
      const Duration(milliseconds: debounceDurationMs),
      () async {
        try {
          await _loadSitesForBounds(
            context: context,
            bounds: bounds,
            onLoaded: onLoaded,
            siteLimit: siteLimit,
            includeFlightCounts: includeFlightCounts,
          );
          completer.complete();
        } catch (e) {
          completer.completeError(e);
        }
      },
    );

    return completer.future;
  }

  /// Internal method to load sites for bounds
  Future<void> _loadSitesForBounds({
    required String context,
    required LatLngBounds bounds,
    required Function(SiteBoundsLoadResult) onLoaded,
    int siteLimit = defaultSiteLimit,
    bool includeFlightCounts = true,
  }) async {
    final boundsKey = getBoundsKey(bounds);

    // Check if already loading
    if (isLoading(context)) {
      LoggingService.debug('[$context] Already loading sites, skipping duplicate request');
      return;
    }

    // Check if same bounds already loaded
    if (_lastLoadedBoundsKeys[context] == boundsKey) {
      LoggingService.debug('[$context] Same bounds already loaded, using cached result');

      // Check cache for result
      if (_cache.containsKey(boundsKey)) {
        onLoaded(_cache[boundsKey]!);
      }
      return;
    }

    // Check cache first
    if (_cache.containsKey(boundsKey)) {
      LoggingService.info('[$context] Using cached sites for bounds: $boundsKey');
      _lastLoadedBoundsKeys[context] = boundsKey;
      onLoaded(_cache[boundsKey]!);

      // Move to end of LRU list
      _cacheKeys.remove(boundsKey);
      _cacheKeys.add(boundsKey);
      return;
    }

    // Set loading state
    _loadingStates[context] = true;

    try {
      LoggingService.info('[$context] Loading sites for bounds: $boundsKey');

      // Load from database
      final result = await SiteBoundsLoaderV2.instance.loadSitesForBounds(
        bounds,
        limit: siteLimit,
        includeFlightCounts: includeFlightCounts,
      );

      // Update cache with LRU eviction
      _addToCache(boundsKey, result);

      // Update last loaded bounds
      _lastLoadedBoundsKeys[context] = boundsKey;

      // Call the callback with results
      onLoaded(result);

      LoggingService.structured('MAP_BOUNDS_LOADED', {
        'context': context,
        'bounds_key': boundsKey,
        'sites_count': result.sites.length,
        'flown_sites': result.sitesWithFlights.length,
        'new_sites': result.sitesWithoutFlights.length,
        'from_cache': false,
      });

    } catch (error, stackTrace) {
      LoggingService.error('[$context] Failed to load sites for bounds', error, stackTrace);
      rethrow;
    } finally {
      _loadingStates[context] = false;
    }
  }

  /// Add result to cache with LRU eviction
  void _addToCache(String key, SiteBoundsLoadResult result) {
    // Remove from current position if exists
    _cacheKeys.remove(key);

    // Add to end (most recently used)
    _cacheKeys.add(key);
    _cache[key] = result;

    // Evict oldest if cache is full
    if (_cacheKeys.length > _maxCacheSize) {
      final oldestKey = _cacheKeys.removeAt(0);
      _cache.remove(oldestKey);
      LoggingService.debug('Evicted oldest cache entry: $oldestKey');
    }
  }

  /// Clear cache for a specific context or all contexts
  void clearCache([String? context]) {
    if (context != null) {
      // Clear specific context
      _lastLoadedBoundsKeys.remove(context);
      _loadingStates.remove(context);
      cancelDebounce(context);
    } else {
      // Clear all
      _cache.clear();
      _cacheKeys.clear();
      _lastLoadedBoundsKeys.clear();
      _loadingStates.clear();
      _debounceTimers.forEach((key, timer) => timer?.cancel());
      _debounceTimers.clear();
    }

    LoggingService.info('Cache cleared ${context != null ? "for context: $context" : "for all contexts"}');
  }

  /// Get cache statistics for monitoring
  Map<String, dynamic> getCacheStats() {
    return {
      'site_cache_size': _cache.length,
      'launch_cache_size': _launchCache.length,
      'max_cache_size': _maxCacheSize,
      'contexts_tracked': _lastLoadedBoundsKeys.length,
      'launch_contexts_tracked': _lastLoadedLaunchBoundsKeys.length,
      'active_timers': _debounceTimers.values.where((t) => t != null && t.isActive).length,
      'active_launch_timers': _launchDebounceTimers.values.where((t) => t != null && t.isActive).length,
      'total_sites_cached': _cache.values.fold(0, (sum, result) => sum + result.sites.length),
      'total_launches_cached': _launchCache.values.fold(0, (sum, result) => sum + result.launches.length),
    };
  }

  // ============== LAUNCH QUERY MANAGEMENT ==============

  /// Cancel any pending launch debounce timer for a context
  void cancelLaunchDebounce(String context) {
    _launchDebounceTimers[context]?.cancel();
    _launchDebounceTimers[context] = null;
  }

  /// Check if launches are currently loading for a context
  bool isLoadingLaunches(String context) {
    return _launchLoadingStates[context] ?? false;
  }

  /// Check if the same launch bounds are already loaded for a context
  bool areLaunchBoundsAlreadyLoaded(String context, LatLngBounds bounds) {
    final boundsKey = getBoundsKey(bounds);
    return _lastLoadedLaunchBoundsKeys[context] == boundsKey;
  }

  /// Load launches for bounds with debouncing and caching
  Future<void> loadLaunchesForBoundsDebounced({
    required String context,
    required LatLngBounds bounds,
    required Function(LaunchBoundsLoadResult) onLoaded,
  }) async {
    // Cancel any existing debounce timer
    cancelLaunchDebounce(context);

    // Set up new debounce timer
    final completer = Completer<void>();
    _launchDebounceTimers[context] = Timer(
      const Duration(milliseconds: debounceDurationMs),
      () async {
        try {
          await _loadLaunchesForBounds(
            context: context,
            bounds: bounds,
            onLoaded: onLoaded,
          );
          completer.complete();
        } catch (e) {
          completer.completeError(e);
        }
      },
    );

    return completer.future;
  }

  /// Internal method to load launches for bounds
  Future<void> _loadLaunchesForBounds({
    required String context,
    required LatLngBounds bounds,
    required Function(LaunchBoundsLoadResult) onLoaded,
  }) async {
    final boundsKey = getBoundsKey(bounds);

    // Check if already loading
    if (isLoadingLaunches(context)) {
      LoggingService.debug('[$context] Already loading launches, skipping duplicate request');
      return;
    }

    // Check if same bounds already loaded
    if (areLaunchBoundsAlreadyLoaded(context, bounds)) {
      LoggingService.debug('[$context] Launch bounds already loaded: $boundsKey');
      return;
    }

    // Check cache first
    if (_launchCache.containsKey(boundsKey)) {
      final cachedResult = _launchCache[boundsKey]!;
      LoggingService.info('[$context] Using cached launches for bounds: $boundsKey');

      onLoaded(cachedResult);
      _lastLoadedLaunchBoundsKeys[context] = boundsKey;

      LoggingService.structured('LAUNCH_BOUNDS_LOADED', {
        'context': context,
        'bounds_key': boundsKey,
        'launches_count': cachedResult.launches.length,
        'from_cache': true,
      });
      return;
    }

    // Mark as loading
    _launchLoadingStates[context] = true;

    try {
      LoggingService.info('[$context] Loading launches for bounds: $boundsKey');

      // Load from database
      final launches = await DatabaseService.instance.getAllLaunchesInBounds(
        north: bounds.north,
        south: bounds.south,
        east: bounds.east,
        west: bounds.west,
      );

      final result = LaunchBoundsLoadResult(
        launches: launches,
        boundsKey: boundsKey,
        timestamp: DateTime.now(),
      );

      // Update cache with LRU eviction
      _addToLaunchCache(boundsKey, result);

      // Update last loaded bounds
      _lastLoadedLaunchBoundsKeys[context] = boundsKey;

      // Call the callback with results
      onLoaded(result);

      LoggingService.structured('LAUNCH_BOUNDS_LOADED', {
        'context': context,
        'bounds_key': boundsKey,
        'launches_count': launches.length,
        'from_cache': false,
      });

    } catch (error, stackTrace) {
      LoggingService.error('[$context] Failed to load launches for bounds', error, stackTrace);
      rethrow;
    } finally {
      _launchLoadingStates[context] = false;
    }
  }

  /// Add launch result to cache with LRU eviction
  void _addToLaunchCache(String key, LaunchBoundsLoadResult result) {
    // Remove from current position if exists
    _launchCacheKeys.remove(key);

    // Add to end (most recent)
    _launchCacheKeys.add(key);
    _launchCache[key] = result;

    // Evict oldest if over limit
    if (_launchCacheKeys.length > _maxCacheSize) {
      final oldestKey = _launchCacheKeys.removeAt(0);
      _launchCache.remove(oldestKey);
      LoggingService.debug('Launch cache evicted oldest entry: $oldestKey');
    }
  }

  /// Clear launch cache for a specific context or all
  void clearLaunchCache([String? context]) {
    if (context != null) {
      // Clear specific context
      _lastLoadedLaunchBoundsKeys.remove(context);
      _launchLoadingStates.remove(context);
      cancelLaunchDebounce(context);
    } else {
      // Clear all launch caches
      _launchCache.clear();
      _launchCacheKeys.clear();
      _lastLoadedLaunchBoundsKeys.clear();
      _launchLoadingStates.clear();
      _launchDebounceTimers.forEach((key, timer) => timer?.cancel());
      _launchDebounceTimers.clear();
    }

    LoggingService.info('Launch cache cleared${context != null ? ' for context: $context' : ' (all contexts)'}');
  }

  /// Dispose of resources when no longer needed
  void dispose() {
    _debounceTimers.forEach((key, timer) => timer?.cancel());
    _debounceTimers.clear();
    _launchDebounceTimers.forEach((key, timer) => timer?.cancel());
    _launchDebounceTimers.clear();
    clearCache();
    clearLaunchCache();
  }
}
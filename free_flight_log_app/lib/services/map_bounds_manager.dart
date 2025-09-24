import 'dart:async';
import 'package:flutter_map/flutter_map.dart';
import 'site_bounds_loader_v2.dart';
import 'logging_service.dart';

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

  // Last loaded bounds for each map context
  final Map<String, String> _lastLoadedBoundsKeys = {};

  // Loading state for each map context
  final Map<String, bool> _loadingStates = {};

  // Cache for loaded sites (bounds key -> result)
  final Map<String, SiteBoundsLoadResult> _cache = {};
  static const int _maxCacheSize = 10; // LRU cache size
  final List<String> _cacheKeys = []; // Track order for LRU

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
      'cache_size': _cache.length,
      'max_cache_size': _maxCacheSize,
      'contexts_tracked': _lastLoadedBoundsKeys.length,
      'active_timers': _debounceTimers.values.where((t) => t != null && t.isActive).length,
      'total_sites_cached': _cache.values.fold(0, (sum, result) => sum + result.sites.length),
    };
  }

  /// Dispose of resources when no longer needed
  void dispose() {
    _debounceTimers.forEach((key, timer) => timer?.cancel());
    _debounceTimers.clear();
    clearCache();
  }
}
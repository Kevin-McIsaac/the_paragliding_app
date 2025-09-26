import 'dart:async';
import 'package:flutter_map/flutter_map.dart';
import '../data/models/flight.dart';
import '../utils/map_constants.dart';
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
  static const int debounceDurationMs = MapConstants.mapBoundsDebounceMs;
  static const int defaultSiteLimit = MapConstants.defaultSiteLimit;

  // Debounce timers for each map context
  final Map<String, Timer?> _debounceTimers = {};
  final Map<String, Timer?> _launchDebounceTimers = {};

  // Last loaded bounds for each map context
  final Map<String, String> _lastLoadedBoundsKeys = {};
  final Map<String, String> _lastLoadedLaunchBoundsKeys = {};

  // Loading state for each map context
  final Map<String, bool> _loadingStates = {};
  final Map<String, bool> _launchLoadingStates = {};

  // Note: Cache removed for simplicity - debouncing provides sufficient performance

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
    double? zoomLevel,
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
            zoomLevel: zoomLevel,
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
    double? zoomLevel,
  }) async {
    final boundsKey = getBoundsKey(bounds);

    // Check if already loading
    if (isLoading(context)) {
      LoggingService.debug('[$context] Already loading sites, skipping duplicate request');
      return;
    }

    // Check if same bounds already loaded (deduplication)
    if (_lastLoadedBoundsKeys[context] == boundsKey) {
      LoggingService.debug('[$context] Same bounds already loaded, skipping duplicate request');
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

      // No caching - debouncing provides sufficient performance

      // Update last loaded bounds
      _lastLoadedBoundsKeys[context] = boundsKey;

      // Call the callback with results
      onLoaded(result);

      LoggingService.structured('MAP_BOUNDS_LOADED', {
        'context': context,
        'bounds_key': boundsKey,
        'zoom_level': zoomLevel?.toStringAsFixed(1) ?? 'unknown',
        'sites_count': result.sites.length,
        'flown_sites': result.sitesWithFlights.length,
        'new_sites': result.sitesWithoutFlights.length,
      });

    } catch (error, stackTrace) {
      LoggingService.error('[$context] Failed to load sites for bounds', error, stackTrace);
      rethrow;
    } finally {
      _loadingStates[context] = false;
    }
  }


  /// Clear state for a specific context or all contexts
  void clearCache([String? context]) {
    if (context != null) {
      // Clear specific context
      _lastLoadedBoundsKeys.remove(context);
      _loadingStates.remove(context);
      cancelDebounce(context);
    } else {
      // Clear all
      _lastLoadedBoundsKeys.clear();
      _loadingStates.clear();
      _debounceTimers.forEach((key, timer) => timer?.cancel());
      _debounceTimers.clear();
    }

    LoggingService.info('State cleared ${context != null ? "for context: $context" : "for all contexts"}');
  }

  /// Get statistics for monitoring
  Map<String, dynamic> getCacheStats() {
    return {
      'contexts_tracked': _lastLoadedBoundsKeys.length,
      'launch_contexts_tracked': _lastLoadedLaunchBoundsKeys.length,
      'active_timers': _debounceTimers.values.where((t) => t != null && t.isActive).length,
      'active_launch_timers': _launchDebounceTimers.values.where((t) => t != null && t.isActive).length,
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

      // No caching - debouncing provides sufficient performance

      // Update last loaded bounds
      _lastLoadedLaunchBoundsKeys[context] = boundsKey;

      // Call the callback with results
      onLoaded(result);

      LoggingService.structured('LAUNCH_BOUNDS_LOADED', {
        'context': context,
        'bounds_key': boundsKey,
        'launches_count': launches.length,
      });

    } catch (error, stackTrace) {
      LoggingService.error('[$context] Failed to load launches for bounds', error, stackTrace);
      rethrow;
    } finally {
      _launchLoadingStates[context] = false;
    }
  }


  /// Clear launch state for a specific context or all
  void clearLaunchCache([String? context]) {
    if (context != null) {
      // Clear specific context
      _lastLoadedLaunchBoundsKeys.remove(context);
      _launchLoadingStates.remove(context);
      cancelLaunchDebounce(context);
    } else {
      // Clear all launch states
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
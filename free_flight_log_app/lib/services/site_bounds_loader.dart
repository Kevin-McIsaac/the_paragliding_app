import 'package:flutter_map/flutter_map.dart';
import '../data/models/site.dart';
import '../data/models/paragliding_site.dart';
import '../data/models/unified_site.dart';
import 'database_service.dart';
import 'paragliding_earth_api.dart';
import 'logging_service.dart';

/// Result of loading sites for a bounding box
class SiteBoundsLoadResult {
  final List<UnifiedSite> sites;
  final LatLngBounds bounds;
  final DateTime loadedAt;

  const SiteBoundsLoadResult({
    required this.sites,
    required this.bounds,
    required this.loadedAt,
  });

  // Convenience filters
  List<UnifiedSite> get localSites => sites.where((s) => s.isLocalSite).toList();
  List<UnifiedSite> get apiOnlySites => sites.where((s) => !s.isLocalSite).toList();
  List<UnifiedSite> get flownSites => sites.where((s) => s.hasFlights).toList();
  List<UnifiedSite> get newSites => sites.where((s) => !s.hasFlights).toList();
}

/// Service for loading sites within map bounds with automatic deduplication
/// and caching. This replaces the duplicated _loadSitesForBounds logic in
/// NearbySitesScreen, EditSiteScreen, and FlightTrack2DWidget.
class SiteBoundsLoader {
  static final SiteBoundsLoader instance = SiteBoundsLoader._();

  SiteBoundsLoader._();

  // Cache for loaded results (keyed by bounds)
  final Map<String, SiteBoundsLoadResult> _cache = {};

  // Cache timeout (5 minutes)
  static const Duration _cacheTimeout = Duration(minutes: 5);

  /// Load sites for the given bounds, with automatic deduplication
  /// and optional flight count loading.
  Future<SiteBoundsLoadResult> loadSitesForBounds(
    LatLngBounds bounds, {
    int apiLimit = 50,
    bool includeFlightCounts = true,
    bool useCache = true,
  }) async {
    final stopwatch = Stopwatch()..start();

    // Create cache key from bounds
    final boundsKey = _getBoundsKey(bounds);

    // Check cache if enabled
    if (useCache && _cache.containsKey(boundsKey)) {
      final cached = _cache[boundsKey]!;
      final age = DateTime.now().difference(cached.loadedAt);
      if (age < _cacheTimeout) {
        LoggingService.info('SiteBoundsLoader: Using cached results for $boundsKey');
        return cached;
      } else {
        // Remove stale cache entry
        _cache.remove(boundsKey);
      }
    }

    try {
      // 1. Load from all sources in parallel
      final futures = <Future>[
        DatabaseService.instance.getSitesInBounds(
          north: bounds.north,
          south: bounds.south,
          east: bounds.east,
          west: bounds.west,
        ),
        ParaglidingEarthApi.instance.getSitesInBounds(
          bounds.north,
          bounds.south,
          bounds.east,
          bounds.west,
          limit: apiLimit,
          detailed: false, // Don't need full details for map markers
        ),
      ];

      // Add flight counts if requested
      if (includeFlightCounts) {
        futures.add(_loadFlightCountsForBounds(bounds));
      }

      final results = await Future.wait(futures);

      final localSites = results[0] as List<Site>;
      final apiSites = results[1] as List<ParaglidingSite>;
      final flightCounts = includeFlightCounts && results.length > 2
        ? results[2] as Map<int?, int?>
        : <int?, int?>{};

      // 2. Build unified site list with deduplication
      final unifiedSites = <UnifiedSite>[];
      final processedLocations = <String>{};

      // Add all local sites first (they take priority)
      for (final localSite in localSites) {
        final locationKey = _getLocationKey(localSite.latitude, localSite.longitude);
        processedLocations.add(locationKey);

        // Try to find matching API site for enrichment
        final matchingApiSite = _findMatchingApiSite(localSite, apiSites);

        final flightCount = flightCounts[localSite.id] ?? 0;

        if (matchingApiSite != null) {
          // Merged site with both local and API data
          unifiedSites.add(UnifiedSite.merged(
            localSite: localSite,
            apiSite: matchingApiSite,
            flightCount: flightCount,
          ));
        } else {
          // Local-only site
          unifiedSites.add(UnifiedSite.fromLocalSite(
            localSite,
            flightCount: flightCount,
          ));
        }
      }

      // Add API-only sites (not matching any local sites)
      for (final apiSite in apiSites) {
        final locationKey = _getLocationKey(apiSite.latitude, apiSite.longitude);
        if (!processedLocations.contains(locationKey)) {
          unifiedSites.add(UnifiedSite.fromApiSite(
            apiSite,
            flightCount: 0, // API-only sites have no local flights
          ));
        }
      }

      // 3. Create result
      final result = SiteBoundsLoadResult(
        sites: unifiedSites,
        bounds: bounds,
        loadedAt: DateTime.now(),
      );

      // 4. Cache if enabled
      if (useCache) {
        _cache[boundsKey] = result;
      }

      stopwatch.stop();
      LoggingService.performance(
        'SiteBoundsLoader',
        stopwatch.elapsed,
        'Loaded ${unifiedSites.length} sites (${localSites.length} local, ${apiSites.length} API)',
      );

      LoggingService.structured('SITES_BOUNDS_LOADED', {
        'bounds_key': boundsKey,
        'total_sites': unifiedSites.length,
        'local_sites': localSites.length,
        'api_sites': apiSites.length,
        'flown_sites': unifiedSites.where((s) => s.hasFlights).length,
        'new_sites': unifiedSites.where((s) => !s.hasFlights).length,
        'load_time_ms': stopwatch.elapsedMilliseconds,
        'cached': false,
      });

      return result;
    } catch (error, stackTrace) {
      LoggingService.error('SiteBoundsLoader: Failed to load sites', error, stackTrace);
      // Return empty result on error
      return SiteBoundsLoadResult(
        sites: [],
        bounds: bounds,
        loadedAt: DateTime.now(),
      );
    }
  }

  /// Clear the cache
  void clearCache() {
    _cache.clear();
    LoggingService.info('SiteBoundsLoader: Cache cleared');
  }

  /// Clear cache for specific bounds
  void clearCacheForBounds(LatLngBounds bounds) {
    final key = _getBoundsKey(bounds);
    if (_cache.remove(key) != null) {
      LoggingService.info('SiteBoundsLoader: Cache cleared for $key');
    }
  }

  /// Load flight counts for sites in bounds
  Future<Map<int?, int?>> _loadFlightCountsForBounds(LatLngBounds bounds) async {
    try {
      // Get all sites in bounds with their flight counts
      final sites = await DatabaseService.instance.getSitesInBounds(
        north: bounds.north,
        south: bounds.south,
        east: bounds.east,
        west: bounds.west,
      );

      final counts = <int?, int?>{};
      for (final site in sites) {
        if (site.id != null && site.flightCount != null && site.flightCount! > 0) {
          counts[site.id] = site.flightCount;
        }
      }

      return counts;
    } catch (error, stackTrace) {
      LoggingService.error('SiteBoundsLoader: Failed to load flight counts', error, stackTrace);
      return {};
    }
  }

  /// Find matching API site for a local site
  ParaglidingSite? _findMatchingApiSite(Site localSite, List<ParaglidingSite> apiSites) {
    const tolerance = 0.001; // ~100m

    for (final apiSite in apiSites) {
      if ((localSite.latitude - apiSite.latitude).abs() < tolerance &&
          (localSite.longitude - apiSite.longitude).abs() < tolerance) {
        return apiSite;
      }
    }
    return null;
  }

  /// Get location key for deduplication
  String _getLocationKey(double latitude, double longitude) {
    return '${latitude.toStringAsFixed(6)},${longitude.toStringAsFixed(6)}';
  }

  /// Generate cache key from bounds
  String _getBoundsKey(LatLngBounds bounds) {
    return '${bounds.north.toStringAsFixed(6)}_'
           '${bounds.south.toStringAsFixed(6)}_'
           '${bounds.east.toStringAsFixed(6)}_'
           '${bounds.west.toStringAsFixed(6)}';
  }
}
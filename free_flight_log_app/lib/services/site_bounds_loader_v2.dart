import 'package:flutter_map/flutter_map.dart';
import '../data/models/site.dart';
import '../data/models/paragliding_site.dart';
import 'database_service.dart';
import 'pge_sites_database_service.dart';
import 'paragliding_earth_api.dart';
import 'logging_service.dart';

/// Enhanced site bounds loader that uses local PGE database first
/// Falls back to API only for detailed site information
class SiteBoundsLoaderV2 {
  static final SiteBoundsLoaderV2 instance = SiteBoundsLoaderV2._();

  SiteBoundsLoaderV2._();

  // No caching - always fetch fresh data from local database

  /// Load sites for the given bounds using local database first
  /// Falls back to API only if local database is not available
  /// Flight counts are now always included using optimized JOIN query
  Future<SiteBoundsLoadResult> loadSitesForBounds(
    LatLngBounds bounds, {
    int limit = 100,
    bool includeFlightCounts = true, // Kept for backward compatibility but ignored
  }) async {
    final stopwatch = Stopwatch()..start();

    // Create bounds key for logging
    final boundsKey = _getBoundsKey(bounds);

    try {
      // Check if local PGE database is available
      final isPgeDataAvailable = await PgeSitesDatabaseService.instance.isDataAvailable();

      LoggingService.structured('SITES_BOUNDS_LOADER_V2', {
        'pge_data_available': isPgeDataAvailable,
        'bounds': '$boundsKey',
      });

      // Prepare futures list
      final futures = <Future>[];

      // 1. Load local user sites WITH flight counts using optimized query
      futures.add(DatabaseService.instance.getSitesInBoundsWithFlightCounts(
        north: bounds.north,
        south: bounds.south,
        east: bounds.east,
        west: bounds.west,
      ));

      // 2. Load PGE sites from local database only
      if (isPgeDataAvailable) {
        // Use local PGE database (fast)
        futures.add(PgeSitesDatabaseService.instance.getSitesInBounds(
          north: bounds.north,
          south: bounds.south,
          east: bounds.east,
          west: bounds.west,
        ));
      } else {
        // No local database available - return empty list
        futures.add(Future.value(<ParaglidingSite>[]));
      }

      final results = await Future.wait(futures);

      // Extract sites and flight counts from optimized query result
      final sitesWithCounts = results[0] as Map<Site, int>;
      final localSites = sitesWithCounts.keys.toList();
      final pgeSites = results[1] as List<ParaglidingSite>;

      // Build flight counts map with site ID as key
      final flightCounts = <int?, int?>{};
      for (final entry in sitesWithCounts.entries) {
        if (entry.key.id != null) {
          flightCounts[entry.key.id] = entry.value;
        }
      }

      // PGE-first approach: Start with PGE sites (which have wind directions) with FK enhancements
      final enrichedSites = <ParaglidingSite>[];
      final processedLocations = <String>{};


      // Process all PGE sites and enrich with flight data
      for (final pgeSite in pgeSites) {
        final locationKey = _getLocationKey(pgeSite.latitude, pgeSite.longitude);
        processedLocations.add(locationKey);

        // Find matching local site using FK-first approach, then coordinate fallback
        final matchingLocalSite = _findMatchingLocalSiteByForeignKey(pgeSite, localSites);
        final flightCount = matchingLocalSite != null
            ? (flightCounts[matchingLocalSite.id] ?? 0)
            : 0;

        // Create enriched ParaglidingSite with flight data
        enrichedSites.add(pgeSite.copyWith(flightCount: flightCount));
      }

      // Add local-only sites (sites with flights but not in PGE database)
      for (final localSite in localSites) {
        final locationKey = _getLocationKey(localSite.latitude, localSite.longitude);
        if (!processedLocations.contains(locationKey)) {
          final flightCount = flightCounts[localSite.id] ?? 0;

          // Convert local Site to ParaglidingSite
          enrichedSites.add(ParaglidingSite(
            id: localSite.id,  // CRITICAL: Preserve site ID for operations
            name: localSite.name,
            latitude: localSite.latitude,
            longitude: localSite.longitude,
            altitude: localSite.altitude?.toInt(),
            country: localSite.country,
            siteType: 'launch', // Default for local sites
            flightCount: flightCount,
          ));
          processedLocations.add(locationKey); // Track to prevent coord duplicates
        }
      }

      // Create result
      final result = SiteBoundsLoadResult(
        sites: enrichedSites,
        bounds: bounds,
        loadedAt: DateTime.now(),
      );

      // No caching - always return fresh results

      stopwatch.stop();

      LoggingService.performance(
        'SiteBoundsLoaderV2',
        stopwatch.elapsed,
        'Loaded ${enrichedSites.length} sites (${localSites.length} local, ${pgeSites.length} PGE from local DB)',
      );

      LoggingService.structured('SITES_BOUNDS_LOADED_V2', {
        'bounds_key': boundsKey,
        'total_sites': enrichedSites.length,
        'local_sites': localSites.length,
        'pge_sites': pgeSites.length,
        'flown_sites': enrichedSites.where((s) => s.hasFlights).length,
        'new_sites': enrichedSites.where((s) => !s.hasFlights).length,
        'data_source': isPgeDataAvailable ? 'local_database' : 'none',
        'load_time_ms': stopwatch.elapsedMilliseconds,
        'cached': false,
      });

      return result;

    } catch (error, stackTrace) {
      LoggingService.error('SiteBoundsLoaderV2: Failed to load sites', error, stackTrace);
      // Return empty result on error
      return SiteBoundsLoadResult(
        sites: [],
        bounds: bounds,
        loadedAt: DateTime.now(),
      );
    }
  }

  /// Search sites by name using local database only
  Future<List<ParaglidingSite>> searchSitesByName(
    String query, {
    double? centerLatitude,
    double? centerLongitude,
  }) async {
    try {
      // Check if local PGE database is available
      final isPgeDataAvailable = await PgeSitesDatabaseService.instance.isDataAvailable();

      if (isPgeDataAvailable) {
        // Use local database for search (fast)
        return await PgeSitesDatabaseService.instance.searchSitesByName(
          query: query,
          centerLatitude: centerLatitude,
          centerLongitude: centerLongitude,
        );
      } else {
        // No local database available
        LoggingService.info('SiteBoundsLoaderV2: Local database not available for search');
        return [];
      }
    } catch (error, stackTrace) {
      LoggingService.error('SiteBoundsLoaderV2: Search failed', error, stackTrace);
      return [];
    }
  }

  /// Load detailed site information (always uses API for full details)
  Future<Map<String, dynamic>?> getSiteDetails(double latitude, double longitude) async {
    try {
      // Always use API for detailed information
      // Local database only has basic fields
      return await ParaglidingEarthApi.instance.getSiteDetails(latitude, longitude);
    } catch (error, stackTrace) {
      LoggingService.error('SiteBoundsLoaderV2: Failed to get site details', error, stackTrace);
      return null;
    }
  }

  // Cache methods removed - no longer needed
  // _loadFlightCountsForBounds removed - now using optimized JOIN query in DatabaseService


  /// Find matching local site for a PGE site using foreign key relationship first
  /// Falls back to coordinate-based matching for unlinked sites
  Site? _findMatchingLocalSiteByForeignKey(ParaglidingSite pgeSite, List<Site> localSites) {
    // Primary: Use foreign key relationship if available
    final linkedSite = localSites.where((localSite) =>
      localSite.pgeSiteId != null && localSite.pgeSiteId == pgeSite.id).firstOrNull;

    if (linkedSite != null) {
      return linkedSite;
    }

    // Fallback: Use coordinate-based matching for unlinked sites
    const tolerance = 0.001; // ~100m
    for (final localSite in localSites) {
      if (localSite.pgeSiteId == null && // Only check unlinked sites
          (pgeSite.latitude - localSite.latitude).abs() < tolerance &&
          (pgeSite.longitude - localSite.longitude).abs() < tolerance) {
        return localSite;
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

/// Result of loading sites for a bounding box
class SiteBoundsLoadResult {
  final List<ParaglidingSite> sites;
  final LatLngBounds bounds;
  final DateTime loadedAt;

  const SiteBoundsLoadResult({
    required this.sites,
    required this.bounds,
    required this.loadedAt,
  });

  // Convenience filters
  List<ParaglidingSite> get sitesWithFlights => sites.where((s) => s.hasFlights).toList();
  List<ParaglidingSite> get sitesWithoutFlights => sites.where((s) => !s.hasFlights).toList();
}
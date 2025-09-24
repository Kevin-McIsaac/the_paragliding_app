import 'package:flutter_map/flutter_map.dart';
import '../data/models/site.dart';
import '../data/models/paragliding_site.dart';
import '../data/models/unified_site.dart';
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
  Future<SiteBoundsLoadResult> loadSitesForBounds(
    LatLngBounds bounds, {
    int limit = 100,
    bool includeFlightCounts = true,
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

      // 1. Always load local user sites (from flights database)
      futures.add(DatabaseService.instance.getSitesInBounds(
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
          limit: limit,
        ));
      } else {
        // No local database available - return empty list
        futures.add(Future.value(<ParaglidingSite>[]));
      }

      // 3. Add flight counts if requested
      if (includeFlightCounts) {
        futures.add(_loadFlightCountsForBounds(bounds));
      }

      final results = await Future.wait(futures);

      final localSites = results[0] as List<Site>;
      final pgeSites = results[1] as List<ParaglidingSite>;
      final flightCounts = includeFlightCounts && results.length > 2
        ? results[2] as Map<int?, int?>
        : <int?, int?>{};

      // Build unified site list with deduplication
      final unifiedSites = <UnifiedSite>[];
      final processedLocations = <String>{};

      // Add all local sites first (they take priority)
      for (final localSite in localSites) {
        final locationKey = _getLocationKey(localSite.latitude, localSite.longitude);
        processedLocations.add(locationKey);

        // Try to find matching PGE site for enrichment
        final matchingPgeSite = _findMatchingPgeSite(localSite, pgeSites);

        final flightCount = flightCounts[localSite.id] ?? 0;

        if (matchingPgeSite != null) {
          // Merged site with both local and PGE data
          unifiedSites.add(UnifiedSite.merged(
            localSite: localSite,
            apiSite: matchingPgeSite,
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

      // Add PGE-only sites (not matching any local sites)
      for (final pgeSite in pgeSites) {
        final locationKey = _getLocationKey(pgeSite.latitude, pgeSite.longitude);
        if (!processedLocations.contains(locationKey)) {
          unifiedSites.add(UnifiedSite.fromApiSite(
            pgeSite,
            flightCount: 0, // PGE-only sites have no local flights
          ));
        }
      }

      // Create result
      final result = SiteBoundsLoadResult(
        sites: unifiedSites,
        bounds: bounds,
        loadedAt: DateTime.now(),
      );

      // No caching - always return fresh results

      stopwatch.stop();

      LoggingService.performance(
        'SiteBoundsLoaderV2',
        stopwatch.elapsed,
        'Loaded ${unifiedSites.length} sites (${localSites.length} local, ${pgeSites.length} PGE from local DB)',
      );

      LoggingService.structured('SITES_BOUNDS_LOADED_V2', {
        'bounds_key': boundsKey,
        'total_sites': unifiedSites.length,
        'local_sites': localSites.length,
        'pge_sites': pgeSites.length,
        'flown_sites': unifiedSites.where((s) => s.hasFlights).length,
        'new_sites': unifiedSites.where((s) => !s.hasFlights).length,
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

  /// Load flight counts for sites in bounds
  Future<Map<int?, int?>> _loadFlightCountsForBounds(LatLngBounds bounds) async {
    try {
      final sites = await DatabaseService.instance.getSitesInBounds(
        north: bounds.north,
        south: bounds.south,
        east: bounds.east,
        west: bounds.west,
      );

      final counts = <int?, int?>{};

      for (final site in sites) {
        if (site.id != null) {
          final flightCount = await DatabaseService.instance.getFlightCountForSite(site.id!);
          if (flightCount > 0) {
            counts[site.id] = flightCount;
          }
        }
      }

      LoggingService.info('SiteBoundsLoaderV2: Loaded flight counts for ${counts.length} sites');
      return counts;

    } catch (error, stackTrace) {
      LoggingService.error('SiteBoundsLoaderV2: Failed to load flight counts', error, stackTrace);
      return {};
    }
  }

  /// Find matching PGE site for a local site
  ParaglidingSite? _findMatchingPgeSite(Site localSite, List<ParaglidingSite> pgeSites) {
    const tolerance = 0.001; // ~100m

    for (final pgeSite in pgeSites) {
      if ((localSite.latitude - pgeSite.latitude).abs() < tolerance &&
          (localSite.longitude - pgeSite.longitude).abs() < tolerance) {
        return pgeSite;
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
import '../data/models/paragliding_site.dart';
import '../data/models/site.dart';
import 'database_service.dart';
import '../services/logging_service.dart';
import 'paragliding_earth_api.dart';

class SiteMatchingService {
  static SiteMatchingService? _instance;
  static SiteMatchingService get instance => _instance ??= SiteMatchingService._();
  
  SiteMatchingService._();

  List<ParaglidingSite>? _sites;
  bool _isInitialized = false;
  bool _useApi = true; // Enable API by default, can be configured
  final DatabaseService _databaseService = DatabaseService.instance;

  /// Initialize the service by loading sites from user's flight log
  /// This provides personalized fallback based on actual flight history
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Load sites that have been used in actual flights
      final usedSites = await _databaseService.getSitesUsedInFlights();
      
      // Convert Site objects to ParaglidingSite objects
      _sites = usedSites.map((site) => _convertSiteToParaglidingSite(site)).toList();
      _isInitialized = true;
      
      if (_sites!.isEmpty) {
        LoggingService.info('SiteMatchingService: No flight log sites available - using API-only mode');
      } else {
        LoggingService.info('SiteMatchingService: Loaded ${_sites!.length} sites from flight log (personalized fallback)');
      }
    } catch (e) {
      LoggingService.error('SiteMatchingService: Error loading flight log sites', e);
      // Initialize with empty list if loading fails
      _sites = [];
      _isInitialized = true;
    }
  }

  /// Find the nearest paragliding launch site to given coordinates
  /// Uses hybrid approach: flight log first for speed, API for enhanced data
  /// Returns null if no site found within maxDistance (meters)
  Future<ParaglidingSite?> findNearestSite(
    double latitude, 
    double longitude, {
    double maxDistance = 500, // 500m default - typical launch site search radius
    String? preferredType, // 'launch' or null for any
  }) async {
    // Try local flight log first (much faster for known sites)
    final localSite = _findNearestSiteLocal(latitude, longitude, maxDistance: maxDistance, preferredType: preferredType);
    
    if (localSite != null) {
      // Found in local database - use it regardless of country info
      if (localSite.country == null || localSite.country!.isEmpty) {
        LoggingService.info('SiteMatchingService: Found site in flight log: "${localSite.name}" (no country info, skipping API enhancement)');
      } else {
        LoggingService.info('SiteMatchingService: Found site in flight log: "${localSite.name}" with country: ${localSite.country}');
      }
      return localSite;
    }

    // No local site found, try API for new sites
    if (_useApi) {
      try {
        final apiSite = await ParaglidingEarthApi.instance.findNearestSite(
          latitude,
          longitude,
          maxDistanceKm: maxDistance / 1000.0, // Convert meters to km
          preferredType: preferredType,
        );
        
        if (apiSite != null) {
          LoggingService.info('SiteMatchingService: Found new site via API: "${apiSite.name}" at ${apiSite.latitude.toStringAsFixed(4)}, ${apiSite.longitude.toStringAsFixed(4)}');
          LoggingService.info('SiteMatchingService: API site location info - Country: "${apiSite.country ?? 'null'}"');
          return apiSite;
        }
      } catch (e) {
        LoggingService.warning('SiteMatchingService: API lookup failed: $e');
      }
    }

    // No site found in either local database or API
    LoggingService.info('SiteMatchingService: No site found within ${maxDistance}m of ${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}');
    return null;
  }

  /// Find the nearest site using local database only
  /// Returns null if no site found within maxDistance (meters)
  ParaglidingSite? _findNearestSiteLocal(
    double latitude, 
    double longitude, {
    double maxDistance = 500, // 500m default - typical launch site search radius
    String? preferredType, // 'launch' or null for any
  }) {
    if (!_isInitialized || _sites == null || _sites!.isEmpty) {
      return null;
    }

    ParaglidingSite? nearestSite;
    double nearestDistance = double.infinity;

    for (final site in _sites!) {
      // Filter by type if specified
      if (preferredType != null && 
          site.siteType != preferredType && 
          site.siteType != 'both') {
        continue;
      }

      final distance = site.distanceTo(latitude, longitude);
      
      if (distance <= maxDistance && distance < nearestDistance) {
        nearestDistance = distance;
        nearestSite = site;
      }
    }

    return nearestSite;
  }

  /// Find the nearest launch site
  Future<ParaglidingSite?> findNearestLaunchSite(
    double latitude, 
    double longitude, {
    double maxDistance = 500, // 500m for launches (more precise)
  }) async {
    return await findNearestSite(
      latitude, 
      longitude, 
      maxDistance: maxDistance,
      preferredType: 'launch',
    );
  }


  /// Find all sites within a given radius
  List<ParaglidingSite> findSitesInRadius(
    double latitude,
    double longitude,
    double radiusMeters,
  ) {
    if (!_isInitialized || _sites == null) {
      return [];
    }

    final nearbyStites = <ParaglidingSite>[];

    for (final site in _sites!) {
      final distance = site.distanceTo(latitude, longitude);
      if (distance <= radiusMeters) {
        nearbyStites.add(site);
      }
    }

    // Sort by distance
    nearbyStites.sort((a, b) {
      final distanceA = a.distanceTo(latitude, longitude);
      final distanceB = b.distanceTo(latitude, longitude);
      return distanceA.compareTo(distanceB);
    });

    return nearbyStites;
  }

  /// Search sites by name (case-insensitive)
  List<ParaglidingSite> searchByName(String query) {
    if (!_isInitialized || _sites == null || query.trim().isEmpty) {
      return [];
    }

    final queryLower = query.toLowerCase().trim();
    final matches = <ParaglidingSite>[];

    for (final site in _sites!) {
      if (site.name.toLowerCase().contains(queryLower) ||
          (site.country?.toLowerCase().contains(queryLower) ?? false) ||
          (site.region?.toLowerCase().contains(queryLower) ?? false)) {
        matches.add(site);
      }
    }

    // Sort by relevance: exact matches first, then partial matches
    matches.sort((a, b) {
      final aNameLower = a.name.toLowerCase();
      final bNameLower = b.name.toLowerCase();

      // Exact name match gets highest priority
      if (aNameLower == queryLower && bNameLower != queryLower) return -1;
      if (bNameLower == queryLower && aNameLower != queryLower) return 1;

      // Name starts with query gets second priority
      final aStartsWith = aNameLower.startsWith(queryLower);
      final bStartsWith = bNameLower.startsWith(queryLower);
      if (aStartsWith && !bStartsWith) return -1;
      if (bStartsWith && !aStartsWith) return 1;

      // Sort by popularity, then rating, then name
      final aScore = a.popularity ?? 0;
      final bScore = b.popularity ?? 0;
      if (aScore != bScore) return bScore.compareTo(aScore);

      if (a.rating != b.rating) return b.rating.compareTo(a.rating);

      return a.name.compareTo(b.name);
    });

    return matches;
  }

  /// Get sites by country
  List<ParaglidingSite> getSitesByCountry(String country) {
    if (!_isInitialized || _sites == null) {
      return [];
    }

    return _sites!
        .where((site) => site.country?.toLowerCase() == country.toLowerCase())
        .toList();
  }

  /// Get statistics about loaded sites
  Map<String, dynamic> getStatistics() {
    if (!_isInitialized || _sites == null) {
      return {'total': 0};
    }

    final stats = <String, dynamic>{
      'total': _sites!.length,
      'launch_sites': _sites!.where((s) => s.siteType == 'launch' || s.siteType == 'both').length,
      'countries': _sites!.map((s) => s.country).where((c) => c != null).toSet().length,
      'rated_sites': _sites!.where((s) => s.rating > 0).length,
    };

    // Top countries by site count
    final countryCount = <String, int>{};
    for (final site in _sites!) {
      if (site.country != null) {
        countryCount[site.country!] = (countryCount[site.country!] ?? 0) + 1;
      }
    }

    stats['top_countries'] = countryCount.entries
        .toList()
        ..sort((a, b) => b.value.compareTo(a.value))
        ..take(10)
        .map((e) => {'country': e.key, 'count': e.value})
        .toList();

    return stats;
  }

  /// Get a site name suggestion for given coordinates
  /// Returns either a matched site name or a formatted coordinate string
  /// Now uses API with fallback to local database
  Future<String> getSiteNameSuggestion(
    double latitude, 
    double longitude, {
    String prefix = '',
    String? siteType,
  }) async {
    // Try to find a matching paragliding site (API + fallback)
    final matchingSite = await findNearestSite(
      latitude, 
      longitude,
      maxDistance: siteType == 'launch' ? 500 : 1000,
      preferredType: siteType,
    );

    if (matchingSite != null) {
      final siteName = prefix.isNotEmpty ? '$prefix ${matchingSite.name}' : matchingSite.name;
      LoggingService.info('SiteMatchingService: Using site name: $siteName');
      return siteName;
    }

    // Fallback to coordinate-based name
    final latStr = '${latitude.toStringAsFixed(3)}°${latitude >= 0 ? 'N' : 'S'}';
    final lonStr = '${longitude.abs().toStringAsFixed(3)}°${longitude >= 0 ? 'E' : 'W'}';
    final coordName = '$latStr $lonStr';
    final finalName = prefix.isNotEmpty ? '$prefix $coordName' : coordName;
    
    LoggingService.info('SiteMatchingService: No site found, using coordinates: $finalName');
    return finalName;
  }

  /// Check if service is initialized and ready to use
  bool get isReady => _isInitialized;

  /// Get the number of loaded sites
  int get siteCount => _sites?.length ?? 0;

  /// Reload sites from flight log (useful when new flights are added)
  Future<void> reload() async {
    _isInitialized = false;
    _sites = null;
    await initialize();
  }

  /// Refresh site list after new flights are imported
  /// Call this after IGC imports to update the personalized fallback
  Future<void> refreshAfterFlightImport() async {
    if (_isInitialized) {
      await reload();
    }
  }

  /// Enable or disable API usage
  void setApiEnabled(bool enabled) {
    _useApi = enabled;
    LoggingService.info('SiteMatchingService: API usage ${enabled ? 'enabled' : 'disabled'}');
  }

  /// Check if API is enabled
  bool get isApiEnabled => _useApi;

  /// Test API connectivity
  Future<bool> testApiConnection() async {
    if (!_useApi) return false;
    return await ParaglidingEarthApi.instance.testConnection();
  }

  /// Get API cache statistics  
  Map<String, dynamic> getApiCacheStats() {
    return ParaglidingEarthApi.instance.getCacheStats();
  }

  /// Clear API cache (no-op since caching was removed)
  void clearApiCache() {
    // No-op: HTTP client caching handles this automatically
  }

  /// Convert a Site object (from database) to ParaglidingSite object (for compatibility)
  ParaglidingSite _convertSiteToParaglidingSite(Site site) {
    // Determine site type based on name patterns (fallback logic)
    String siteType = 'launch'; // Default
    final name = site.name.toLowerCase();
    if (name.contains('landing') || 
        name.contains('atterrissage') ||
        name.contains('landeplatz') ||
        name.contains('campo')) {
      siteType = 'landing';
    }

    return ParaglidingSite(
      name: site.name,
      latitude: site.latitude,
      longitude: site.longitude,
      altitude: site.altitude?.toInt(), // Convert double? to int?
      description: 'Flight log site', // Simple description for user sites
      windDirections: [], // Not available in user sites
      siteType: siteType,
      rating: 4, // User sites get good rating since they're proven locations
      country: null, // Not stored in user sites
      region: null, // Not stored in user sites  
      popularity: 75.0, // High popularity for user's personal sites
    );
  }
}
import '../data/models/site.dart';
import '../data/models/paragliding_site.dart';

/// Shared utilities for site operations across different map components
class SiteUtils {
  static const double _coordinateTolerance = 0.000001; // ~0.1 meter tolerance for floating point comparison
  
  /// Create a unique key for site flight status lookup
  /// Format: "latitude,longitude" with 6 decimal places precision
  static String createSiteKey(double latitude, double longitude) {
    return '${latitude.toStringAsFixed(6)},${longitude.toStringAsFixed(6)}';
  }
  
  /// Check if an API site is already represented by a local site
  /// Uses foreign key relationship when available, falls back to coordinates
  /// Used to avoid showing duplicate markers on maps
  static bool isDuplicateApiSite(ParaglidingSite apiSite, List<Site> localSites) {
    // First check if any local site has this API site linked via foreign key
    final linkedSite = localSites.where((localSite) =>
      localSite.pgeSiteId != null && localSite.pgeSiteId == apiSite.id).firstOrNull;

    if (linkedSite != null) {
      return true; // Found exact FK match
    }

    // Fallback to coordinate-based matching for unlinked sites
    return localSites.any((localSite) =>
      localSite.pgeSiteId == null && // Only check unlinked sites
      (localSite.latitude - apiSite.latitude).abs() < _coordinateTolerance &&
      (localSite.longitude - apiSite.longitude).abs() < _coordinateTolerance
    );
  }
  
  /// Check if two coordinates are considered the same location
  /// Useful for site matching and deduplication
  static bool areCoordinatesEqual(double lat1, double lng1, double lat2, double lng2) {
    return (lat1 - lat2).abs() < _coordinateTolerance &&
           (lng1 - lng2).abs() < _coordinateTolerance;
  }
  
  /// Find a local site that matches the given coordinates
  /// Returns null if no match is found
  static Site? findMatchingLocalSite(double latitude, double longitude, List<Site> localSites) {
    return localSites.where((site) =>
      areCoordinatesEqual(latitude, longitude, site.latitude, site.longitude)
    ).firstOrNull;
  }

  /// Find a local site that is linked to the given PGE site ID
  /// More efficient than coordinate-based matching
  static Site? findLinkedLocalSite(int pgeSiteId, List<Site> localSites) {
    return localSites.where((site) => site.pgeSiteId == pgeSiteId).firstOrNull;
  }

  /// Check if a site is linked to PGE data
  static bool isSiteLinkedToPge(Site site) {
    return site.pgeSiteId != null;
  }

  /// Get sites grouped by their linking status for UI purposes
  static Map<String, List<Site>> groupSitesByLinkingStatus(List<Site> sites) {
    final linked = sites.where((site) => site.pgeSiteId != null).toList();
    final unlinked = sites.where((site) => site.pgeSiteId == null).toList();

    return {
      'linked': linked,
      'unlinked': unlinked,
    };
  }
}
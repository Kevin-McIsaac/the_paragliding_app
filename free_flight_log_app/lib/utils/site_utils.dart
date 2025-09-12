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
  /// Used to avoid showing duplicate markers on maps
  static bool isDuplicateApiSite(ParaglidingSite apiSite, List<Site> localSites) {
    return localSites.any((localSite) =>
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
}
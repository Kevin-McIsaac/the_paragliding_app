/// Centralized constants for map-related functionality
class MapConstants {
  // Site loading limits
  static const int defaultSiteLimit = 100;
  static const int flightMapSiteLimit = 100; // Same as default for consistency

  // Debouncing durations
  static const int mapBoundsDebounceMs = 300; // Reduced from 500 for better responsiveness
  static const int searchDebounceMs = 300;
  static const Duration animationDuration = Duration(milliseconds: 300);

  // Site management distances
  static const double launchRadiusMeters = 500.0;
  static const double siteProximityMeters = 500.0;

  // Map defaults
  static const double defaultZoom = 13.0;
  static const double minZoom = 1.0;
  static const double maxZoom = 22.0;
  static const double maxAltitudeFt = 10000.0;

  // Map UI constants
  static const double mapPadding = 0.005;

  // Cache settings (if needed in future)
  static const int maxCacheSize = 20;

  // Loading delays
  static const int loadingIndicatorDelayMs = 500;

  MapConstants._(); // Prevent instantiation
}
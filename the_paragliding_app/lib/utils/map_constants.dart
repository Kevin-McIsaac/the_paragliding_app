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

  // Weather forecast and station display
  static const double minForecastZoom = 10.0; // Minimum zoom for forecasts and weather stations
  static const int zoomDisplayDecimals = 1; // Zoom display precision (0.1 increments)

  /// Round zoom level to display precision (1 decimal place)
  /// This ensures behavior matches what users see in the UI
  static double roundZoomForDisplay(double zoom) {
    return (zoom * 10).round() / 10.0;
  }

  // Weather station caching (METAR data)
  static const Duration weatherStationCacheTTL = Duration(minutes: 30); // METAR updates every 30min
  static const Duration stationListCacheTTL = Duration(minutes: 30); // Combined with weather data

  // NWS-specific caching
  static const Duration nwsStationListCacheTTL = Duration(hours: 24); // Stations don't move/change
  static const Duration nwsObservationCacheTTL = Duration(minutes: 10); // Observations update 1-60min

  // Pioupiou-specific caching (global station list strategy)
  static const Duration pioupiouStationListCacheTTL = Duration(hours: 24); // Stations don't move
  static const Duration pioupiouMeasurementsCacheTTL = Duration(minutes: 20); // Wind updates frequently

  // Map UI constants
  static const double mapPadding = 0.005;

  // Cache settings (if needed in future)
  static const int maxCacheSize = 20;

  // Loading delays
  static const int loadingIndicatorDelayMs = 500;

  MapConstants._(); // Prevent instantiation
}
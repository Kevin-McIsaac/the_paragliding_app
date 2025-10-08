import 'package:flutter_map/flutter_map.dart';
import '../../data/models/weather_station.dart';
import '../../data/models/wind_data.dart';
import '../../data/models/weather_station_source.dart';

/// Abstract interface for weather station data providers
/// Allows multiple data sources (METAR, NOAA CDO, etc.) to be used interchangeably
abstract class WeatherStationProvider {
  /// Unique provider identifier (e.g., "metar", "noaa-cdo")
  WeatherStationSource get source;

  /// Human-readable provider name for UI display
  String get displayName;

  /// Short description for UI (e.g., filter dialog subtitles)
  String get description;

  /// Full attribution name for data source (e.g., "Aviation Weather Center")
  String get attributionName;

  /// Attribution URL for data source (e.g., "https://aviationweather.gov/")
  String get attributionUrl;

  /// Cache duration for this provider's data
  /// Weather data freshness varies by provider
  Duration get cacheTTL;

  /// Whether this provider requires an API key
  bool get requiresApiKey;

  /// Fetch weather stations within a bounding box
  /// Returns list of stations with coordinates and metadata
  /// May or may not include wind data depending on provider API
  Future<List<WeatherStation>> fetchStations(LatLngBounds bounds);

  /// Fetch current weather data for a list of stations
  /// Returns map of station ID -> WindData
  /// Some providers return weather data with station metadata, others require separate call
  Future<Map<String, WindData>> fetchWeatherData(
    List<WeatherStation> stations,
  );

  /// Check if provider is properly configured and ready to use
  /// For example, checks if required API key is present
  Future<bool> isConfigured();

  /// Clear any cached data for this provider
  void clearCache();

  /// Get cache statistics for debugging
  Map<String, dynamic> getCacheStats();
}

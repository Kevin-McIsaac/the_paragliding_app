/// Source/provider for weather station data
///
/// Pure enum identifier for weather station data providers.
/// All provider-specific information (names, URLs, methods) is in the provider classes.
/// Use source.name to get string ID ("metar", "nws", etc.)
enum WeatherStationSource {
  /// METAR data from aviationweather.gov
  /// Airport weather stations with real-time observations
  metar,

  /// National Weather Service (NWS) from api.weather.gov
  /// Real-time weather observations from non-airport stations
  nws,
}

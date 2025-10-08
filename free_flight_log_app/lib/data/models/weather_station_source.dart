/// Source/provider for weather station data
///
/// Pure enum identifier for weather station data providers.
/// All provider-specific information (names, URLs, methods) is in the provider classes.
/// Use source.name to get string ID ("awcMetar", "nws", etc.)
enum WeatherStationSource {
  /// Aviation Weather Center (METAR format) from aviationweather.gov
  /// Airport weather stations with real-time observations in METAR format
  awcMetar,

  /// National Weather Service (NWS) from api.weather.gov
  /// Real-time weather observations from non-airport stations
  nws,

  /// Pioupiou/OpenWindMap from api.pioupiou.fr
  /// Community wind stations with global coverage
  pioupiou,
}

/// Weather forecast models available from Open-Meteo API
/// Note: Ensemble models (like BOM) are not included as they don't provide standard aggregated fields
enum WeatherModel {
  bestMatch('best_match', 'Best Match', 'Auto', 'Automatic model selection for optimal accuracy'),
  gfsSeamless('gfs_seamless', 'NOAA GFS (USA)', 'GFS', 'Global, best for North America, 13km resolution, extends to 16 days'),
  iconSeamless('icon_seamless', 'DWD ICON (Germany)', 'ICON', 'Combines ICON-D2 (2km), ICON-EU (7km), and ICON Global, best for Europe'),
  ecmwfIfs025('ecmwf_ifs025', 'ECMWF IFS', 'ECMWF', 'Widely regarded as most accurate globally for medium-range forecasts (~25km)'),
  meteofranceSeamless('meteofrance_seamless', 'Météo-France', 'MF', 'Combines AROME (1.5km) and ARPEGE models, excellent for France/Western Europe'),
  jmaSeamless('jma_seamless', 'JMA (Japan)', 'JMA', 'Japan Meteorological Agency - Best for East Asia/Japan'),
  gemSeamless('gem_seamless', 'GEM (Canada)', 'GEM', 'Canadian model - Best for Canada');

  /// API parameter value for Open-Meteo (e.g., "gfs_seamless")
  final String apiValue;

  /// Short display name (e.g., "NOAA GFS (USA)")
  final String displayName;

  /// Abbreviated name for compact UI (e.g., "GFS")
  final String abbrev;

  /// Full description for dropdown
  final String description;

  const WeatherModel(this.apiValue, this.displayName, this.abbrev, this.description);

  /// Get display text for dropdown (name + description)
  String get dropdownText => '$displayName - $description';

  /// Get attribution text for display (e.g., "Open-Meteo (Best Match)")
  String get attributionText => 'Forecast: Open-Meteo ($displayName)';

  /// Parse from API value string (e.g., "gfs_seamless" -> WeatherModel.gfsSeamless)
  static WeatherModel fromApiValue(String apiValue) {
    return WeatherModel.values.firstWhere(
      (model) => model.apiValue == apiValue,
      orElse: () => WeatherModel.bestMatch,
    );
  }

  /// Get models parameter for API URL (null for best match)
  String? get apiParameter {
    // Best match doesn't need models parameter (uses default)
    if (this == WeatherModel.bestMatch) return null;
    return apiValue;
  }
}

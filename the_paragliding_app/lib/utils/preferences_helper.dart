import 'package:shared_preferences/shared_preferences.dart';

/// Helper class for managing app preferences using SharedPreferences
/// Uses the stable legacy API for reliable persistence
class PreferencesHelper {
  // Cesium 3D Map preferences
  static const String cesiumSceneModeKey = 'cesium_scene_mode';
  static const String cesiumBaseMapKey = 'cesium_base_map';
  static const String cesiumTerrainEnabledKey = 'cesium_terrain_enabled';
  static const String cesiumNavigationHelpDialogKey = 'cesium_navigation_help_dialog_open';
  static const String cesiumFlyThroughModeKey = 'cesium_fly_through_mode';
  static const String cesiumTrailDurationKey = 'cesium_trail_duration';
  static const String cesiumQualityKey = 'cesium_quality';
  
  // Default values
  static const int defaultCesiumTrailDuration = 180; // 3 minutes in seconds
  static const List<int> validCesiumTrailDurations = [60, 120, 180, 240, 300]; // 1-5 minutes in seconds
  
  // Cesium Ion Token preferences (for premium maps)
  static const String cesiumUserTokenKey = 'cesium_user_token';
  static const String cesiumTokenValidatedKey = 'cesium_token_validated';
  static const String cesiumTokenValidationDateKey = 'cesium_token_validation_date';
  
  // IGC Import preferences
  static const String igcLastFolderKey = 'igc_last_folder';
  
  // OpenAIP preferences
  static const String openAipApiKeyKey = 'openaip_api_key';
  static const String openAipAirspaceEnabledKey = 'openaip_airspace_enabled';
  static const String openAipOverlayOpacityKey = 'openaip_overlay_opacity';
  
  // Default values for OpenAIP
  static const double defaultOpenAipOverlayOpacity = 0.6;
  static const bool defaultOpenAipAirspaceEnabled = false;
  
  // Takeoff/Landing Detection preferences
  static const String detectionSpeedThresholdKey = 'detection_speed_threshold';
  static const String detectionClimbRateThresholdKey = 'detection_climb_rate_threshold';
  static const String triangleClosingDistanceKey = 'triangle_closing_distance';
  static const String triangleSamplingIntervalKey = 'triangle_sampling_interval';
  
  // Default values for detection
  static const double defaultDetectionSpeedThreshold = 9.0; // km/h
  static const double defaultDetectionClimbRateThreshold = 0.2; // m/s
  static const double defaultTriangleClosingDistance = 1000.0; // meters
  static const int defaultTriangleSamplingInterval = 30; // seconds
  static const List<double> validSpeedThresholds = [5.0, 7.0, 9.0, 11.0, 15.0]; // km/h
  static const List<double> validClimbRateThresholds = [0.1, 0.2, 0.3, 0.5]; // m/s
  static const List<double> validTriangleClosingDistances = [500.0, 1000.0, 2000.0]; // meters
  static const List<int> validTriangleSamplingIntervals = [15, 30, 60]; // seconds

  // Wind limits for flyability
  static const String maxWindSpeedKey = 'max_wind_speed';
  static const String maxWindGustsKey = 'max_wind_gusts';
  static const String cautionWindSpeedKey = 'caution_wind_speed';
  static const String cautionWindGustsKey = 'caution_wind_gusts';

  // Default values for wind limits
  static const double defaultMaxWindSpeed = 25.0; // km/h
  static const double defaultMaxWindGusts = 35.0; // km/h
  static const double defaultCautionWindSpeed = 20.0; // km/h
  static const double defaultCautionWindGusts = 30.0; // km/h (caution range: 30-35)

  // Cesium 3D Map methods
  static Future<String?> getCesiumSceneMode() async {
    final prefs = await SharedPreferences.getInstance();
    // Check if the preference has been set before
    if (!prefs.containsKey(cesiumSceneModeKey)) {
      // First time - set default to 3D
      await prefs.setString(cesiumSceneModeKey, '3D');
      return '3D';
    }
    return prefs.getString(cesiumSceneModeKey);
  }
  
  static Future<void> setCesiumSceneMode(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(cesiumSceneModeKey, value);
  }
  
  static Future<String?> getCesiumBaseMap() async {
    final prefs = await SharedPreferences.getInstance();
    // Check if the preference has been set before
    if (!prefs.containsKey(cesiumBaseMapKey)) {
      // First time - set default to satellite
      await prefs.setString(cesiumBaseMapKey, 'satellite');
      return 'satellite';
    }
    return prefs.getString(cesiumBaseMapKey);
  }
  
  static Future<void> setCesiumBaseMap(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(cesiumBaseMapKey, value);
  }
  
  static Future<bool?> getCesiumTerrainEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    // Check if the preference has been set before
    if (!prefs.containsKey(cesiumTerrainEnabledKey)) {
      // First time - set default to true for flight visualization
      await prefs.setBool(cesiumTerrainEnabledKey, true);
      return true;
    }
    return prefs.getBool(cesiumTerrainEnabledKey);
  }
  
  static Future<void> setCesiumTerrainEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(cesiumTerrainEnabledKey, value);
  }
  
  static Future<bool?> getCesiumNavigationHelpDialog() async {
    final prefs = await SharedPreferences.getInstance();
    // Check if the preference has been set before
    if (!prefs.containsKey(cesiumNavigationHelpDialogKey)) {
      // First time - set default to false
      await prefs.setBool(cesiumNavigationHelpDialogKey, false);
      return false;
    }
    return prefs.getBool(cesiumNavigationHelpDialogKey);
  }
  
  static Future<void> setCesiumNavigationHelpDialog(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(cesiumNavigationHelpDialogKey, value);
  }
  
  static Future<bool?> getCesiumFlyThroughMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(cesiumFlyThroughModeKey);
  }
  
  static Future<void> setCesiumFlyThroughMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(cesiumFlyThroughModeKey, value);
  }
  
  static Future<int?> getCesiumTrailDuration() async {
    final prefs = await SharedPreferences.getInstance();
    // Check if the preference has been set before
    if (!prefs.containsKey(cesiumTrailDurationKey)) {
      // First time - set default to 3 minutes
      await prefs.setInt(cesiumTrailDurationKey, defaultCesiumTrailDuration);
      return defaultCesiumTrailDuration;
    }
    return prefs.getInt(cesiumTrailDurationKey);
  }
  
  static Future<void> setCesiumTrailDuration(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(cesiumTrailDurationKey, value);
  }
  
  static Future<double?> getCesiumQuality() async {
    final prefs = await SharedPreferences.getInstance();
    // Check if the preference has been set before
    if (!prefs.containsKey(cesiumQualityKey)) {
      // First time - set default to 1.0 (Medium)
      await prefs.setDouble(cesiumQualityKey, 1.0);
      return 1.0;
    }
    return prefs.getDouble(cesiumQualityKey);
  }

  static Future<void> setCesiumQuality(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(cesiumQualityKey, value);
  }
  
  // Cesium Ion Token methods
  static Future<String?> getCesiumUserToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(cesiumUserTokenKey);
  }
  
  static Future<void> setCesiumUserToken(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(cesiumUserTokenKey, value);
  }
  
  static Future<void> removeCesiumUserToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(cesiumUserTokenKey);
    await prefs.remove(cesiumTokenValidatedKey);
    await prefs.remove(cesiumTokenValidationDateKey);
  }
  
  static Future<bool?> getCesiumTokenValidated() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(cesiumTokenValidatedKey);
  }
  
  static Future<void> setCesiumTokenValidated(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(cesiumTokenValidatedKey, value);
    await prefs.setString(cesiumTokenValidationDateKey, DateTime.now().toIso8601String());
  }
  
  static Future<DateTime?> getCesiumTokenValidationDate() async {
    final prefs = await SharedPreferences.getInstance();
    final dateString = prefs.getString(cesiumTokenValidationDateKey);
    return dateString != null ? DateTime.tryParse(dateString) : null;
  }
  
  // IGC Import methods
  static Future<String?> getIgcLastFolder() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(igcLastFolderKey);
  }
  
  static Future<void> setIgcLastFolder(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(igcLastFolderKey, value);
  }
  
  static Future<void> removeIgcLastFolder() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(igcLastFolderKey);
  }
  
  // Takeoff/Landing Detection methods
  static Future<double> getDetectionSpeedThreshold() async {
    final prefs = await SharedPreferences.getInstance();
    // Check if the preference has been set before
    if (!prefs.containsKey(detectionSpeedThresholdKey)) {
      // First time - set default
      await prefs.setDouble(detectionSpeedThresholdKey, defaultDetectionSpeedThreshold);
      return defaultDetectionSpeedThreshold;
    }
    return prefs.getDouble(detectionSpeedThresholdKey) ?? defaultDetectionSpeedThreshold;
  }
  
  static Future<void> setDetectionSpeedThreshold(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(detectionSpeedThresholdKey, value);
  }
  
  static Future<double> getDetectionClimbRateThreshold() async {
    final prefs = await SharedPreferences.getInstance();
    // Check if the preference has been set before
    if (!prefs.containsKey(detectionClimbRateThresholdKey)) {
      // First time - set default
      await prefs.setDouble(detectionClimbRateThresholdKey, defaultDetectionClimbRateThreshold);
      return defaultDetectionClimbRateThreshold;
    }
    return prefs.getDouble(detectionClimbRateThresholdKey) ?? defaultDetectionClimbRateThreshold;
  }
  
  static Future<void> setDetectionClimbRateThreshold(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(detectionClimbRateThresholdKey, value);
  }


  static Future<double> getTriangleClosingDistance() async {
    final prefs = await SharedPreferences.getInstance();
    // Check if the preference has been set before
    if (!prefs.containsKey(triangleClosingDistanceKey)) {
      // First time - set default
      await prefs.setDouble(triangleClosingDistanceKey, defaultTriangleClosingDistance);
      return defaultTriangleClosingDistance;
    }
    return prefs.getDouble(triangleClosingDistanceKey) ?? defaultTriangleClosingDistance;
  }
  
  static Future<void> setTriangleClosingDistance(double value) async {
    if (value < 50.0 || value > 2000.0) {
      throw ArgumentError('Triangle closing distance must be between 50-2000m');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(triangleClosingDistanceKey, value);
  }
  
  static Future<int> getTriangleSamplingInterval() async {
    final prefs = await SharedPreferences.getInstance();
    // Check if the preference has been set before
    if (!prefs.containsKey(triangleSamplingIntervalKey)) {
      // First time - set default
      await prefs.setInt(triangleSamplingIntervalKey, defaultTriangleSamplingInterval);
      return defaultTriangleSamplingInterval;
    }
    return prefs.getInt(triangleSamplingIntervalKey) ?? defaultTriangleSamplingInterval;
  }
  
  static Future<void> setTriangleSamplingInterval(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(triangleSamplingIntervalKey, value);
  }

  // Wind limit methods for flyability assessment
  static Future<double> getMaxWindSpeed() async {
    final prefs = await SharedPreferences.getInstance();
    // Check if the preference has been set before
    if (!prefs.containsKey(maxWindSpeedKey)) {
      // First time - set default
      await prefs.setDouble(maxWindSpeedKey, defaultMaxWindSpeed);
      return defaultMaxWindSpeed;
    }
    return prefs.getDouble(maxWindSpeedKey) ?? defaultMaxWindSpeed;
  }

  static Future<void> setMaxWindSpeed(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(maxWindSpeedKey, value);
  }

  static Future<double> getMaxWindGusts() async {
    final prefs = await SharedPreferences.getInstance();
    // Check if the preference has been set before
    if (!prefs.containsKey(maxWindGustsKey)) {
      // First time - set default
      await prefs.setDouble(maxWindGustsKey, defaultMaxWindGusts);
      return defaultMaxWindGusts;
    }
    return prefs.getDouble(maxWindGustsKey) ?? defaultMaxWindGusts;
  }

  static Future<void> setMaxWindGusts(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(maxWindGustsKey, value);
  }

  static Future<double> getCautionWindSpeed() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(cautionWindSpeedKey)) {
      await prefs.setDouble(cautionWindSpeedKey, defaultCautionWindSpeed);
      return defaultCautionWindSpeed;
    }
    return prefs.getDouble(cautionWindSpeedKey) ?? defaultCautionWindSpeed;
  }

  static Future<void> setCautionWindSpeed(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(cautionWindSpeedKey, value);
  }

  static Future<double> getCautionWindGusts() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(cautionWindGustsKey)) {
      await prefs.setDouble(cautionWindGustsKey, defaultCautionWindGusts);
      return defaultCautionWindGusts;
    }
    return prefs.getDouble(cautionWindGustsKey) ?? defaultCautionWindGusts;
  }

  static Future<void> setCautionWindGusts(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(cautionWindGustsKey, value);
  }

  // Card expansion state management is now handled by CardExpansionManager
  // Legacy methods removed - use CardExpansionManager instead

  // Generic methods for direct access if needed
  static Future<String?> getString(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }
  
  static Future<void> setString(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }
  
  static Future<bool?> getBool(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key);
  }
  
  static Future<void> setBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }
  
  static Future<int?> getInt(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(key);
  }
  
  static Future<void> setInt(String key, int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, value);
  }
  
  static Future<void> remove(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }
  
  // OpenAIP methods
  static Future<String?> getOpenAipApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(openAipApiKeyKey);
  }
  
  static Future<void> setOpenAipApiKey(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(openAipApiKeyKey, value);
  }
  
  static Future<void> removeOpenAipApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(openAipApiKeyKey);
  }
  
  static Future<bool> getOpenAipAirspaceEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(openAipAirspaceEnabledKey)) {
      await prefs.setBool(openAipAirspaceEnabledKey, defaultOpenAipAirspaceEnabled);
      return defaultOpenAipAirspaceEnabled;
    }
    return prefs.getBool(openAipAirspaceEnabledKey) ?? defaultOpenAipAirspaceEnabled;
  }
  
  static Future<void> setOpenAipAirspaceEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(openAipAirspaceEnabledKey, value);
  }

  static Future<double> getOpenAipOverlayOpacity() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(openAipOverlayOpacityKey)) {
      await prefs.setDouble(openAipOverlayOpacityKey, defaultOpenAipOverlayOpacity);
      return defaultOpenAipOverlayOpacity;
    }
    return prefs.getDouble(openAipOverlayOpacityKey) ?? defaultOpenAipOverlayOpacity;
  }
  
  static Future<void> setOpenAipOverlayOpacity(double value) async {
    if (value < 0.0 || value > 1.0) {
      throw ArgumentError('Opacity must be between 0.0 and 1.0');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(openAipOverlayOpacityKey, value);
  }

  // Weather forecast model preferences
  static const String weatherForecastModelKey = 'weather_forecast_model';
  static const String defaultWeatherForecastModel = 'best_match';

  // PGE Sites preferences
  static const String pgeSitesDownloadedKey = 'pge_sites_downloaded';
  static const String pgeSitesDownloadDateKey = 'pge_sites_download_date';

  /// Check if PGE sites have ever been downloaded
  static Future<bool> hasPgeSitesBeenDownloaded() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(pgeSitesDownloadedKey) ?? false;
  }

  /// Mark PGE sites as downloaded
  static Future<void> setPgeSitesDownloaded(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(pgeSitesDownloadedKey, value);
    if (value) {
      // Also store the download date
      await prefs.setString(pgeSitesDownloadDateKey, DateTime.now().toIso8601String());
    }
  }

  /// Get the date when PGE sites were last downloaded
  static Future<DateTime?> getPgeSitesDownloadDate() async {
    final prefs = await SharedPreferences.getInstance();
    final dateStr = prefs.getString(pgeSitesDownloadDateKey);
    if (dateStr != null) {
      return DateTime.tryParse(dateStr);
    }
    return null;
  }

  // Weather forecast model methods
  /// Get the selected weather forecast model (default: best_match)
  static Future<String> getWeatherForecastModel() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(weatherForecastModelKey)) {
      await prefs.setString(weatherForecastModelKey, defaultWeatherForecastModel);
      return defaultWeatherForecastModel;
    }
    return prefs.getString(weatherForecastModelKey) ?? defaultWeatherForecastModel;
  }

  /// Set the selected weather forecast model
  static Future<void> setWeatherForecastModel(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(weatherForecastModelKey, value);
  }
}
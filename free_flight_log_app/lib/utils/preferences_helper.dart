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
  
  // Takeoff/Landing Detection preferences
  static const String detectionSpeedThresholdKey = 'detection_speed_threshold';
  static const String detectionClimbRateThresholdKey = 'detection_climb_rate_threshold';
  static const String chartTrimmingEnabledKey = 'chart_trimming_enabled';
  static const String triangleClosingDistanceKey = 'triangle_closing_distance';
  static const String triangleSamplingIntervalKey = 'triangle_sampling_interval';
  
  // Default values for detection
  static const double defaultDetectionSpeedThreshold = 9.0; // km/h
  static const double defaultDetectionClimbRateThreshold = 0.2; // m/s
  static const bool defaultChartTrimmingEnabled = true; // Default to trimmed charts
  static const double defaultTriangleClosingDistance = 1000.0; // meters
  static const int defaultTriangleSamplingInterval = 30; // seconds
  static const List<double> validSpeedThresholds = [5.0, 7.0, 9.0, 11.0, 15.0]; // km/h
  static const List<double> validClimbRateThresholds = [0.1, 0.2, 0.3, 0.5]; // m/s
  static const List<double> validTriangleClosingDistances = [500.0, 1000.0, 2000.0]; // meters
  static const List<int> validTriangleSamplingIntervals = [15, 30, 60]; // seconds
  
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

  static Future<bool> getChartTrimmingEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    // Check if the preference has been set before
    if (!prefs.containsKey(chartTrimmingEnabledKey)) {
      // First time - set default
      await prefs.setBool(chartTrimmingEnabledKey, defaultChartTrimmingEnabled);
      return defaultChartTrimmingEnabled;
    }
    return prefs.getBool(chartTrimmingEnabledKey) ?? defaultChartTrimmingEnabled;
  }

  static Future<void> setChartTrimmingEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(chartTrimmingEnabledKey, value);
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
    if (value < 50.0 || value > 1000.0) {
      throw ArgumentError('Triangle closing distance must be between 50-1000m');
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
  
  // Flight Detail Card expansion states
  static const String flightDetailsCardExpandedKey = 'flight_details_card_expanded';
  static const String flightStatisticsCardExpandedKey = 'flight_statistics_card_expanded';
  static const String flightTrackCardExpandedKey = 'flight_track_card_expanded';
  static const String flightNotesCardExpandedKey = 'flight_notes_card_expanded';
  
  // Card type constants for generic methods
  static const String cardTypeFlightDetails = 'flight_details';
  static const String cardTypeFlightStatistics = 'flight_statistics';
  static const String cardTypeFlightTrack = 'flight_track';
  static const String cardTypeFlightNotes = 'flight_notes';
  
  static const Map<String, String> _cardTypeToKeyMap = {
    cardTypeFlightDetails: flightDetailsCardExpandedKey,
    cardTypeFlightStatistics: flightStatisticsCardExpandedKey,
    cardTypeFlightTrack: flightTrackCardExpandedKey,
    cardTypeFlightNotes: flightNotesCardExpandedKey,
  };

  static Future<bool> getFlightDetailsCardExpanded() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(flightDetailsCardExpandedKey) ?? true; // Default expanded
  }

  static Future<void> setFlightDetailsCardExpanded(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(flightDetailsCardExpandedKey, value);
  }

  static Future<bool> getFlightStatisticsCardExpanded() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(flightStatisticsCardExpandedKey) ?? true; // Default expanded
  }

  static Future<void> setFlightStatisticsCardExpanded(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(flightStatisticsCardExpandedKey, value);
  }

  static Future<bool> getFlightTrackCardExpanded() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(flightTrackCardExpandedKey) ?? true; // Default expanded
  }

  static Future<void> setFlightTrackCardExpanded(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(flightTrackCardExpandedKey, value);
  }

  static Future<bool> getFlightNotesCardExpanded() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(flightNotesCardExpandedKey) ?? true; // Default expanded
  }

  static Future<void> setFlightNotesCardExpanded(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(flightNotesCardExpandedKey, value);
  }
  
  // Optimized batched loading method
  static Future<Map<String, bool>> getAllCardExpansionStates() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      cardTypeFlightDetails: prefs.getBool(flightDetailsCardExpandedKey) ?? true,
      cardTypeFlightStatistics: prefs.getBool(flightStatisticsCardExpandedKey) ?? true,
      cardTypeFlightTrack: prefs.getBool(flightTrackCardExpandedKey) ?? true,
      cardTypeFlightNotes: prefs.getBool(flightNotesCardExpandedKey) ?? true,
    };
  }
  
  // Generic method for setting card expansion state
  static Future<void> setCardExpansionState(String cardType, bool value) async {
    final key = _cardTypeToKeyMap[cardType];
    if (key != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    }
  }
  
  // Generic method for getting card expansion state
  static Future<bool> getCardExpansionState(String cardType) async {
    final key = _cardTypeToKeyMap[cardType];
    if (key != null) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(key) ?? true; // Default expanded
    }
    return true; // Default expanded
  }

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
}
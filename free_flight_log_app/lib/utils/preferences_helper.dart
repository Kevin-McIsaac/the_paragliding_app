import 'package:shared_preferences/shared_preferences.dart';

/// Helper class for managing app preferences using SharedPreferencesAsync
/// This uses the new async API which will replace the legacy SharedPreferences
class PreferencesHelper {
  static final SharedPreferencesAsync _prefs = SharedPreferencesAsync();
  
  // Cesium 3D Map preferences
  static const String cesiumSceneModeKey = 'cesium_scene_mode';
  static const String cesiumBaseMapKey = 'cesium_base_map';
  static const String cesiumTerrainEnabledKey = 'cesium_terrain_enabled';
  static const String cesiumNavigationHelpDialogKey = 'cesium_navigation_help_dialog_open';
  static const String cesiumFlyThroughModeKey = 'cesium_fly_through_mode';
  static const String cesiumTrailDurationKey = 'cesium_trail_duration';
  
  // Flight Track Widget preferences - REMOVED (2D map widget no longer used)
  
  // IGC Import preferences
  static const String igcLastFolderKey = 'igc_last_folder';
  
  // Cesium 3D Map methods
  static Future<String?> getCesiumSceneMode() async {
    return await _prefs.getString(cesiumSceneModeKey);
  }
  
  static Future<void> setCesiumSceneMode(String value) async {
    await _prefs.setString(cesiumSceneModeKey, value);
  }
  
  static Future<String?> getCesiumBaseMap() async {
    return await _prefs.getString(cesiumBaseMapKey);
  }
  
  static Future<void> setCesiumBaseMap(String value) async {
    await _prefs.setString(cesiumBaseMapKey, value);
  }
  
  static Future<bool?> getCesiumTerrainEnabled() async {
    return await _prefs.getBool(cesiumTerrainEnabledKey);
  }
  
  static Future<void> setCesiumTerrainEnabled(bool value) async {
    await _prefs.setBool(cesiumTerrainEnabledKey, value);
  }
  
  static Future<bool?> getCesiumNavigationHelpDialog() async {
    return await _prefs.getBool(cesiumNavigationHelpDialogKey);
  }
  
  static Future<void> setCesiumNavigationHelpDialog(bool value) async {
    await _prefs.setBool(cesiumNavigationHelpDialogKey, value);
  }
  
  static Future<bool?> getCesiumFlyThroughMode() async {
    return await _prefs.getBool(cesiumFlyThroughModeKey);
  }
  
  static Future<void> setCesiumFlyThroughMode(bool value) async {
    await _prefs.setBool(cesiumFlyThroughModeKey, value);
  }
  
  static Future<int?> getCesiumTrailDuration() async {
    return await _prefs.getInt(cesiumTrailDurationKey);
  }
  
  static Future<void> setCesiumTrailDuration(int value) async {
    await _prefs.setInt(cesiumTrailDurationKey, value);
  }
  
  // Flight Track Widget methods - REMOVED (2D map widget no longer used)
  
  // IGC Import methods
  static Future<String?> getIgcLastFolder() async {
    return await _prefs.getString(igcLastFolderKey);
  }
  
  static Future<void> setIgcLastFolder(String value) async {
    await _prefs.setString(igcLastFolderKey, value);
  }
  
  static Future<void> removeIgcLastFolder() async {
    await _prefs.remove(igcLastFolderKey);
  }
  
  // Generic methods for direct access if needed
  static Future<String?> getString(String key) async {
    return await _prefs.getString(key);
  }
  
  static Future<void> setString(String key, String value) async {
    await _prefs.setString(key, value);
  }
  
  static Future<bool?> getBool(String key) async {
    return await _prefs.getBool(key);
  }
  
  static Future<void> setBool(String key, bool value) async {
    await _prefs.setBool(key, value);
  }
  
  static Future<int?> getInt(String key) async {
    return await _prefs.getInt(key);
  }
  
  static Future<void> setInt(String key, int value) async {
    await _prefs.setInt(key, value);
  }
  
  static Future<void> remove(String key) async {
    await _prefs.remove(key);
  }
}
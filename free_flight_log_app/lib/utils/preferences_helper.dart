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
  
  // IGC Import preferences
  static const String igcLastFolderKey = 'igc_last_folder';
  
  // Cesium 3D Map methods
  static Future<String?> getCesiumSceneMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(cesiumSceneModeKey);
  }
  
  static Future<void> setCesiumSceneMode(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(cesiumSceneModeKey, value);
  }
  
  static Future<String?> getCesiumBaseMap() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(cesiumBaseMapKey);
  }
  
  static Future<void> setCesiumBaseMap(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(cesiumBaseMapKey, value);
  }
  
  static Future<bool?> getCesiumTerrainEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(cesiumTerrainEnabledKey);
  }
  
  static Future<void> setCesiumTerrainEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(cesiumTerrainEnabledKey, value);
  }
  
  static Future<bool?> getCesiumNavigationHelpDialog() async {
    final prefs = await SharedPreferences.getInstance();
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
    return prefs.getInt(cesiumTrailDurationKey);
  }
  
  static Future<void> setCesiumTrailDuration(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(cesiumTrailDurationKey, value);
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
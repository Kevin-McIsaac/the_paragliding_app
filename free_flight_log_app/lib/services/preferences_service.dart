import 'package:shared_preferences/shared_preferences.dart';
import 'logging_service.dart';

/// Service for managing user preferences and settings
class PreferencesService {
  static const String _sceneModeKey = 'cesium_scene_mode';
  static const String _terrainEnabledKey = 'cesium_terrain_enabled';
  static const String _baseMapKey = 'cesium_base_map';
  static const String _navigationHelpDialogKey = 'cesium_navigation_help_dialog';
  
  // Scene mode constants
  static const String sceneMode2D = '2D';
  static const String sceneMode3D = '3D';
  static const String sceneModeColumbus = 'COLUMBUS';
  
  // Singleton instance
  static final PreferencesService _instance = PreferencesService._internal();
  factory PreferencesService() => _instance;
  PreferencesService._internal();
  
  // Cache preferences instance
  SharedPreferences? _prefs;
  
  /// Initialize the preferences service
  Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      LoggingService.debug('PreferencesService: Initialized successfully');
    } catch (e) {
      LoggingService.error('PreferencesService', 'Failed to initialize: $e');
    }
  }
  
  /// Get the SharedPreferences instance
  Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }
  
  // ============================================================================
  // Scene Mode Preferences
  // ============================================================================
  
  /// Get the saved scene mode preference
  Future<String> getSceneMode() async {
    try {
      final prefs = await _getPrefs();
      final mode = prefs.getString(_sceneModeKey) ?? sceneMode3D;
      LoggingService.debug('PreferencesService: Retrieved scene mode: $mode');
      return mode;
    } catch (e) {
      LoggingService.error('PreferencesService', 'Failed to get scene mode: $e');
      return sceneMode3D; // Default to 3D
    }
  }
  
  /// Save the scene mode preference
  Future<bool> setSceneMode(String mode) async {
    try {
      // Validate mode
      if (mode != sceneMode2D && mode != sceneMode3D && mode != sceneModeColumbus) {
        LoggingService.error('PreferencesService', 'Invalid scene mode: $mode');
        return false;
      }
      
      final prefs = await _getPrefs();
      final success = await prefs.setString(_sceneModeKey, mode);
      if (success) {
        LoggingService.debug('PreferencesService: Saved scene mode: $mode');
      }
      return success;
    } catch (e) {
      LoggingService.error('PreferencesService', 'Failed to save scene mode: $e');
      return false;
    }
  }
  
  // ============================================================================
  // Terrain Preferences
  // ============================================================================
  
  /// Get the terrain enabled preference
  Future<bool> getTerrainEnabled() async {
    try {
      final prefs = await _getPrefs();
      final enabled = prefs.getBool(_terrainEnabledKey) ?? true;
      LoggingService.debug('PreferencesService: Retrieved terrain enabled: $enabled');
      return enabled;
    } catch (e) {
      LoggingService.error('PreferencesService', 'Failed to get terrain enabled: $e');
      return true; // Default to enabled
    }
  }
  
  /// Save the terrain enabled preference
  Future<bool> setTerrainEnabled(bool enabled) async {
    try {
      final prefs = await _getPrefs();
      final success = await prefs.setBool(_terrainEnabledKey, enabled);
      if (success) {
        LoggingService.debug('PreferencesService: Saved terrain enabled: $enabled');
      }
      return success;
    } catch (e) {
      LoggingService.error('PreferencesService', 'Failed to save terrain enabled: $e');
      return false;
    }
  }
  
  // ============================================================================
  // Base Map Preferences
  // ============================================================================
  
  /// Get the base map preference
  Future<String> getBaseMap() async {
    try {
      final prefs = await _getPrefs();
      final baseMap = prefs.getString(_baseMapKey) ?? 'Bing Maps Aerial';
      LoggingService.debug('PreferencesService: Retrieved base map: $baseMap');
      return baseMap;
    } catch (e) {
      LoggingService.error('PreferencesService', 'Failed to get base map: $e');
      return 'Bing Maps Aerial'; // Default
    }
  }
  
  /// Save the base map preference
  Future<bool> setBaseMap(String baseMap) async {
    try {
      final prefs = await _getPrefs();
      final success = await prefs.setString(_baseMapKey, baseMap);
      if (success) {
        LoggingService.debug('PreferencesService: Saved base map: $baseMap');
      }
      return success;
    } catch (e) {
      LoggingService.error('PreferencesService', 'Failed to save base map: $e');
      return false;
    }
  }
  
  // ============================================================================
  // Navigation Help Dialog Preferences
  // ============================================================================
  
  /// Get the navigation help dialog open state preference
  Future<bool> getNavigationHelpDialogOpen() async {
    try {
      final prefs = await _getPrefs();
      final isOpen = prefs.getBool(_navigationHelpDialogKey) ?? false;
      LoggingService.debug('PreferencesService: Retrieved navigation help dialog state: $isOpen');
      return isOpen;
    } catch (e) {
      LoggingService.error('PreferencesService', 'Failed to get navigation help dialog state: $e');
      return false; // Default to closed
    }
  }
  
  /// Save the navigation help dialog open state preference
  Future<bool> setNavigationHelpDialogOpen(bool isOpen) async {
    try {
      final prefs = await _getPrefs();
      final success = await prefs.setBool(_navigationHelpDialogKey, isOpen);
      if (success) {
        LoggingService.debug('PreferencesService: Saved navigation help dialog state: $isOpen');
      }
      return success;
    } catch (e) {
      LoggingService.error('PreferencesService', 'Failed to save navigation help dialog state: $e');
      return false;
    }
  }
  
  // ============================================================================
  // Utility Methods
  // ============================================================================
  
  /// Clear all preferences
  Future<bool> clearAll() async {
    try {
      final prefs = await _getPrefs();
      final success = await prefs.clear();
      if (success) {
        LoggingService.info('PreferencesService: Cleared all preferences');
      }
      return success;
    } catch (e) {
      LoggingService.error('PreferencesService', 'Failed to clear preferences: $e');
      return false;
    }
  }
  
  /// Check if preferences have been initialized
  bool get isInitialized => _prefs != null;
}
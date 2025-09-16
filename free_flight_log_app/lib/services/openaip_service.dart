import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/logging_service.dart';
import '../data/models/airspace_enums.dart';

/// Available OpenAIP data layers for aviation maps
/// Note: As of May 2023, OpenAIP consolidated all layers into a single 'openaip' layer
enum OpenAipLayer {
  // Single consolidated layer (current format)
  openaip('openaip', 'OpenAIP Data', 'Consolidated airspaces'),

  // Legacy layer names (for UI compatibility, but all map to 'openaip')
  airspaces('openaip', 'Airspaces', 'Controlled and restricted airspace zones');

  const OpenAipLayer(this.urlPath, this.displayName, this.description);
  
  final String urlPath;
  final String displayName;
  final String description;
}

/// Service for managing OpenAIP tile overlays and API integration
class OpenAipService {
  static OpenAipService? _instance;
  static OpenAipService get instance => _instance ??= OpenAipService._();
  
  OpenAipService._();

  // OpenAIP tile server configuration
  // Updated format: consolidated 'openaip' layer with minimum zoom 7
  static const String _tileServerPattern = 'https://{s}.api.tiles.openaip.net/api/data/{layer}/{z}/{x}/{y}.png';
  static const List<String> _subdomains = ['a', 'b', 'c']; // Only a, b, c subdomains exist
  static const int _minZoom = 7; // OpenAIP requires minimum zoom level 7
  static const int _maxZoom = 16;
  
  // Preferences keys
  static const String _apiKeyKey = 'openaip_api_key';
  static const String _airspaceEnabledKey = 'openaip_airspace_enabled';
  static const String _overlayOpacityKey = 'openaip_overlay_opacity';

  // Individual airspace type preferences
  static const String _airspaceTypesExcludedKey = 'openaip_airspace_types_excluded';

  // Individual ICAO class preferences
  static const String _icaoClassesExcludedKey = 'openaip_icao_classes_excluded';

  // Airspace clipping preference
  static const String _airspaceClippingEnabledKey = 'openaip_airspace_clipping_enabled';

  // Default values
  static const double _defaultOpacity = 0.15; // 15% optimal for airspace visibility
  static const bool _defaultAirspaceEnabled = false;
  static const bool _defaultClippingEnabled = true; // Default to enabled for backwards compatibility

  // Default airspace type exclusions (false = include/show, true = exclude/hide)
  // This ensures unmapped types are shown by default
  static Map<AirspaceType, bool> get _defaultAirspaceTypesExclusion => {
    for (final type in AirspaceType.values)
      type: type.isHiddenByDefault,
  };

  // Default ICAO class exclusions (false = include/show, true = exclude/hide)
  // This ensures unmapped classes are shown by default
  static Map<IcaoClass, bool> get _defaultIcaoClassesExclusion => {
    for (final icaoClass in IcaoClass.values)
      icaoClass: icaoClass.isHiddenByDefault,
  };
  
  /// Get the tile URL template for a specific layer
  String getTileUrlTemplate(OpenAipLayer layer, {String? apiKey}) {
    String url = _tileServerPattern
        .replaceAll('{layer}', layer.urlPath);
    
    // Add API key if provided
    if (apiKey != null && apiKey.isNotEmpty) {
      url += '?apiKey=$apiKey';
    }
    
    LoggingService.structured('OPENAIP_TILE_URL', {
      'layer': layer.urlPath,
      'has_api_key': apiKey != null && apiKey.isNotEmpty,
    });
    
    return url;
  }
  
  /// Get subdomains for load balancing
  List<String> get subdomains => _subdomains;
  
  /// Get zoom limits
  int get minZoom => _minZoom;
  int get maxZoom => _maxZoom;
  
  // API Key Management
  
  /// Get stored OpenAIP API key
  Future<String?> getApiKey() async {
    // Restore the API key with simplified authentication method
    return 'a75461fcd8a0e9cbca91058d23c78f4c';

    // TODO: Later implement user-configurable API keys
    // final prefs = await SharedPreferences.getInstance();
    // return prefs.getString(_apiKeyKey);
  }
  
  /// Store OpenAIP API key
  Future<void> setApiKey(String apiKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiKeyKey, apiKey);
    LoggingService.info('OpenAIP API key updated');
  }
  
  /// Remove OpenAIP API key
  Future<void> removeApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_apiKeyKey);
    LoggingService.info('OpenAIP API key removed');
  }
  
  /// Check if API key is configured
  Future<bool> hasApiKey() async {
    final key = await getApiKey();
    return key != null && key.isNotEmpty;
  }
  
  // Layer Visibility Management
  
  /// Get visibility state for airspace layer
  Future<bool> isAirspaceEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_airspaceEnabledKey)) {
      await prefs.setBool(_airspaceEnabledKey, _defaultAirspaceEnabled);
      return _defaultAirspaceEnabled;
    }
    return prefs.getBool(_airspaceEnabledKey) ?? _defaultAirspaceEnabled;
  }
  
  /// Set visibility state for airspace layer
  Future<void> setAirspaceEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_airspaceEnabledKey, enabled);
    LoggingService.structured('OPENAIP_LAYER_TOGGLE', {
      'layer': 'airspace',
      'enabled': enabled,
    });
  }
  
  
  
  
  
  

  /// Get clipping state for airspace layer
  Future<bool> isClippingEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_airspaceClippingEnabledKey)) {
      await prefs.setBool(_airspaceClippingEnabledKey, _defaultClippingEnabled);
      return _defaultClippingEnabled;
    }
    return prefs.getBool(_airspaceClippingEnabledKey) ?? _defaultClippingEnabled;
  }

  /// Set clipping state for airspace layer
  Future<void> setClippingEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_airspaceClippingEnabledKey, enabled);
    LoggingService.structured('AIRSPACE_CLIPPING_TOGGLE', {
      'enabled': enabled,
    });
  }

  /// Get enabled state for a specific layer
  Future<bool> isLayerEnabled(OpenAipLayer layer) async {
    switch (layer) {
      case OpenAipLayer.openaip:
        // For consolidated layer, return true if airspace is enabled
        return await isAirspaceEnabled();
      case OpenAipLayer.airspaces:
        return isAirspaceEnabled();
    }
  }

  // Convenience methods for individual layer state access
  Future<bool> getAirspaceEnabled() => isAirspaceEnabled();
  
  /// Set enabled state for a specific layer
  Future<void> setLayerEnabled(OpenAipLayer layer, bool enabled) async {
    switch (layer) {
      case OpenAipLayer.openaip:
        // For consolidated layer, enable/disable airspace
        await setAirspaceEnabled(enabled);
        break;
      case OpenAipLayer.airspaces:
        await setAirspaceEnabled(enabled);
        break;
    }
  }
  
  /// Get all enabled layers
  Future<List<OpenAipLayer>> getEnabledLayers() async {
    final List<OpenAipLayer> enabledLayers = [];
    
    for (final layer in OpenAipLayer.values) {
      if (await isLayerEnabled(layer)) {
        enabledLayers.add(layer);
      }
    }
    
    return enabledLayers;
  }
  
  // Opacity Management
  
  /// Get overlay opacity setting
  Future<double> getOverlayOpacity() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_overlayOpacityKey)) {
      await prefs.setDouble(_overlayOpacityKey, _defaultOpacity);
      return _defaultOpacity;
    }
    return prefs.getDouble(_overlayOpacityKey) ?? _defaultOpacity;
  }
  
  /// Set overlay opacity setting
  Future<void> setOverlayOpacity(double opacity) async {
    if (opacity < 0.0 || opacity > 1.0) {
      throw ArgumentError('Opacity must be between 0.0 and 1.0');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_overlayOpacityKey, opacity);
    LoggingService.structured('OPENAIP_OPACITY_CHANGE', {
      'opacity': opacity,
    });
  }
  
  /// Reset all settings to defaults
  Future<void> resetToDefaults() async {
    final prefs = await SharedPreferences.getInstance();

    // Remove all OpenAIP preferences
    await prefs.remove(_apiKeyKey);
    await prefs.remove(_airspaceEnabledKey);
    await prefs.remove(_overlayOpacityKey);
    await prefs.remove(_airspaceTypesExcludedKey);
    await prefs.remove(_icaoClassesExcludedKey);

    LoggingService.info('OpenAIP settings reset to defaults');
  }
  
  /// Get excluded airspace types (internal - returns string keys)
  Future<Map<String, bool>> _getExcludedAirspaceTypesInternal() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_airspaceTypesExcludedKey);

    if (jsonString == null) {
      // First time - use defaults
      final stringDefaults = _convertEnumMapToStringMap(_defaultAirspaceTypesExclusion);
      await _setExcludedAirspaceTypesInternal(stringDefaults);
      return stringDefaults;
    }

    try {
      final Map<String, dynamic> decoded = json.decode(jsonString);
      return decoded.cast<String, bool>();
    } catch (e) {
      LoggingService.error('Failed to decode airspace types exclusions', e, StackTrace.current);
      return _convertEnumMapToStringMap(_defaultAirspaceTypesExclusion);
    }
  }

  /// Set excluded state for multiple airspace types (internal)
  Future<void> _setExcludedAirspaceTypesInternal(Map<String, bool> types) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = json.encode(types);
    await prefs.setString(_airspaceTypesExcludedKey, jsonString);

    LoggingService.structured('AIRSPACE_TYPES_UPDATE', {
      'excluded_count': types.values.where((v) => v).length,
      'total_count': types.length,
      'excluded_types': types.entries.where((e) => e.value).map((e) => e.key).toList(),
    });
  }

  /// Set excluded state for a specific airspace type
  Future<void> setAirspaceTypeExcluded(AirspaceType type, bool excluded) async {
    final currentTypes = await getExcludedAirspaceTypes();
    currentTypes[type] = excluded;
    await setExcludedAirspaceTypes(currentTypes);
  }

  /// Check if a specific airspace type is excluded
  Future<bool> isAirspaceTypeExcluded(AirspaceType type) async {
    final excludedTypes = await getExcludedAirspaceTypes();
    // _defaultAirspaceTypesExclusion is already enum-based, no conversion needed
    return excludedTypes[type] ?? _defaultAirspaceTypesExclusion[type] ?? false;
  }

  /// Set airspace and ICAO class preset (quick configurations)
  Future<void> setAirspacePreset(String presetName) async {
    Map<String, bool> typeExclusionPreset;
    Map<String, bool> classExclusionPreset;

    switch (presetName) {
      case 'vfr':
        typeExclusionPreset = {
          'CTR': false, 'TMA': false, 'CTA': false,
          'D': false, 'R': false, 'P': false,
          'FIR': true, 'None': true,
        };
        classExclusionPreset = {
          'A': true, 'B': false, 'C': false, 'D': false,
          'E': true, 'F': true, 'G': false, 'None': true,
        };
        break;
      case 'ifr':
        typeExclusionPreset = {
          'CTR': false, 'TMA': false, 'CTA': false,
          'D': false, 'R': false, 'P': false,
          'FIR': false, 'None': true,
        };
        classExclusionPreset = {
          'A': false, 'B': false, 'C': false, 'D': false,
          'E': false, 'F': false, 'G': true, 'None': true,
        };
        break;
      case 'hazards':
        typeExclusionPreset = {
          'CTR': true, 'TMA': true, 'CTA': true,
          'D': false, 'R': false, 'P': false,
          'FIR': true, 'None': true,
        };
        classExclusionPreset = {
          'A': true, 'B': true, 'C': true, 'D': true,
          'E': true, 'F': true, 'G': true, 'None': false,
        };
        break;
      case 'training':
        typeExclusionPreset = {
          'CTR': false, 'TMA': false, 'CTA': true,
          'D': false, 'R': false, 'P': false,
          'FIR': true, 'None': true,
        };
        classExclusionPreset = {
          'A': true, 'B': true, 'C': false, 'D': false,
          'E': true, 'F': true, 'G': true, 'None': true,
        };
        break;
      default:
        typeExclusionPreset = _convertEnumMapToStringMap(_defaultAirspaceTypesExclusion);
        classExclusionPreset = _convertIcaoEnumMapToStringMap(_defaultIcaoClassesExclusion);
    }

    await setExcludedAirspaceTypes(_convertStringMapToEnumMap(typeExclusionPreset));
    await setExcludedIcaoClasses(_convertIcaoStringMapToEnumMap(classExclusionPreset));

    LoggingService.structured('AIRSPACE_PRESET_APPLIED', {
      'preset': presetName,
      'excluded_types_count': typeExclusionPreset.values.where((v) => v).length,
      'excluded_classes_count': classExclusionPreset.values.where((v) => v).length,
    });
  }

  /// Get excluded ICAO classes (internal)
  Future<Map<String, bool>> _getExcludedIcaoClassesInternal() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_icaoClassesExcludedKey);

    if (jsonString == null) {
      // First time - use defaults
      final stringDefaults = _convertIcaoEnumMapToStringMap(_defaultIcaoClassesExclusion);
      await _setExcludedIcaoClassesInternal(stringDefaults);
      return stringDefaults;
    }

    try {
      final Map<String, dynamic> decoded = json.decode(jsonString);
      return decoded.cast<String, bool>();
    } catch (e) {
      LoggingService.error('Failed to decode ICAO classes exclusions', e, StackTrace.current);
      return _convertIcaoEnumMapToStringMap(_defaultIcaoClassesExclusion);
    }
  }

  /// Set excluded state for multiple ICAO classes (internal)
  Future<void> _setExcludedIcaoClassesInternal(Map<String, bool> classes) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = json.encode(classes);
    await prefs.setString(_icaoClassesExcludedKey, jsonString);

    LoggingService.structured('ICAO_CLASSES_UPDATE', {
      'excluded_count': classes.values.where((v) => v).length,
      'total_count': classes.length,
      'excluded_classes': classes.entries.where((e) => e.value).map((e) => e.key).toList(),
    });
  }

  /// Set excluded state for a specific ICAO class
  Future<void> setIcaoClassExcluded(IcaoClass icaoClass, bool excluded) async {
    final currentClasses = await getExcludedIcaoClasses();
    currentClasses[icaoClass] = excluded;
    await setExcludedIcaoClasses(currentClasses);
  }

  /// Check if a specific ICAO class is excluded
  Future<bool> isIcaoClassExcluded(IcaoClass icaoClass) async {
    final excludedClasses = await getExcludedIcaoClasses();
    // _defaultIcaoClassesExclusion is already enum-based, no conversion needed
    return excludedClasses[icaoClass] ?? _defaultIcaoClassesExclusion[icaoClass] ?? false;
  }

  /// Get a summary of current settings
  Future<Map<String, dynamic>> getSettingsSummary() async {
    final excludedTypes = await getExcludedAirspaceTypes();
    final excludedClasses = await getExcludedIcaoClasses();
    return {
      'has_api_key': await hasApiKey(),
      'airspace_enabled': await isAirspaceEnabled(),
      'airspace_clipping_enabled': await isClippingEnabled(),
      'overlay_opacity': await getOverlayOpacity(),
      'excluded_airspace_types': excludedTypes,
      'excluded_airspace_count': excludedTypes.values.where((v) => v).length,
      'excluded_icao_classes': excludedClasses,
      'excluded_icao_count': excludedClasses.values.where((v) => v).length,
    };
  }

  // ==========================================================================
  // ENUM CONVERSION HELPERS
  // ==========================================================================

  /// Convert enum-based map to string-based map for storage
  static Map<String, bool> _convertEnumMapToStringMap(Map<AirspaceType, bool> enumMap) {
    return {
      for (final entry in enumMap.entries)
        entry.key.abbreviation: entry.value
    };
  }

  /// Convert string-based map to enum-based map for API
  static Map<AirspaceType, bool> _convertStringMapToEnumMap(Map<String, bool> stringMap) {
    final result = <AirspaceType, bool>{};

    // First, set all enum values to their defaults
    for (final type in AirspaceType.values) {
      result[type] = type.isHiddenByDefault;
    }

    // Then override with stored preferences
    for (final entry in stringMap.entries) {
      final type = AirspaceType.values.where((t) => t.abbreviation == entry.key).firstOrNull;
      if (type != null) {
        result[type] = entry.value;
      }
    }

    return result;
  }

  /// Convert enum-based ICAO map to string-based map for storage
  static Map<String, bool> _convertIcaoEnumMapToStringMap(Map<IcaoClass, bool> enumMap) {
    return {
      for (final entry in enumMap.entries)
        entry.key.abbreviation: entry.value
    };
  }

  /// Convert string-based ICAO map to enum-based map for API
  static Map<IcaoClass, bool> _convertIcaoStringMapToEnumMap(Map<String, bool> stringMap) {
    final result = <IcaoClass, bool>{};

    // First, set all enum values to their defaults
    for (final icaoClass in IcaoClass.values) {
      result[icaoClass] = icaoClass.isHiddenByDefault;
    }

    // Then override with stored preferences
    for (final entry in stringMap.entries) {
      final icaoClass = IcaoClass.values.where((c) => c.abbreviation == entry.key).firstOrNull;
      if (icaoClass != null) {
        result[icaoClass] = entry.value;
      }
    }

    return result;
  }

  // ==========================================================================
  // EXCLUSION-BASED PUBLIC API
  // ==========================================================================

  /// Get excluded airspace types (enum-based)
  Future<Map<AirspaceType, bool>> getExcludedAirspaceTypes() async {
    final stringMap = await _getExcludedAirspaceTypesInternal();
    return _convertStringMapToEnumMap(stringMap);
  }

  /// Set excluded airspace types (enum-based)
  Future<void> setExcludedAirspaceTypes(Map<AirspaceType, bool> types) async {
    final stringMap = _convertEnumMapToStringMap(types);
    await _setExcludedAirspaceTypesInternal(stringMap);
  }

  /// Get excluded ICAO classes (enum-based)
  Future<Map<IcaoClass, bool>> getExcludedIcaoClasses() async {
    final stringMap = await _getExcludedIcaoClassesInternal();
    return _convertIcaoStringMapToEnumMap(stringMap);
  }

  /// Set excluded ICAO classes (enum-based)
  Future<void> setExcludedIcaoClasses(Map<IcaoClass, bool> classes) async {
    final stringMap = _convertIcaoEnumMapToStringMap(classes);
    await _setExcludedIcaoClassesInternal(stringMap);
  }
}
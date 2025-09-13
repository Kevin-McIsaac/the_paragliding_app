import 'package:shared_preferences/shared_preferences.dart';
import '../services/logging_service.dart';

/// Available OpenAIP data layers for aviation maps
/// Note: As of May 2023, OpenAIP consolidated all layers into a single 'openaip' layer
enum OpenAipLayer {
  // Single consolidated layer (current format)
  openaip('openaip', 'OpenAIP Data', 'Consolidated airspaces, airports, and navigation data'),
  
  // Legacy layer names (for UI compatibility, but all map to 'openaip')
  airspaces('openaip', 'Airspaces', 'Controlled and restricted airspace zones'),
  airports('openaip', 'Airports', 'Airport locations and information'),
  navaids('openaip', 'Navigation Aids', 'VOR, NDB, and other navigation aids'),
  reportingPoints('openaip', 'Reporting Points', 'VFR reporting points');

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
  static const String _airportsEnabledKey = 'openaip_airports_enabled';
  static const String _navaidsEnabledKey = 'openaip_navaids_enabled';
  static const String _reportingPointsEnabledKey = 'openaip_reporting_points_enabled';
  static const String _overlayOpacityKey = 'openaip_overlay_opacity';
  
  // Default values
  static const double _defaultOpacity = 0.6;
  static const bool _defaultAirspaceEnabled = false;
  static const bool _defaultAirportsEnabled = false;
  static const bool _defaultNavaidsEnabled = false;
  static const bool _defaultReportingPointsEnabled = false;
  
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
    // Use hardcoded app-wide API key for now
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
  
  /// Get visibility state for airports layer
  Future<bool> isAirportsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_airportsEnabledKey)) {
      await prefs.setBool(_airportsEnabledKey, _defaultAirportsEnabled);
      return _defaultAirportsEnabled;
    }
    return prefs.getBool(_airportsEnabledKey) ?? _defaultAirportsEnabled;
  }
  
  /// Set visibility state for airports layer
  Future<void> setAirportsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_airportsEnabledKey, enabled);
    LoggingService.structured('OPENAIP_LAYER_TOGGLE', {
      'layer': 'airports',
      'enabled': enabled,
    });
  }
  
  /// Get visibility state for navaids layer
  Future<bool> isNavaidsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_navaidsEnabledKey)) {
      await prefs.setBool(_navaidsEnabledKey, _defaultNavaidsEnabled);
      return _defaultNavaidsEnabled;
    }
    return prefs.getBool(_navaidsEnabledKey) ?? _defaultNavaidsEnabled;
  }
  
  /// Set visibility state for navaids layer
  Future<void> setNavaidsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_navaidsEnabledKey, enabled);
    LoggingService.structured('OPENAIP_LAYER_TOGGLE', {
      'layer': 'navaids',
      'enabled': enabled,
    });
  }
  
  /// Get visibility state for reporting points layer
  Future<bool> isReportingPointsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_reportingPointsEnabledKey)) {
      await prefs.setBool(_reportingPointsEnabledKey, _defaultReportingPointsEnabled);
      return _defaultReportingPointsEnabled;
    }
    return prefs.getBool(_reportingPointsEnabledKey) ?? _defaultReportingPointsEnabled;
  }
  
  /// Set visibility state for reporting points layer
  Future<void> setReportingPointsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_reportingPointsEnabledKey, enabled);
    LoggingService.structured('OPENAIP_LAYER_TOGGLE', {
      'layer': 'reporting_points',
      'enabled': enabled,
    });
  }
  
  /// Get enabled state for a specific layer
  Future<bool> isLayerEnabled(OpenAipLayer layer) async {
    switch (layer) {
      case OpenAipLayer.openaip:
        // For consolidated layer, return true if any individual layer is enabled
        return await isAirspaceEnabled() || await isAirportsEnabled() || await isNavaidsEnabled() || await isReportingPointsEnabled();
      case OpenAipLayer.airspaces:
        return isAirspaceEnabled();
      case OpenAipLayer.airports:
        return isAirportsEnabled();
      case OpenAipLayer.navaids:
        return isNavaidsEnabled();
      case OpenAipLayer.reportingPoints:
        return isReportingPointsEnabled();
    }
  }
  
  /// Set enabled state for a specific layer
  Future<void> setLayerEnabled(OpenAipLayer layer, bool enabled) async {
    switch (layer) {
      case OpenAipLayer.openaip:
        // For consolidated layer, enable/disable all individual layers
        await setAirspaceEnabled(enabled);
        await setAirportsEnabled(enabled);
        await setNavaidsEnabled(enabled);
        await setReportingPointsEnabled(enabled);
        break;
      case OpenAipLayer.airspaces:
        await setAirspaceEnabled(enabled);
        break;
      case OpenAipLayer.airports:
        await setAirportsEnabled(enabled);
        break;
      case OpenAipLayer.navaids:
        await setNavaidsEnabled(enabled);
        break;
      case OpenAipLayer.reportingPoints:
        await setReportingPointsEnabled(enabled);
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
    await prefs.remove(_airportsEnabledKey);
    await prefs.remove(_navaidsEnabledKey);
    await prefs.remove(_reportingPointsEnabledKey);
    await prefs.remove(_overlayOpacityKey);
    
    LoggingService.info('OpenAIP settings reset to defaults');
  }
  
  /// Get a summary of current settings
  Future<Map<String, dynamic>> getSettingsSummary() async {
    return {
      'has_api_key': await hasApiKey(),
      'airspace_enabled': await isAirspaceEnabled(),
      'airports_enabled': await isAirportsEnabled(),
      'navaids_enabled': await isNavaidsEnabled(),
      'reporting_points_enabled': await isReportingPointsEnabled(),
      'overlay_opacity': await getOverlayOpacity(),
    };
  }
}
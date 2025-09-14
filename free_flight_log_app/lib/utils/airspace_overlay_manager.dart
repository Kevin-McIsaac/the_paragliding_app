import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/openaip_service.dart';
import '../services/airspace_geojson_service.dart';
import '../services/aviation_data_service.dart';
import '../services/logging_service.dart';
import '../data/models/airport.dart';
import '../data/models/navaid.dart';
import '../data/models/reporting_point.dart';
import '../utils/aviation_marker_utils.dart';

/// Manages all OpenAIP aviation data overlay layers for flutter_map
class AirspaceOverlayManager {
  static AirspaceOverlayManager? _instance;
  static AirspaceOverlayManager get instance => _instance ??= AirspaceOverlayManager._();

  AirspaceOverlayManager._();

  final OpenAipService _openAipService = OpenAipService.instance;
  final AirspaceGeoJsonService _geoJsonService = AirspaceGeoJsonService.instance;
  final AviationDataService _aviationDataService = AviationDataService.instance;

  // Cache for aviation data markers
  List<Airport> _cachedAirports = [];
  List<Navaid> _cachedNavaids = [];
  List<ReportingPoint> _cachedReportingPoints = [];
  String? _lastBoundsKey;

  /// Build all overlay layers for enabled OpenAIP data types
  Future<List<Widget>> buildEnabledOverlayLayers({
    required LatLng center,
    required double zoom,
  }) async {
    final List<Widget> layers = [];
    final bounds = _geoJsonService.calculateBoundingBox(center, zoom);
    final boundsKey = '${bounds.south},${bounds.west},${bounds.north},${bounds.east}';

    LoggingService.structured('AVIATION_OVERLAY_BUILD', {
      'center': '${center.latitude},${center.longitude}',
      'zoom': zoom,
      'bounds_key': boundsKey,
    });

    // Build airspace polygons (bottom layer)
    if (await _openAipService.getAirspaceEnabled()) {
      try {
        final opacity = await _openAipService.getOverlayOpacity();
        final polygons = await _buildAirspacePolygons(center, zoom, opacity);

        if (polygons.isNotEmpty) {
          final polygonLayer = PolygonLayer(
            polygons: polygons,
            polygonCulling: true,
          );
          layers.add(polygonLayer);
        }
      } catch (error, stackTrace) {
        LoggingService.error('Failed to build airspace layer', error, stackTrace);
      }
    }

    // Update aviation data cache if bounds changed
    if (_lastBoundsKey != boundsKey) {
      await _updateAviationDataCache(bounds);
      _lastBoundsKey = boundsKey;
    }

    // Build marker layers (on top of polygons)
    final markerLayers = await _buildMarkerLayers();
    layers.addAll(markerLayers);

    return layers;
  }

  /// Build airspace polygons from GeoJSON data
  Future<List<Polygon>> _buildAirspacePolygons(LatLng center, double zoom, double opacity) async {
    try {
      // Calculate bounding box for API request
      final bounds = _geoJsonService.calculateBoundingBox(center, zoom);

      LoggingService.structured('AIRSPACE_FETCH_START', {
        'bounds': '${bounds.west},${bounds.south},${bounds.east},${bounds.north}',
        'zoom': zoom,
      });

      // Fetch GeoJSON data from OpenAIP
      final geoJsonString = await _geoJsonService.fetchAirspaceGeoJson(bounds);

      // Get enabled airspace types for filtering
      final enabledStringTypes = await _openAipService.getEnabledAirspaceTypes();

      // Convert string type keys to numeric type keys
      final enabledTypes = _convertStringTypesToNumeric(enabledStringTypes);

      // Parse GeoJSON and convert to styled polygons (filtered by enabled types)
      final polygons = await _geoJsonService.parseAirspaceGeoJson(geoJsonString, opacity, enabledTypes);

      LoggingService.structured('AIRSPACE_FETCH_SUCCESS', {
        'polygon_count': polygons.length,
        'geojson_size': geoJsonString.length,
        'enabled_types_count': enabledStringTypes.values.where((enabled) => enabled).length,
        'total_types_count': enabledTypes.length,
      });

      return polygons;

    } catch (error, stackTrace) {
      LoggingService.error('Failed to build airspace polygons', error, stackTrace);
      // Return empty list to continue without airspace data
      return [];
    }
  }
  
  /// Update cached aviation data for the given bounds
  Future<void> _updateAviationDataCache(LatLngBounds bounds) async {
    final futures = <Future>[];

    if (await _openAipService.getAirportsEnabled()) {
      futures.add(_aviationDataService.fetchAirports(bounds).then((airports) {
        _cachedAirports = airports;
      }));
    } else {
      _cachedAirports = [];
    }

    if (await _openAipService.getNavaidsEnabled()) {
      futures.add(_aviationDataService.fetchNavaids(bounds).then((navaids) {
        _cachedNavaids = navaids;
      }));
    } else {
      _cachedNavaids = [];
    }

    if (await _openAipService.getReportingPointsEnabled()) {
      futures.add(_aviationDataService.fetchReportingPoints(bounds).then((points) {
        _cachedReportingPoints = points;
      }));
    } else {
      _cachedReportingPoints = [];
    }

    // Wait for all enabled data types to load
    if (futures.isNotEmpty) {
      await Future.wait(futures);
    }

    LoggingService.structured('AVIATION_DATA_CACHE_UPDATE', {
      'airports': _cachedAirports.length,
      'navaids': _cachedNavaids.length,
      'reporting_points': _cachedReportingPoints.length,
    });
  }

  /// Build marker layers for aviation data
  Future<List<Widget>> _buildMarkerLayers() async {
    final List<Widget> layers = [];
    final List<Marker> allMarkers = [];

    // Add airport markers
    for (final airport in _cachedAirports) {
      allMarkers.add(AviationMarkerUtils.buildAirportMarker(
        airport: airport,
        onTap: () => _onAirportTap(airport),
      ));
    }

    // Add navaid markers
    for (final navaid in _cachedNavaids) {
      allMarkers.add(AviationMarkerUtils.buildNavaidMarker(
        navaid: navaid,
        onTap: () => _onNavaidTap(navaid),
      ));
    }

    // Add reporting point markers
    for (final point in _cachedReportingPoints) {
      allMarkers.add(AviationMarkerUtils.buildReportingPointMarker(
        reportingPoint: point,
        onTap: () => _onReportingPointTap(point),
      ));
    }

    if (allMarkers.isNotEmpty) {
      layers.add(MarkerLayer(markers: allMarkers));

      LoggingService.structured('AVIATION_MARKERS_BUILT', {
        'total_markers': allMarkers.length,
        'airports': _cachedAirports.length,
        'navaids': _cachedNavaids.length,
        'reporting_points': _cachedReportingPoints.length,
      });
    }

    return layers;
  }

  /// Handle airport marker tap
  void _onAirportTap(Airport airport) {
    LoggingService.structured('AIRPORT_MARKER_TAP', {
      'airport_id': airport.id,
      'airport_name': airport.name,
      'icao': airport.icaoCode,
    });
    // Additional tap handling can be added here
  }

  /// Handle navaid marker tap
  void _onNavaidTap(Navaid navaid) {
    LoggingService.structured('NAVAID_MARKER_TAP', {
      'navaid_id': navaid.id,
      'navaid_name': navaid.name,
      'type': navaid.type.code,
    });
    // Additional tap handling can be added here
  }

  /// Handle reporting point marker tap
  void _onReportingPointTap(ReportingPoint point) {
    LoggingService.structured('REPORTING_POINT_MARKER_TAP', {
      'point_id': point.id,
      'point_name': point.name,
      'type': point.type.code,
    });
    // Additional tap handling can be added here
  }

  /// Check if any overlay layers are enabled
  Future<bool> hasEnabledLayers() async {
    final airspaceEnabled = await _openAipService.getAirspaceEnabled();
    final airportsEnabled = await _openAipService.getAirportsEnabled();
    final navaidsEnabled = await _openAipService.getNavaidsEnabled();
    final reportingPointsEnabled = await _openAipService.getReportingPointsEnabled();

    return airspaceEnabled || airportsEnabled || navaidsEnabled || reportingPointsEnabled;
  }

  /// Get count of enabled layers
  Future<int> getEnabledLayerCount() async {
    int count = 0;
    if (await _openAipService.getAirspaceEnabled()) count++;
    if (await _openAipService.getAirportsEnabled()) count++;
    if (await _openAipService.getNavaidsEnabled()) count++;
    if (await _openAipService.getReportingPointsEnabled()) count++;
    return count;
  }
  
  /// Build a comprehensive legend widget for all enabled aviation layers
  Future<Widget?> buildLayerLegend(BuildContext context) async {
    final hasEnabledData = await hasEnabledLayers();

    if (!hasEnabledData) {
      return null;
    }

    final List<Widget> legendItems = [];

    // Add airspace legend if enabled
    if (await _openAipService.getAirspaceEnabled()) {
      final visibleAirspaceTypes = _geoJsonService.visibleAirspaceTypes;

      if (visibleAirspaceTypes.isNotEmpty) {
        final airspaceLegendItems = await Future.value(
          // Use the existing airspace legend from SiteMarkerUtils
          _geoJsonService.allAirspaceStyles.entries
              .where((entry) => visibleAirspaceTypes.contains(entry.key))
              .map((entry) => _buildAirspaceLegendItem(entry.key, entry.value))
              .toList(),
        );

        if (airspaceLegendItems.isNotEmpty) {
          legendItems.addAll(airspaceLegendItems);
          legendItems.add(const SizedBox(height: 4));
        }
      }
    }

    // Add aviation data legends
    final aviationLegendItems = AviationMarkerUtils.buildAviationLegendItems(
      showAirports: await _openAipService.getAirportsEnabled() && _cachedAirports.isNotEmpty,
      showNavaids: await _openAipService.getNavaidsEnabled() && _cachedNavaids.isNotEmpty,
      showReportingPoints: await _openAipService.getReportingPointsEnabled() && _cachedReportingPoints.isNotEmpty,
    );

    legendItems.addAll(aviationLegendItems);

    if (legendItems.isEmpty) {
      return null;
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Aviation Data',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          ...legendItems,
          const SizedBox(height: 2),
          Text(
            'Source: OpenAIP',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }

  /// Build a single legend item for an airspace type
  Widget _buildAirspaceLegendItem(String type, AirspaceStyle style) {
    final typeNames = {
      'CTR': 'Control Zone',
      'TMA': 'Terminal Area',
      'CTA': 'Control Area',
      'D': 'Danger',
      'R': 'Restricted',
      'P': 'Prohibited',
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 6,
            decoration: BoxDecoration(
              color: style.fillColor,
              border: Border.all(
                color: style.borderColor,
                width: 0.5,
              ),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$type - ${typeNames[type] ?? type}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// Validate that required dependencies are available
  static bool validateDependencies() {
    try {
      // Check if flutter_map and GeoJSON dependencies are available
      PolygonLayer;
      return true;
    } catch (e) {
      LoggingService.error('AirspaceOverlayManager dependency validation failed', e);
      return false;
    }
  }
  
  /// Clear cached aviation data
  void clearCache() {
    _cachedAirports = [];
    _cachedNavaids = [];
    _cachedReportingPoints = [];
    _lastBoundsKey = null;
    _aviationDataService.clearCaches();
    LoggingService.info('Aviation overlay cache cleared');
  }

  /// Get overlay status for logging/debugging
  Future<Map<String, dynamic>> getOverlayStatus() async {
    final airspaceEnabled = await _openAipService.getAirspaceEnabled();
    final airportsEnabled = await _openAipService.getAirportsEnabled();
    final navaidsEnabled = await _openAipService.getNavaidsEnabled();
    final reportingPointsEnabled = await _openAipService.getReportingPointsEnabled();
    final opacity = await _openAipService.getOverlayOpacity();
    final hasApiKey = await _openAipService.hasApiKey();

    return {
      'airspace_enabled': airspaceEnabled,
      'airports_enabled': airportsEnabled,
      'navaids_enabled': navaidsEnabled,
      'reporting_points_enabled': reportingPointsEnabled,
      'cached_airports': _cachedAirports.length,
      'cached_navaids': _cachedNavaids.length,
      'cached_reporting_points': _cachedReportingPoints.length,
      'opacity': opacity,
      'has_api_key': hasApiKey,
      'dependencies_valid': validateDependencies(),
    };
  }

  /// Convert string type keys to numeric type keys for airspace filtering
  Map<int, bool> _convertStringTypesToNumeric(Map<String, bool> stringTypes) {
    // Mapping from string abbreviations to numeric codes
    const stringToNumeric = {
      'Unknown': 0,
      'A': 1,       // Class A (could be 1, 6, or others depending on context)
      'B': 2,       // Class B
      'C': 3,       // Class C
      'CTR': 4,     // Control Zone
      'E': 5,       // Class E (could be 2 or 5 depending on context)
      'TMA': 6,     // Terminal Control Area
      'G': 7,       // Class G
      'CTA': 10,    // Control Area (primary mapping to 10/26)
      'R': 11,      // Restricted
      'P': 12,      // Prohibited
      'ATZ': 13,    // Aerodrome Traffic Zone
      'D': 14,      // Danger Area
    };

    final numericTypes = <int, bool>{};

    stringTypes.forEach((stringType, enabled) {
      final numericCode = stringToNumeric[stringType];
      if (numericCode != null) {
        numericTypes[numericCode] = enabled;

        // Handle special mappings for types that have multiple numeric codes
        if (stringType == 'CTA') {
          // CTA maps to both 10 and 26
          numericTypes[26] = enabled;
        } else if (stringType == 'CTR') {
          // CTR maps to 4, 8, and 17
          numericTypes[8] = enabled;
          numericTypes[17] = enabled;
        } else if (stringType == 'TMA') {
          // TMA maps to 6, 9, 16, and 21
          numericTypes[9] = enabled;
          numericTypes[16] = enabled;
          numericTypes[21] = enabled;
        } else if (stringType == 'A') {
          // Class A can be code 6 as well
          numericTypes[6] = enabled;
        } else if (stringType == 'E') {
          // Class E can be code 2 as well
          numericTypes[2] = enabled;
        } else if (stringType == 'R') {
          // Restricted maps to 11, 15, and 18
          numericTypes[15] = enabled;
          numericTypes[18] = enabled;
        } else if (stringType == 'P') {
          // Prohibited maps to 12 and 19
          numericTypes[19] = enabled;
        } else if (stringType == 'D') {
          // Danger maps to 14 and 20
          numericTypes[20] = enabled;
        }
      }
    });

    return numericTypes;
  }
}
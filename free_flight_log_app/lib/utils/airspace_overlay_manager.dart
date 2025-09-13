import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/openaip_service.dart';
import '../services/airspace_geojson_service.dart';
import '../services/logging_service.dart';

/// Manages OpenAIP airspace overlay layers using GeoJSON data for flutter_map
class AirspaceOverlayManager {
  static AirspaceOverlayManager? _instance;
  static AirspaceOverlayManager get instance => _instance ??= AirspaceOverlayManager._();

  AirspaceOverlayManager._();

  final OpenAipService _openAipService = OpenAipService.instance;
  final AirspaceGeoJsonService _geoJsonService = AirspaceGeoJsonService.instance;

  /// Build PolygonLayer with airspace data for all enabled OpenAIP layers
  Future<List<Widget>> buildEnabledOverlayLayers({
    required LatLng center,
    required double zoom,
  }) async {
    final List<Widget> layers = [];
    final enabledLayers = await _openAipService.getEnabledLayers();
    final opacity = await _openAipService.getOverlayOpacity();

    LoggingService.structured('AIRSPACE_OVERLAY_BUILD', {
      'enabled_layers': enabledLayers.map((l) => l.urlPath).toList(),
      'opacity': opacity,
      'center': '${center.latitude},${center.longitude}',
      'zoom': zoom,
    });

    // Only build polygons if any layers are enabled
    if (enabledLayers.isNotEmpty) {
      try {
        final polygons = await _buildAirspacePolygons(center, zoom, opacity);

        if (polygons.isNotEmpty) {
          final polygonLayer = PolygonLayer(
            polygons: polygons,
            polygonCulling: true, // Performance optimization for off-screen polygons
          );
          layers.add(polygonLayer);

          LoggingService.structured('AIRSPACE_POLYGON_LAYER', {
            'polygon_count': polygons.length,
            'enabled_ui_layers': enabledLayers.map((l) => l.displayName).toList(),
            'opacity': opacity,
          });
        }
      } catch (error, stackTrace) {
        LoggingService.error('Failed to build airspace polygon layer', error, stackTrace);
        // Continue without airspace layer rather than failing completely
      }
    }

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

      // Parse GeoJSON and convert to styled polygons
      final polygons = await _geoJsonService.parseAirspaceGeoJson(geoJsonString, opacity);

      LoggingService.structured('AIRSPACE_FETCH_SUCCESS', {
        'polygon_count': polygons.length,
        'geojson_size': geoJsonString.length,
      });

      return polygons;

    } catch (error, stackTrace) {
      LoggingService.error('Failed to build airspace polygons', error, stackTrace);
      // Return empty list to continue without airspace data
      return [];
    }
  }
  
  /// Check if any overlay layers are enabled
  Future<bool> hasEnabledLayers() async {
    final enabledLayers = await _openAipService.getEnabledLayers();
    return enabledLayers.isNotEmpty;
  }
  
  /// Get count of enabled layers
  Future<int> getEnabledLayerCount() async {
    final enabledLayers = await _openAipService.getEnabledLayers();
    return enabledLayers.length;
  }
  
  /// Build a simple legend widget for enabled layers with airspace types
  Future<Widget?> buildLayerLegend(BuildContext context) async {
    final enabledLayers = await _openAipService.getEnabledLayers();

    if (enabledLayers.isEmpty) {
      return null;
    }

    final opacity = await _openAipService.getOverlayOpacity();
    final airspaceStyles = _geoJsonService.allAirspaceStyles;

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
          Text(
            'Airspace Types',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          // Show main airspace types with their colors
          ...airspaceStyles.entries
              .where((entry) => ['CTR', 'TMA', 'CTA', 'D', 'R', 'P'].contains(entry.key))
              .map((entry) => _buildLegendItem(entry.key, entry.value)),
          const SizedBox(height: 4),
          Text(
            'Opacity: ${(opacity * 100).round()}%',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 10,
            ),
          ),
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
  Widget _buildLegendItem(String type, AirspaceStyle style) {
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
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: style.borderColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            typeNames[type] ?? type,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 10,
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
  
  /// Get overlay status for logging/debugging
  Future<Map<String, dynamic>> getOverlayStatus() async {
    final enabledLayers = await _openAipService.getEnabledLayers();
    final opacity = await _openAipService.getOverlayOpacity();
    final hasApiKey = await _openAipService.hasApiKey();
    
    return {
      'enabled_layers': enabledLayers.map((l) => l.urlPath).toList(),
      'layer_count': enabledLayers.length,
      'opacity': opacity,
      'has_api_key': hasApiKey,
      'dependencies_valid': validateDependencies(),
    };
  }
}
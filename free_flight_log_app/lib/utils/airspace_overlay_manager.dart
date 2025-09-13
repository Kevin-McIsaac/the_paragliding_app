import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../services/openaip_service.dart';
import '../services/logging_service.dart';
import '../utils/map_tile_provider.dart';

/// Manages OpenAIP airspace overlay layers for flutter_map
class AirspaceOverlayManager {
  static AirspaceOverlayManager? _instance;
  static AirspaceOverlayManager get instance => _instance ??= AirspaceOverlayManager._();
  
  AirspaceOverlayManager._();
  
  final OpenAipService _openAipService = OpenAipService.instance;
  
  /// Build TileLayer widgets for all enabled OpenAIP layers
  Future<List<TileLayer>> buildEnabledOverlayLayers() async {
    final List<TileLayer> layers = [];
    final enabledLayers = await _openAipService.getEnabledLayers();
    final opacity = await _openAipService.getOverlayOpacity();
    final apiKey = await _openAipService.getApiKey();
    
    LoggingService.structured('AIRSPACE_OVERLAY_BUILD', {
      'enabled_layers': enabledLayers.map((l) => l.urlPath).toList(),
      'opacity': opacity,
      'has_api_key': apiKey != null && apiKey.isNotEmpty,
    });
    
    // Since OpenAIP consolidated all layers into a single 'openaip' layer,
    // we only add one tile layer if any layers are enabled
    if (enabledLayers.isNotEmpty) {
      // All layers now use the same 'openaip' endpoint
      final tileLayer = _buildTileLayer(OpenAipLayer.openaip, opacity, apiKey);
      layers.add(tileLayer);
      
      LoggingService.structured('AIRSPACE_CONSOLIDATED_LAYER', {
        'enabled_ui_layers': enabledLayers.map((l) => l.displayName).toList(),
        'actual_tile_layer': 'openaip',
        'note': 'All UI toggles map to single consolidated OpenAIP layer',
      });
    }
    
    return layers;
  }
  
  /// Build a single TileLayer for the specified OpenAIP layer
  TileLayer _buildTileLayer(OpenAipLayer layer, double opacity, String? apiKey) {
    final urlTemplate = _openAipService.getTileUrlTemplate(layer, apiKey: apiKey);
    
    return TileLayer(
      urlTemplate: urlTemplate,
      subdomains: _openAipService.subdomains,
      userAgentPackageName: 'com.example.free_flight_log_app',
      minZoom: _openAipService.minZoom.toDouble(),
      maxZoom: _openAipService.maxZoom.toDouble(),
      tileProvider: MapTileProvider.createInstance(),
      errorTileCallback: _getErrorCallback(layer),
      tileBuilder: _getTileBuilder(layer),
      // Tile loading settings optimized for overlay data
      tileDimension: 256,
      // Prevent tiles from being kept too long in memory for overlay data
      keepBuffer: 2,
    );
  }
  
  /// Get error callback for tile loading failures
  ErrorTileCallBack? _getErrorCallback(OpenAipLayer layer) {
    return (tile, error, stackTrace) {
      LoggingService.error('OpenAIP tile loading failed for ${layer.urlPath}', error, stackTrace);
      // Just log the error, flutter_map will handle the display
    };
  }
  
  /// Get tile builder for custom tile styling
  TileBuilder? _getTileBuilder(OpenAipLayer layer) {
    return (context, widget, tile) {
      // Add subtle border for debugging tile boundaries in development
      if (const bool.fromEnvironment('dart.vm.product') == false) {
        return Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: _getLayerDebugColor(layer).withValues(alpha: 0.1),
              width: 0.5,
            ),
          ),
          child: widget,
        );
      }
      return widget;
    };
  }
  
  /// Get debug color for layer identification during development
  Color _getLayerDebugColor(OpenAipLayer layer) {
    switch (layer) {
      case OpenAipLayer.openaip:
        return Colors.orange; // Consolidated layer
      case OpenAipLayer.airspaces:
        return Colors.red;
      case OpenAipLayer.airports:
        return Colors.blue;
      case OpenAipLayer.navaids:
        return Colors.green;
      case OpenAipLayer.reportingPoints:
        return Colors.purple;
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
  
  /// Build a simple legend widget for enabled layers
  Future<Widget?> buildLayerLegend(BuildContext context) async {
    final enabledLayers = await _openAipService.getEnabledLayers();
    
    if (enabledLayers.isEmpty) {
      return null;
    }
    
    final opacity = await _openAipService.getOverlayOpacity();
    
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
            'Airspace Overlay',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          ...enabledLayers.map((layer) => _buildLegendItem(layer)),
          if (enabledLayers.length > 1) ...[
            const SizedBox(height: 4),
            Text(
              'Opacity: ${(opacity * 100).round()}%',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }
  
  /// Build a single legend item for a layer
  Widget _buildLegendItem(OpenAipLayer layer) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _getLayerColor(layer),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            layer.displayName,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
  
  /// Get representative color for each layer type
  Color _getLayerColor(OpenAipLayer layer) {
    switch (layer) {
      case OpenAipLayer.openaip:
        return Colors.orange; // Consolidated layer
      case OpenAipLayer.airspaces:
        return Colors.red;
      case OpenAipLayer.airports:
        return Colors.blue;
      case OpenAipLayer.navaids:
        return Colors.green;
      case OpenAipLayer.reportingPoints:
        return Colors.purple;
    }
  }
  
  /// Validate that required dependencies are available
  static bool validateDependencies() {
    try {
      // Check if flutter_map is available
      TileLayer;
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
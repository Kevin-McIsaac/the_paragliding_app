import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../services/logging_service.dart';

/// Widget for map control buttons (zoom, layer switching, etc.)
class FlightMapControls extends StatefulWidget {
  final MapController mapController;
  final VoidCallback? onLayerChanged;

  const FlightMapControls({
    super.key,
    required this.mapController,
    this.onLayerChanged,
  });

  @override
  State<FlightMapControls> createState() => _FlightMapControlsState();
}

class _FlightMapControlsState extends State<FlightMapControls> {
  String _currentLayer = 'OpenStreetMap';
  
  final Map<String, String> _mapLayers = {
    'OpenStreetMap': 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    'OpenTopoMap': 'https://tile.opentopomap.org/{z}/{x}/{y}.png',
    'Satellite': 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
    'Terrain': 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Terrain_Base/MapServer/tile/{z}/{y}/{x}',
  };

  @override
  void initState() {
    super.initState();
    _loadCurrentLayer();
  }

  Future<void> _loadCurrentLayer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedLayer = prefs.getString('map_layer_name') ?? 'OpenStreetMap';
      
      if (mounted && _mapLayers.containsKey(savedLayer)) {
        setState(() {
          _currentLayer = savedLayer;
        });
      }
    } catch (e) {
      LoggingService.error('FlightMapControls: Failed to load current layer', e);
    }
  }

  Future<void> _switchLayer(String layerName) async {
    if (!_mapLayers.containsKey(layerName)) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('map_layer_name', layerName);
      await prefs.setString('map_tile_url', _mapLayers[layerName]!);
      
      setState(() {
        _currentLayer = layerName;
      });
      
      widget.onLayerChanged?.call();
      
      LoggingService.info('FlightMapControls: Switched to layer: $layerName');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Switched to $layerName'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      LoggingService.error('FlightMapControls: Failed to switch layer', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 16,
      bottom: 80, // Above attribution
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Layer selector
          _buildLayerSelector(context),
          
          const SizedBox(height: 8),
          
          // Zoom controls
          _buildZoomControls(context),
        ],
      ),
    );
  }

  Widget _buildLayerSelector(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: PopupMenuButton<String>(
        icon: const Icon(Icons.layers, size: 20),
        tooltip: 'Map Layers',
        onSelected: _switchLayer,
        itemBuilder: (context) => _mapLayers.keys.map((layerName) {
          return PopupMenuItem<String>(
            value: layerName,
            child: Row(
              children: [
                Icon(
                  _currentLayer == layerName 
                      ? Icons.radio_button_checked 
                      : Icons.radio_button_unchecked,
                  size: 16,
                  color: _currentLayer == layerName 
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(layerName),
              ],
            ),
          );
        }).toList(),
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          child: const Icon(Icons.layers, size: 20),
        ),
      ),
    );
  }

  Widget _buildZoomControls(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Zoom in
          _buildZoomButton(
            context,
            Icons.add,
            'Zoom In',
            () => widget.mapController.move(
              widget.mapController.camera.center,
              widget.mapController.camera.zoom + 1,
            ),
          ),
          
          Container(
            width: 32,
            height: 1,
            color: Colors.grey[300],
          ),
          
          // Zoom out
          _buildZoomButton(
            context,
            Icons.remove,
            'Zoom Out',
            () => widget.mapController.move(
              widget.mapController.camera.center,
              widget.mapController.camera.zoom - 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildZoomButton(
    BuildContext context,
    IconData icon,
    String tooltip,
    VoidCallback onPressed,
  ) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        child: Icon(icon, size: 20),
      ),
    );
  }
}
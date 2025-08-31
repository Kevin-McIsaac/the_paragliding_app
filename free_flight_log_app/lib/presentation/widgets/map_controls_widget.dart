import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

enum MapProvider {
  openStreetMap('OpenStreetMap', 'OSM', 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', 19, '© OpenStreetMap'),
  openTopoMap('OpenTopoMap', 'Topo', 'https://tile.opentopomap.org/{z}/{x}/{y}.png', 17, '© OpenTopoMap'),
  cartoDB('CartoDB', 'CartoDB', 'https://tile.openstreetmap.fr/hot/{z}/{x}/{y}.png', 19, '© CartoDB'),
  esriSatellite('ESRI Satellite', 'Satellite', 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}', 18, '© ESRI');

  const MapProvider(this.displayName, this.shortName, this.urlTemplate, this.maxZoom, this.attribution);
  final String displayName;
  final String shortName;
  final String urlTemplate;
  final int maxZoom;
  final String attribution;
}

/// Widget for map provider selection and zoom controls
class MapControlsWidget extends StatelessWidget {
  final MapProvider selectedProvider;
  final Function(MapProvider) onProviderChanged;
  final MapController? mapController;
  final Function()? onZoomIn;
  final Function()? onZoomOut;
  final Function()? onShowHelp;

  const MapControlsWidget({
    super.key,
    required this.selectedProvider,
    required this.onProviderChanged,
    this.mapController,
    this.onZoomIn,
    this.onZoomOut,
    this.onShowHelp,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 10,
      right: 10,
      child: Column(
        children: [
          // Map provider selector
          Card(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: DropdownButton<MapProvider>(
                value: selectedProvider,
                underline: Container(),
                items: MapProvider.values.map((provider) {
                  return DropdownMenuItem<MapProvider>(
                    value: provider,
                    child: Text(provider.shortName),
                  );
                }).toList(),
                onChanged: (MapProvider? newProvider) {
                  if (newProvider != null) {
                    onProviderChanged(newProvider);
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Zoom controls
          Card(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: onZoomIn,
                  icon: const Icon(Icons.add),
                  tooltip: 'Zoom In',
                ),
                IconButton(
                  onPressed: onZoomOut,
                  icon: const Icon(Icons.remove),
                  tooltip: 'Zoom Out',
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Help button
          if (onShowHelp != null)
            Card(
              child: IconButton(
                onPressed: onShowHelp,
                icon: const Icon(Icons.help_outline),
                tooltip: 'Show Help',
              ),
            ),
        ],
      ),
    );
  }
}
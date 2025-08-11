import 'package:flutter/material.dart';
import 'cesium/cesium_webview_controller.dart';
import '../../services/logging_service.dart';

/// Control panel for Cesium 3D map features
class Cesium3DControlsWidget extends StatefulWidget {
  final CesiumWebViewController controller;
  final VoidCallback? onClose;

  const Cesium3DControlsWidget({
    Key? key,
    required this.controller,
    this.onClose,
  }) : super(key: key);

  @override
  State<Cesium3DControlsWidget> createState() => _Cesium3DControlsWidgetState();
}

class _Cesium3DControlsWidgetState extends State<Cesium3DControlsWidget> {
  double _terrainExaggeration = 1.0;
  double _trackOpacity = 0.8;
  String _selectedBaseMap = 'satellite';
  bool _showColoredTrack = false;

  // Sample flight data for testing
  final List<Map<String, dynamic>> _sampleFlightPoints = [
    {'latitude': 47.14, 'longitude': 11.30, 'altitude': 1200, 'climbRate': 0.5},
    {'latitude': 47.15, 'longitude': 11.31, 'altitude': 1400, 'climbRate': 2.0},
    {'latitude': 47.16, 'longitude': 11.32, 'altitude': 1800, 'climbRate': 3.5},
    {'latitude': 47.17, 'longitude': 11.33, 'altitude': 2200, 'climbRate': 2.8},
    {'latitude': 47.18, 'longitude': 11.34, 'altitude': 2400, 'climbRate': 1.2},
    {'latitude': 47.19, 'longitude': 11.35, 'altitude': 2300, 'climbRate': -0.8},
    {'latitude': 47.20, 'longitude': 11.36, 'altitude': 2100, 'climbRate': -1.5},
    {'latitude': 47.21, 'longitude': 11.37, 'altitude': 1900, 'climbRate': -1.2},
    {'latitude': 47.22, 'longitude': 11.38, 'altitude': 1600, 'climbRate': -2.0},
    {'latitude': 47.23, 'longitude': 11.39, 'altitude': 1200, 'climbRate': -2.5},
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280, // Fixed width to avoid layout issues
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '3D Controls',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (widget.onClose != null)
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: widget.onClose,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              
              // Terrain Exaggeration
              _buildSectionTitle('Terrain'),
              SizedBox(
                height: 40,
                child: Row(
                  children: [
                    const Text('Exaggeration:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Slider(
                        value: _terrainExaggeration,
                        min: 1.0,
                        max: 5.0,
                        divisions: 8,
                        label: _terrainExaggeration.toStringAsFixed(1),
                        onChanged: (value) {
                          setState(() => _terrainExaggeration = value);
                          widget.controller.setTerrainExaggeration(value);
                        },
                      ),
                    ),
                    Text(
                      '${_terrainExaggeration.toStringAsFixed(1)}x',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              
              // Base Map Selector
              _buildSectionTitle('Base Map'),
              Wrap(
                spacing: 8,
                children: ['satellite', 'terrain', 'hybrid'].map((type) {
                  return ChoiceChip(
                    label: Text(type.substring(0, 1).toUpperCase() + type.substring(1)),
                    selected: _selectedBaseMap == type,
                    selectedColor: Colors.blue,
                    backgroundColor: Colors.grey[800],
                    labelStyle: TextStyle(
                      color: _selectedBaseMap == type ? Colors.white : Colors.white70,
                      fontSize: 12,
                    ),
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _selectedBaseMap = type);
                        widget.controller.switchBaseMap(type);
                      }
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              
              // Flight Track
              _buildSectionTitle('Flight Track'),
              Row(
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.timeline, size: 16),
                    label: const Text('Load Track', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onPressed: () {
                      if (_showColoredTrack) {
                        widget.controller.createColoredFlightTrack(_sampleFlightPoints);
                      } else {
                        widget.controller.createFlightTrack(_sampleFlightPoints);
                      }
                      LoggingService.info('Cesium3DControls: Flight track loaded');
                    },
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: CheckboxListTile(
                      title: const Text('Color by climb', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      value: _showColoredTrack,
                      onChanged: (value) {
                        setState(() => _showColoredTrack = value ?? false);
                      },
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
              SizedBox(
                height: 40,
                child: Row(
                  children: [
                    const Text('Opacity:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Slider(
                        value: _trackOpacity,
                        min: 0.1,
                        max: 1.0,
                        divisions: 9,
                        label: '${(_trackOpacity * 100).round()}%',
                        onChanged: (value) {
                          setState(() => _trackOpacity = value);
                          widget.controller.setTrackOpacity(value);
                        },
                      ),
                    ),
                    Text(
                      '${(_trackOpacity * 100).round()}%',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              
              // Camera Presets
              _buildSectionTitle('Camera Views'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildCameraButton('Top Down', 'topDown', Icons.arrow_downward),
                  _buildCameraButton('Side', 'sideProfile', Icons.arrow_forward),
                  _buildCameraButton('Pilot', 'pilotView', Icons.flight),
                  _buildCameraButton('3/4', 'threeFourView', Icons.panorama_fish_eye),
                ],
              ),
              const SizedBox(height: 12),
              
              // Camera Controls Toggle
              ElevatedButton.icon(
                icon: const Icon(Icons.lock_open, size: 16),
                label: const Text('Toggle Camera Controls', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onPressed: () {
                  // Toggle camera controls
                  widget.controller.setCameraControlsEnabled(true);
                  LoggingService.info('Cesium3DControls: Camera controls toggled');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildCameraButton(String label, String preset, IconData icon) {
    return ElevatedButton.icon(
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 11)),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.grey[700],
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: const Size(0, 30),
      ),
      onPressed: () {
        widget.controller.setCameraPreset(preset);
        LoggingService.info('Cesium3DControls: Camera preset set to $preset');
      },
    );
  }
}
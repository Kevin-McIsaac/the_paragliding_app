import 'package:flutter/material.dart';
import '../../services/openaip_service.dart';
import '../../services/logging_service.dart';

/// Widget for controlling OpenAIP airspace overlay layers
class AirspaceControlsWidget extends StatefulWidget {
  final VoidCallback? onLayersChanged;
  final bool isExpanded;
  final VoidCallback onToggleExpanded;
  
  const AirspaceControlsWidget({
    super.key,
    this.onLayersChanged,
    required this.isExpanded,
    required this.onToggleExpanded,
  });

  @override
  State<AirspaceControlsWidget> createState() => _AirspaceControlsWidgetState();
}

class _AirspaceControlsWidgetState extends State<AirspaceControlsWidget> {
  final OpenAipService _openAipService = OpenAipService.instance;
  
  // Layer state
  bool _airspaceEnabled = false;
  bool _airportsEnabled = false;
  bool _navaidsEnabled = false;
  bool _reportingPointsEnabled = false;
  double _opacity = 0.6;
  bool _hasApiKey = false;
  
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await _openAipService.getSettingsSummary();
      
      if (mounted) {
        setState(() {
          _airspaceEnabled = settings['airspace_enabled'] ?? false;
          _airportsEnabled = settings['airports_enabled'] ?? false;
          _navaidsEnabled = settings['navaids_enabled'] ?? false;
          _reportingPointsEnabled = settings['reporting_points_enabled'] ?? false;
          _opacity = settings['overlay_opacity'] ?? 0.6;
          _hasApiKey = settings['has_api_key'] ?? false;
          _loading = false;
        });
      }
    } catch (error, stackTrace) {
      LoggingService.error('Failed to load airspace settings', error, stackTrace);
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _updateLayerEnabled(OpenAipLayer layer, bool enabled) async {
    try {
      await _openAipService.setLayerEnabled(layer, enabled);
      
      // Update local state - defer to avoid mouse tracker conflicts
      if (mounted) {
        setState(() {
          switch (layer) {
            case OpenAipLayer.openaip:
              // For consolidated layer, enable/disable all UI toggles
              _airspaceEnabled = enabled;
              _airportsEnabled = enabled;
              _navaidsEnabled = enabled;
              _reportingPointsEnabled = enabled;
              break;
            case OpenAipLayer.airspaces:
              _airspaceEnabled = enabled;
              break;
            case OpenAipLayer.airports:
              _airportsEnabled = enabled;
              break;
            case OpenAipLayer.navaids:
              _navaidsEnabled = enabled;
              break;
            case OpenAipLayer.reportingPoints:
              _reportingPointsEnabled = enabled;
              break;
          }
        });
        
        // Defer parent callback to avoid re-entrancy during gesture handling
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            widget.onLayersChanged?.call();
          }
        });
      }
      
    } catch (error, stackTrace) {
      LoggingService.error('Failed to update layer enabled state', error, stackTrace);
    }
  }

  Future<void> _updateOpacity(double opacity) async {
    try {
      await _openAipService.setOverlayOpacity(opacity);
      
      // Update local state safely
      if (mounted) {
        setState(() => _opacity = opacity);
        
        // Defer parent callback to avoid re-entrancy during gesture handling
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            widget.onLayersChanged?.call();
          }
        });
      }
      
    } catch (error, stackTrace) {
      LoggingService.error('Failed to update overlay opacity', error, stackTrace);
    }
  }

  bool _hasEnabledLayers() {
    return _airspaceEnabled || _airportsEnabled || _navaidsEnabled || _reportingPointsEnabled;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white70,
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with toggle button
          InkWell(
            onTap: widget.onToggleExpanded,
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.airplanemode_active,
                    size: 16,
                    color: _hasEnabledLayers() ? Colors.blue : Colors.white70,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Airspace',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  if (_hasEnabledLayers())
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                      ),
                    ),
                  const SizedBox(width: 4),
                  Icon(
                    widget.isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: Colors.white70,
                  ),
                ],
              ),
            ),
          ),
          
          // Expanded controls
          if (widget.isExpanded) ...[
            Container(
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              color: Colors.white.withValues(alpha: 0.2),
            ),
            
            Container(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // API Key status
                  if (!_hasApiKey)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 12,
                            color: Colors.orange.withValues(alpha: 0.8),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Free tier (rate limited)',
                            style: TextStyle(
                              color: Colors.orange.withValues(alpha: 0.9),
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  
                  // Layer toggles
                  _buildLayerToggle(
                    'Airspaces',
                    _airspaceEnabled,
                    Colors.red,
                    (value) => _updateLayerEnabled(OpenAipLayer.airspaces, value),
                  ),
                  _buildLayerToggle(
                    'Airports',
                    _airportsEnabled,
                    Colors.blue,
                    (value) => _updateLayerEnabled(OpenAipLayer.airports, value),
                  ),
                  _buildLayerToggle(
                    'Navigation Aids',
                    _navaidsEnabled,
                    Colors.green,
                    (value) => _updateLayerEnabled(OpenAipLayer.navaids, value),
                  ),
                  _buildLayerToggle(
                    'Reporting Points',
                    _reportingPointsEnabled,
                    Colors.purple,
                    (value) => _updateLayerEnabled(OpenAipLayer.reportingPoints, value),
                  ),
                  
                  // Opacity slider
                  if (_hasEnabledLayers()) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Opacity',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 10,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SliderTheme(
                            data: SliderThemeData(
                              trackHeight: 2,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6,
                              ),
                              overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 12,
                              ),
                              activeTrackColor: Colors.blue,
                              inactiveTrackColor: Colors.white.withValues(alpha: 0.3),
                              thumbColor: Colors.blue,
                              overlayColor: Colors.blue.withValues(alpha: 0.2),
                            ),
                            child: Slider(
                              value: _opacity,
                              min: 0.2,
                              max: 1.0,
                              divisions: 8,
                              onChanged: _updateOpacity,
                            ),
                          ),
                        ),
                        Text(
                          '${(_opacity * 100).round()}%',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLayerToggle(
    String label,
    bool value,
    Color color,
    ValueChanged<bool> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: value ? color : color.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: value ? Colors.white : Colors.white.withValues(alpha: 0.6),
                fontSize: 11,
              ),
            ),
          ),
          InkWell(
            onTap: () => onChanged(!value),
            borderRadius: BorderRadius.circular(9),
            child: Container(
              width: 32,
              height: 18,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                color: value ? color : Colors.white.withValues(alpha: 0.2),
                border: Border.all(
                  color: value ? color : Colors.white.withValues(alpha: 0.4),
                  width: 1,
                ),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 150),
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 14,
                  height: 14,
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
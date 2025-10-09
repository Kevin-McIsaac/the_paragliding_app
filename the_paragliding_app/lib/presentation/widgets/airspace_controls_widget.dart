import 'package:flutter/material.dart';
import '../../services/openaip_service.dart';
import '../../services/logging_service.dart';
import '../../data/models/airspace_enums.dart';

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
  double _opacity = 0.6;
  bool _hasApiKey = false;

  // Individual airspace type states
  Map<AirspaceType, bool> _airspaceTypes = {};
  bool _airspaceTypesExpanded = false;

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await _openAipService.getSettingsSummary();
      final airspaceTypes = await _openAipService.getExcludedAirspaceTypes();

      if (mounted) {
        setState(() {
          _airspaceEnabled = settings['airspace_enabled'] ?? false;
          _opacity = settings['overlay_opacity'] ?? 0.6;
          _hasApiKey = settings['has_api_key'] ?? false;
          _airspaceTypes = airspaceTypes;
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

  Future<void> _updateAirspaceEnabled(bool enabled) async {
    try {
      await _openAipService.setAirspaceEnabled(enabled);

      if (mounted) {
        setState(() => _airspaceEnabled = enabled);
        _deferCallback();
      }
    } catch (error, stackTrace) {
      LoggingService.error('Failed to update airspace enabled state', error, stackTrace);
    }
  }


  void _deferCallback() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onLayersChanged?.call();
      }
    });
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

  Future<void> _updateAirspaceTypeEnabled(String type, bool enabled) async {
    try {
      // Convert string abbreviation to AirspaceType enum
      final airspaceType = AirspaceType.values.firstWhere(
        (t) => t.abbreviation == type,
        orElse: () => AirspaceType.other,
      );

      await _openAipService.setAirspaceTypeExcluded(airspaceType, enabled);

      // Update local state
      if (mounted) {
        setState(() {
          _airspaceTypes[airspaceType] = enabled;
        });

        // Defer parent callback to avoid re-entrancy during gesture handling
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            widget.onLayersChanged?.call();
          }
        });
      }

    } catch (error, stackTrace) {
      LoggingService.error('Failed to update airspace type enabled state', error, stackTrace);
    }
  }

  bool _hasEnabledLayers() {
    return _airspaceEnabled;
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
                  // API Key / Demo Data status
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: _hasApiKey ?
                        Colors.green.withValues(alpha: 0.2) :
                        Colors.blue.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _hasApiKey ? Icons.cloud_done : Icons.science,
                          size: 12,
                          color: _hasApiKey ?
                            Colors.green.withValues(alpha: 0.8) :
                            Colors.blue.withValues(alpha: 0.8),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _hasApiKey ? 'Live OpenAIP Data' : 'Demo Airspace Data',
                          style: TextStyle(
                            color: _hasApiKey ?
                              Colors.green.withValues(alpha: 0.9) :
                              Colors.blue.withValues(alpha: 0.9),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Layer toggles
                  _buildHierarchicalAirspaceToggle(),


                  // Opacity controls (optimized for airspace visibility)
                  if (_hasEnabledLayers()) ...[
                    const SizedBox(height: 8),
                    Container(
                      height: 1,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Opacity',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            '${(_opacity * 100).round()}%',
                            style: TextStyle(
                              color: Colors.blue.withValues(alpha: 0.9),
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Quick preset buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildOpacityPreset('0%', 0.0),
                        _buildOpacityPreset('10%', 0.10),
                        _buildOpacityPreset('15%', 0.15),
                        _buildOpacityPreset('20%', 0.20),
                        _buildOpacityPreset('30%', 0.30),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Precision slider for 0-30% range
                    SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 7,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 14,
                        ),
                        activeTrackColor: Colors.blue,
                        inactiveTrackColor: Colors.white.withValues(alpha: 0.3),
                        thumbColor: Colors.blue,
                        overlayColor: Colors.blue.withValues(alpha: 0.2),
                        tickMarkShape: const RoundSliderTickMarkShape(
                          tickMarkRadius: 2,
                        ),
                        activeTickMarkColor: Colors.blue.withValues(alpha: 0.7),
                        inactiveTickMarkColor: Colors.white.withValues(alpha: 0.3),
                      ),
                      child: Slider(
                        value: _opacity.clamp(0.0, 0.3),
                        min: 0.0,
                        max: 0.3,
                        divisions: 6, // 0%, 5%, 10%, 15%, 20%, 25%, 30%
                        onChanged: _updateOpacity,
                      ),
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


  /// Build hierarchical airspace toggle with expandable type controls
  Widget _buildHierarchicalAirspaceToggle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Main airspace toggle with expand button
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _airspaceEnabled ? Colors.red : Colors.red.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Airspaces',
                  style: TextStyle(
                    color: _airspaceEnabled ? Colors.white : Colors.white.withValues(alpha: 0.6),
                    fontSize: 11,
                  ),
                ),
              ),
              // Expand/collapse button for types (only when airspace is enabled)
              if (_airspaceEnabled) ...[
                InkWell(
                  onTap: () => setState(() => _airspaceTypesExpanded = !_airspaceTypesExpanded),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      _airspaceTypesExpanded ? Icons.expand_less : Icons.expand_more,
                      size: 16,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              // Main airspace toggle
              InkWell(
                onTap: () => _updateAirspaceEnabled(!_airspaceEnabled),
                borderRadius: BorderRadius.circular(9),
                child: Container(
                  width: 32,
                  height: 18,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(9),
                    color: _airspaceEnabled ? Colors.red : Colors.white.withValues(alpha: 0.2),
                    border: Border.all(
                      color: _airspaceEnabled ? Colors.red : Colors.white.withValues(alpha: 0.4),
                      width: 1,
                    ),
                  ),
                  child: AnimatedAlign(
                    duration: const Duration(milliseconds: 150),
                    alignment: _airspaceEnabled ? Alignment.centerRight : Alignment.centerLeft,
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
        ),

        // Expandable individual airspace types section
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: _buildAirspaceTypesSection(),
          crossFadeState: (_airspaceEnabled && _airspaceTypesExpanded)
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 300),
        ),
      ],
    );
  }

  /// Build the individual airspace types section
  Widget _buildAirspaceTypesSection() {
    return Container(
      margin: const EdgeInsets.only(left: 16, top: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Quick presets row
          Text(
            'Quick Presets',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildAirspacePreset('VFR', 'vfr'),
              _buildAirspacePreset('IFR', 'ifr'),
              _buildAirspacePreset('Hazards', 'hazards'),
              _buildAirspacePreset('Training', 'training'),
            ],
          ),
          const SizedBox(height: 8),

          // Control zones section
          _buildAirspaceTypeGroup('Control Zones', {
            'CTR': 'Control Zone',
            'TMA': 'Terminal Control Area',
            'CTA': 'Control Area',
          }, Colors.red),

          const SizedBox(height: 6),

          // Restricted areas section
          _buildAirspaceTypeGroup('Restricted Areas', {
            'D': 'Danger Area',
            'R': 'Restricted',
            'P': 'Prohibited',
          }, Colors.orange),

          const SizedBox(height: 6),

          // Airspace classes section
          _buildAirspaceTypeGroup('Airspace Classes', {
            'A': 'Class A (IFR only)',
            'B': 'Class B (ATC required)',
            'C': 'Class C (ATC/contact)',
            'E': 'Class E (IFR clearance)',
            'F': 'Class F (Info service)',
            'G': 'Class G (Uncontrolled)',
          }, Colors.blue),
        ],
      ),
    );
  }

  /// Build a group of airspace types with a title
  Widget _buildAirspaceTypeGroup(String title, Map<String, String> types, Color accentColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: accentColor.withValues(alpha: 0.9),
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        ...types.entries.map((entry) => _buildAirspaceTypeToggle(
          entry.key,
          entry.value,
          accentColor,
        )),
      ],
    );
  }

  /// Build individual airspace type toggle
  Widget _buildAirspaceTypeToggle(String type, String description, Color color) {
    // Convert string abbreviation to AirspaceType enum
    final airspaceType = AirspaceType.values.firstWhere(
      (t) => t.abbreviation == type,
      orElse: () => AirspaceType.other,
    );
    final isEnabled = _airspaceTypes[airspaceType] ?? false;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: isEnabled ? color : color.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '$type - $description',
              style: TextStyle(
                color: isEnabled ? Colors.white : Colors.white.withValues(alpha: 0.6),
                fontSize: 9,
              ),
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: () => _updateAirspaceTypeEnabled(type, !isEnabled),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              width: 24,
              height: 12,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: isEnabled ? color.withValues(alpha: 0.8) : Colors.white.withValues(alpha: 0.2),
                border: Border.all(
                  color: isEnabled ? color : Colors.white.withValues(alpha: 0.4),
                  width: 0.5,
                ),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 150),
                alignment: isEnabled ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build airspace preset button
  Widget _buildAirspacePreset(String label, String preset) {
    return InkWell(
      onTap: () async {
        await _openAipService.setAirspacePreset(preset);
        await _loadSettings(); // Reload to update UI
      },
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: Colors.blue.withValues(alpha: 0.4),
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.blue.withValues(alpha: 0.9),
            fontSize: 8,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  /// Build quick opacity preset button
  Widget _buildOpacityPreset(String label, double value) {
    final isSelected = (_opacity - value).abs() < 0.01; // Allow small floating point differences

    return InkWell(
      onTap: () => _updateOpacity(value),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue : Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.white.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.8),
            fontSize: 9,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
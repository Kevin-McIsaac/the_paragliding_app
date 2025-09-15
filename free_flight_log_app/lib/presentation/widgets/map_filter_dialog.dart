import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/logging_service.dart';
import '../../utils/map_provider.dart';
import '../../data/models/airspace_enums.dart';

/// Filter dialog for controlling map layer visibility
/// Supports sites toggle, airspace type filtering, ICAO class filtering, and altitude filtering
class MapFilterDialog extends StatefulWidget {
  final bool sitesEnabled;
  final bool airspaceEnabled;
  final Map<String, bool> airspaceTypes;
  final Map<String, bool> icaoClasses;
  final double maxAltitudeFt;
  final MapProvider mapProvider;
  final Function(bool sitesEnabled, bool airspaceEnabled, Map<String, bool> types, Map<String, bool> classes, double maxAltitudeFt, MapProvider mapProvider) onApply;

  const MapFilterDialog({
    super.key,
    required this.sitesEnabled,
    required this.airspaceEnabled,
    required this.airspaceTypes,
    required this.icaoClasses,
    required this.maxAltitudeFt,
    required this.mapProvider,
    required this.onApply,
  });

  @override
  State<MapFilterDialog> createState() => _MapFilterDialogState();
}

class _MapFilterDialogState extends State<MapFilterDialog> {
  late bool _sitesEnabled;
  late bool _airspaceEnabled;
  late Map<String, bool> _airspaceTypes;
  late Map<String, bool> _icaoClasses;
  late double _maxAltitudeFt;
  late MapProvider _selectedMapProvider;

  Timer? _debounceTimer;

  // Dynamic generation of all airspace types from enum
  static Map<String, String> get _typeDescriptions {
    final Map<String, String> descriptions = {};
    for (final type in AirspaceType.values) {
      descriptions[type.abbreviation] = '${type.displayName} - ${type.description}';
    }
    return descriptions;
  }

  // Available ICAO classes with detailed descriptions
  static const Map<String, String> _classDescriptions = {
    'A': 'Class A - IFR only. All flights receive ATC service and separation',
    'B': 'Class B - IFR/VFR. All flights receive ATC service and separation',
    'C': 'Class C - IFR/VFR. All receive ATC, IFR separated from all',
    'D': 'Class D - IFR/VFR. All receive ATC, IFR separated from IFR only',
    'E': 'Class E - IFR/VFR. IFR receives ATC service and separation',
    'F': 'Class F - IFR/VFR. Advisory service, not widely implemented',
    'G': 'Class G - Uncontrolled airspace, flight information only',
    'None': 'No ICAO class assigned in the OpenAIP system',
  };

  @override
  void initState() {
    super.initState();
    _sitesEnabled = widget.sitesEnabled;
    _airspaceEnabled = widget.airspaceEnabled;
    _airspaceTypes = Map<String, bool>.from(widget.airspaceTypes);
    _icaoClasses = Map<String, bool>.from(widget.icaoClasses);
    _maxAltitudeFt = widget.maxAltitudeFt;
    _selectedMapProvider = widget.mapProvider;

    // Initialize any missing types/classes with false
    for (final type in _typeDescriptions.keys) {
      _airspaceTypes[type] ??= false;
    }
    for (final icaoClass in _classDescriptions.keys) {
      _icaoClasses[icaoClass] ??= false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: MediaQuery.of(context).size.width > 320 ? 280 : MediaQuery.of(context).size.width * 0.9,
        constraints: const BoxConstraints(maxHeight: 500),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: const BoxDecoration(
                color: Color(0xFF2A2A2A),
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.tune, color: Colors.blue, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'Filter Map',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Two-column layout: Maps and Sites/Airspace
                    _buildTopTwoColumnSection(),
                    const SizedBox(height: 16),

                    // Three-column layout: Types | Classes | Altitude
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Types column
                        Expanded(
                          flex: 1,
                          child: Opacity(
                            opacity: _airspaceEnabled ? 1.0 : 0.3,
                            child: IgnorePointer(
                              ignoring: !_airspaceEnabled,
                              child: _buildTypesColumn(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),

                        // Classes column
                        Expanded(
                          flex: 1,
                          child: Opacity(
                            opacity: _airspaceEnabled ? 1.0 : 0.3,
                            child: IgnorePointer(
                              ignoring: !_airspaceEnabled,
                              child: _buildClassesColumn(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),

                        // Altitude column
                        Expanded(
                          flex: 1,
                          child: Opacity(
                            opacity: _airspaceEnabled ? 1.0 : 0.3,
                            child: IgnorePointer(
                              ignoring: !_airspaceEnabled,
                              child: _buildAltitudeColumn(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopTwoColumnSection() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left column: Map provider section
        Expanded(
          child: _buildMapProviderColumn(),
        ),
        const SizedBox(width: 16),
        // Right column: Sites and airspace toggles
        Expanded(
          child: _buildToggleColumn(),
        ),
      ],
    );
  }

  Widget _buildMapProviderColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Maps',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        ...MapProvider.values.map((provider) =>
          InkWell(
            onTap: () => setState(() {
              _selectedMapProvider = provider;
              _applyFiltersDebounced();
            }),
            borderRadius: BorderRadius.circular(4),
            child: Container(
              height: 24,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Transform.scale(
                    scale: 0.7,
                    child: Radio<MapProvider>(
                      value: provider,
                      groupValue: _selectedMapProvider,
                      onChanged: (value) => setState(() {
                        _selectedMapProvider = value!;
                        _applyFiltersDebounced();
                      }),
                      activeColor: Colors.blue,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      provider.shortName,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ).toList(),
      ],
    );
  }

  Widget _buildToggleColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Layers',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        // Sites checkbox
        InkWell(
          onTap: () => setState(() {
            _sitesEnabled = !_sitesEnabled;
            _applyFiltersDebounced();
          }),
          borderRadius: BorderRadius.circular(4),
          child: Container(
            height: 24,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.scale(
                  scale: 0.7,
                  child: Checkbox(
                    value: _sitesEnabled,
                    onChanged: (value) => setState(() {
                      _sitesEnabled = value ?? true;
                      _applyFiltersDebounced();
                    }),
                    activeColor: Colors.blue,
                    checkColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 4),
                const Text(
                  'Sites',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        // Airspace checkbox
        InkWell(
          onTap: () => setState(() {
            _airspaceEnabled = !_airspaceEnabled;
            _applyFiltersDebounced();
          }),
          borderRadius: BorderRadius.circular(4),
          child: Container(
            height: 24,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.scale(
                  scale: 0.7,
                  child: Checkbox(
                    value: _airspaceEnabled,
                    onChanged: (value) => setState(() {
                      _airspaceEnabled = value ?? true;
                      _applyFiltersDebounced();
                    }),
                    activeColor: Colors.blue,
                    checkColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 4),
                const Text(
                  'Airspace',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTypesColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Types',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const Spacer(),
            // Select All / Clear All buttons
            GestureDetector(
              onTap: () {
                setState(() {
                  final allSelected = _airspaceTypes.values.every((selected) => selected == true);
                  for (final key in _airspaceTypes.keys) {
                    _airspaceTypes[key] = !allSelected;
                  }
                  _applyFiltersDebounced();
                });
              },
              child: Text(
                _airspaceTypes.values.every((selected) => selected == true) ? 'Clear' : 'All',
                style: const TextStyle(
                  color: Colors.blue,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          height: 144,
          child: SingleChildScrollView(
            child: Column(
              children: _typeDescriptions.entries.map((entry) {
                return Tooltip(
                  message: entry.value,
                  textStyle: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _airspaceTypes[entry.key] = !(_airspaceTypes[entry.key] ?? false);
                        _applyFiltersDebounced();
                      });
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      height: 18,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Transform.scale(
                            scale: 0.6,
                            child: Checkbox(
                              value: _airspaceTypes[entry.key] ?? false,
                              onChanged: (value) {
                                setState(() {
                                  _airspaceTypes[entry.key] = value ?? false;
                                  _applyFiltersDebounced();
                                });
                              },
                              activeColor: Colors.blue,
                              checkColor: Colors.white,
                              side: const BorderSide(color: Colors.white54),
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              entry.key,
                              style: const TextStyle(color: Colors.white, fontSize: 10),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildClassesColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Classes',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        ..._classDescriptions.entries.map((entry) {
          return Tooltip(
            message: entry.value,
            textStyle: const TextStyle(color: Colors.white, fontSize: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white24),
            ),
            child: InkWell(
              onTap: () {
                setState(() {
                  _icaoClasses[entry.key] = !(_icaoClasses[entry.key] ?? false);
                  // Apply changes immediately
                  _applyFiltersDebounced();
                });
              },
              borderRadius: BorderRadius.circular(4),
              child: Container(
                height: 18,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Transform.scale(
                      scale: 0.6,
                      child: Checkbox(
                        value: _icaoClasses[entry.key] ?? false,
                        onChanged: (value) {
                          setState(() {
                            _icaoClasses[entry.key] = value ?? false;
                            // Apply changes immediately
                            _applyFiltersDebounced();
                          });
                        },
                        activeColor: Colors.blue,
                        checkColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    Text(
                      entry.key,
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildAltitudeColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Elevation',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 144,
          child: Row(
            children: [
              // Labels on the left
              Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text('30k', style: TextStyle(color: Colors.white54, fontSize: 8)),
                  Text('20k', style: TextStyle(color: Colors.white54, fontSize: 8)),
                  Text('10k', style: TextStyle(color: Colors.white54, fontSize: 8)),
                  Text('0', style: TextStyle(color: Colors.white54, fontSize: 8)),
                ],
              ),
              const SizedBox(width: 4),
              // Vertical slider
              RotatedBox(
                quarterTurns: 3,
                child: SizedBox(
                  width: 144,
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 2,
                      thumbColor: Colors.blue,
                      activeTrackColor: Colors.blue,
                      inactiveTrackColor: Colors.white24,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                      tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 1),
                      activeTickMarkColor: Colors.blue,
                      inactiveTickMarkColor: Colors.white54,
                    ),
                    child: Slider(
                      value: _maxAltitudeFt,
                      min: 0,
                      max: 30000,
                      divisions: 3, // For tick marks at 10k intervals
                      onChanged: (value) {
                        setState(() {
                          _maxAltitudeFt = value;
                          _applyFiltersDebounced();
                        });
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // Current value display
              Text(
                '${(_maxAltitudeFt / 1000).toStringAsFixed(0)} k',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _applyFiltersDebounced() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _applyFiltersImmediately();
    });
  }

  void _applyFiltersImmediately() {
    final selectedTypes = _airspaceTypes.entries
        .where((entry) => entry.value)
        .length;
    final selectedClasses = _icaoClasses.entries
        .where((entry) => entry.value)
        .length;

    LoggingService.structured('MAP_FILTER_APPLIED', {
      'sites_enabled': _sitesEnabled,
      'airspace_enabled': _airspaceEnabled,
      'selected_types': selectedTypes,
      'selected_classes': selectedClasses,
      'total_types': _airspaceTypes.length,
      'total_classes': _icaoClasses.length,
      'max_altitude_ft': _maxAltitudeFt,
      'map_provider': _selectedMapProvider.displayName,
    });

    widget.onApply(_sitesEnabled, _airspaceEnabled, _airspaceTypes, _icaoClasses, _maxAltitudeFt, _selectedMapProvider);
  }
}


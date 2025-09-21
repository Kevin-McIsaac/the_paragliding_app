import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/logging_service.dart';
import '../../utils/map_provider.dart';
import '../../data/models/airspace_enums.dart';
import 'package:multi_dropdown/multi_dropdown.dart';

/// Filter dialog for controlling map layer visibility
/// Supports sites toggle, airspace type filtering, ICAO class filtering, altitude filtering, and clipping
class MapFilterDialog extends StatefulWidget {
  final bool sitesEnabled;
  final bool airspaceEnabled;
  final Map<String, bool> airspaceTypes;
  final Map<String, bool> icaoClasses;
  final double maxAltitudeFt;
  final bool clippingEnabled;
  final MapProvider mapProvider;
  final Function(bool sitesEnabled, bool airspaceEnabled, Map<String, bool> types, Map<String, bool> classes, double maxAltitudeFt, bool clippingEnabled, MapProvider mapProvider) onApply;

  const MapFilterDialog({
    super.key,
    required this.sitesEnabled,
    required this.airspaceEnabled,
    required this.airspaceTypes,
    required this.icaoClasses,
    required this.maxAltitudeFt,
    required this.clippingEnabled,
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
  late bool _clippingEnabled;
  late MapProvider _selectedMapProvider;

  Timer? _debounceTimer;

  // Controllers for multi_dropdown
  late final MultiSelectController<String> _typesController;
  late final MultiSelectController<String> _classesController;

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
    _clippingEnabled = widget.clippingEnabled;
    _selectedMapProvider = widget.mapProvider;

    // Initialize any missing types/classes with false
    for (final type in _typeDescriptions.keys) {
      _airspaceTypes[type] ??= false;
    }
    for (final icaoClass in _classDescriptions.keys) {
      _icaoClasses[icaoClass] ??= false;
    }

    // Initialize controllers with selected items
    _typesController = MultiSelectController<String>();
    _classesController = MultiSelectController<String>();

    // Set initial selected items (those that are hidden)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final hiddenTypes = _airspaceTypes.entries
          .where((e) => e.value)
          .map((e) => e.key)
          .toList();
      final hiddenClasses = _icaoClasses.entries
          .where((e) => e.value)
          .map((e) => e.key)
          .toList();

      // Set initial selected items using the controller methods
      for (final key in hiddenTypes) {
        final index = _typeDescriptions.keys.toList().indexOf(key);
        if (index >= 0) {
          _typesController.selectAtIndex(index);
        }
      }
      for (final key in hiddenClasses) {
        final index = _classDescriptions.keys.toList().indexOf(key);
        if (index >= 0) {
          _classesController.selectAtIndex(index);
        }
      }
    });
  }


  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: MediaQuery.of(context).size.width > 350 ? 320 : MediaQuery.of(context).size.width * 0.9,
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

                    // Divider line (no title)
                    Opacity(
                      opacity: _airspaceEnabled ? 1.0 : 0.3,
                      child: Container(
                        height: 1,
                        color: Colors.grey.withValues(alpha: 0.3),
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Two-column layout: (Types + Classes) | Altitude
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left column: Types and Classes stacked
                        Expanded(
                          flex: 7,  // Much wider column (78% width)
                          child: Opacity(
                            opacity: _airspaceEnabled ? 1.0 : 0.3,
                            child: IgnorePointer(
                              ignoring: !_airspaceEnabled,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Airspace Types
                                  _buildTypesColumn(),
                                  const SizedBox(height: 12),
                                  // ICAO Classes
                                  _buildClassesColumn(),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Right column: Altitude
                        Expanded(
                          flex: 2,  // Narrower column (33% width)
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
        RadioGroup<MapProvider>(
          groupValue: _selectedMapProvider,
          onChanged: (value) => setState(() {
            _selectedMapProvider = value!;
            _applyFiltersDebounced();
          }),
          child: Column(
            children: MapProvider.values.map((provider) =>
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
                          activeColor: Colors.blue,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Tooltip(
                          message: provider.tooltip,
                          textStyle: const TextStyle(color: Colors.white, fontSize: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1E1E),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Text(
                            provider.shortName,
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ).toList(),
          ),
        ),
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
        Tooltip(
          message: 'Show all the Paragliding Earth flying sites for this area',
          textStyle: const TextStyle(color: Colors.white, fontSize: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white24),
          ),
          child: InkWell(
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
        ),
        // Airspace checkbox
        Tooltip(
          message: 'Overlay the OpenAIP airspaces for this area',
          textStyle: const TextStyle(color: Colors.white, fontSize: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white24),
          ),
          child: InkWell(
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
        ),
        // Clipping toggle (only shown when airspace is enabled)
        if (_airspaceEnabled)
          Tooltip(
            message: 'Only show the bottom layer at each point',
            textStyle: const TextStyle(color: Colors.white, fontSize: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white24),
            ),
            child: InkWell(
              onTap: () {
                setState(() {
                  _clippingEnabled = !_clippingEnabled;
                  _applyFiltersDebounced();
                });
              },
              borderRadius: BorderRadius.circular(4),
              child: Container(
                height: 24,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Transform.scale(
                      scale: 0.7,
                      child: Checkbox(
                        value: _clippingEnabled,
                        onChanged: (value) {
                          setState(() {
                            _clippingEnabled = value ?? true;
                            _applyFiltersDebounced();
                          });
                        },
                        activeColor: Colors.blue,
                        checkColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'Clip',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTypesColumn() {
    // Create dropdown items from airspace types - show only abbreviations
    final typeItems = _typeDescriptions.entries.map((entry) {
      final abbrev = entry.key;
      return DropdownItem<String>(
        label: abbrev,  // Only show abbreviation
        value: abbrev,
      );
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Tooltip(
          message: 'Exclude these Airspace Types from the airspace overlay',
          child: const Text(
            'Exclude Airspace Types',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 4),
        MultiDropdown<String>(
          controller: _typesController,
          items: typeItems,
          enabled: true,
          searchEnabled: true,
          itemBuilder: (item, index, onTap) {
            return InkWell(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 10,
                          color: item.selected ? Colors.white : Colors.white70,
                          fontWeight: item.selected ? FontWeight.w500 : FontWeight.normal,
                        ),
                      ),
                    ),
                    if (item.selected)
                      Icon(
                        Icons.check,
                        size: 12,
                        color: Colors.blue,
                      ),
                  ],
                ),
              ),
            );
          },
          chipDecoration: ChipDecoration(
            backgroundColor: Colors.blue.withValues(alpha: 0.2),
            labelStyle: const TextStyle(color: Colors.white, fontSize: 9),
            deleteIcon: const Icon(Icons.close, size: 10, color: Colors.white70),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.withValues(alpha: 0.5)),
            wrap: true,
            spacing: 2,
            runSpacing: 2,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          ),
          fieldDecoration: FieldDecoration(
            hintText: 'Select types to hide',
            hintStyle: const TextStyle(color: Colors.white54, fontSize: 10),
            backgroundColor: Colors.black.withValues(alpha: 0.3),
            border: OutlineInputBorder(
              borderSide: const BorderSide(color: Colors.white54),
              borderRadius: BorderRadius.circular(6),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: Colors.blue),
              borderRadius: BorderRadius.circular(6),
            ),
            suffixIcon: const Icon(Icons.arrow_drop_down, color: Colors.white70, size: 16),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            showClearIcon: false,
          ),
          dropdownDecoration: DropdownDecoration(
            backgroundColor: const Color(0xFF2C2C2C),
            marginTop: 1,
            maxHeight: 280,
            borderRadius: BorderRadius.circular(6),
            elevation: 4,
          ),
          dropdownItemDecoration: DropdownItemDecoration(
            selectedBackgroundColor: Colors.blue.withValues(alpha: 0.3),
            selectedTextColor: Colors.white,
            textColor: Colors.white70,
          ),
          searchDecoration: SearchFieldDecoration(
            hintText: 'Search...',
            searchIcon: const Icon(Icons.search, color: Colors.white54, size: 14),
            border: OutlineInputBorder(
              borderSide: const BorderSide(color: Colors.white24),
              borderRadius: BorderRadius.circular(4),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: Colors.blue),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          onSelectionChange: (selectedItems) {
            // Convert to Map<String, bool> (true = hidden)
            final newTypes = Map<String, bool>.from(_airspaceTypes);
            // First, set all to false (visible)
            for (final key in newTypes.keys) {
              newTypes[key] = false;
            }
            // Then set selected items to true (hidden)
            for (final item in selectedItems) {
              newTypes[item] = true;
            }
            setState(() {
              _airspaceTypes = newTypes;
              _applyFiltersDebounced();
            });
          },
        ),
      ],
    );
  }

  Widget _buildClassesColumn() {
    // Create dropdown items from ICAO classes
    final classItems = _classDescriptions.entries.map((entry) {
      final className = entry.key;
      return DropdownItem<String>(
        label: className,
        value: className,
      );
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Tooltip(
          message: 'Exclude these Airspace Classes from the airspace overlay',
          child: const Text(
            'Exclude ICAO Classes',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 4),
        MultiDropdown<String>(
          controller: _classesController,
          items: classItems,
          enabled: true,
          searchEnabled: false, // Less items, no need for search
          itemBuilder: (item, index, onTap) {
            return InkWell(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 10,
                          color: item.selected ? Colors.white : Colors.white70,
                          fontWeight: item.selected ? FontWeight.w500 : FontWeight.normal,
                        ),
                      ),
                    ),
                    if (item.selected)
                      Icon(
                        Icons.check,
                        size: 12,
                        color: Colors.orange,
                      ),
                  ],
                ),
              ),
            );
          },
          chipDecoration: ChipDecoration(
            backgroundColor: Colors.orange.withValues(alpha: 0.2),
            labelStyle: const TextStyle(color: Colors.white, fontSize: 9),
            deleteIcon: const Icon(Icons.close, size: 10, color: Colors.white70),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
            wrap: true,
            spacing: 2,
            runSpacing: 2,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          ),
          fieldDecoration: FieldDecoration(
            hintText: 'Select classes to hide',
            hintStyle: const TextStyle(color: Colors.white54, fontSize: 10),
            backgroundColor: Colors.black.withValues(alpha: 0.3),
            border: OutlineInputBorder(
              borderSide: const BorderSide(color: Colors.white54),
              borderRadius: BorderRadius.circular(6),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: Colors.blue),
              borderRadius: BorderRadius.circular(6),
            ),
            suffixIcon: const Icon(Icons.arrow_drop_down, color: Colors.white70, size: 16),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            showClearIcon: false,
          ),
          dropdownDecoration: DropdownDecoration(
            backgroundColor: const Color(0xFF2C2C2C),
            marginTop: 1,
            maxHeight: 240,
            borderRadius: BorderRadius.circular(6),
            elevation: 4,
          ),
          dropdownItemDecoration: DropdownItemDecoration(
            selectedBackgroundColor: Colors.orange.withValues(alpha: 0.3),
            selectedTextColor: Colors.white,
            textColor: Colors.white70,
          ),
          onSelectionChange: (selectedItems) {
            // Convert to Map<String, bool> (true = hidden)
            final newClasses = Map<String, bool>.from(_icaoClasses);
            // First, set all to false (visible)
            for (final key in newClasses.keys) {
              newClasses[key] = false;
            }
            // Then set selected items to true (hidden)
            for (final item in selectedItems) {
              newClasses[item] = true;
            }
            setState(() {
              _icaoClasses = newClasses;
              _applyFiltersDebounced();
            });
          },
        ),
      ],
    );
  }

  Widget _buildAltitudeColumn() {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        Tooltip(
          message: 'Exclude airspace with lower altitude above this elevation (in feet)',
          child: const Text(
            'Elevation',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 4),
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
              Expanded(
                child: Padding(
                  padding: EdgeInsets.zero, // Remove padding to align slider with labels
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          RotatedBox(
                            quarterTurns: 3,
                            child: SliderTheme(
                              data: SliderThemeData(
                                trackHeight: 2,
                                thumbColor: Colors.blue,
                                activeTrackColor: Colors.blue,
                                inactiveTrackColor: Colors.white24,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 0),
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 0),
                                tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 1),
                                activeTickMarkColor: Colors.blue,
                                inactiveTickMarkColor: Colors.white54,
                              ),
                              child: SizedBox(
                                width: constraints.maxHeight, // Use the actual available height
                                child: Slider(
                                  value: _maxAltitudeFt,
                                  min: 0,
                                  max: 30000,
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
                        ],
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // Current value display
              SizedBox(
                width: 25,
                child: Text(
                  '${(_maxAltitudeFt / 1000).toStringAsFixed(0)} k',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ],
      ),
    );
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _typesController.dispose();
    _classesController.dispose();
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
      'clipping_enabled': _clippingEnabled,
      'map_provider': _selectedMapProvider.displayName,
    });

    widget.onApply(_sitesEnabled, _airspaceEnabled, _airspaceTypes, _icaoClasses, _maxAltitudeFt, _clippingEnabled, _selectedMapProvider);
  }
}


import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/logging_service.dart';
import '../../data/models/airspace_enums.dart';
import '../../data/models/weather_station_source.dart';
import '../../services/weather_providers/weather_station_provider_registry.dart';
import 'package:multi_dropdown/multi_dropdown.dart';

/// Filter dialog for controlling map layer visibility
/// Supports sites toggle, airspace type filtering, ICAO class filtering, altitude filtering, clipping, and weather stations
class MapFilterDialog extends StatefulWidget {
  final bool sitesEnabled;
  final bool airspaceEnabled;
  final bool forecastEnabled;
  final bool weatherStationsEnabled;
  final bool metarEnabled;
  final bool nwsEnabled;
  final bool pioupiouEnabled;
  final Map<String, bool> airspaceTypes;
  final Map<String, bool> icaoClasses;
  final double maxAltitudeFt;
  final bool clippingEnabled;
  final Function(
    bool sitesEnabled,
    bool airspaceEnabled,
    bool forecastEnabled,
    bool weatherStationsEnabled,
    bool metarEnabled,
    bool nwsEnabled,
    bool pioupiouEnabled,
    Map<String, bool> types,
    Map<String, bool> classes,
    double maxAltitudeFt,
    bool clippingEnabled,
  ) onApply;

  const MapFilterDialog({
    super.key,
    required this.sitesEnabled,
    required this.airspaceEnabled,
    required this.forecastEnabled,
    required this.weatherStationsEnabled,
    required this.metarEnabled,
    required this.nwsEnabled,
    required this.pioupiouEnabled,
    required this.airspaceTypes,
    required this.icaoClasses,
    required this.maxAltitudeFt,
    required this.clippingEnabled,
    required this.onApply,
  });

  @override
  State<MapFilterDialog> createState() => _MapFilterDialogState();
}

class _MapFilterDialogState extends State<MapFilterDialog> {
  late bool _sitesEnabled;
  late bool _airspaceEnabled;
  late bool _forecastEnabled;
  late bool _weatherStationsEnabled;
  late bool _metarEnabled;
  late bool _nwsEnabled;
  late bool _pioupiouEnabled;
  late Map<String, bool> _airspaceTypes;
  late Map<String, bool> _icaoClasses;
  late double _maxAltitudeFt;
  late bool _clippingEnabled;

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
    _forecastEnabled = widget.forecastEnabled;
    _weatherStationsEnabled = widget.weatherStationsEnabled;
    _metarEnabled = widget.metarEnabled;
    _nwsEnabled = widget.nwsEnabled;
    _pioupiouEnabled = widget.pioupiouEnabled;
    _airspaceTypes = Map<String, bool>.from(widget.airspaceTypes);
    _icaoClasses = Map<String, bool>.from(widget.icaoClasses);
    _maxAltitudeFt = widget.maxAltitudeFt;
    _clippingEnabled = widget.clippingEnabled;

    // Initialize any missing types/classes with false
    for (final type in _typeDescriptions.keys) {
      _airspaceTypes[type] ??= false;
    }
    for (final icaoClass in _classDescriptions.keys) {
      _icaoClasses[icaoClass] ??= false;
    }

    // Initialize controllers
    _typesController = MultiSelectController<String>();
    _classesController = MultiSelectController<String>();

    // Update controller selections after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateControllerSelections();
    });
  }

  @override
  void didUpdateWidget(MapFilterDialog oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Update local maps if widget props changed
    if (oldWidget.airspaceTypes != widget.airspaceTypes) {
      _airspaceTypes = Map<String, bool>.from(widget.airspaceTypes);
      for (final type in _typeDescriptions.keys) {
        _airspaceTypes[type] ??= false;
      }
    }

    if (oldWidget.icaoClasses != widget.icaoClasses) {
      _icaoClasses = Map<String, bool>.from(widget.icaoClasses);
      for (final icaoClass in _classDescriptions.keys) {
        _icaoClasses[icaoClass] ??= false;
      }
    }

    // Update controller selections if filter data changed
    if (oldWidget.airspaceTypes != widget.airspaceTypes ||
        oldWidget.icaoClasses != widget.icaoClasses) {
      _updateControllerSelections();
    }
  }

  /// Update dropdown controller selections based on current filter state
  void _updateControllerSelections() {
    final hiddenTypes = _airspaceTypes.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toList();
    final hiddenClasses = _icaoClasses.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toList();

    // Clear and reset type selections
    _typesController.clearAll();
    for (final key in hiddenTypes) {
      final index = _typeDescriptions.keys.toList().indexOf(key);
      if (index >= 0) {
        _typesController.selectAtIndex(index);
      }
    }

    // Clear and reset class selections
    _classesController.clearAll();
    for (final key in hiddenClasses) {
      final index = _classDescriptions.keys.toList().indexOf(key);
      if (index >= 0) {
        _classesController.selectAtIndex(index);
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: MediaQuery.of(context).size.width > 350 ? 320 : MediaQuery.of(context).size.width * 0.9,
        constraints: const BoxConstraints(maxHeight: 600),
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
                    // Horizontal Layers section
                    _buildLayersSection(),

                    // Two-column layout: (Types + Classes) | Altitude
                    // Always shown, indented, disabled when airspace is disabled
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.only(left: 24),
                      child: IgnorePointer(
                        ignoring: !_airspaceEnabled,
                        child: Opacity(
                          opacity: _airspaceEnabled ? 1.0 : 0.4,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                            ),
                            padding: const EdgeInsets.all(8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Left column: Types and Classes stacked
                                Expanded(
                                  flex: 7,  // Much wider column (78% width)
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
                                const SizedBox(width: 12),

                                // Right column: Altitude
                                Expanded(
                                  flex: 2,  // Narrower column (33% width)
                                  child: _buildAltitudeColumn(),
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLayersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Tooltip(
          message: 'Toggle map layers to customize your view',
          textStyle: const TextStyle(color: Colors.white, fontSize: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white24),
          ),
          child: const Text(
            'Layers',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Row 1: Sites
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
              _applyFiltersImmediately();
            }),
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 24,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: Checkbox(
                      value: _sitesEnabled,
                      onChanged: (value) => setState(() {
                        _sitesEnabled = value ?? true;
                        _applyFiltersImmediately();
                      }),
                      activeColor: Colors.blue,
                      checkColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
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
        // Forecast checkbox (indented, disabled when sites are disabled)
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 24),
          child: _buildProviderCheckbox(
            value: _forecastEnabled,
            label: 'Forecast',
            subtitle: 'Wind forecast and flyability for sites',
            onChanged: _sitesEnabled ? (value) => setState(() {
              _forecastEnabled = value ?? true;
              _applyFiltersImmediately();
            }) : null,
          ),
        ),
        const SizedBox(height: 8),
        // Row 2: Weather
        Row(
          children: [
            Tooltip(
              message: 'Show actual weather stations with real-time wind data',
              textStyle: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white24),
              ),
              child: InkWell(
                onTap: () => setState(() {
                  _weatherStationsEnabled = !_weatherStationsEnabled;
                  _applyFiltersImmediately();
                }),
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  height: 24,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: Checkbox(
                          value: _weatherStationsEnabled,
                          onChanged: (value) => setState(() {
                            _weatherStationsEnabled = value ?? true;
                            _applyFiltersImmediately();
                          }),
                          activeColor: Colors.blue,
                          checkColor: Colors.white,
                          side: const BorderSide(color: Colors.white54),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'Weather Stations',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        // Weather provider checkboxes (indented, disabled when stations disabled)
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // METAR provider
              _buildProviderCheckbox(
                value: _metarEnabled,
                label: 'METAR (Aviation)',
                subtitle: WeatherStationProviderRegistry.getProvider(WeatherStationSource.metar).description,
                onChanged: _weatherStationsEnabled ? (value) => setState(() {
                  _metarEnabled = value ?? true;
                  _applyFiltersImmediately();
                }) : null,
              ),
              const SizedBox(height: 2),
              // NWS provider (US only)
              _buildProviderCheckbox(
                value: _nwsEnabled,
                label: 'NWS (US only)',
                subtitle: WeatherStationProviderRegistry.getProvider(WeatherStationSource.nws).description,
                onChanged: _weatherStationsEnabled ? (value) => setState(() {
                  _nwsEnabled = value ?? true;
                  _applyFiltersImmediately();
                }) : null,
              ),
              const SizedBox(height: 2),
              // Pioupiou provider (global)
              _buildProviderCheckbox(
                value: _pioupiouEnabled,
                label: 'Pioupiou (OpenWindMap)',
                subtitle: WeatherStationProviderRegistry.getProvider(WeatherStationSource.pioupiou).description,
                onChanged: _weatherStationsEnabled ? (value) => setState(() {
                  _pioupiouEnabled = value ?? true;
                  _applyFiltersImmediately();
                }) : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Row 3: Airspace
        Tooltip(
          message: 'Overlay the OpenAIP airspaces for this area',
          textStyle: const TextStyle(color: Colors.white, fontSize: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white24),
          ),
          child: InkWell(
            onTap: () {
              final wasDisabled = !_airspaceEnabled;
              setState(() {
                _airspaceEnabled = !_airspaceEnabled;
                _applyFiltersImmediately();
              });
              // Update controllers after enabling airspace so dropdowns reflect saved values
              if (wasDisabled && _airspaceEnabled) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _updateControllerSelections();
                });
              }
            },
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 24,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: Checkbox(
                      value: _airspaceEnabled,
                      onChanged: (value) {
                        final wasDisabled = !_airspaceEnabled;
                        setState(() {
                          _airspaceEnabled = value ?? true;
                          _applyFiltersImmediately();
                        });
                        // Update controllers after enabling airspace so dropdowns reflect saved values
                        if (wasDisabled && _airspaceEnabled) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _updateControllerSelections();
                          });
                        }
                      },
                      activeColor: Colors.blue,
                      checkColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
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
        // Clip checkbox (indented, disabled when airspace is disabled)
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 24),
          child: _buildProviderCheckbox(
            value: _clippingEnabled,
            label: 'Clip',
            subtitle: 'Only show the bottom layer at each point',
            onChanged: _airspaceEnabled ? (value) => setState(() {
              _clippingEnabled = value ?? true;
              _applyFiltersImmediately();
            }) : null,
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
      padding: const EdgeInsets.only(left: 4), // Reduced from 8 to 4
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
              const SizedBox(width: 2), // Reduced from 4 to 2
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
              const SizedBox(width: 2), // Reduced from 4 to 2
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
      'forecast_enabled': _forecastEnabled,
      'weather_stations_enabled': _weatherStationsEnabled,
      'selected_types': selectedTypes,
      'selected_classes': selectedClasses,
      'total_types': _airspaceTypes.length,
      'total_classes': _icaoClasses.length,
      'max_altitude_ft': _maxAltitudeFt,
      'clipping_enabled': _clippingEnabled,
    });

    widget.onApply(_sitesEnabled, _airspaceEnabled, _forecastEnabled, _weatherStationsEnabled, _metarEnabled, _nwsEnabled, _pioupiouEnabled, _airspaceTypes, _icaoClasses, _maxAltitudeFt, _clippingEnabled);
  }

  /// Build a provider checkbox widget
  Widget _buildProviderCheckbox({
    required bool value,
    required String label,
    required String subtitle,
    required ValueChanged<bool?>? onChanged,
  }) {
    return InkWell(
      onTap: onChanged != null ? () => onChanged(!value) : null,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: Checkbox(
                value: value,
                onChanged: onChanged,
                activeColor: Colors.blue,
                checkColor: Colors.white,
                side: const BorderSide(color: Colors.white54),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.white54, fontSize: 9),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

}


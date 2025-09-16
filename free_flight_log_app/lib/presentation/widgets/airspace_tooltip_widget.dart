import 'package:flutter/material.dart';
import '../../services/airspace_geojson_service.dart';
import '../../data/models/airspace_enums.dart';

/// Widget that displays airspace information in a floating tooltip
/// Positioned near the cursor/touch location on the map
class AirspaceTooltipWidget extends StatelessWidget {
  final List<AirspaceData> airspaces;
  final Offset position;
  final Size screenSize;
  final VoidCallback? onClose;

  const AirspaceTooltipWidget({
    super.key,
    required this.airspaces,
    required this.position,
    required this.screenSize,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    if (airspaces.isEmpty) return const SizedBox.shrink();

    // Calculate tooltip dimensions
    const double tooltipWidth = 220.0;
    // Dynamic height based on content, with reasonable limits
    final double maxTooltipHeight = (screenSize.height * 0.8).clamp(400.0, 600.0);
    const double padding = 8.0;

    // Determine optimal position to avoid screen edges
    final tooltipPosition = _calculateOptimalPosition(
      position,
      tooltipWidth,
      maxTooltipHeight,
      screenSize,
      padding,
    );

    return Positioned(
      left: tooltipPosition.dx,
      top: tooltipPosition.dy,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(8),
        color: Colors.transparent,
        child: Container(
          width: tooltipWidth,
          constraints: BoxConstraints(maxHeight: maxTooltipHeight),
          decoration: BoxDecoration(
            color: const Color(0xE6000000), // Semi-transparent black
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.2),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(8),
                    topRight: Radius.circular(8),
                  ),
                  border: Border(
                    bottom: BorderSide(
                      color: Colors.white.withValues(alpha: 0.2),
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.airplanemode_active,
                      color: Colors.white70,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      airspaces.length == 1
                          ? 'Airspace'
                          : '${airspaces.length} Airspaces',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    // Close button for mobile users
                    if (onClose != null)
                      GestureDetector(
                        onTap: onClose,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          margin: const EdgeInsets.only(left: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // Airspace list (no scrolling - all items visible)
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(left: 8, right: 12, top: 8, bottom: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (int index = 0; index < airspaces.length; index++) ...[
                        _buildAirspaceItem(airspaces[index]),
                        if (index < airspaces.length - 1) Container(
                          height: 1,
                          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // Footer with source attribution
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  'Source: OpenAIP',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 9,
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build individual airspace information item (compact 2-line format)
  Widget _buildAirspaceItem(AirspaceData airspace) {
    // Get ICAO class-based styling (prioritizes ICAO class over type)
    final style = AirspaceGeoJsonService.instance.getStyleForAirspace(airspace);

    // Format compact details line (type, altitude, country)
    final String compactDetails = _formatCompactDetails(airspace);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Line 1: Airspace name with visibility indicator
          Row(
            children: [
              // Visibility status indicator (moved from right to left)
              Tooltip(
                preferBelow: false,
                message: airspace.isCurrentlyFiltered
                  ? 'This airspace is currently hidden on map'
                  : 'This airspace is visible on map',
                decoration: BoxDecoration(
                  color: const Color(0xE6000000),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                ),
                textStyle: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    airspace.isCurrentlyFiltered
                      ? Icons.visibility_off
                      : Icons.visibility,
                    size: 12,
                    color: airspace.isCurrentlyFiltered
                      ? Colors.orange.withValues(alpha: 0.8)
                      : Colors.green.withValues(alpha: 0.8),
                  ),
                ),
              ),
              const SizedBox(width: 6),

              // Airspace name
              Expanded(
                child: Text(
                  airspace.name,
                  style: TextStyle(
                    color: airspace.isCurrentlyFiltered ? Colors.grey : Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          // Line 2: Type, ICAO class, altitude, country with tooltips
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 1),
            child: Row(
              children: [
                // Airspace type with mapping and tooltip
                Tooltip(
                  preferBelow: false,
                  margin: const EdgeInsets.symmetric(horizontal: 30),
                  decoration: BoxDecoration(
                    color: const Color(0xE6000000),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  textStyle: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                  message: airspace.type.tooltip,
                  child: Text(
                    '${_getDisplayTypeAbbreviation(airspace.type)},',
                    style: TextStyle(
                      color: airspace.isCurrentlyFiltered
                        ? Colors.grey.withValues(alpha: 0.8)
                        : Colors.white.withValues(alpha: 0.85),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

                // ICAO class with mapping and tooltip (always show if available)
                if (airspace.icaoClass != null) ...[
                  const SizedBox(width: 6),
                  Tooltip(
                    preferBelow: false,
                    margin: const EdgeInsets.symmetric(horizontal: 30),
                    verticalOffset: -8,
                    waitDuration: const Duration(milliseconds: 500),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white24),
                    ),
                    richMessage: TextSpan(
                      children: [
                        WidgetSpan(
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 250),
                            child: Text(
                              airspace.icaoClass!.tooltip,
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                            ),
                          ),
                        ),
                      ],
                    ),
                    child: Text(
                      '${_getDisplayIcaoClassAbbreviation(airspace.icaoClass!)},',
                      style: TextStyle(
                        color: airspace.isCurrentlyFiltered
                          ? Colors.grey.withValues(alpha: 0.8)
                          : style.borderColor, // Use ICAO class color for highlighting when visible
                        fontSize: 10,
                        fontWeight: FontWeight.bold, // Make it bold to emphasize
                      ),
                    ),
                  ),
                ],

                const SizedBox(width: 6),

                // Altitude range and country
                Expanded(
                  child: Text(
                    '${_formatAltitudeRangeWithUnits(airspace)} ${_getCountryName(airspace.country)}',
                    style: TextStyle(
                      color: airspace.isCurrentlyFiltered
                        ? Colors.grey.withValues(alpha: 0.8)
                        : Colors.white.withValues(alpha: 0.85),
                      fontSize: 10,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Format altitude range for display
  String _formatAltitudeRange(AirspaceData airspace) {
    final lower = airspace.lowerAltitude;
    final upper = airspace.upperAltitude;

    if (lower == 'Unknown' && upper == 'Unknown') {
      return '';
    }

    if (lower == upper) {
      return 'Altitude: $lower';
    }

    return '$lower - $upper';
  }

  /// Format altitude range with proper aviation units for compact display
  String _formatAltitudeRangeWithUnits(AirspaceData airspace) {
    final lower = _formatAltitudeWithUnits(airspace.lowerLimit);
    final upper = _formatAltitudeWithUnits(airspace.upperLimit);

    if (lower.isEmpty && upper.isEmpty) {
      return '';
    }

    if (lower == upper) {
      return lower;
    }

    return '$lower-$upper';
  }

  /// Format individual altitude with proper aviation units
  String _formatAltitudeWithUnits(Map<String, dynamic>? limit) {
    if (limit == null) return '';

    final value = limit['value'];
    final unit = limit['unit'] ?? '';
    final reference = limit['reference'] ?? '';

    if (value == null) return '';

    // Handle special values
    if (value is String) {
      final lowerValue = value.toLowerCase();
      if (lowerValue == 'gnd' || lowerValue == 'sfc') {
        return 'GND';
      }
      if (lowerValue == 'unlimited' || lowerValue == 'unl') {
        return 'UNL';
      }
    }

    // Format numeric values with aviation units
    final valueStr = value is num ? value.round().toString() : value.toString();

    // Handle flight levels
    final unitLower = unit.toString().toLowerCase();
    if (unitLower == 'fl' || unitLower.contains('flight')) {
      return 'FL$valueStr';
    }

    // Handle standard altitude units
    String unitStr = '';
    String refStr = '';

    if (unitLower.contains('ft') || unitLower.contains('feet')) {
      unitStr = ' ft';
    } else if (unitLower.contains('m') && !unitLower.contains('ft')) {
      unitStr = ' m';
    }

    // Handle reference (AGL, AMSL, etc.)
    if (reference.isNotEmpty) {
      final refLower = reference.toString().toLowerCase();
      if (refLower.contains('agl') || refLower.contains('above ground')) {
        refStr = ' AGL';
      } else if (refLower.contains('amsl') || refLower.contains('above mean sea')) {
        refStr = ' AMSL';
      } else if (refLower.contains('msl') || refLower.contains('mean sea')) {
        refStr = ' MSL';
      }
    }

    return '$valueStr$unitStr$refStr';
  }

  /// Format compact details line (type, icaoClass, altitude, country)
  String _formatCompactDetails(AirspaceData airspace) {
    final parts = <String>[];

    // Add type abbreviation
    parts.add(airspace.type.abbreviation);

    // Add ICAO class abbreviation if available
    if (airspace.icaoClass != null && airspace.icaoClass != IcaoClass.none) {
      parts.add(airspace.icaoClass!.abbreviation);
    }

    // Add altitude range with units
    final altitudeRange = _formatAltitudeRangeWithUnits(airspace);
    if (altitudeRange.isNotEmpty) {
      parts.add(altitudeRange);
    }

    // Add country name
    final countryName = _getCountryName(airspace.country);
    if (countryName.isNotEmpty) {
      parts.add(countryName);
    }

    return parts.join(' ');
  }



  /// Get ICAO class full description from numeric code
  String _getIcaoClassDescription(int? icaoClassCode) {
    if (icaoClassCode == null) return 'No ICAO class information';

    final icaoClassDescriptionMap = {
      0: 'Class A - Controlled Airspace',
      1: 'Class B - Controlled Airspace',
      2: 'Class C - Controlled Airspace',
      3: 'Class D - Controlled Airspace',
      4: 'Class E - Controlled Airspace',
      5: 'Class F - Advisory Airspace',
      6: 'Class G - Uncontrolled Airspace',
      8: 'No ICAO class assigned',
    };

    return icaoClassDescriptionMap[icaoClassCode] ?? 'Unknown ICAO class';
  }

  /// Get country name from country code
  String _getCountryName(String? countryCode) {
    if (countryCode == null || countryCode.isEmpty) return '';

    final countryNames = {
      'AU': 'Australia',
      'US': 'USA',
      'CA': 'Canada',
      'GB': 'UK',
      'NZ': 'New Zealand',
      'FR': 'France',
      'DE': 'Germany',
      'IT': 'Italy',
      'ES': 'Spain',
      'CH': 'Switzerland',
      'AT': 'Austria',
      'NL': 'Netherlands',
      'BE': 'Belgium',
      'NO': 'Norway',
      'SE': 'Sweden',
      'DK': 'Denmark',
      'FI': 'Finland',
      'PL': 'Poland',
      'CZ': 'Czech Republic',
      'HU': 'Hungary',
      'SK': 'Slovakia',
      'SI': 'Slovenia',
      'HR': 'Croatia',
      'BA': 'Bosnia',
      'RS': 'Serbia',
      'ME': 'Montenegro',
      'MK': 'Macedonia',
      'BG': 'Bulgaria',
      'RO': 'Romania',
      'GR': 'Greece',
      'TR': 'Turkey',
      'JP': 'Japan',
      'KR': 'South Korea',
      'CN': 'China',
      'IN': 'India',
      'BR': 'Brazil',
      'AR': 'Argentina',
      'CL': 'Chile',
      'MX': 'Mexico',
      'ZA': 'South Africa',
      'EG': 'Egypt',
      'IL': 'Israel',
      'AE': 'UAE',
      'SA': 'Saudi Arabia',
    };

    return countryNames[countryCode.toUpperCase()] ?? countryCode;
  }

  /// Calculate optimal position for tooltip in top right corner
  Offset _calculateOptimalPosition(
    Offset cursorPosition,
    double tooltipWidth,
    double tooltipHeight,
    Size screenSize,
    double padding,
  ) {
    // Always position tooltip in top right corner
    const double topOffset = 80.0; // Below app bar and controls

    double x = screenSize.width - tooltipWidth - padding;
    double y = topOffset;

    // Ensure tooltip doesn't go off screen edges (safety checks)
    if (x < padding) {
      x = padding;
    }
    if (y + tooltipHeight > screenSize.height - padding) {
      y = screenSize.height - tooltipHeight - padding;
      if (y < padding) y = padding; // Fallback if screen is too small
    }

    return Offset(x, y);
  }

  /// Get type string from numeric code based on OpenAIP documentation
  String _getTypeMappedString(int typeCode) {
    final typeMap = {
      0: 'Unknown',
      1: 'Restricted',
      2: 'Danger',
      4: 'CTR',
      6: 'TMA',
      7: 'TMA',
      10: 'FIR',
      26: 'CTA',
    };

    return typeMap[typeCode] ?? typeCode.toString();
  }

  /// Get ICAO class string from numeric code based on OpenAIP documentation
  String _getIcaoClassMappedString(int? icaoClassCode) {
    if (icaoClassCode == null) return '';

    final icaoClassMap = {
      0: 'Class A',
      1: 'Class B',
      2: 'Class C',
      3: 'Class D',
      4: 'Class E',
      5: 'Class F',
      6: 'Class G',
      8: 'None',
    };

    return icaoClassMap[icaoClassCode] ?? icaoClassCode.toString();
  }

  /// Get tooltip description for airspace type
  String _getTypeTooltip(int typeCode) {
    final typeTooltipMap = {
      0: 'Unknown airspace type',
      1: 'RESTRICTED - Restricted Area (entry restricted)',
      2: 'DANGER - Danger Area (hazardous activities)',
      4: 'CTR - Control Zone/Controlled Tower Region (airport control zone)',
      6: 'TMA - Terminal Maneuvering Area (terminal control area)',
      7: 'TMA - Terminal Maneuvering Area (terminal control area)',
      10: 'FIR - Flight Information Region',
      26: 'CTA - Control Area',
    };

    return typeTooltipMap[typeCode] ?? 'Airspace type $typeCode';
  }

  /// Get tooltip description for ICAO class
  String _getIcaoClassTooltip(int? icaoClassCode) {
    if (icaoClassCode == null) return '';

    final icaoTooltipMap = {
      0: 'Class A - IFR only. All flights receive air traffic control service and are separated from all other traffic',
      1: 'Class B - IFR and VFR permitted. All flights receive air traffic control service and are separated from all other traffic',
      2: 'Class C - IFR and VFR permitted. All flights receive air traffic control service. IFR flights are separated from other IFR and VFR flights. VFR flights are separated from IFR flights and receive traffic information on other VFR flights',
      3: 'Class D - IFR and VFR permitted. All flights receive air traffic control service. IFR flights are separated from other IFR flights and receive traffic information on VFR flights. VFR flights receive traffic information on all other traffic',
      4: 'Class E - IFR and VFR permitted. IFR flights receive air traffic control service and are separated from other IFR flights. All flights receive traffic information as far as practical. VFR flights do not receive separation service',
      5: 'Class F - IFR and VFR permitted. IFR flights receive air traffic advisory service and all flights receive flight information service if requested. Class F is not implemented in many countries',
      6: 'Class G - Uncontrolled airspace. Only flight information service provided if requested. No separation service provided',
      8: 'No ICAO class assigned - This airspace does not have an ICAO classification in the OpenAIP system',
    };

    return icaoTooltipMap[icaoClassCode] ?? 'ICAO Class $icaoClassCode';
  }

  /// Get display abbreviation for airspace type, showing 'Unknown' for unmapped types
  String _getDisplayTypeAbbreviation(AirspaceType type) {
    // Always use the enum's abbreviation for consistency with Filter Map
    return type.abbreviation;
  }

  /// Get display abbreviation for ICAO class, using enum's display name for consistency
  String _getDisplayIcaoClassAbbreviation(IcaoClass icaoClass) {
    // Always use the enum's display name for consistency with Filter Map
    return icaoClass.displayName;
  }
}
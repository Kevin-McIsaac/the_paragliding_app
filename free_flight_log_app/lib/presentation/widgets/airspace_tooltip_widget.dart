import 'package:flutter/material.dart';
import '../../services/airspace_geojson_service.dart';

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
    const double tooltipWidth = 300.0;
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
                    if (airspaces.length > 3)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.unfold_more,
                              color: Colors.white,
                              size: 10,
                            ),
                            SizedBox(width: 2),
                            Text(
                              'Scroll',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (airspaces.length > 1)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${airspaces.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
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
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(left: 8, right: 12, top: 8, bottom: 8),
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: airspaces.length,
                  separatorBuilder: (context, index) => Container(
                    height: 1,
                    margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4), // Reduced spacing
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                  itemBuilder: (context, index) {
                    final airspace = airspaces[index];
                    return _buildAirspaceItem(airspace);
                  },
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
    // Get type-specific styling
    final style = AirspaceGeoJsonService.instance.getStyleForType(_getTypeAbbreviation(airspace.type));

    // Format compact details line (type, altitude, country)
    final String compactDetails = _formatCompactDetails(airspace);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Line 1: Airspace name with type indicator
          Row(
            children: [
              // Type color indicator
              Container(
                width: 10,
                height: 6,
                decoration: BoxDecoration(
                  color: style.fillColor,
                  border: Border.all(
                    color: style.borderColor,
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),

              // Airspace name
              Expanded(
                child: Text(
                  airspace.name,
                  style: const TextStyle(
                    color: Colors.white,
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
                // Airspace type with tooltip
                Tooltip(
                  message: _getTypeDescription(airspace.type),
                  child: Text(
                    '${_getTypeAbbreviation(airspace.type)},',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

                // ICAO class with tooltip (if available)
                if (airspace.icaoClass != null && _getIcaoClassAbbreviation(airspace.icaoClass).isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Tooltip(
                    message: _getIcaoClassDescription(airspace.icaoClass),
                    child: Text(
                      _getIcaoClassAbbreviation(airspace.icaoClass),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
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
                      color: Colors.white.withValues(alpha: 0.85),
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
    final typeAbbrev = _getTypeAbbreviation(airspace.type);
    parts.add(typeAbbrev);

    // Add ICAO class abbreviation if available
    final icaoClassAbbrev = _getIcaoClassAbbreviation(airspace.icaoClass);
    if (icaoClassAbbrev.isNotEmpty) {
      parts.add(icaoClassAbbrev);
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


  /// Get airspace type abbreviation from numeric code
  String _getTypeAbbreviation(int typeCode) {
    final typeMap = {
      0: 'Unknown',
      1: 'A',       // Class A
      2: 'B',       // Class B
      3: 'C',       // Class C
      4: 'CTR',     // Control Zone
      5: 'E',       // Class E
      6: 'TMA',     // Terminal Control Area
      7: 'G',       // Class G
      8: 'CTR',     // Control Zone
      9: 'TMA',     // Terminal Control Area
      10: 'CTA',    // Control Area
      11: 'R',      // Restricted
      12: 'P',      // Prohibited
      13: 'ATZ',    // Aerodrome Traffic Zone
      14: 'D',      // Danger Area
      15: 'R',      // Military Restricted
      16: 'TMA',    // Approach Control
      17: 'CTR',    // Airport Control Zone
      18: 'R',      // Temporary Restricted
      19: 'P',      // Temporary Prohibited
      20: 'D',      // Temporary Danger
      21: 'TMA',    // Terminal Area
      22: 'CTA',    // Control Terminal Area
      23: 'CTA',    // Control Area Extension
      24: 'CTA',    // Control Area Sector
      25: 'CTA',    // Control Area Step
      26: 'CTA',    // Control Terminal Area (CTA A, CTA C1-C7)
    };

    return typeMap[typeCode] ?? 'Unknown';
  }

  /// Get airspace type full name from numeric code
  String _getTypeDescription(int typeCode) {
    final typeDescriptionMap = {
      0: 'Unknown/Center Airspace',
      1: 'Class A Airspace',
      2: 'Class B Airspace',
      3: 'Class C Airspace',
      4: 'Control Zone',
      5: 'Class E Airspace',
      6: 'Terminal Control Area',
      7: 'Class G Airspace',
      8: 'Control Zone',
      9: 'Terminal Control Area',
      10: 'Control Area',
      11: 'Restricted Area',
      12: 'Prohibited Area',
      13: 'Aerodrome Traffic Zone',
      14: 'Danger Area',
      15: 'Military Restricted Area',
      16: 'Approach Control Area',
      17: 'Airport Control Zone',
      18: 'Temporary Restricted Area',
      19: 'Temporary Prohibited Area',
      20: 'Temporary Danger Area',
      21: 'Terminal Area',
      22: 'Control Terminal Area',
      23: 'Control Area Extension',
      24: 'Control Area Sector',
      25: 'Control Area Step',
      26: 'Control Terminal Area',
    };

    return typeDescriptionMap[typeCode] ?? 'Unknown Airspace Type';
  }

  /// Get ICAO class abbreviation from numeric code
  String _getIcaoClassAbbreviation(int? icaoClassCode) {
    if (icaoClassCode == null) return '';

    final icaoClassMap = {
      0: 'Class G',       // Class G - Uncontrolled
      1: 'Class F',       // Class F - Advisory
      2: 'Class E',       // Class E - Controlled
      3: 'Class D',       // Class D - Controlled
      4: 'Class C',       // Class C - Controlled
      5: 'Class B',       // Class B - Controlled
      6: 'Class A',       // Class A - Controlled
      8: '',              // No class defined/Unknown - show empty
    };

    return icaoClassMap[icaoClassCode] ?? '';
  }

  /// Get ICAO class full description from numeric code
  String _getIcaoClassDescription(int? icaoClassCode) {
    if (icaoClassCode == null) return 'No ICAO class information';

    final icaoClassDescriptionMap = {
      0: 'Class G - Uncontrolled Airspace',
      1: 'Class F - Advisory Airspace',
      2: 'Class E - Controlled Airspace',
      3: 'Class D - Controlled Airspace',
      4: 'Class C - Controlled Airspace',
      5: 'Class B - Controlled Airspace',
      6: 'Class A - Controlled Airspace',
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
}
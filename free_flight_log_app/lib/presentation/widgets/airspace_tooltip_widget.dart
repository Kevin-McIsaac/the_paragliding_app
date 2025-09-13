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
    const double maxTooltipHeight = 350.0;
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
          constraints: const BoxConstraints(maxHeight: maxTooltipHeight),
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

              // Airspace list with scrollbar
              Flexible(
                child: Scrollbar(
                  thumbVisibility: airspaces.length > 3,
                  thickness: 4.0,
                  radius: const Radius.circular(2),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(left: 8, right: 12, top: 8, bottom: 8),
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: airspaces.length,
                    separatorBuilder: (context, index) => Container(
                      height: 1,
                      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                    itemBuilder: (context, index) {
                      final airspace = airspaces[index];
                      return _buildAirspaceItem(airspace);
                    },
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
    // Get type-specific styling
    final style = AirspaceGeoJsonService.instance.getStyleForType(airspace.type);

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

          // Line 2: Type, altitude, country (compact format)
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 1),
            child: Text(
              compactDetails,
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

  /// Format compact details line (type, altitude, country)
  String _formatCompactDetails(AirspaceData airspace) {
    final parts = <String>[];

    // Add type abbreviation
    final typeAbbrev = _getTypeAbbreviation(airspace.type, airspace.class_);
    parts.add(typeAbbrev);

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

    return parts.join(', ');
  }

  /// Get human-readable type description
  String _getTypeDescription(String type, String? class_) {
    final descriptions = {
      'CTR': 'Control Zone',
      'TMA': 'Terminal Control Area',
      'CTA': 'Control Area',
      'D': 'Danger Area',
      'R': 'Restricted Area',
      'P': 'Prohibited Area',
      'A': 'Class A Airspace',
      'B': 'Class B Airspace',
      'C': 'Class C Airspace',
      'E': 'Class E Airspace',
      'F': 'Class F Airspace',
      'G': 'Class G Airspace',
    };

    String description = descriptions[type.toUpperCase()] ?? 'Unknown Airspace';

    if (class_ != null && class_.isNotEmpty && !description.contains('Class')) {
      description += ' (Class $class_)';
    }

    return description;
  }

  /// Get abbreviated type code for compact display
  String _getTypeAbbreviation(String type, String? class_) {
    // Return the type code directly for most cases
    final typeUpper = type.toUpperCase();

    // Handle class-specific airspace types
    if (typeUpper == 'A' || typeUpper == 'B' || typeUpper == 'C' ||
        typeUpper == 'E' || typeUpper == 'F' || typeUpper == 'G') {
      return typeUpper; // Already abbreviated
    }

    // Return standard abbreviations
    final abbreviations = {
      'CTR': 'CTR',
      'TMA': 'TMA',
      'CTA': 'CTA',
      'D': 'D',
      'R': 'R',
      'P': 'P',
    };

    return abbreviations[typeUpper] ?? typeUpper;
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

  /// Calculate optimal position for tooltip to avoid screen edges
  Offset _calculateOptimalPosition(
    Offset cursorPosition,
    double tooltipWidth,
    double tooltipHeight,
    Size screenSize,
    double padding,
  ) {
    double x = cursorPosition.dx;
    double y = cursorPosition.dy;

    // Default: show tooltip to the right and below cursor
    const double cursorOffset = 16.0;
    x += cursorOffset;
    y += cursorOffset;

    // Adjust if tooltip would go off right edge
    if (x + tooltipWidth + padding > screenSize.width) {
      x = cursorPosition.dx - tooltipWidth - cursorOffset;
    }

    // Adjust if tooltip would go off bottom edge
    if (y + tooltipHeight + padding > screenSize.height) {
      y = cursorPosition.dy - tooltipHeight - cursorOffset;
    }

    // Ensure tooltip doesn't go off left edge
    if (x < padding) {
      x = padding;
    }

    // Ensure tooltip doesn't go off top edge
    if (y < padding) {
      y = padding;
    }

    return Offset(x, y);
  }
}
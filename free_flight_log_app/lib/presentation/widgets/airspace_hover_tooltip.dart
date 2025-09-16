import 'package:flutter/material.dart';
import '../../services/airspace_geojson_service.dart';
import '../../data/models/airspace_enums.dart';

/// Lightweight tooltip for displaying airspace information on hover
class AirspaceHoverTooltip extends StatelessWidget {
  final AirspaceData airspace;
  final Offset position;
  final Size screenSize;

  const AirspaceHoverTooltip({
    super.key,
    required this.airspace,
    required this.position,
    required this.screenSize,
  });

  @override
  Widget build(BuildContext context) {
    // Calculate tooltip position (offset from cursor to avoid obscuring)
    const tooltipWidth = 280.0;
    const tooltipHeight = 120.0;
    const offset = 15.0;

    // Default position: to the right and below cursor
    double left = position.dx + offset;
    double top = position.dy + offset;

    // Adjust if tooltip would go off screen
    if (left + tooltipWidth > screenSize.width) {
      left = position.dx - tooltipWidth - offset;
    }
    if (top + tooltipHeight > screenSize.height) {
      top = position.dy - tooltipHeight - offset;
    }

    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: Container(
          width: tooltipWidth,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xF0121212), // Slightly transparent dark background
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.2),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 10,
                offset: const Offset(2, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Airspace name
              Text(
                airspace.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),

              // Type and class
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _getTypeColor(airspace.type).withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: _getTypeColor(airspace.type),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      airspace.type.abbreviation,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (airspace.icaoClass != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: airspace.icaoClass!.fillColor,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: airspace.icaoClass!.borderColor,
                          width: 1,
                        ),
                      ),
                      child: Text(
                        'Class ${airspace.icaoClass!.abbreviation}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),

              // Altitude limits
              Text(
                _formatAltitudeLimits(),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatAltitudeLimits() {
    final lower = _formatAltitude(airspace.lowerLimit);
    final upper = _formatAltitude(airspace.upperLimit);
    return '$lower - $upper';
  }

  String _formatAltitude(Map<String, dynamic>? limit) {
    if (limit == null) return 'Unknown';

    final value = limit['value'];
    final unit = limit['unit'];
    final reference = limit['reference'];

    // Handle ground reference
    if (reference == 0 || (value is String && value.toLowerCase() == 'gnd')) {
      return 'GND';
    }

    // Handle numeric values with OpenAIP unit codes
    if (value is num) {
      // OpenAIP unit codes: 1=ft, 2=m, 6=FL
      if (unit == 6) {
        return 'FL${value.round().toString().padLeft(3, '0')}';
      } else if (unit == 1) {
        // Reference codes: 1=AMSL, 2=AGL
        final refStr = reference == 2 ? ' AGL' : '';
        return '${value.round()} ft$refStr';
      } else if (unit == 2) {
        final refStr = reference == 2 ? ' AGL' : '';
        return '${value.round()} m$refStr';
      }
    }

    // Fallback for string units
    if (unit is String && value is num) {
      final unitStr = unit.toString().toLowerCase();
      if (unitStr == 'fl') {
        return 'FL${value.round().toString().padLeft(3, '0')}';
      } else if (unitStr == 'ft') {
        return '${value.round()} ft';
      } else if (unitStr == 'm') {
        return '${value.round()} m';
      }
    }

    return value.toString();
  }

  Color _getTypeColor(AirspaceType type) {
    switch (type) {
      case AirspaceType.prohibited:
      case AirspaceType.danger:
        return Colors.red;
      case AirspaceType.restricted:
        return Colors.orange;
      case AirspaceType.ctr:
      case AirspaceType.atz:
        return Colors.blue;
      case AirspaceType.tma:
      case AirspaceType.cta:
        return Colors.purple;
      case AirspaceType.tmz:
      case AirspaceType.rmz:
        return Colors.yellow;
      default:
        return Colors.grey;
    }
  }
}
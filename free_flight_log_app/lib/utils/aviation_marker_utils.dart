import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../data/models/airport.dart';
import '../data/models/navaid.dart';
import '../data/models/reporting_point.dart';

/// Utilities for creating consistent aviation markers across different map views
class AviationMarkerUtils {
  // Airport marker sizes based on category
  static const double largeAirportSize = 32.0;
  static const double mediumAirportSize = 26.0;
  static const double smallAirportSize = 20.0;

  // Navaid marker size
  static const double navaidMarkerSize = 22.0;

  // Reporting point marker size
  static const double reportingPointSize = 18.0;

  // Common styling
  static const Color airportColor = Color(0xFF2196F3); // Blue
  static const Color airportBorderColor = Colors.white;

  // Airport marker colors by category
  static const Color largeAirportColor = Color(0xFF1976D2); // Dark blue
  static const Color mediumAirportColor = Color(0xFF2196F3); // Blue
  static const Color smallAirportColor = Color(0xFF42A5F5); // Light blue

  // Navaid colors by type
  static const Color vorColor = Color(0xFF4CAF50); // Green
  static const Color ndbColor = Color(0xFF9C27B0); // Purple
  static const Color dmeColor = Color(0xFFFF9800); // Orange
  static const Color waypointColor = Color(0xFF607D8B); // Blue grey

  /// Create an airport marker with appropriate size and styling
  static Marker buildAirportMarker({
    required Airport airport,
    VoidCallback? onTap,
  }) {
    final size = _getAirportMarkerSize(airport.category);
    final color = _getAirportMarkerColor(airport.category);

    return Marker(
      point: airport.position,
      width: size + 8, // Extra space for border
      height: size + 8,
      child: GestureDetector(
        onTap: onTap,
        child: Tooltip(
          message: _buildAirportTooltip(airport),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: airportBorderColor, width: 2),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 3,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            child: Icon(
              Icons.flight,
              color: Colors.white,
              size: size * 0.6,
            ),
          ),
        ),
      ),
    );
  }

  /// Create a navaid marker with type-specific symbol and color
  static Marker buildNavaidMarker({
    required Navaid navaid,
    VoidCallback? onTap,
  }) {
    final color = _getNavaidMarkerColor(navaid.type);
    final symbol = navaid.type.iconSymbol;

    return Marker(
      point: navaid.position,
      width: navaidMarkerSize + 4,
      height: navaidMarkerSize + 4,
      child: GestureDetector(
        onTap: onTap,
        child: Tooltip(
          message: _buildNavaidTooltip(navaid),
          child: Container(
            width: navaidMarkerSize,
            height: navaidMarkerSize,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 2,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            child: Center(
              child: Text(
                symbol,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Create a reporting point marker with type-specific symbol and color
  static Marker buildReportingPointMarker({
    required ReportingPoint reportingPoint,
    VoidCallback? onTap,
  }) {
    final color = Color(reportingPoint.type.color);
    final symbol = reportingPoint.type.iconSymbol;

    return Marker(
      point: reportingPoint.position,
      width: reportingPointSize + 4,
      height: reportingPointSize + 4,
      child: GestureDetector(
        onTap: onTap,
        child: Tooltip(
          message: reportingPoint.tooltipText,
          child: Container(
            width: reportingPointSize,
            height: reportingPointSize,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 2,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            child: Center(
              child: Text(
                symbol,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Get marker size based on airport category
  static double _getAirportMarkerSize(AirportCategory category) {
    switch (category) {
      case AirportCategory.large:
        return largeAirportSize;
      case AirportCategory.medium:
        return mediumAirportSize;
      case AirportCategory.small:
        return smallAirportSize;
    }
  }

  /// Get marker color based on airport category
  static Color _getAirportMarkerColor(AirportCategory category) {
    switch (category) {
      case AirportCategory.large:
        return largeAirportColor;
      case AirportCategory.medium:
        return mediumAirportColor;
      case AirportCategory.small:
        return smallAirportColor;
    }
  }

  /// Get marker color based on navaid type
  static Color _getNavaidMarkerColor(NavaidType type) {
    switch (type) {
      case NavaidType.vor:
      case NavaidType.vordme:
        return vorColor;
      case NavaidType.ndb:
        return ndbColor;
      case NavaidType.dme:
        return dmeColor;
      case NavaidType.tacan:
        return vorColor; // Similar to VOR
      case NavaidType.waypoint:
        return waypointColor;
      case NavaidType.unknown:
        return Colors.grey;
    }
  }

  /// Build tooltip text for airports
  static String _buildAirportTooltip(Airport airport) {
    final buffer = StringBuffer(airport.displayName);

    if (airport.type.isNotEmpty) {
      buffer.write('\nType: ${airport.type.replaceAll('_', ' ').toLowerCase()}');
    }

    if (airport.elevation != null) {
      buffer.write('\nElevation: ${airport.elevation!.toInt()}m');
    }

    if (airport.runways != null && airport.runways!.isNotEmpty) {
      final longestRunway = airport.runways!
          .where((r) => r.lengthMeters != null)
          .fold<Runway?>(null, (prev, curr) {
        if (prev == null) return curr;
        return (curr.lengthMeters! > prev.lengthMeters!) ? curr : prev;
      });

      if (longestRunway != null) {
        buffer.write('\nLongest runway: ${longestRunway.lengthMeters!.toInt()}m');
      }
    }

    if (airport.frequencies != null && airport.frequencies!.isNotEmpty) {
      final tower = airport.frequencies!
          .where((f) => f.type?.toLowerCase() == 'tower')
          .firstOrNull;
      if (tower != null) {
        buffer.write('\nTower: ${tower.formattedFrequency}');
      }
    }

    return buffer.toString();
  }

  /// Build tooltip text for navaids
  static String _buildNavaidTooltip(Navaid navaid) {
    final buffer = StringBuffer(navaid.displayName);

    buffer.write('\nType: ${navaid.type.description}');

    if (navaid.formattedFrequency != null) {
      buffer.write('\nFrequency: ${navaid.formattedFrequency}');
    }

    if (navaid.range != null) {
      buffer.write('\nRange: ${navaid.range} NM');
    }

    if (navaid.elevation != null) {
      buffer.write('\nElevation: ${navaid.elevation!.toInt()}m');
    }

    return buffer.toString();
  }

  /// Create legend items for aviation overlays
  static List<Widget> buildAviationLegendItems({
    bool showAirports = false,
    bool showNavaids = false,
    bool showReportingPoints = false,
  }) {
    final List<Widget> legendItems = [];

    if (showAirports) {
      legendItems.addAll([
        _buildLegendItem(
          Icons.flight,
          largeAirportColor,
          'Large Airports',
          size: largeAirportSize * 0.6,
        ),
        const SizedBox(height: 2),
        _buildLegendItem(
          Icons.flight,
          mediumAirportColor,
          'Medium Airports',
          size: mediumAirportSize * 0.6,
        ),
        const SizedBox(height: 2),
        _buildLegendItem(
          Icons.flight,
          smallAirportColor,
          'Small Airports',
          size: smallAirportSize * 0.6,
        ),
        const SizedBox(height: 4),
      ]);
    }

    if (showNavaids) {
      legendItems.addAll([
        _buildSymbolLegendItem('⬡', vorColor, 'VOR/VOR-DME'),
        const SizedBox(height: 2),
        _buildSymbolLegendItem('●', ndbColor, 'NDB'),
        const SizedBox(height: 2),
        _buildSymbolLegendItem('◇', dmeColor, 'DME'),
        const SizedBox(height: 2),
        _buildSymbolLegendItem('◉', waypointColor, 'Waypoints'),
        const SizedBox(height: 4),
      ]);
    }

    if (showReportingPoints) {
      legendItems.addAll([
        _buildSymbolLegendItem(
          '▲',
          Color(ReportingPointType.visual.color),
          'Visual Reporting Points',
        ),
        const SizedBox(height: 2),
        _buildSymbolLegendItem(
          '▲',
          Color(ReportingPointType.compulsory.color),
          'Compulsory Points',
        ),
        const SizedBox(height: 4),
      ]);
    }

    return legendItems;
  }

  /// Build a legend item with an icon
  static Widget _buildLegendItem(
    IconData icon,
    Color color,
    String label, {
    double size = 16,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1),
          ),
          child: Icon(
            icon,
            color: Colors.white,
            size: size,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w500,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  /// Build a legend item with a text symbol
  static Widget _buildSymbolLegendItem(
    String symbol,
    Color color,
    String label,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1),
          ),
          child: Center(
            child: Text(
              symbol,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w500,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}
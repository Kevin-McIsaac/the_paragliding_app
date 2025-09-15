import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/airspace_geojson_service.dart';

/// Shared utilities for creating consistent site markers across different map views
class SiteMarkerUtils {
  // Marker size constants
  static const double siteMarkerSize = 42.0;
  static const double siteMarkerIconSize = 36.0;
  static const double launchMarkerSize = 25.0;
  
  // Colors
  static const Color flownSiteColor = Colors.blue;
  static const Color newSiteColor = Colors.deepPurple;
  static const Color launchColor = Colors.green;
  static const Color landingColor = Colors.red;
  static const Color selectedPointColor = Colors.amber;
  
  // Common const decorations for performance
  static const _defaultBoxShadow = [
    BoxShadow(
      color: Color(0x4D000000), // Colors.black.withValues(alpha: 0.3) as const
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
  ];
  
  // Static methods for commonly used non-const objects
  static Border get _whiteCircleBorder => Border.all(color: Colors.white, width: 2);
  
  /// Create a site marker icon with consistent styling
  static Widget buildSiteMarkerIcon({
    required Color color,
    bool showBorder = false,
    Color borderColor = Colors.white,
    double borderWidth = 2.0,
  }) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // White outline
        const Icon(
          Icons.location_on,
          color: Colors.white,
          size: siteMarkerSize,
        ),
        // Colored marker
        Icon(
          Icons.location_on,
          color: color,
          size: siteMarkerIconSize,
        ),
        // Optional border for special states
        if (showBorder)
          Container(
            width: siteMarkerSize + (borderWidth * 2),
            height: siteMarkerSize + (borderWidth * 2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: borderColor, width: borderWidth),
            ),
          ),
      ],
    );
  }
  
  /// Create a site label with consistent styling
  static Widget buildSiteLabel({
    required String siteName,
    int? flightCount,
    double fontSize = 9.0,
    Color backgroundColor = const Color(0x80000000), // Colors.black.withValues(alpha: 0.5)
    Color textColor = Colors.white,
    double maxWidth = 140.0,
  }) {
    return IntrinsicWidth(
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              siteName,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: TextStyle(
                fontSize: fontSize,
                color: textColor,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            if (flightCount != null && flightCount > 0)
              Text(
                '$flightCount flight${flightCount == 1 ? '' : 's'}',
                style: TextStyle(
                  fontSize: fontSize - 1,
                  color: textColor.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w400,
                ),
                textAlign: TextAlign.center,
              ),
          ],
        ),
      ),
    );
  }
  
  /// Create a complete site marker for display-only maps (no interaction)
  static Marker buildDisplaySiteMarker({
    required LatLng position,
    required String siteName,
    required bool isFlownSite,
    int? flightCount,
    String? tooltip,
  }) {
    final color = isFlownSite ? flownSiteColor : newSiteColor;
    
    return Marker(
      point: position,
      width: 140,
      height: 80,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          buildSiteMarkerIcon(color: color),
          buildSiteLabel(
            siteName: siteName,
            flightCount: flightCount,
          ),
        ],
      ),
    );
  }
  
  /// Create a launch marker with consistent styling
  static Widget buildLaunchMarkerIcon({
    Color color = launchColor,
    double size = launchMarkerSize,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: _whiteCircleBorder,
        boxShadow: _defaultBoxShadow,
      ),
    );
  }
  
  /// Create a landing marker with consistent styling
  static Widget buildLandingMarkerIcon({
    Color color = Colors.red,
    double size = launchMarkerSize,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: _whiteCircleBorder,
        boxShadow: _defaultBoxShadow,
      ),
    );
  }
  
  /// Create legend items for consistent styling across maps
  static Widget buildLegendItem(
    BuildContext context,
    IconData? icon,
    Color color,
    String label, {
    bool isCircle = false,
    double iconSize = 16,
    double circleSize = launchMarkerSize,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isCircle)
          Container(
            width: circleSize,
            height: circleSize,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: _whiteCircleBorder,
            ),
          )
        else if (icon == Icons.location_on)
          // Site markers need white outline like actual markers
          Stack(
            alignment: Alignment.center,
            children: [
              Icon(Icons.location_on, color: Colors.white, size: iconSize + 2),
              Icon(Icons.location_on, color: color, size: iconSize),
            ],
          )
        else
          Icon(icon!, color: color, size: iconSize),
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

  /// Convert numeric airspace types back to string abbreviations for legacy compatibility
  static Set<String> _convertNumericTypesToStrings(Set<int> numericTypes) {
    const numericToString = {
      0: 'Unknown',
      1: 'A',
      2: 'E',
      3: 'C',
      4: 'CTR',
      5: 'E',
      6: 'TMA',
      7: 'G',
      8: 'CTR',
      9: 'TMA',
      10: 'CTA',
      11: 'R',
      12: 'P',
      13: 'ATZ',
      14: 'D',
      15: 'R',
      16: 'TMA',
      17: 'CTR',
      18: 'R',
      19: 'P',
      20: 'D',
      21: 'TMA',
      26: 'CTA',
    };

    return numericTypes.map((type) => numericToString[type] ?? 'Unknown').toSet();
  }

  /// Build airspace legend items with tooltips, optionally filtered by visible types
  static List<Widget> buildAirspaceLegendItems({Set<String>? visibleTypes}) {
    final airspaceService = AirspaceGeoJsonService.instance;
    final styles = airspaceService.allAirspaceStyles;

    // If visibleTypes is not provided, get from service (for backwards compatibility)
    final typesToShow = visibleTypes ?? airspaceService.visibleAirspaceTypes.map((type) => type.abbreviation).toSet();

    // Define airspace type descriptions with detailed tooltips
    final typeDescriptions = {
      'CTR': {'name': 'Control Zone', 'tooltip': 'CTR - Control Zone: Controlled airspace around airports'},
      'TMA': {'name': 'Terminal Area', 'tooltip': 'TMA - Terminal Area: Controlled airspace in terminal areas'},
      'CTA': {'name': 'Control Area', 'tooltip': 'CTA - Control Area: General controlled airspace'},
      'D': {'name': 'Danger Area', 'tooltip': 'D - Danger Area: Areas with potential hazards to aircraft'},
      'R': {'name': 'Restricted', 'tooltip': 'R - Restricted: Areas with restrictions on aircraft operations'},
      'P': {'name': 'Prohibited', 'tooltip': 'P - Prohibited: Areas where flight is completely prohibited'},
      'A': {'name': 'Class A', 'tooltip': 'Class A: IFR only, ATC clearance required'},
      'B': {'name': 'Class B', 'tooltip': 'Class B: IFR and VFR, ATC clearance required'},
      'C': {'name': 'Class C', 'tooltip': 'Class C: IFR and VFR, ATC clearance for IFR, contact for VFR'},
      'E': {'name': 'Class E', 'tooltip': 'Class E: IFR and VFR, ATC clearance for IFR only'},
      'F': {'name': 'Class F', 'tooltip': 'Class F: IFR and VFR, flight information service'},
      'G': {'name': 'Class G', 'tooltip': 'Class G: IFR and VFR, uncontrolled airspace'},
    };

    // Show most common/important types first, but only if they're visible
    final priorityOrder = ['CTR', 'TMA', 'D', 'R', 'P', 'C', 'A', 'B', 'E', 'F', 'G'];

    final List<Widget> legendItems = [];

    for (final type in priorityOrder) {
      // Only show types that are both in styles and visible in current area
      if (styles.containsKey(type) && typesToShow.contains(type)) {
        final style = styles[type]!;
        final typeInfo = typeDescriptions[type]!;

        legendItems.add(
          Tooltip(
            message: typeInfo['tooltip']!,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 12,
                    height: 6,
                    decoration: BoxDecoration(
                      color: style.fillColor,
                      border: Border.all(
                        color: style.borderColor,
                        width: 0.5,
                      ),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$type - ${typeInfo['name']}',
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    }

    return legendItems;
  }

  /// Build a legend widget with consistent styling
  static Widget buildMapLegend({
    required BuildContext context,
    bool showLaunches = false,
    bool showSites = true,
    List<Widget>? additionalLegendItems,
  }) {
    return Positioned(
      top: 8,
      left: 8,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: const BoxDecoration(
          color: Color(0x80000000),
          borderRadius: BorderRadius.all(Radius.circular(4)),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showLaunches) ...[
              buildLegendItem(context, null, launchColor, 'Launches', isCircle: true),
              const SizedBox(height: 4),
            ],
            if (showSites) ...[
              buildLegendItem(context, Icons.location_on, flownSiteColor, 'Flown Sites'),
              const SizedBox(height: 4),
              buildLegendItem(context, Icons.location_on, newSiteColor, 'New Sites'),
            ],
            // Add additional legend items if provided
            if (additionalLegendItems != null && additionalLegendItems.isNotEmpty) ...[
              if (showSites || showLaunches) const SizedBox(height: 4),
              ...additionalLegendItems,
            ],
          ],
        ),
      ),
    );
  }
  
  /// Build a collapsible legend widget with consistent styling
  static Widget buildCollapsibleMapLegend({
    required BuildContext context,
    required bool isExpanded,
    required VoidCallback onToggle,
    required List<Widget> legendItems,
  }) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0x80000000),
        borderRadius: BorderRadius.all(Radius.circular(4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Toggle button
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Legend',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: isExpanded ? 0.25 : 0.0,
                    duration: const Duration(milliseconds: 300),
                    child: const Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Legend content
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Container(
              padding: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: legendItems,
              ),
            ),
            crossFadeState: isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 300),
          ),
        ],
      ),
    );
  }
}
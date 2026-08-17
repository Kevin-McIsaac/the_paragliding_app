import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../presentation/widgets/windsock_marker.dart';
import '../services/airspace_geojson_service.dart';

/// Shared utilities for creating consistent site markers across different map views
class SiteMarkerUtils {
  // Marker size constants
  static const double siteMarkerSize = 42.0;
  static const double siteMarkerIconSize = 36.0;
  static const double launchMarkerSize = 25.0;

  // A catalogue landing, drawn deliberately smaller than a launch.
  //
  // It used to be drawn at siteMarkerSize, the same weight as a launch, which
  // made the eye rank the two equally. They are not equal on this map: you
  // choose a launch, and its landing follows from that choice. Two thirds the
  // size, and the muted slate below, is enough to say "supporting information"
  // without making it hard to find when you are looking for one.
  static const double landingMarkerSize = 28.0;

  // A legend row's symbol, small enough to sit on a text line. The same
  // symbols the map draws, only smaller - see siteSymbol.
  static const double legendSymbolSize = 18.0;
  
  // Site status colors (for other screens)
  static const Color flownSiteColor = Color(0xFF0047AB);     // Sites with logged flights (cobalt blue)
  static const Color newSiteColor = Colors.blue;         // Sites from PGE API

  // Nearby Sites map flyability colors
  static const Color flyableSiteColor = Colors.green;    // Flyable with current wind
  static const Color strongWindSiteColor = Colors.orange; // Flyable but strong winds (caution)
  static const Color notFlyableSiteColor = Colors.red;   // Not flyable with current wind
  static const Color unknownFlyabilitySiteColor = Colors.blue; // No wind directions or wind data not available - same as new sites

  // Landing sites in the catalogue.
  //
  // Slate rather than a colour from the flyability palette above: green,
  // orange, red and blue all mean "can I fly here today", and a landing has no
  // wind directions to answer that with. It is told apart by *shape* - a flag
  // rather than a pin - so its colour is free to say nothing at all.
  //
  // Blue-grey 400 rather than 700: a landing recedes behind the launches the
  // map is for. See landingMarkerSize.
  static const Color landingSiteColor = Color(0xFF78909C);

  // Launch/landing colors (flight track endpoints, not catalogue rows)
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
  
  /// The symbol a site type is drawn with, at whatever size is asked for.
  ///
  /// One answer in one place, for the map and its legend alike - they differ
  /// only in size. The symbol used to be stated separately by two icon
  /// builders, an `if` at the map's call site, and a hand-written legend row,
  /// so "landings are flags" was said four times and could have been changed in
  /// three of them without the fourth noticing.
  ///
  /// Returning the widget rather than a glyph is what lets the two site types
  /// be drawn differently - a launch is a character from the icon font, a
  /// landing is painted, because Material has no windsock - without any caller
  /// having to know which it got.
  ///
  /// A landing is drawn smaller because it is supporting information: you
  /// choose a launch, and its landing follows from that choice.
  static Widget siteSymbol(
    String? siteType, {
    required Color color,
    double? size,
  }) {
    if (siteType == 'landing') {
      // The windsock carries its own palette - a landing has no wind
      // directions to be graded against - so [color] is deliberately unused.
      return WindsockMarker(size: size ?? landingMarkerSize);
    }

    final outer = size ?? siteMarkerSize;
    return Stack(
      alignment: Alignment.center,
      children: [
        // White outline - what keeps the marker legible against terrain, so it
        // scales with the glyph rather than being fixed.
        Icon(Icons.location_on, color: Colors.white, size: outer),
        Icon(
          Icons.location_on,
          color: color,
          size: outer * (siteMarkerIconSize / siteMarkerSize),
        ),
      ],
    );
  }

  /// Create a site marker icon with consistent styling.
  ///
  /// [siteType] picks the glyph and its size; everything else about the marker
  /// is identical, which is the point - a landing is a site drawn with a
  /// different symbol, not a different kind of thing. Defaults to a launch, so
  /// the display-only maps that have no site type keep the pin they had.
  static Widget buildSiteMarkerIcon({
    required Color color,
    String? siteType,
    bool showBorder = false,
    Color borderColor = Colors.white,
    double borderWidth = 2.0,
  }) {
    final outer =
        siteType == 'landing' ? landingMarkerSize : siteMarkerSize;

    return Stack(
      alignment: Alignment.center,
      children: [
        siteSymbol(siteType, color: color),
        // Optional border for special states
        if (showBorder)
          Container(
            width: outer + (borderWidth * 2),
            height: outer + (borderWidth * 2),
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
    double fontSize = 11.0,
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
  
  // buildLandingSiteMarkerIcon is gone: it was buildSiteMarkerIcon with a
  // different glyph, chosen by an `if` wherever a marker was built. A landing
  // is now a windsock rather than a flag - it says what the place is for, not
  // just that something is there - and that is one branch in siteSymbol rather
  // than a second builder to keep in step with the first.

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
  ///
  /// [swatch] is for rows describing a site marker: pass
  /// `siteSymbol(type, color: ..., size: ...)` so the legend draws the marker
  /// by calling the same function the map calls. It used to rebuild a site pin
  /// here from its own pair of `Icon`s, which is how a legend ends up
  /// describing a marker the map no longer draws.
  static Widget buildLegendItem(
    BuildContext context,
    IconData? icon,
    Color color,
    String label, {
    bool isCircle = false,
    double iconSize = 16,
    double circleSize = launchMarkerSize,
    Widget? swatch,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (swatch != null)
          swatch
        else if (isCircle)
          Container(
            width: circleSize,
            height: circleSize,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: _whiteCircleBorder,
            ),
          )
        else
          Icon(icon!, color: color, size: iconSize),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Colors.white,
          ),
        ),
      ],
    );
  }


  /// Build airspace legend items with tooltips, optionally filtered by visible types
  static List<Widget> buildAirspaceLegendItems({Set<String>? visibleTypes}) {
    final airspaceService = AirspaceGeoJsonService.instance;
    final styles = airspaceService.allAirspaceStyles;

    // If visibleTypes is not provided, get from service (for backwards compatibility)
    final typesToShow = visibleTypes ?? airspaceService.visibleAirspaceTypes.map((type) => type.abbreviation).toSet();

    // Define ICAO class descriptions only (removed airspace types)
    final typeDescriptions = {
      'A': {'name': 'Class A', 'tooltip': 'Class A: IFR only, ATC clearance required'},
      'B': {'name': 'Class B', 'tooltip': 'Class B: IFR and VFR, ATC clearance required'},
      'C': {'name': 'Class C', 'tooltip': 'Class C: IFR and VFR, ATC clearance for IFR, contact for VFR'},
      'E': {'name': 'Class E', 'tooltip': 'Class E: IFR and VFR, ATC clearance for IFR only'},
      'F': {'name': 'Class F', 'tooltip': 'Class F: IFR and VFR, flight information service'},
      'G': {'name': 'Class G', 'tooltip': 'Class G: IFR and VFR, uncontrolled airspace'},
    };

    // Show only ICAO classes in priority order
    final priorityOrder = ['A', 'B', 'C', 'E', 'F', 'G'];

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
              // Symbols from siteSymbol - the same call the map makes - so a
              // legend cannot describe a marker the map no longer draws.
              buildLegendItem(context, null, flownSiteColor, 'Flown Sites',
                  swatch: siteSymbol('launch',
                      color: flownSiteColor, size: legendSymbolSize)),
              const SizedBox(height: 4),
              buildLegendItem(context, null, newSiteColor, 'New Sites',
                  swatch: siteSymbol('launch',
                      color: newSiteColor, size: legendSymbolSize)),
              const SizedBox(height: 4),
              buildLegendItem(context, null, landingSiteColor, 'Landings',
                  swatch: siteSymbol('landing',
                      color: landingSiteColor, size: legendSymbolSize)),
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Legend',
                    style: TextStyle(
                      fontSize: 13,
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
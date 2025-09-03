import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Shared utilities for creating consistent site markers across different map views
class SiteMarkerUtils {
  // Marker size constants
  static const double siteMarkerSize = 72.0;
  static const double siteMarkerIconSize = 66.0;
  static const double launchMarkerSize = 15.0;
  
  // Colors
  static const Color flownSiteColor = Colors.blue;
  static const Color newSiteColor = Colors.green;
  static const Color launchColor = Colors.blue;
  
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
    Color backgroundColor = const Color(0x4D000000), // Colors.black.withValues(alpha: 0.3)
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
      width: 300,
      height: 120,
      child: Tooltip(
        message: tooltip ?? siteName,
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
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
    );
  }
  
  /// Create legend items for consistent styling across maps
  static Widget buildLegendItem(
    IconData? icon,
    Color color,
    String label, {
    bool isCircle = false,
    double iconSize = 20,
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
              border: Border.all(color: Colors.white, width: 2),
            ),
          )
        else
          Icon(icon!, color: color, size: iconSize),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.normal,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }
  
  /// Build a legend widget with consistent styling
  static Widget buildMapLegend({
    required BuildContext context,
    bool showLaunches = false,
    bool showSites = true,
  }) {
    return Positioned(
      top: 8,
      left: 8,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(4),
          boxShadow: [
            const BoxShadow(
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
              buildLegendItem(null, launchColor, 'Launches', isCircle: true),
              const SizedBox(height: 4),
            ],
            if (showSites) ...[
              buildLegendItem(Icons.location_on, flownSiteColor, 'Flown Sites'),
              const SizedBox(height: 4),
              buildLegendItem(Icons.location_on, newSiteColor, 'New Sites'),
            ],
          ],
        ),
      ),
    );
  }
}
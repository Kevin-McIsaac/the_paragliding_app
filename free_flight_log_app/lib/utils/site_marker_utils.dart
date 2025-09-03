import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'ui_utils.dart';

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
      child: AppTooltip(
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
        else
          Icon(icon!, color: color, size: iconSize),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.normal,
            color: Theme.of(context).colorScheme.onSurface,
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
              buildLegendItem(context, null, launchColor, 'Launches', isCircle: true),
              const SizedBox(height: 4),
            ],
            if (showSites) ...[
              buildLegendItem(context, Icons.location_on, flownSiteColor, 'Flown Sites'),
              const SizedBox(height: 4),
              buildLegendItem(context, Icons.location_on, newSiteColor, 'New Sites'),
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
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Toggle button
          GestureDetector(
            onTap: onToggle,
            child: Container(
              padding: const EdgeInsets.all(8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Legend',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: isExpanded ? 0.25 : 0.0,
                    duration: const Duration(milliseconds: 300),
                    child: Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurface,
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
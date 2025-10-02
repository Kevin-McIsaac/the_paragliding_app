import 'package:flutter/material.dart';
import '../../data/models/paragliding_site.dart';
import '../../data/models/flyability_status.dart';
import '../../data/models/wind_data.dart';
import '../../utils/site_marker_utils.dart';

/// Encapsulates all visual presentation state for a site marker
///
/// This class centralizes the logic for determining marker color, tooltip,
/// and opacity based on site type and flyability status. It provides a
/// single source of truth for marker presentation across different screens.
class SiteMarkerPresentation {
  /// The color to use for the marker icon
  final Color color;

  /// The tooltip message to display (null if no tooltip)
  final String? tooltip;

  /// The opacity to apply to the marker (0.0 to 1.0)
  final double opacity;

  const SiteMarkerPresentation({
    required this.color,
    this.tooltip,
    this.opacity = 1.0,
  });

  /// Create presentation for simple site type-based coloring (flown vs new)
  ///
  /// Used in screens that don't show flyability:
  /// - Flight list map
  /// - Edit site screen
  factory SiteMarkerPresentation.forSiteType(ParaglidingSite site) {
    return SiteMarkerPresentation(
      color: site.hasFlights
          ? SiteMarkerUtils.flownSiteColor
          : SiteMarkerUtils.newSiteColor,
      tooltip: null,
      opacity: 1.0,
    );
  }

  /// Create presentation for flyability-based coloring
  ///
  /// Used in the Nearby Sites screen where markers show wind flyability.
  /// Combines site type, wind data, and forecast settings to determine
  /// the appropriate color, tooltip, and opacity.
  factory SiteMarkerPresentation.forFlyability({
    required ParaglidingSite site,
    FlyabilityStatus? status,
    WindData? windData,
    required double maxWindSpeed,
    required double maxWindGusts,
    required bool forecastEnabled,
  }) {
    // Determine flyability status if not provided
    final effectiveStatus = status ?? FlyabilityStatus.unknown;

    // Determine color based on flyability status
    Color color;
    switch (effectiveStatus) {
      case FlyabilityStatus.flyable:
        color = SiteMarkerUtils.flyableSiteColor;
        break;
      case FlyabilityStatus.notFlyable:
        color = SiteMarkerUtils.notFlyableSiteColor;
        break;
      case FlyabilityStatus.loading:
      case FlyabilityStatus.unknown:
        color = SiteMarkerUtils.unknownFlyabilitySiteColor;
        break;
    }

    // Determine opacity
    double opacity;
    if (!forecastEnabled) {
      // When forecast is disabled, all sites are solid
      opacity = 1.0;
    } else {
      // Show reduced opacity for sites awaiting wind data (have directions but no data yet)
      final hasWindDirections = site.windDirections.isNotEmpty;
      final hasWindData = windData != null;

      if (hasWindDirections && !hasWindData && effectiveStatus == FlyabilityStatus.unknown) {
        // Site has directions but waiting for wind data
        opacity = 0.5;
      } else {
        // Site has no directions, has data, or has known status
        opacity = 1.0;
      }
    }

    // Generate tooltip
    String? tooltip = _generateFlyabilityTooltip(
      site: site,
      status: effectiveStatus,
      windData: windData,
      maxWindSpeed: maxWindSpeed,
      maxWindGusts: maxWindGusts,
    );

    return SiteMarkerPresentation(
      color: color,
      tooltip: tooltip,
      opacity: opacity,
    );
  }

  /// Generate a descriptive tooltip explaining flyability status
  static String? _generateFlyabilityTooltip({
    required ParaglidingSite site,
    required FlyabilityStatus status,
    WindData? windData,
    required double maxWindSpeed,
    required double maxWindGusts,
  }) {
    switch (status) {
      case FlyabilityStatus.flyable:
      case FlyabilityStatus.notFlyable:
        // Use WindData's built-in reason if available
        if (windData != null && site.windDirections.isNotEmpty) {
          return windData.getFlyabilityReason(
            site.windDirections,
            maxWindSpeed,
            maxWindGusts,
          );
        }
        return 'Flyability calculation error';

      case FlyabilityStatus.loading:
        return 'Loading wind forecast...';

      case FlyabilityStatus.unknown:
        // Distinguish between different "unknown" scenarios
        if (windData == null) {
          return 'No wind forecast available';
        } else if (site.windDirections.isEmpty) {
          return 'No wind directions defined for site';
        }
        return 'Flyability status available';
    }
  }
}

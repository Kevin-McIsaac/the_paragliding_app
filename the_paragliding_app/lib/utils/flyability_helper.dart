import 'package:flutter/material.dart';
import '../data/models/wind_data.dart';

/// Flyability levels for wind conditions
enum FlyabilityLevel {
  safe,      // Good conditions for flying
  caution,   // Flyable but strong winds - experienced pilots only
  unsafe,    // Not flyable - wrong direction or too strong
  unknown,   // No wind data or no site wind directions
}

/// Centralized flyability determination logic with consistent colors and tooltips
class FlyabilityHelper {
  // Wind thresholds (km/h)
  static const double cautionWindSpeedKmh = 20.0;  // Speed above this triggers caution
  static const double maxWindSpeedKmh = 25.0;      // Speed above this is unsafe
  static const double cautionGustsKmh = 25.0;      // Gusts above this trigger caution
  static const double maxGustsKmh = 30.0;          // Gusts above this are unsafe

  // Flyability colors (matching SiteMarkerUtils for consistency)
  static const Color safeColor = Colors.green;      // Safe to fly
  static const Color cautionColor = Colors.orange;  // Caution - strong winds
  static const Color unsafeColor = Colors.red;      // Unsafe conditions
  static const Color unknownColor = Colors.blue;    // Unknown/no data

  /// Determine flyability level based on wind conditions
  ///
  /// Returns:
  /// - FlyabilityLevel.safe: Good conditions for flying
  /// - FlyabilityLevel.caution: Flyable but strong (speed 20-25 or gusts 25-30)
  /// - FlyabilityLevel.unsafe: Too strong or wrong direction
  /// - FlyabilityLevel.unknown: No wind directions defined
  static FlyabilityLevel getFlyabilityLevel({
    required WindData windData,
    required List<String> siteDirections,
    double? maxSpeed,
    double? maxGusts,
  }) {
    // Use provided limits or defaults
    final speedLimit = maxSpeed ?? maxWindSpeedKmh;
    final gustsLimit = maxGusts ?? maxGustsKmh;

    // No wind directions = unknown
    if (siteDirections.isEmpty) {
      return FlyabilityLevel.unknown;
    }

    // Check if flyable based on direction and limits
    final isFlyable = windData.isFlyable(siteDirections, speedLimit, gustsLimit);

    if (!isFlyable) {
      return FlyabilityLevel.unsafe;
    }

    // Flyable, but check if in caution zone (strong but within limits)
    final isStrong = windData.speedKmh > cautionWindSpeedKmh ||
                     (windData.gustsKmh != null && windData.gustsKmh! > cautionGustsKmh);

    return isStrong ? FlyabilityLevel.caution : FlyabilityLevel.safe;
  }

  /// Get color for a flyability level
  static Color getColorForLevel(FlyabilityLevel level) {
    switch (level) {
      case FlyabilityLevel.safe:
        return safeColor;
      case FlyabilityLevel.caution:
        return cautionColor;
      case FlyabilityLevel.unsafe:
        return unsafeColor;
      case FlyabilityLevel.unknown:
        return unknownColor;
    }
  }

  /// Get tooltip explanation for flyability level
  ///
  /// Provides human-readable explanation of why the conditions are
  /// safe/caution/unsafe, including specific wind values and direction info
  static String getTooltipForLevel({
    required FlyabilityLevel level,
    required WindData windData,
    required List<String> siteDirections,
    double? maxSpeed,
    double? maxGusts,
  }) {
    final speedLimit = maxSpeed ?? maxWindSpeedKmh;
    final gustsLimit = maxGusts ?? maxGustsKmh;

    switch (level) {
      case FlyabilityLevel.unknown:
        return 'No wind directions defined for this site';

      case FlyabilityLevel.safe:
        // Good conditions
        if (windData.speedKmh < 1.0) {
          return 'Light wind (${windData.speedKmh.toStringAsFixed(1)} km/h) - any direction OK';
        }
        return '${windData.speedKmh.toStringAsFixed(1)} km/h from ${windData.compassDirection} - good conditions';

      case FlyabilityLevel.caution:
        // Strong but flyable
        final gustsStr = windData.gustsKmh != null
            ? ' (gusts ${windData.gustsKmh!.toStringAsFixed(1)} km/h)'
            : '';
        return '${windData.speedKmh.toStringAsFixed(1)} km/h from ${windData.compassDirection}$gustsStr - strong winds, experienced pilots only';

      case FlyabilityLevel.unsafe:
        // Get detailed reason from WindData
        return windData.getFlyabilityReason(siteDirections, speedLimit, gustsLimit);
    }
  }

  /// Get short label for flyability level (for UI badges/chips)
  static String getLabelForLevel(FlyabilityLevel level) {
    switch (level) {
      case FlyabilityLevel.safe:
        return 'Safe';
      case FlyabilityLevel.caution:
        return 'Caution';
      case FlyabilityLevel.unsafe:
        return 'Unsafe';
      case FlyabilityLevel.unknown:
        return 'Unknown';
    }
  }
}

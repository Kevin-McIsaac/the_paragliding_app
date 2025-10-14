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
  /// Logic flow (clearest order):
  /// 1. Check if site has wind directions (unknown if empty)
  /// 2. Check direction match (unsafe if wrong direction)
  /// 3. Check speed thresholds in order:
  ///    - unsafe if speed/gusts > maxSpeed/maxGusts
  ///    - caution if speed/gusts > cautionSpeed/cautionGusts
  ///    - safe otherwise
  ///
  /// Returns:
  /// - FlyabilityLevel.safe: Good conditions for flying
  /// - FlyabilityLevel.caution: Flyable but strong (above caution thresholds)
  /// - FlyabilityLevel.unsafe: Too strong or wrong direction
  /// - FlyabilityLevel.unknown: No wind directions defined
  static FlyabilityLevel getFlyabilityLevel({
    required WindData windData,
    required List<String> siteDirections,
    double? maxSpeed,
    double? maxGusts,
    double? cautionSpeed,
    double? cautionGusts,
  }) {
    // Use provided limits or defaults
    final speedLimit = maxSpeed ?? maxWindSpeedKmh;
    final gustsLimit = maxGusts ?? maxGustsKmh;
    final cautionSpeedLimit = cautionSpeed ?? cautionWindSpeedKmh;
    final cautionGustsLimit = cautionGusts ?? cautionGustsKmh;

    // Step 1: No wind directions = unknown
    if (siteDirections.isEmpty) {
      return FlyabilityLevel.unknown;
    }

    // Step 2: Check direction match (only if wind speed > 1 km/h)
    if (windData.speedKmh > 1.0) {
      final directionMatches = windData.isDirectionFlyable(siteDirections);
      if (!directionMatches) {
        return FlyabilityLevel.unsafe;
      }
    }

    // Step 3: Check speed thresholds (direction is OK or wind is light)
    // Check if above unsafe threshold
    final speedUnsafe = windData.speedKmh > speedLimit;
    final gustsUnsafe = windData.gustsKmh != null && windData.gustsKmh! > gustsLimit;

    if (speedUnsafe || gustsUnsafe) {
      return FlyabilityLevel.unsafe;
    }

    // Check if above caution threshold
    final speedCaution = windData.speedKmh > cautionSpeedLimit;
    final gustsCaution = windData.gustsKmh != null && windData.gustsKmh! > cautionGustsLimit;

    if (speedCaution || gustsCaution) {
      return FlyabilityLevel.caution;
    }

    // Safe conditions
    return FlyabilityLevel.safe;
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
    double? cautionSpeed,
    double? cautionGusts,
  }) {
    final speedLimit = maxSpeed ?? maxWindSpeedKmh;
    final gustsLimit = maxGusts ?? maxGustsKmh;
    // Note: cautionSpeed and cautionGusts are not used in tooltip generation

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

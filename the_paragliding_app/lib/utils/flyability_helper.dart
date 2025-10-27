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
///
/// Flyability is determined by wind SPEED only (gusts are displayed but not used for colors)
/// Thresholds are loaded from user preferences via PreferencesHelper
class FlyabilityHelper {
  // Flyability colors (matching SiteMarkerUtils for consistency)
  static const Color safeColor = Colors.green;      // Safe to fly
  static const Color cautionColor = Colors.orange;  // Caution - strong winds
  static const Color unsafeColor = Colors.red;      // Unsafe conditions
  static const Color unknownColor = Colors.blue;    // Unknown/no data

  /// Determine flyability level based on weather conditions
  ///
  /// Logic flow (priority order - safety first):
  /// 1. Check for rain (unsafe if precipitation > 0)
  /// 2. Check if site has wind directions (unknown if empty)
  /// 3. Check direction match (unsafe if wrong direction)
  /// 4. Check speed thresholds in order:
  ///    - unsafe if speed > maxSpeed
  ///    - caution if speed > cautionSpeed
  ///    - safe otherwise
  ///
  /// Note: Wind gusts are displayed for information but NOT used for flyability determination
  ///
  /// Returns:
  /// - FlyabilityLevel.safe: Good conditions for flying
  /// - FlyabilityLevel.caution: Flyable but strong (above caution threshold)
  /// - FlyabilityLevel.unsafe: Rain, too strong, or wrong direction
  /// - FlyabilityLevel.unknown: No wind directions defined
  static FlyabilityLevel getFlyabilityLevel({
    required WindData windData,
    required List<String> siteDirections,
    required double maxSpeed,
    required double cautionSpeed,
  }) {
    // PRIORITY 1: Check for rain (paragliders can't fly in rain)
    if (windData.precipitationMm > 0) {
      return FlyabilityLevel.unsafe;
    }

    // Step 2: No wind directions = unknown
    if (siteDirections.isEmpty) {
      return FlyabilityLevel.unknown;
    }

    // Step 3: Check direction match (only if wind speed > 1 km/h)
    if (windData.speedKmh > 1.0) {
      final directionMatches = windData.isDirectionFlyable(siteDirections);
      if (!directionMatches) {
        return FlyabilityLevel.unsafe;
      }
    }

    // Step 4: Check speed thresholds (direction is OK or wind is light)
    // Check if above unsafe threshold
    if (windData.speedKmh > maxSpeed) {
      return FlyabilityLevel.unsafe;
    }

    // Check if above caution threshold
    if (windData.speedKmh > cautionSpeed) {
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
  /// safe/caution/unsafe, including rain, wind values and direction info
  static String getTooltipForLevel({
    required FlyabilityLevel level,
    required WindData windData,
    required List<String> siteDirections,
    required double maxSpeed,
  }) {
    switch (level) {
      case FlyabilityLevel.unknown:
        return 'No wind directions defined for this site';

      case FlyabilityLevel.safe:
        // Good conditions
        if (windData.speedKmh < 1.0) {
          return 'Light wind (${windData.speedKmh.toStringAsFixed(1)} km/h) - any direction OK';
        }
        final gustsStr = windData.gustsKmh != null
            ? ' (gusts ${windData.gustsKmh!.toStringAsFixed(1)} km/h)'
            : '';
        return '${windData.speedKmh.toStringAsFixed(1)} km/h from ${windData.compassDirectionWithAngle}$gustsStr - good conditions';

      case FlyabilityLevel.caution:
        // Strong but flyable
        final gustsStr = windData.gustsKmh != null
            ? ' (gusts ${windData.gustsKmh!.toStringAsFixed(1)} km/h)'
            : '';
        return '${windData.speedKmh.toStringAsFixed(1)} km/h from ${windData.compassDirectionWithAngle}$gustsStr - strong winds, experienced pilots only';

      case FlyabilityLevel.unsafe:
        // Check rain first (highest priority safety issue)
        if (windData.precipitationMm > 0) {
          return 'Unsafe - Rain (${windData.precipitationMm.toStringAsFixed(1)} mm/hr)';
        }

        // Get detailed wind-related reason from WindData
        return windData.getFlyabilityReason(siteDirections, maxSpeed);
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

  /// Check if a list of flyability levels contains consecutive occurrences of a target level
  ///
  /// Used for daily summaries to check if there are 2+ consecutive good/caution hours.
  /// Null entries in the list are skipped (treated as breaks in the sequence).
  ///
  /// Returns true if [consecutiveCount] or more consecutive occurrences of [targetLevel] are found.
  static bool hasConsecutiveLevels({
    required List<FlyabilityLevel?> levels,
    required FlyabilityLevel targetLevel,
    int consecutiveCount = 2,
  }) {
    if (levels.length < consecutiveCount) return false;

    for (int i = 0; i <= levels.length - consecutiveCount; i++) {
      // Check if we have consecutiveCount consecutive matches starting at index i
      bool allMatch = true;
      for (int j = 0; j < consecutiveCount; j++) {
        if (levels[i + j] != targetLevel) {
          allMatch = false;
          break;
        }
      }

      if (allMatch) return true;
    }

    return false;
  }
}

import 'dart:math';
import 'package:flutter/material.dart';
import '../../data/models/paragliding_site.dart';
import '../../data/models/wind_data.dart';
import '../../utils/flyability_helper.dart';
import '../../utils/flyability_constants.dart';

/// Reusable flyability cell widget displaying wind conditions with color-coded background
///
/// Shows:
/// - Color-coded background (green/yellow/red) based on flyability
/// - Wind arrow showing direction
/// - Wind speed in km/h
/// - Tooltip with detailed flyability information
class FlyabilityCellWidget extends StatelessWidget {
  final WindData windData;
  final ParaglidingSite site;
  final double maxWindSpeed;
  final double maxWindGusts;
  final double? cellSize;

  const FlyabilityCellWidget({
    super.key,
    required this.windData,
    required this.site,
    required this.maxWindSpeed,
    required this.maxWindGusts,
    this.cellSize,
  });

  @override
  Widget build(BuildContext context) {
    final size = cellSize ?? FlyabilityConstants.cellSize;

    // Calculate flyability using centralized helper
    final flyabilityLevel = FlyabilityHelper.getFlyabilityLevel(
      windData: windData,
      siteDirections: site.windDirections,
      maxSpeed: maxWindSpeed,
      maxGusts: maxWindGusts,
    );

    // Get color with full opacity
    final bgColor = FlyabilityHelper.getColorForLevel(flyabilityLevel);

    // Generate tooltip with detailed flyability explanation
    final tooltipMessage = FlyabilityHelper.getTooltipForLevel(
      level: flyabilityLevel,
      windData: windData,
      siteDirections: site.windDirections,
      maxSpeed: maxWindSpeed,
      maxGusts: maxWindGusts,
    );

    return Tooltip(
      message: tooltipMessage,
      child: Container(
        height: size,
        color: bgColor,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Wind arrow and speed with white color for contrast
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Using Transform.rotate for wind direction arrow
                Transform.rotate(
                  angle: windData.directionDegrees * (pi / 180), // Convert degrees to radians
                  child: const Icon(
                    Icons.arrow_upward,
                    size: 12,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '${windData.speedKmh.round()}',
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    height: 1.0,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

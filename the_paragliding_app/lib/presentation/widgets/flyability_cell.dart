import 'dart:math';
import 'package:flutter/material.dart';
import '../../data/models/paragliding_site.dart';
import '../../data/models/wind_data.dart';
import '../../data/models/wind_forecast.dart';
import '../../utils/flyability_helper.dart';
import '../../utils/flyability_constants.dart';

/// Reusable flyability cell widget displaying wind conditions with color-coded background
///
/// Shows:
/// - Color-coded background (green/yellow/red) based on flyability
/// - Wind arrow showing direction
/// - Wind speed and gusts in km/h (format: "speed-gusts")
/// - Tooltip with detailed flyability information
class FlyabilityCellWidget extends StatelessWidget {
  final WindData windData;
  final ParaglidingSite site;
  final double maxWindSpeed;
  final double cautionWindSpeed;
  final double? cellSize;
  final WindForecast? forecast; // Optional forecast for daylight times

  const FlyabilityCellWidget({
    super.key,
    required this.windData,
    required this.site,
    required this.maxWindSpeed,
    required this.cautionWindSpeed,
    this.cellSize,
    this.forecast,
  });

  @override
  Widget build(BuildContext context) {
    final size = cellSize ?? FlyabilityConstants.cellSize;

    // Calculate flyability using centralized helper
    final flyabilityLevel = FlyabilityHelper.getFlyabilityLevel(
      windData: windData,
      siteDirections: site.windDirections,
      maxSpeed: maxWindSpeed,
      cautionSpeed: cautionWindSpeed,
    );

    // Get color with full opacity
    final bgColor = FlyabilityHelper.getColorForLevel(flyabilityLevel);

    // Generate tooltip with detailed flyability explanation
    final tooltipMessage = FlyabilityHelper.getTooltipForLevel(
      level: flyabilityLevel,
      windData: windData,
      siteDirections: site.windDirections,
      maxSpeed: maxWindSpeed,
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
                // Wind arrow points where wind is blowing TO (meteorological convention)
                // Wind direction = FROM direction, so add 180° to point downwind
                Transform.rotate(
                  angle: (windData.directionDegrees + 180) * (pi / 180),
                  child: const Icon(
                    Icons.arrow_upward,
                    size: 12,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  windData.gustsKmh != null
                      ? '${windData.speedKmh.round()}-${windData.gustsKmh!.round()}'
                      : '${windData.speedKmh.round()}',
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

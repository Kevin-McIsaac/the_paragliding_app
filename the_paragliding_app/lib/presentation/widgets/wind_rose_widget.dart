import 'package:flutter/material.dart';
import 'wind_rose_painter.dart';

class WindRoseWidget extends StatelessWidget {
  final List<String> launchableDirections;
  final double size;
  final double? windSpeed; // Wind speed in km/h
  final double? windDirection; // Wind direction in degrees (0 = North)
  final Color? centerDotColor; // Optional color for center dot based on flyability
  final String? centerDotTooltip; // Optional tooltip for center dot showing flyability status

  const WindRoseWidget({
    super.key,
    required this.launchableDirections,
    this.size = 250.0,
    this.windSpeed,
    this.windDirection,
    this.centerDotColor,
    this.centerDotTooltip,
  });

  @override
  Widget build(BuildContext context) {
    final windRose = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: CustomPaint(
        size: Size(size, size),
        painter: WindRosePainter(
          launchableDirections: launchableDirections,
          theme: Theme.of(context),
          windSpeed: windSpeed,
          windDirection: windDirection,
          centerDotColor: centerDotColor,
        ),
        isComplex: true,
        willChange: false,
      ),
    );

    // Wrap in tooltip if provided
    if (centerDotTooltip != null && centerDotTooltip!.isNotEmpty) {
      return Tooltip(
        message: centerDotTooltip!,
        child: windRose,
      );
    }

    return windRose;
  }
}
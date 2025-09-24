import 'package:flutter/material.dart';
import 'wind_rose_painter.dart';
import '../../services/logging_service.dart';

class WindRoseWidget extends StatelessWidget {
  final List<String> launchableDirections;
  final double size;
  final double? windSpeed; // Wind speed in km/h
  final double? windDirection; // Wind direction in degrees (0 = North)

  const WindRoseWidget({
    super.key,
    required this.launchableDirections,
    this.size = 250.0,
    this.windSpeed,
    this.windDirection,
  });

  @override
  Widget build(BuildContext context) {
    LoggingService.debug('WindRoseWidget building with directions: $launchableDirections');

    return Container(
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
        ),
      ),
    );
  }
}
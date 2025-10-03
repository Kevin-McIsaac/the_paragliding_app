import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../data/models/weather_station.dart';
import '../../data/models/wind_data.dart';
import 'package:intl/intl.dart';

/// Weather station marker showing wind direction and speed with barbed arrow
class WeatherStationMarker extends StatelessWidget {
  final WeatherStation station;
  final double maxWindSpeed;
  final double maxWindGusts;
  final VoidCallback? onTap;

  static const double markerSize = 40.0;

  const WeatherStationMarker({
    super.key,
    required this.station,
    required this.maxWindSpeed,
    required this.maxWindGusts,
    this.onTap,
  });

  bool get _isWindGood {
    if (station.windData == null) return false;
    final windData = station.windData!;
    return windData.speedKmh <= maxWindSpeed && windData.gustsKmh <= maxWindGusts;
  }

  Color get _markerColor => _isWindGood ? Colors.green : Colors.red;

  @override
  Widget build(BuildContext context) {
    final windData = station.windData;
    final tooltipText = windData != null
        ? '${station.name ?? station.id}\n${windData.speedKmh.toStringAsFixed(0)}-${windData.gustsKmh.toStringAsFixed(0)} km/h from ${windData.directionDegrees.toStringAsFixed(0)}°'
        : '${station.name ?? station.id}\nNo wind data';

    return Tooltip(
      message: tooltipText,
      textStyle: const TextStyle(color: Colors.white, fontSize: 11),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white24),
      ),
      child: GestureDetector(
        onTap: onTap ?? () => _showStationDialog(context),
        child: SizedBox(
          width: markerSize,
          height: markerSize,
          child: CustomPaint(
            painter: _WeatherStationPainter(
              windData: station.windData,
              color: _markerColor,
            ),
          ),
        ),
      ),
    );
  }

  void _showStationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _WeatherStationDialog(
        station: station,
        maxWindSpeed: maxWindSpeed,
        maxWindGusts: maxWindGusts,
      ),
    );
  }
}

/// Custom painter for weather station marker with barbed arrow
class _WeatherStationPainter extends CustomPainter {
  final WindData? windData;
  final Color color;

  _WeatherStationPainter({
    required this.windData,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Circle outline (NOAA style)
    final circleRadius = 6.0;

    // Draw circle outline only (no fill)
    final circlePaint = Paint()
      ..color = Colors.grey[800]!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawCircle(center, circleRadius, circlePaint);

    // Draw wind barb if wind data is available
    if (windData != null) {
      _drawWindBarb(canvas, center, circleRadius, windData!);
    }
  }

  void _drawWindBarb(Canvas canvas, Offset center, double circleRadius, WindData windData) {
    final barbPaint = Paint()
      ..color = Colors.grey[800]!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    // Convert wind direction to radians (meteorological convention: direction FROM)
    // Rotate so north (0°) points up
    final angle = (windData.directionDegrees - 90) * math.pi / 180;

    // Shaft starts at circle edge and extends outward
    final shaftStart = Offset(
      center.dx + circleRadius * math.cos(angle),
      center.dy + circleRadius * math.sin(angle),
    );

    final shaftLength = 25.0;
    final shaftEnd = Offset(
      shaftStart.dx + shaftLength * math.cos(angle),
      shaftStart.dy + shaftLength * math.sin(angle),
    );

    // Draw main shaft
    canvas.drawLine(shaftStart, shaftEnd, barbPaint);

    // Draw speed barbs
    _drawSpeedBarbs(canvas, shaftEnd, angle, windData.speedKmh, barbPaint);
  }

  void _drawSpeedBarbs(Canvas canvas, Offset shaftEnd, double angle, double speedKmh, Paint paint) {
    // Wind barbs: each full barb = 10 km/h, half barb = 5 km/h
    final fullBarbs = (speedKmh / 10).floor();
    final halfBarb = (speedKmh % 10) >= 5;

    final barbLength = 10.0;  // Longer barbs (more prominent)
    final barbSpacing = 5.0;  // Spacing between barbs
    final barbAngle = 60 * math.pi / 180; // 60 degrees from shaft

    // Start from the end of the shaft and work backwards
    double distanceFromEnd = 2.0; // Small offset from shaft end

    // Draw half barb first (closest to end, like NOAA standard)
    if (halfBarb && fullBarbs < 5) {
      final barbBase = Offset(
        shaftEnd.dx - distanceFromEnd * math.cos(angle),
        shaftEnd.dy - distanceFromEnd * math.sin(angle),
      );
      final barbTip = Offset(
        barbBase.dx + (barbLength / 2) * math.cos(angle + barbAngle),
        barbBase.dy + (barbLength / 2) * math.sin(angle + barbAngle),
      );
      canvas.drawLine(barbBase, barbTip, paint);
      distanceFromEnd += barbSpacing;
    }

    // Draw full barbs (working backwards from end)
    for (int i = 0; i < fullBarbs && i < 5; i++) {
      final barbBase = Offset(
        shaftEnd.dx - distanceFromEnd * math.cos(angle),
        shaftEnd.dy - distanceFromEnd * math.sin(angle),
      );
      final barbTip = Offset(
        barbBase.dx + barbLength * math.cos(angle + barbAngle),
        barbBase.dy + barbLength * math.sin(angle + barbAngle),
      );
      canvas.drawLine(barbBase, barbTip, paint);
      distanceFromEnd += barbSpacing;
    }
  }

  @override
  bool shouldRepaint(_WeatherStationPainter oldDelegate) {
    return oldDelegate.windData != windData || oldDelegate.color != color;
  }
}

/// Dialog showing detailed weather station information
class _WeatherStationDialog extends StatelessWidget {
  final WeatherStation station;
  final double maxWindSpeed;
  final double maxWindGusts;

  const _WeatherStationDialog({
    required this.station,
    required this.maxWindSpeed,
    required this.maxWindGusts,
  });

  String _getTimeAgo(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  bool get _isWindGood {
    if (station.windData == null) return false;
    final windData = station.windData!;
    return windData.speedKmh <= maxWindSpeed && windData.gustsKmh <= maxWindGusts;
  }

  @override
  Widget build(BuildContext context) {
    final windData = station.windData;

    return Dialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Compact header with station name and close button
            Row(
              children: [
                const Icon(Icons.cloud, color: Colors.blue, size: 20),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${station.name ?? station.id} (${station.id})',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70, size: 18),
                  onPressed: () => Navigator.of(context).pop(),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Wind data - prominent display with barb graphic
            if (windData != null) ...[
              // Wind barb graphic and speed/direction
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Wind barb visualization
                  SizedBox(
                    width: 60,
                    height: 60,
                    child: CustomPaint(
                      painter: _WeatherStationPainter(
                        windData: windData,
                        color: _isWindGood ? Colors.green : Colors.red,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Wind info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Speed range with status indicator
                        Row(
                          children: [
                            Text(
                              '${windData.speedKmh.toStringAsFixed(0)}-${windData.gustsKmh.toStringAsFixed(0)} km/h',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              _isWindGood ? Icons.check_circle : Icons.warning,
                              color: _isWindGood ? Colors.green : Colors.red,
                              size: 18,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'from ${windData.compassDirection} (${windData.directionDegrees.toStringAsFixed(0)}°)',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _getTimeAgo(windData.timestamp),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white54,
                          ),
                        ),
                        const SizedBox(height: 6),
                        // Location and elevation on same line with icons
                        Row(
                          children: [
                            const Icon(Icons.location_on, size: 12, color: Colors.white54),
                            const SizedBox(width: 3),
                            Text(
                              '${station.latitude.toStringAsFixed(2)}°, ${station.longitude.toStringAsFixed(2)}°',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white54,
                              ),
                            ),
                            if (station.elevation != null) ...[
                              const SizedBox(width: 8),
                              const Icon(Icons.terrain, size: 12, color: Colors.white54),
                              const SizedBox(width: 3),
                              Text(
                                '${station.elevation!.toStringAsFixed(0)}m',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.white54,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ] else ...[
              const Text(
                'No wind data available',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
      ),
    );
  }
}

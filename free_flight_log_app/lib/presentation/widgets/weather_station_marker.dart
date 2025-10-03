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

  static const double markerSize = 30.0;

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
    return GestureDetector(
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
    final radius = size.width / 2;

    // Draw circle background
    final circlePaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius, circlePaint);

    // Draw circle border
    final borderPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawCircle(center, radius, borderPaint);

    // Draw wind arrow if wind data is available
    if (windData != null) {
      _drawWindArrow(canvas, center, radius, windData!);
    }
  }

  void _drawWindArrow(Canvas canvas, Offset center, double radius, WindData windData) {
    final arrowPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    // Convert wind direction to radians (meteorological convention: direction FROM)
    // Rotate so north (0°) points up
    final angle = (windData.directionDegrees - 90) * math.pi / 180;

    // Arrow shaft (from center to edge)
    final arrowLength = radius * 0.7;
    final arrowEnd = Offset(
      center.dx + arrowLength * math.cos(angle),
      center.dy + arrowLength * math.sin(angle),
    );

    // Draw main arrow shaft
    canvas.drawLine(center, arrowEnd, arrowPaint);

    // Draw arrowhead
    final headLength = radius * 0.2;
    final headAngle = 25 * math.pi / 180; // 25 degree angle for arrowhead

    final headLeft = Offset(
      arrowEnd.dx - headLength * math.cos(angle - headAngle),
      arrowEnd.dy - headLength * math.sin(angle - headAngle),
    );
    final headRight = Offset(
      arrowEnd.dx - headLength * math.cos(angle + headAngle),
      arrowEnd.dy - headLength * math.sin(angle + headAngle),
    );

    canvas.drawLine(arrowEnd, headLeft, arrowPaint);
    canvas.drawLine(arrowEnd, headRight, arrowPaint);

    // Draw wind barbs based on speed (traditional meteorology style)
    _drawWindBarbs(canvas, center, angle, windData.speedKmh, arrowPaint);
  }

  void _drawWindBarbs(Canvas canvas, Offset center, double angle, double speedKmh, Paint paint) {
    // Wind barbs: each full barb = 10 km/h, half barb = 5 km/h
    final fullBarbs = (speedKmh / 10).floor();
    final halfBarb = (speedKmh % 10) >= 5;

    final barbLength = 6.0;
    final barbSpacing = 4.0;
    final barbAngle = 60 * math.pi / 180; // 60 degrees from shaft

    double distanceFromCenter = 8.0; // Start barbs slightly away from center

    // Draw full barbs
    for (int i = 0; i < fullBarbs && i < 5; i++) {
      final barbBase = Offset(
        center.dx + distanceFromCenter * math.cos(angle),
        center.dy + distanceFromCenter * math.sin(angle),
      );
      final barbTip = Offset(
        barbBase.dx + barbLength * math.cos(angle + barbAngle),
        barbBase.dy + barbLength * math.sin(angle + barbAngle),
      );
      canvas.drawLine(barbBase, barbTip, paint);
      distanceFromCenter += barbSpacing;
    }

    // Draw half barb
    if (halfBarb && fullBarbs < 5) {
      final barbBase = Offset(
        center.dx + distanceFromCenter * math.cos(angle),
        center.dy + distanceFromCenter * math.sin(angle),
      );
      final barbTip = Offset(
        barbBase.dx + (barbLength / 2) * math.cos(angle + barbAngle),
        barbBase.dy + (barbLength / 2) * math.sin(angle + barbAngle),
      );
      canvas.drawLine(barbBase, barbTip, paint);
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

  @override
  Widget build(BuildContext context) {
    final windData = station.windData;

    return Dialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.cloud, color: Colors.blue, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    station.name ?? 'Station ${station.id}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Station details
            _buildInfoRow('Station ID', station.id),
            _buildInfoRow('Location', '${station.latitude.toStringAsFixed(4)}, ${station.longitude.toStringAsFixed(4)}'),
            if (station.elevation != null)
              _buildInfoRow('Elevation', '${station.elevation!.toStringAsFixed(0)} m'),

            const Divider(color: Colors.white24, height: 24),

            // Wind data
            if (windData != null) ...[
              Text(
                'Wind Conditions',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 12),
              _buildWindInfo('Speed', '${windData.speedKmh.toStringAsFixed(1)} km/h', windData.speedKmh <= maxWindSpeed),
              _buildWindInfo('Gusts', '${windData.gustsKmh.toStringAsFixed(1)} km/h', windData.gustsKmh <= maxWindGusts),
              _buildInfoRow('Direction', '${windData.directionDegrees.toStringAsFixed(0)}° (${windData.compassDirection})'),
              _buildInfoRow('Time', DateFormat('MMM d, h:mm a').format(windData.timestamp)),
            ] else ...[
              const Text(
                'No wind data available',
                style: TextStyle(color: Colors.white54, fontSize: 14),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWindInfo(String label, String value, bool isGood) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  isGood ? Icons.check_circle : Icons.warning,
                  color: isGood ? Colors.green : Colors.red,
                  size: 16,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

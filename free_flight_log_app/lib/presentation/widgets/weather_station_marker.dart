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

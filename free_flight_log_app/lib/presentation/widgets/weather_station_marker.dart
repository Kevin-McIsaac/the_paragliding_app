import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../data/models/weather_station.dart';
import '../../data/models/weather_station_source.dart';
import '../../data/models/wind_data.dart';
import '../../services/weather_providers/weather_station_provider_registry.dart';
import 'package:url_launcher/url_launcher.dart';

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

  @override
  Widget build(BuildContext context) {
    final windData = station.windData;
    final String tooltipText;
    if (windData != null) {
      // Show "CALM" for winds < 1 km/h (direction meaningless when no wind)
      if (windData.speedKmh < 1.0) {
        tooltipText = '${station.name ?? station.id}\nCALM';
      } else {
        final gustsStr = windData.gustsKmh != null
            ? '-${windData.gustsKmh!.toStringAsFixed(0)}'
            : '';
        tooltipText = '${station.name ?? station.id}\n${windData.speedKmh.toStringAsFixed(0)}$gustsStr km/h from ${windData.directionDegrees.toStringAsFixed(0)}°';
      }
    } else {
      tooltipText = '${station.name ?? station.id}\nNo wind data';
    }

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

  _WeatherStationPainter({
    required this.windData,
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

    // Draw wind barb only if wind speed >= 1 km/h (calm winds show circle only)
    final data = windData;
    if (data != null && data.speedKmh >= 1.0) {
      _drawWindBarb(canvas, center, circleRadius, data);
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
    // Round to nearest 5 km/h (meteorological standard)
    final roundedSpeed = (speedKmh / 5).round() * 5.0;

    // Wind barbs: each full barb = 10 km/h, half barb = 5 km/h
    final fullBarbs = (roundedSpeed / 10).floor();
    final halfBarb = (roundedSpeed % 10) >= 5;

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
    return oldDelegate.windData != windData;
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

  @override
  Widget build(BuildContext context) {
    final windData = station.windData;

    return Dialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 350),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header: Station name and close button
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${station.name ?? station.id} (${station.id})',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18, color: Colors.white70),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Wind data section
              if (windData != null) ...[
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Wind barb
                      SizedBox(
                        width: 50,
                        child: CustomPaint(
                          painter: _WeatherStationPainter(
                            windData: windData,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Wind info
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            // Wind speed and direction
                            Text(
                              () {
                                // Show "CALM" for winds < 1 km/h
                                if (windData.speedKmh < 1.0) {
                                  return 'CALM';
                                }
                                final gustsStr = windData.gustsKmh != null
                                    ? '-${windData.gustsKmh!.toStringAsFixed(0)}'
                                    : '';
                                return '${windData.speedKmh.toStringAsFixed(0)}$gustsStr km/h from ${windData.compassDirection} (${windData.directionDegrees.toStringAsFixed(0)}°)';
                              }(),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Colors.white70,
                              ),
                            ),
                            const SizedBox(height: 8),
                            // Time and type on first line
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                _buildInfoChip(Icons.access_time, _getTimeAgo(windData.timestamp)),
                                if (station.observationType != null)
                                  _buildInfoChip(Icons.sensors, station.observationType!),
                              ],
                            ),
                            const SizedBox(height: 4),
                            // Location and elevation on second line
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                _buildInfoChip(Icons.location_on, '${station.latitude.toStringAsFixed(2)}°, ${station.longitude.toStringAsFixed(2)}°'),
                                if (station.elevation != null)
                                  _buildInfoChip(Icons.terrain, '${station.elevation!.toStringAsFixed(0)}m'),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                const Text(
                  'No wind data available',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ],
              const SizedBox(height: 12),
              // Attribution
              _buildAttribution(station),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: Colors.white54),
        const SizedBox(width: 3),
        Text(
          text,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.white54,
          ),
        ),
      ],
    );
  }

  Widget _buildAttribution(WeatherStation station) {
    final provider = WeatherStationProviderRegistry.getProvider(station.source);

    // For METAR stations, link to specific station observation page
    final url = station.source == WeatherStationSource.metar
        ? 'https://aviationweather.gov/data/metar/?decoded=1&ids=${station.id}'
        : provider.attributionUrl;

    return TextButton(
      onPressed: () async {
        await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        );
      },
      style: TextButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        'Data: ${provider.attributionName}',
        style: const TextStyle(
          fontSize: 10,
          color: Colors.white38,
        ),
      ),
    );
  }
}

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Reusable widget for displaying user location on maps
/// Provides consistent styling across all map implementations
class UserLocationMarker extends StatelessWidget {
  final LatLng location;
  final double accuracy; // Accuracy in meters
  final Color color;
  final bool showAccuracyCircle;
  final bool animate;
  final VoidCallback? onTap;

  const UserLocationMarker({
    super.key,
    required this.location,
    this.accuracy = 10.0,
    this.color = Colors.blue,
    this.showAccuracyCircle = true,
    this.animate = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MarkerLayer(
      markers: [
        Marker(
          point: location,
          width: 80,
          height: 80,
          child: GestureDetector(
            onTap: onTap,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Accuracy circle
                if (showAccuracyCircle)
                  AnimatedContainer(
                    duration: animate
                        ? const Duration(milliseconds: 800)
                        : Duration.zero,
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withValues(alpha: 0.15),
                      border: Border.all(
                        color: color.withValues(alpha: 0.5),
                        width: 2,
                      ),
                    ),
                  ),
                // Center dot
                AnimatedContainer(
                  duration: animate
                      ? const Duration(milliseconds: 300)
                      : Duration.zero,
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                    border: Border.all(
                      color: Colors.white,
                      width: 3,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Widget to display user location with heading/bearing indicator
class UserLocationWithHeading extends StatelessWidget {
  final LatLng location;
  final double? heading; // Heading in degrees (0-360)
  final Color color;
  final VoidCallback? onTap;

  const UserLocationWithHeading({
    super.key,
    required this.location,
    this.heading,
    this.color = Colors.blue,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MarkerLayer(
      markers: [
        Marker(
          point: location,
          width: 40,
          height: 40,
          child: GestureDetector(
            onTap: onTap,
            child: Transform.rotate(
              angle: heading != null ? (heading! * 3.14159 / 180) : 0,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Direction indicator
                  if (heading != null)
                    CustomPaint(
                      size: const Size(40, 40),
                      painter: _DirectionPainter(color: color),
                    ),
                  // Center dot
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color,
                      border: Border.all(
                        color: Colors.white,
                        width: 2,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 3,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Custom painter for direction indicator
class _DirectionPainter extends CustomPainter {
  final Color color;

  _DirectionPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.4)
      ..style = PaintingStyle.fill;

    final path = ui.Path();
    final center = Offset(size.width / 2, size.height / 2);

    // Draw triangle pointing upward (north)
    path.moveTo(center.dx, center.dy - size.height / 2); // Top point
    path.lineTo(center.dx - 6, center.dy + 5); // Bottom left
    path.lineTo(center.dx + 6, center.dy + 5); // Bottom right
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Builder widget for user location that handles null locations gracefully
class UserLocationBuilder extends StatelessWidget {
  final LatLng? location;
  final Widget Function(BuildContext context, LatLng location) builder;
  final Widget? placeholder;

  const UserLocationBuilder({
    super.key,
    required this.location,
    required this.builder,
    this.placeholder,
  });

  @override
  Widget build(BuildContext context) {
    if (location == null) {
      return placeholder ?? const SizedBox.shrink();
    }
    return builder(context, location!);
  }
}

/// Legend item for user location
class UserLocationLegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const UserLocationLegendItem({
    super.key,
    this.color = Colors.blue,
    this.label = 'Your Location',
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.3),
            border: Border.all(color: color, width: 2),
          ),
          child: Center(
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w500,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}
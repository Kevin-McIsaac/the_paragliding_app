import 'package:flutter/material.dart';
import 'dart:math';

class WindRosePainter extends CustomPainter {
  final List<String> launchableDirections;
  final ThemeData theme;
  final double? windSpeed; // Wind speed in km/h
  final double? windDirection; // Wind direction in degrees (0 = North)
  final Color? centerDotColor; // Optional color for center dot based on flyability

  // 8 directions for sectors (all directions for wind display)
  static const List<String> _allDirections = [
    'N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'
  ];

  // 4 cardinal directions for labels (cleaner display, especially at small sizes)
  static const List<String> _labelDirections = [
    'N', 'E', 'S', 'W'
  ];

  // Direction angles in degrees (North = 0°, clockwise)
  static const Map<String, double> _directionAngles = {
    'N': 0,
    'NE': 45,
    'E': 90,
    'SE': 135,
    'S': 180,
    'SW': 225,
    'W': 270,
    'NW': 315,
  };

  WindRosePainter({
    required this.launchableDirections,
    required this.theme,
    this.windSpeed,
    this.windDirection,
    this.centerDotColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - (size.width * 0.12); // Proportional margin (12% of size)

    // Debug logging removed to reduce noise

    // Draw background circle
    _drawBackground(canvas, center, radius);

    // Draw wind sectors
    _drawWindSectors(canvas, center, radius);

    // Draw compass ring and labels
    _drawCompassRing(canvas, center, radius);
    _drawDirectionLabels(canvas, center, radius);

    // Draw wind direction arrow if wind data available
    if (windDirection != null) {
      _drawWindArrow(canvas, center, radius);
    }

    // Draw center point
    _drawCenterPoint(canvas, center, radius);

    // Draw wind speed text if wind data available
    if (windSpeed != null) {
      _drawWindSpeedText(canvas, center, radius);
    }
  }

  void _drawBackground(Canvas canvas, Offset center, double radius) {
    final backgroundPaint = Paint()
      ..color = theme.colorScheme.surface
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius, backgroundPaint);
  }

  void _drawWindSectors(Canvas canvas, Offset center, double radius) {
    final gap = radius * 0.00; // Gap size proportional to radius (0%)
    final centerDotRadius = radius * 0.45; // Center dot scales with radius (45%)
    final sectorOuterRadius = radius - gap; // Outer edge of wedges (gap from outer ring)
    final sectorInnerRadius = centerDotRadius + gap; // Inner edge of wedges (gap from center dot)

    for (final direction in _allDirections) {
      final isLaunchable = launchableDirections.contains(direction);
      final angle = _directionAngles[direction]!;

      // Each sector spans 45 degrees (360° / 8 directions)
      // Subtract 90° to align with label coordinate system (N at top)
      final startAngle = _degreesToRadians(angle - 90 - 22.5);
      final sweepAngle = _degreesToRadians(45);

      final sectorPaint = Paint()
        ..color = isLaunchable
            ? Colors.green.withValues(alpha: 0.3)
            : Colors.grey.withValues(alpha: 0.1)
        ..style = PaintingStyle.fill;

      // Draw sector as a donut path (with equal inner and outer gaps)
      final path = Path();

      // Outer arc
      path.arcTo(
        Rect.fromCircle(center: center, radius: sectorOuterRadius),
        startAngle,
        sweepAngle,
        false,
      );

      // Inner arc (reverse direction to create donut with equal gaps)
      path.arcTo(
        Rect.fromCircle(center: center, radius: sectorInnerRadius),
        startAngle + sweepAngle,
        -sweepAngle,
        false,
      );

      path.close();

      canvas.drawPath(path, sectorPaint);

      // Draw sector outline
      final outlinePaint = Paint()
        ..color = isLaunchable
            ? Colors.green.withValues(alpha: 0.6)
            : Colors.grey.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;

      canvas.drawPath(path, outlinePaint);
    }
  }

  void _drawCompassRing(Canvas canvas, Offset center, double radius) {
    final ringPaint = Paint()
      ..color = theme.colorScheme.outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawCircle(center, radius, ringPaint);
  }

  void _drawDirectionLabels(Canvas canvas, Offset center, double radius) {
    final labelRadius = radius + (radius * 0.30); // Proportional label offset (30% of radius)

    // Only draw labels for cardinal directions (N, E, S, W) for cleaner display
    for (final direction in _labelDirections) {
      final angle = _directionAngles[direction]!;
      final isLaunchable = launchableDirections.contains(direction);

      // Calculate label position
      final radians = _degreesToRadians(angle - 90); // Subtract 90° to start from top
      final x = center.dx + labelRadius * cos(radians);
      final y = center.dy + labelRadius * sin(radians);

      // Create text painter with smaller font size
      final textPainter = TextPainter(
        text: TextSpan(
          text: direction,
          style: theme.textTheme.labelSmall?.copyWith(
            fontSize: 11,  // Smaller font for cardinal directions
            color: isLaunchable
                ? Colors.green.shade700
                : theme.colorScheme.onSurface.withValues(alpha: 0.7),
            fontWeight: isLaunchable ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        textDirection: TextDirection.ltr,
      );

      textPainter.layout();

      // Center the text on the calculated position
      final offset = Offset(
        x - textPainter.width / 2,
        y - textPainter.height / 2,
      );

      textPainter.paint(canvas, offset);
    }
  }

  void _drawCenterPoint(Canvas canvas, Offset center, double radius) {
    final centerDotRadius = radius * 0.45; // Scale with radius (45%)

    // Use provided color from parent (which uses SiteMarkerPresentation logic)
    // If no color provided, fall back to theme default
    final centerColor = centerDotColor ?? theme.colorScheme.primary;

    final centerPaint = Paint()
      ..color = centerColor
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, centerDotRadius, centerPaint);
  }

  void _drawWindArrow(Canvas canvas, Offset center, double radius) {
    final gap = radius * 0.00; // Proportional gap (0%)
    final centerDotRadius = radius * 0.45; // Match other methods (45%)
    final arrowStartRadius = centerDotRadius; // Start from center
    final arrowEndRadius = radius - gap; // End at outer edge

    // Convert wind direction to radians
    // Wind direction from API is "FROM" direction (meteorologically correct)
    // Subtract 90° to align with coordinate system (North at top)
    final arrowAngle = _degreesToRadians(windDirection! - 90);

    // Calculate arrow start (outer edge) and end points (center)
    // Arrow points FROM edge INWARD to show where wind comes from
    final startX = center.dx + arrowEndRadius * cos(arrowAngle);
    final startY = center.dy + arrowEndRadius * sin(arrowAngle);
    final endX = center.dx + arrowStartRadius * cos(arrowAngle);
    final endY = center.dy + arrowStartRadius * sin(arrowAngle);

    final arrowPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.08  // Scale with radius (8% - 2x thicker)
      ..strokeCap = StrokeCap.round;

    // Draw arrow line from outer edge toward center
    canvas.drawLine(
      Offset(startX, startY),
      Offset(endX, endY),
      arrowPaint,
    );

    // Draw arrowhead pointing inward (showing wind source direction)
    final arrowheadLength = radius * 0.20;  // Scale with radius (20% - bigger)
    final arrowheadAngle = 30 * pi / 180; // Wider angle for bigger arrowhead

    // Arrowhead at the END point (center), pointing inward
    // Add instead of subtract to reverse arrowhead direction
    final arrowheadLeft = Offset(
      endX + arrowheadLength * cos(arrowAngle - arrowheadAngle),
      endY + arrowheadLength * sin(arrowAngle - arrowheadAngle),
    );

    final arrowheadRight = Offset(
      endX + arrowheadLength * cos(arrowAngle + arrowheadAngle),
      endY + arrowheadLength * sin(arrowAngle + arrowheadAngle),
    );

    canvas.drawLine(Offset(endX, endY), arrowheadLeft, arrowPaint);
    canvas.drawLine(Offset(endX, endY), arrowheadRight, arrowPaint);
  }

  void _drawWindSpeedText(Canvas canvas, Offset center, double radius) {
    // Use proportional center dot radius (45%)
    final centerDotRadius = radius * 0.45;
    // Make font size relative to center dot
    final speedFontSize = centerDotRadius * 1.0; // Scale text with center dot

    // Draw speed number (centered)
    final speedTextPainter = TextPainter(
      text: TextSpan(
        text: windSpeed!.toStringAsFixed(0),
        style: TextStyle(
          color: Colors.white,
          fontSize: speedFontSize,
          fontWeight: FontWeight.w600,  // Reduced from w900 to w600
        ),
      ),
      textDirection: TextDirection.ltr,
    );

    speedTextPainter.layout();

    // Center the speed text perfectly in the circle
    final speedOffset = Offset(
      center.dx - speedTextPainter.width / 2,
      center.dy - speedTextPainter.height / 2,
    );

    speedTextPainter.paint(canvas, speedOffset);
  }

  double _degreesToRadians(double degrees) {
    return degrees * pi / 180;
  }

  @override
  bool shouldRepaint(WindRosePainter oldDelegate) {
    return launchableDirections != oldDelegate.launchableDirections ||
           theme != oldDelegate.theme ||
           windSpeed != oldDelegate.windSpeed ||
           windDirection != oldDelegate.windDirection ||
           centerDotColor != oldDelegate.centerDotColor;
  }
}
import 'package:flutter/material.dart';

/// Mockup version of the filter dialog showing the new 3-column layout
class MapFilterDialogMockup extends StatefulWidget {
  const MapFilterDialogMockup({super.key});

  @override
  State<MapFilterDialogMockup> createState() => _MapFilterDialogMockupState();
}

class _MapFilterDialogMockupState extends State<MapFilterDialogMockup> {
  bool _sitesEnabled = true;
  double _maxAltitudeFt = 15000.0;

  // Sample data for mockup
  final Map<String, bool> _airspaceTypes = {
    'CTR': true,
    'TMA': true,
    'CTA': false,
    'D': true,
    'R': false,
    'P': true,
    'FIR': false,
    '?': false, // Changed from 'Unknown' to '?' to fix overflow
  };

  final Map<String, bool> _icaoClasses = {
    'A': true,
    'B': true,
    'C': false,
    'D': true,
    'E': false,
    'F': false,
    'G': false,
    'None': false,
  };

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Transparent overlay to capture taps
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            color: Colors.transparent,
            width: double.infinity,
            height: double.infinity,
          ),
        ),
        // Positioned dropdown
        Positioned(
          top: 130, // Position under the filter button (approximate)
          right: 20,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 280,
              constraints: const BoxConstraints(maxHeight: 400),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: const BoxDecoration(
                color: Color(0xFF2A2A2A),
                borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.tune, color: Colors.blue, size: 18),
                  const SizedBox(width: 8),
                  const Text(
                    'Filter Map',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),

            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Sites toggle section
                    _buildSitesSection(),
                    const SizedBox(height: 16),

                    // Three-column layout: Types | Classes | Altitude
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Types column
                        Expanded(
                          flex: 1,
                          child: _buildTypesColumn(),
                        ),
                        const SizedBox(width: 6),

                        // Classes column
                        Expanded(
                          flex: 1,
                          child: _buildClassesColumn(),
                        ),
                        const SizedBox(width: 6),

                        // Altitude column
                        Expanded(
                          flex: 1,
                          child: _buildAltitudeColumn(),
                        ),
                      ],
                    ),
                  ],
                ),
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

  Widget _buildSitesSection() {
    return InkWell(
      onTap: () => setState(() => _sitesEnabled = !_sitesEnabled),
      borderRadius: BorderRadius.circular(4),
      child: Row(
        children: [
          Transform.scale(
            scale: 0.8,
            child: Checkbox(
              value: _sitesEnabled,
              onChanged: (value) => setState(() => _sitesEnabled = value ?? true),
              activeColor: Colors.blue,
              checkColor: Colors.white,
              side: const BorderSide(color: Colors.white54),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 4),
          const Text(
            'Show Sites',
            style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildTypesColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Types',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        ..._airspaceTypes.entries.map((entry) {
          return InkWell(
            onTap: () {
              setState(() {
                _airspaceTypes[entry.key] = !entry.value;
              });
            },
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 18,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Transform.scale(
                    scale: 0.6,
                    child: Checkbox(
                      value: entry.value,
                      onChanged: (value) {
                        setState(() {
                          _airspaceTypes[entry.key] = value ?? false;
                        });
                      },
                      activeColor: Colors.blue,
                      checkColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  Text(
                    entry.key,
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildClassesColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Classes',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        ..._icaoClasses.entries.map((entry) {
          return InkWell(
            onTap: () {
              setState(() {
                _icaoClasses[entry.key] = !entry.value;
              });
            },
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 18,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Transform.scale(
                    scale: 0.6,
                    child: Checkbox(
                      value: entry.value,
                      onChanged: (value) {
                        setState(() {
                          _icaoClasses[entry.key] = value ?? false;
                        });
                      },
                      activeColor: Colors.blue,
                      checkColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  Text(
                    entry.key,
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildAltitudeColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Elevation',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),

        // Custom vertical slider with tick marks and value display
        SizedBox(
          height: 144, // Match height of other columns (~8 items × 18px)
          child: _buildCustomVerticalSlider(),
        ),
      ],
    );
  }

  Widget _buildCustomVerticalSlider() {
    return Stack(
      children: [
        // Track and tick marks
        Positioned(
          left: 16,
          top: 0,
          bottom: 0,
          child: CustomPaint(
            size: const Size(20, 144),
            painter: _VerticalSliderTrackPainter(_maxAltitudeFt, 30000.0),
          ),
        ),

        // Slider thumb and value
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          child: GestureDetector(
            onPanUpdate: (details) {
              final RenderBox box = context.findRenderObject() as RenderBox;
              final localPosition = box.globalToLocal(details.globalPosition);
              final sliderHeight = 144.0;
              final thumbY = localPosition.dy.clamp(0.0, sliderHeight);
              final normalizedValue = 1.0 - (thumbY / sliderHeight);
              final newValue = (normalizedValue * 30000).clamp(0.0, 30000.0);

              setState(() {
                _maxAltitudeFt = newValue;
              });
            },
            child: Stack(
              children: [
                // Thumb position calculation
                Positioned(
                  left: 12,
                  top: (1.0 - (_maxAltitudeFt / 30000)) * 144 - 6,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: const BoxDecoration(
                      color: Colors.blue,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),

                // Value display next to thumb
                Positioned(
                  left: 26,
                  top: (1.0 - (_maxAltitudeFt / 30000)) * 144 - 8,
                  child: Text(
                    '${(_maxAltitudeFt / 1000).toStringAsFixed(0)}k',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
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

class _VerticalSliderTrackPainter extends CustomPainter {
  final double currentValue;
  final double maxValue;

  _VerticalSliderTrackPainter(this.currentValue, this.maxValue);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 2.0
      ..color = Colors.white24;

    final activePaint = Paint()
      ..strokeWidth = 2.0
      ..color = Colors.blue;

    final tickPaint = Paint()
      ..strokeWidth = 1.0
      ..color = Colors.white54;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    final trackRect = Rect.fromLTWH(8, 0, 2, size.height);

    // Draw inactive track
    canvas.drawRect(trackRect, paint);

    // Draw active track (from bottom to current value)
    final activeHeight = (currentValue / maxValue) * size.height;
    final activeTrackRect = Rect.fromLTWH(8, size.height - activeHeight, 2, activeHeight);
    canvas.drawRect(activeTrackRect, activePaint);

    // Draw tick marks and labels
    final tickMarks = [
      {'value': 10000, 'label': '10k'},
      {'value': 20000, 'label': '20k'},
    ];

    for (final tick in tickMarks) {
      final value = tick['value'] as double;
      final label = tick['label'] as String;
      final y = size.height - (value / maxValue) * size.height;

      // Draw tick mark
      canvas.drawLine(
        Offset(6, y),
        Offset(12, y),
        tickPaint,
      );

      // Draw label
      textPainter.text = TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 8,
          fontWeight: FontWeight.w400,
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(-2, y - textPainter.height / 2));
    }

    // Draw 0 and 30k labels
    textPainter.text = const TextSpan(
      text: '0',
      style: TextStyle(
        color: Colors.white54,
        fontSize: 8,
        fontWeight: FontWeight.w400,
      ),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(-2, size.height - textPainter.height / 2));

    textPainter.text = const TextSpan(
      text: '30k',
      style: TextStyle(
        color: Colors.white54,
        fontSize: 8,
        fontWeight: FontWeight.w400,
      ),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(-2, -textPainter.height / 2));
  }

  @override
  bool shouldRepaint(_VerticalSliderTrackPainter oldDelegate) {
    return currentValue != oldDelegate.currentValue || maxValue != oldDelegate.maxValue;
  }
}
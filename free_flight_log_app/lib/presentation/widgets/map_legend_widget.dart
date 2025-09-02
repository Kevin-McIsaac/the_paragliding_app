import 'package:flutter/material.dart';

/// Widget for displaying map legend
class MapLegendWidget extends StatelessWidget {
  final bool isMergeMode;

  const MapLegendWidget({
    super.key,
    this.isMergeMode = false,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 60,
      left: 10,
      child: Card(
        color: Colors.white.withValues(alpha: 0.9),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Legend',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              
              // Local sites
              _buildLegendItem(
                Icons.flight_takeoff,
                Colors.blue,
                'Local sites (flown)',
              ),
              
              // Paragliding Earth sites
              _buildLegendItem(
                null,
                Colors.green,
                'ParaglidingEarth sites',
                isCircle: true,
              ),
              
              // Launches
              _buildLegendItem(
                null,
                Colors.red,
                'Launch points',
                isCircle: true,
              ),
              
              if (isMergeMode) ...[
                const Divider(height: 8),
                const Text(
                  'Merge Mode Active',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    color: Colors.orange,
                  ),
                ),
                const Text(
                  'Drop site on target',
                  style: TextStyle(fontSize: 10),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLegendItem(IconData? icon, Color color, String label, {bool isCircle = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Icon(icon, color: color, size: 14)
          else if (isCircle)
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            )
          else
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.rectangle,
              ),
            ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 10),
          ),
        ],
      ),
    );
  }
}
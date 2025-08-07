import 'package:flutter/material.dart';
import '../../../data/models/igc_file.dart';

/// Widget for displaying the flight track legend with climb rate information
class FlightTrackLegend extends StatelessWidget {
  final IgcFile? igcData;
  final bool compact;

  const FlightTrackLegend({
    super.key,
    this.igcData,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (igcData?.trackPoints.isEmpty ?? true) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!compact) ...[
            Text(
              'Legend',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
          ],
          
          // Markers legend
          _buildMarkerSection(context),
          
          if (!compact) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            
            // Climb rate legend
            _buildClimbRateSection(context),
          ],
        ],
      ),
    );
  }

  Widget _buildMarkerSection(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!compact) ...[
          Text(
            'Markers',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
        ],
        _buildMarkerLegendItem(Colors.green, 'Launch'),
        const SizedBox(height: 2),
        _buildMarkerLegendItem(Colors.red, 'Landing'),
        const SizedBox(height: 2),
        _buildLineLegendItem(Colors.blue, 'Flight Track'),
        const SizedBox(height: 2),
        _buildLineLegendItem(Colors.red.withValues(alpha: 0.7), 'Straight Distance'),
      ],
    );
  }

  Widget _buildClimbRateSection(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Climb Rate (m/s)',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        _buildLegendItem(const Color(0xFF2196F3), '> 3.0', 'Strong Lift'),
        _buildLegendItem(const Color(0xFF4CAF50), '1.0 - 3.0', 'Good Lift'),
        _buildLegendItem(const Color(0xFF8BC34A), '0.5 - 1.0', 'Weak Lift'),
        _buildLegendItem(const Color(0xFFFFC107), '0.0 - 0.5', 'Neutral'),
        _buildLegendItem(const Color(0xFFFF9800), '-0.5 - 0.0', 'Light Sink'),
        _buildLegendItem(const Color(0xFFFF5722), '-1.0 - -0.5', 'Moderate Sink'),
        _buildLegendItem(const Color(0xFFF44336), '< -1.0', 'Strong Sink'),
      ],
    );
  }

  Widget _buildMarkerLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1),
          ),
          child: const Icon(
            Icons.place,
            color: Colors.white,
            size: 10,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildLineLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(1.5),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildLegendItem(Color color, String range, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$range: $label',
            style: const TextStyle(fontSize: 11),
          ),
        ],
      ),
    );
  }
}
import 'package:flutter/material.dart';
import '../../data/models/flight.dart';
import '../../utils/date_time_utils.dart';

class FlightStatisticsWidget extends StatelessWidget {
  final Flight flight;

  const FlightStatisticsWidget({
    super.key,
    required this.flight,
  });


  @override
  Widget build(BuildContext context) {
    final duration = DateTimeUtils.formatDurationCompact(flight.duration);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
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
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildStatItem(
                  'Duration',
                  duration,
                  Icons.access_time,
                  context,
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  'Straight Distance',
                  flight.straightDistance != null 
                      ? '${flight.straightDistance!.toStringAsFixed(1)} km'
                      : 'N/A',
                  Icons.straighten,
                  context,
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  'Track Distance',
                  flight.distance != null 
                      ? '${flight.distance!.toStringAsFixed(1)} km'
                      : 'N/A',
                  Icons.timeline,
                  context,
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  'Max Alt',
                  flight.maxAltitude != null
                      ? '${flight.maxAltitude!.toInt()} m'
                      : 'N/A',
                  Icons.height,
                  context,
                ),
              ),
            ],
          ),
          if (flight.maxClimbRate != null || flight.maxClimbRate5Sec != null) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (flight.maxClimbRate != null)
                  Expanded(
                    child: _buildStatItem(
                      'Max Climb (Inst)',
                      '${flight.maxClimbRate!.toStringAsFixed(1)} m/s',
                      Icons.trending_up,
                      context,
                    ),
                  ),
                if (flight.maxSinkRate != null)
                  Expanded(
                    child: _buildStatItem(
                      'Max Sink (Inst)',
                      '${flight.maxSinkRate!.toStringAsFixed(1)} m/s',
                      Icons.trending_down,
                      context,
                    ),
                  ),
                if (flight.maxClimbRate5Sec != null)
                  Expanded(
                    child: _buildStatItem(
                      'Max Climb (5s)',
                      '${flight.maxClimbRate5Sec!.toStringAsFixed(1)} m/s',
                      Icons.trending_up,
                      context,
                    ),
                  ),
                if (flight.maxSinkRate5Sec != null)
                  Expanded(
                    child: _buildStatItem(
                      'Max Sink (5s)',
                      '${flight.maxSinkRate5Sec!.toStringAsFixed(1)} m/s',
                      Icons.trending_down,
                      context,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
}
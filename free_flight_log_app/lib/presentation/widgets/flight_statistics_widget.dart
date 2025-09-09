import 'package:flutter/material.dart';
import '../../data/models/flight.dart';
import '../../utils/date_time_utils.dart';
import '../../services/logging_service.dart';

class FlightStatisticsWidget extends StatelessWidget {
  final Flight flight;

  const FlightStatisticsWidget({
    super.key,
    required this.flight,
  });


  @override
  Widget build(BuildContext context) {
    final duration = DateTimeUtils.formatDurationCompact(flight.effectiveDuration);

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
          // Basic Statistics
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
                  tooltip: 'Total time from launch to landing in hours and minutes',
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
                  tooltip: 'Direct point-to-point distance between launch and landing sites',
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  'Triangle',
                  flight.isClosed 
                      ? '${flight.faiTriangleDistance?.toStringAsFixed(1) ?? 'N/A'} km'
                      : 'Open',
                  Icons.change_history,
                  context,
                  tooltip: flight.isClosed 
                      ? 'Flight returned within ${flight.closingDistance?.toStringAsFixed(0) ?? 'N/A'}m of launch point${flight.faiTriangleDistance != null ? '. Triangle distance shown.' : ''}'
                      : 'Flight did not return close enough to launch point to be considered a closed triangle',
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
                  tooltip: 'Total distance flown along the actual flight path',
                ),
              ),
            ],
          ),
          
          // Climb Rate Statistics
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
                      tooltip: 'Peak instantaneous climb rate',
                    ),
                  ),
                if (flight.maxSinkRate != null)
                  Expanded(
                    child: _buildStatItem(
                      'Max Sink (Inst)',
                      '${flight.maxSinkRate!.toStringAsFixed(1)} m/s',
                      Icons.trending_down,
                      context,
                      tooltip: 'Peak instantaneous sink rate',
                    ),
                  ),
                if (flight.maxClimbRate5Sec != null)
                  Expanded(
                    child: _buildStatItem(
                      'Max Climb (5s)',
                      '${flight.maxClimbRate5Sec!.toStringAsFixed(1)} m/s',
                      Icons.trending_up,
                      context,
                      tooltip: 'Maximum 5-second average climb rate.',
                    ),
                  ),
                if (flight.maxSinkRate5Sec != null)
                  Expanded(
                    child: _buildStatItem(
                      'Max Sink (5s)',
                      '${flight.maxSinkRate5Sec!.toStringAsFixed(1)} m/s',
                      Icons.trending_down,
                      context,
                      tooltip: 'Maximum 5-second average sink rate',
                    ),
                  ),
              ],
            ),
          ],
          
          // Advanced Statistics
          if (_hasAdvancedStats()) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            _buildAdvancedStatistics(context),
          ],
        ],
      ),
    );
  }

  bool _hasAdvancedStats() {
    return flight.maxAltitude != null ||
           flight.maxGroundSpeed != null ||
           flight.thermalCount != null ||
           flight.bestLD != null ||
           flight.avgLD != null ||
           flight.longestGlide != null ||
           flight.climbPercentage != null ||
           flight.avgThermalStrength != null ||
           flight.bestThermal != null ||
           flight.gpsFixQuality != null;
  }

  Widget _buildAdvancedStatistics(BuildContext context) {
    return Column(
      children: [
        // Row 1: Max Alt, Best L/D, Avg L/D, Climb % (4 items)
        if (flight.maxAltitude != null || flight.bestLD != null || flight.avgLD != null || flight.climbPercentage != null) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              if (flight.maxAltitude != null)
                Expanded(
                  child: _buildStatItem(
                    'Max Alt',
                    '${flight.maxAltitude!.toInt()} m',
                    Icons.height,
                    context,
                    tooltip: 'Maximum GPS altitude above sea level',
                  ),
                )
              else
                const Expanded(child: SizedBox()),
              if (flight.bestLD != null)
                Expanded(
                  child: _buildStatItem(
                    'Best L/D',
                    flight.bestLD!.toStringAsFixed(1),
                    Icons.flight,
                    context,
                    tooltip: 'Best glide ratio achieved',
                  ),
                )
              else
                const Expanded(child: SizedBox()),
              if (flight.avgLD != null)
                Expanded(
                  child: _buildStatItem(
                    'Avg L/D',
                    flight.avgLD!.toStringAsFixed(1),
                    Icons.flight,
                    context,
                    tooltip: 'Average glide ratio over the entire flight',
                  ),
                )
              else
                const Expanded(child: SizedBox()),
              if (flight.climbPercentage != null)
                Expanded(
                  child: _buildStatItem(
                    'Climb %',
                    '${flight.climbPercentage!.toStringAsFixed(0)}%',
                    Icons.trending_up,
                    context,
                    tooltip: 'Percentage of flight time spent climbing',
                  ),
                )
              else
                const Expanded(child: SizedBox()),
            ],
          ),
        ],
        
        // Row 2: Longest Glide, Thermals, Avg Thermal, Best Thermal (4 items)  
        if (flight.longestGlide != null || flight.thermalCount != null || flight.avgThermalStrength != null || flight.bestThermal != null) ...[
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              if (flight.longestGlide != null)
                Expanded(
                  child: _buildStatItem(
                    'Longest Glide',
                    '${flight.longestGlide!.toStringAsFixed(1)} km',
                    Icons.trending_flat,
                    context,
                    tooltip: 'Maximum distance covered in a single glide without thermaling or climbing',
                  ),
                )
              else
                const Expanded(child: SizedBox()),
              if (flight.thermalCount != null)
                Expanded(
                  child: _buildStatItem(
                    'Thermals',
                    flight.thermalCount.toString(),
                    Icons.air,
                    context,
                    tooltip: 'Number of distinct thermal climbs. 15s Average climb rate > 0.5m/s for 30 seconds',
                  ),
                )
              else
                const Expanded(child: SizedBox()),
              if (flight.avgThermalStrength != null)
                Expanded(
                  child: _buildStatItem(
                    'Avg Thermal',
                    '${flight.avgThermalStrength!.toStringAsFixed(1)} m/s',
                    Icons.trending_up,
                    context,
                    tooltip: 'Average climb rate across all thermals. Indicates typical thermal strength for the day',
                  ),
                )
              else
                const Expanded(child: SizedBox()),
              if (flight.bestThermal != null)
                Expanded(
                  child: _buildStatItem(
                    'Best Thermal',
                    '${flight.bestThermal!.toStringAsFixed(1)} m/s',
                    Icons.trending_up,
                    context,
                    tooltip: 'Strongest average climb rate achieved in a single thermal',
                  ),
                )
              else
                const Expanded(child: SizedBox()),
            ],
          ),
        ],
        
        // Row 3: Max Speed, Avg Speed, GPS Quality, Recording (4 items)
        if (flight.maxGroundSpeed != null || flight.avgGroundSpeed != null || flight.gpsFixQuality != null || flight.recordingInterval != null) ...[
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              if (flight.maxGroundSpeed != null)
                Expanded(
                  child: _buildStatItem(
                    'Max Speed',
                    '${flight.maxGroundSpeed!.toStringAsFixed(1)} km/h',
                    Icons.speed,
                    context,
                    tooltip: 'Maximum GPS ground speed recorded during the flight',
                  ),
                )
              else
                const Expanded(child: SizedBox()),
              if (flight.avgGroundSpeed != null)
                Expanded(
                  child: _buildStatItem(
                    'Avg Speed',
                    '${flight.avgGroundSpeed!.toStringAsFixed(1)} km/h',
                    Icons.speed,
                    context,
                    tooltip: 'Average GPS ground speed over the entire flight',
                  ),
                )
              else
                const Expanded(child: SizedBox()),
              if (flight.gpsFixQuality != null)
                Expanded(
                  child: _buildStatItem(
                    'GPS Quality',
                    '${flight.gpsFixQuality!.toStringAsFixed(0)}%',
                    Icons.gps_fixed,
                    context,
                    tooltip: 'Percentage of GPS fixes with good satellite reception (>4 satellites)',
                  ),
                )
              else
                const Expanded(child: SizedBox()),
              if (flight.recordingInterval != null)
                Expanded(
                  child: _buildStatItem(
                    'Recording',
                    '${flight.recordingInterval!.toStringAsFixed(0)}s',
                    Icons.schedule,
                    context,
                    tooltip: 'Time interval between GPS track points in the IGC file',
                  ),
                )
              else
                const Expanded(child: SizedBox()),
            ],
          ),
        ],
      ],
    );
  }


  Widget _buildStatItem(String label, String value, IconData icon, BuildContext context, {String? tooltip}) {
    Widget statWidget = Column(
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

    if (tooltip != null) {
      return Tooltip(
        message: tooltip,
        child: statWidget,
      );
    }

    return statWidget;
  }
}
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
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildStatItem(
                  'Max Climb (Inst)',
                  flight.maxClimbRate != null 
                      ? '${flight.maxClimbRate!.toStringAsFixed(1)} m/s'
                      : 'N/A',
                  Icons.trending_up,
                  context,
                  tooltip: 'Peak instantaneous climb rate',
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  'Max Sink (Inst)',
                  flight.maxSinkRate != null
                      ? '${flight.maxSinkRate!.toStringAsFixed(1)} m/s'
                      : 'N/A',
                  Icons.trending_down,
                  context,
                  tooltip: 'Peak instantaneous sink rate',
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  'Max Climb (5s)',
                  flight.maxClimbRate5Sec != null
                      ? '${flight.maxClimbRate5Sec!.toStringAsFixed(1)} m/s'
                      : 'N/A',
                  Icons.trending_up,
                  context,
                  tooltip: 'Maximum 5-second average climb rate',
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  'Max Sink (5s)',
                  flight.maxSinkRate5Sec != null
                      ? '${flight.maxSinkRate5Sec!.toStringAsFixed(1)} m/s'
                      : 'N/A',
                  Icons.trending_down,
                  context,
                  tooltip: 'Maximum 5-second average sink rate',
                ),
              ),
            ],
          ),
          
          // All Additional Statistics
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),
          _buildAllStatistics(context),
        ],
      ),
    );
  }


  Widget _buildAllStatistics(BuildContext context) {
    // Collect statistics into logical groups - always show all stats
    final altitudePerformanceStats = <Map<String, dynamic>>[
      {'label': 'Max Alt', 'value': flight.maxAltitude != null ? '${flight.maxAltitude!.toInt()} m' : 'N/A', 'icon': Icons.height, 'tooltip': 'Maximum GPS altitude above sea level'},
      {'label': 'Climb %', 'value': flight.climbPercentage != null ? '${flight.climbPercentage!.toStringAsFixed(0)}%' : 'N/A', 'icon': Icons.trending_up, 'tooltip': 'Percentage of flight time spent climbing'},
      {'label': 'Avg Glide Ratio', 'value': flight.avgLD != null ? '${flight.avgLD!.toStringAsFixed(1)}:1' : 'N/A', 'icon': Icons.flight, 'tooltip': 'Average glide ratio over the entire flight'},
      {'label': 'Longest Glide', 'value': flight.longestGlide != null ? '${flight.longestGlide!.toStringAsFixed(1)} km' : 'N/A', 'icon': Icons.trending_flat, 'tooltip': 'Maximum distance covered in a single glide without thermaling or climbing'},
    ];

    final thermalStats = <Map<String, dynamic>>[
      {'label': 'Thermals', 'value': flight.thermalCount != null ? flight.thermalCount.toString() : 'N/A', 'icon': Icons.air, 'tooltip': 'Number of distinct thermal climbs. 15s Average climb rate > 0.5m/s for 30 seconds'},
      {'label': 'Time in Thermals', 'value': flight.totalTimeInThermals != null ? '${(flight.totalTimeInThermals! / 60).toStringAsFixed(0)} min' : 'N/A', 'icon': Icons.timer, 'tooltip': 'Total time spent in thermal climbs during the flight'},
      {'label': 'Avg Thermal', 'value': flight.avgThermalStrength != null ? '${flight.avgThermalStrength!.toStringAsFixed(1)} m/s' : 'N/A', 'icon': Icons.trending_up, 'tooltip': 'Average climb rate across all thermals. Indicates typical thermal strength for the day'},
      {'label': 'Best Thermal', 'value': flight.bestThermal != null ? '${flight.bestThermal!.toStringAsFixed(1)} m/s' : 'N/A', 'icon': Icons.trending_up, 'tooltip': 'Strongest average climb rate achieved in a single thermal'},
    ];

    final glideSpeedStats = <Map<String, dynamic>>[
      {'label': 'Max Speed', 'value': flight.maxGroundSpeed != null ? '${flight.maxGroundSpeed!.toStringAsFixed(1)} km/h' : 'N/A', 'icon': Icons.speed, 'tooltip': 'Maximum GPS ground speed recorded during the flight'},
      {'label': 'Avg Speed', 'value': flight.avgGroundSpeed != null ? '${flight.avgGroundSpeed!.toStringAsFixed(1)} km/h' : 'N/A', 'icon': Icons.speed, 'tooltip': 'Average GPS ground speed over the entire flight'},
      {'label': 'GPS Quality', 'value': flight.gpsFixQuality != null ? '${flight.gpsFixQuality!.toStringAsFixed(0)}%' : 'N/A', 'icon': Icons.gps_fixed, 'tooltip': 'Percentage of GPS fixes with good satellite reception (>4 satellites)'},
      {'label': 'Recording', 'value': flight.recordingInterval != null ? '${flight.recordingInterval!.toStringAsFixed(0)}s' : 'N/A', 'icon': Icons.schedule, 'tooltip': 'Time interval between GPS track points in the IGC file'},
    ];


    return Column(
      children: [
        // Altitude & Performance Stats Row
        _buildStatsRow(altitudePerformanceStats, context),
        
        // Thermal Stats Row
        const SizedBox(height: 12),
        const Divider(height: 1),
        const SizedBox(height: 8),
        _buildStatsRow(thermalStats, context),
        
        // Speed & Recording Stats Row
        const SizedBox(height: 12),
        const Divider(height: 1),
        const SizedBox(height: 8),
        _buildStatsRow(glideSpeedStats, context),
      ],
    );
  }

  Widget _buildStatsRow(List<Map<String, dynamic>?> stats, BuildContext context) {
    // Ensure exactly 4 items (padding with nulls if needed)
    final paddedStats = List<Map<String, dynamic>?>.from(stats);
    while (paddedStats.length < 4) {
      paddedStats.add(null);
    }
    paddedStats.length = 4; // Trim to exactly 4

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: paddedStats.map((stat) {
        if (stat == null) {
          return const Expanded(child: SizedBox());
        }
        return Expanded(
          child: _buildStatItem(
            stat['label'] as String,
            stat['value'] as String,
            stat['icon'] as IconData,
            context,
            tooltip: stat['tooltip'] as String,
          ),
        );
      }).toList(),
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
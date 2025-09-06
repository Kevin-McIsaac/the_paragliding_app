import 'package:flutter/material.dart';
import '../../data/models/flight.dart';
import '../../utils/date_time_utils.dart';

class FlightStatisticsWidget extends StatefulWidget {
  final Flight flight;

  const FlightStatisticsWidget({
    super.key,
    required this.flight,
  });

  @override
  State<FlightStatisticsWidget> createState() => _FlightStatisticsWidgetState();
}

class _FlightStatisticsWidgetState extends State<FlightStatisticsWidget> {
  bool _showAdvanced = false;

  @override
  Widget build(BuildContext context) {
    final duration = DateTimeUtils.formatDurationCompact(widget.flight.duration);

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
                  widget.flight.straightDistance != null 
                      ? '${widget.flight.straightDistance!.toStringAsFixed(1)} km'
                      : 'N/A',
                  Icons.straighten,
                  context,
                  tooltip: 'Direct point-to-point distance between launch and landing sites',
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  'FAI Triangle',
                  widget.flight.faiTriangleDistance != null 
                      ? '${widget.flight.faiTriangleDistance!.toStringAsFixed(1)} km'
                      : 'N/A',
                  Icons.change_history,
                  context,
                  tooltip: 'FAI triangle distance using maximum area approximation',
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  'Track Distance',
                  widget.flight.distance != null 
                      ? '${widget.flight.distance!.toStringAsFixed(1)} km'
                      : 'N/A',
                  Icons.timeline,
                  context,
                  tooltip: 'Total distance flown along the actual flight path',
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  'Max Alt',
                  widget.flight.maxAltitude != null
                      ? '${widget.flight.maxAltitude!.toInt()} m'
                      : 'N/A',
                  Icons.height,
                  context,
                  tooltip: 'Maximum GPS altitude above sea level',
                ),
              ),
            ],
          ),
          
          // Climb Rate Statistics
          if (widget.flight.maxClimbRate != null || widget.flight.maxClimbRate5Sec != null) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.flight.maxClimbRate != null)
                  Expanded(
                    child: _buildStatItem(
                      'Max Climb (Inst)',
                      '${widget.flight.maxClimbRate!.toStringAsFixed(1)} m/s',
                      Icons.trending_up,
                      context,
                      tooltip: 'Peak instantaneous climb rate',
                    ),
                  ),
                if (widget.flight.maxSinkRate != null)
                  Expanded(
                    child: _buildStatItem(
                      'Max Sink (Inst)',
                      '${widget.flight.maxSinkRate!.toStringAsFixed(1)} m/s',
                      Icons.trending_down,
                      context,
                      tooltip: 'Peak instantaneous sink rate',
                    ),
                  ),
                if (widget.flight.maxClimbRate5Sec != null)
                  Expanded(
                    child: _buildStatItem(
                      'Max Climb (5s)',
                      '${widget.flight.maxClimbRate5Sec!.toStringAsFixed(1)} m/s',
                      Icons.trending_up,
                      context,
                      tooltip: 'Maximum 5-second average climb rate.',
                    ),
                  ),
                if (widget.flight.maxSinkRate5Sec != null)
                  Expanded(
                    child: _buildStatItem(
                      'Max Sink (5s)',
                      '${widget.flight.maxSinkRate5Sec!.toStringAsFixed(1)} m/s',
                      Icons.trending_down,
                      context,
                      tooltip: 'Maximum 5-second average sink rate',
                    ),
                  ),
              ],
            ),
          ],
          
          // Expandable Advanced Statistics
          if (_hasAdvancedStats()) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            InkWell(
              onTap: () => setState(() => _showAdvanced = !_showAdvanced),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _showAdvanced ? Icons.expand_less : Icons.expand_more,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _showAdvanced ? 'Hide Advanced Stats' : 'Show Advanced Stats',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
          
          // Advanced Statistics (expandable)
          if (_showAdvanced && _hasAdvancedStats()) ...[
            const SizedBox(height: 12),
            _buildAdvancedStatistics(),
          ],
        ],
      ),
    );
  }

  bool _hasAdvancedStats() {
    return widget.flight.maxGroundSpeed != null ||
           widget.flight.thermalCount != null ||
           widget.flight.bestLD != null ||
           widget.flight.gpsFixQuality != null;
  }

  Widget _buildAdvancedStatistics() {
    return Column(
      children: [
        // Row 1: Best L/D, Avg L/D, Longest Glide, Climb % (4 items)
        if (widget.flight.bestLD != null || widget.flight.avgLD != null || widget.flight.longestGlide != null || widget.flight.climbPercentage != null) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              if (widget.flight.bestLD != null)
                Expanded(
                  child: _buildStatItem(
                    'Best L/D',
                    widget.flight.bestLD!.toStringAsFixed(1),
                    Icons.flight,
                    context,
                    tooltip: 'Best glide ratio achieved',
                  ),
                )
              else
                const Expanded(child: SizedBox()),
              if (widget.flight.avgLD != null)
                Expanded(
                  child: _buildStatItem(
                    'Avg L/D',
                    widget.flight.avgLD!.toStringAsFixed(1),
                    Icons.flight,
                    context,
                    tooltip: 'Average glide ratio over the entire flight',
                  ),
                )
              else
                const Expanded(child: SizedBox()),
              if (widget.flight.longestGlide != null)
                Expanded(
                  child: _buildStatItem(
                    'Longest Glide',
                    '${widget.flight.longestGlide!.toStringAsFixed(1)} km',
                    Icons.trending_flat,
                    context,
                    tooltip: 'Maximum distance covered in a single glide without thermaling or climbing',
                  ),
                )
              else
                const Expanded(child: SizedBox()),
              if (widget.flight.climbPercentage != null)
                Expanded(
                  child: _buildStatItem(
                    'Climb %',
                    '${widget.flight.climbPercentage!.toStringAsFixed(0)}%',
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
        
        // Row 2: Thermals, Avg Thermal, Best Thermal, Thermal Time (4 items)  
        if (widget.flight.thermalCount != null || widget.flight.avgThermalStrength != null || widget.flight.bestThermal != null || widget.flight.totalTimeInThermals != null) ...[
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              if (widget.flight.thermalCount != null)
                Expanded(
                  child: _buildStatItem(
                    'Thermals',
                    widget.flight.thermalCount.toString(),
                    Icons.air,
                    context,
                    tooltip: 'Number of distinct thermal climbs. 15s Average climb rate > 0.5m/s for 30 seconds',
                  ),
                )
              else
                const Expanded(child: SizedBox()),
              if (widget.flight.avgThermalStrength != null)
                Expanded(
                  child: _buildStatItem(
                    'Avg Thermal',
                    '${widget.flight.avgThermalStrength!.toStringAsFixed(1)} m/s',
                    Icons.trending_up,
                    context,
                    tooltip: 'Average climb rate across all thermals. Indicates typical thermal strength for the day',
                  ),
                )
              else
                const Expanded(child: SizedBox()),
              if (widget.flight.bestThermal != null)
                Expanded(
                  child: _buildStatItem(
                    'Best Thermal',
                    '${widget.flight.bestThermal!.toStringAsFixed(1)} m/s',
                    Icons.trending_up,
                    context,
                    tooltip: 'Strongest average climb rate achieved in a single thermal',
                  ),
                )
              else
                const Expanded(child: SizedBox()),
              if (widget.flight.totalTimeInThermals != null)
                Expanded(
                  child: _buildStatItem(
                    'Thermal %',
                    '${((widget.flight.totalTimeInThermals! / (widget.flight.duration * 60)) * 100).toStringAsFixed(0)}%',
                    Icons.trending_up,
                    context,
                    tooltip: 'Percentage of total flight time spent thermaling',
                  ),
                )
              else
                const Expanded(child: SizedBox()),
            ],
          ),
        ],
        
        // Row 3: Max Speed, Avg Speed, GPS Quality, Recording (4 items)
        if (widget.flight.maxGroundSpeed != null || widget.flight.avgGroundSpeed != null || widget.flight.gpsFixQuality != null || widget.flight.recordingInterval != null) ...[
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              if (widget.flight.maxGroundSpeed != null)
                Expanded(
                  child: _buildStatItem(
                    'Max Speed',
                    '${widget.flight.maxGroundSpeed!.toStringAsFixed(1)} km/h',
                    Icons.speed,
                    context,
                    tooltip: 'Maximum GPS ground speed recorded during the flight',
                  ),
                )
              else
                const Expanded(child: SizedBox()),
              if (widget.flight.avgGroundSpeed != null)
                Expanded(
                  child: _buildStatItem(
                    'Avg Speed',
                    '${widget.flight.avgGroundSpeed!.toStringAsFixed(1)} km/h',
                    Icons.speed,
                    context,
                    tooltip: 'Average GPS ground speed over the entire flight',
                  ),
                )
              else
                const Expanded(child: SizedBox()),
              if (widget.flight.gpsFixQuality != null)
                Expanded(
                  child: _buildStatItem(
                    'GPS Quality',
                    '${widget.flight.gpsFixQuality!.toStringAsFixed(0)}%',
                    Icons.gps_fixed,
                    context,
                    tooltip: 'Percentage of GPS fixes with good satellite reception (>4 satellites)',
                  ),
                )
              else
                const Expanded(child: SizedBox()),
              if (widget.flight.recordingInterval != null)
                Expanded(
                  child: _buildStatItem(
                    'Recording',
                    '${widget.flight.recordingInterval!.toStringAsFixed(0)}s',
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
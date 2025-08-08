import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../data/models/flight.dart';
import '../../../data/models/igc_file.dart';

/// Widget for displaying flight altitude and climb rate charts
class FlightAltitudeChart extends StatefulWidget {
  final Flight flight;
  final IgcFile? igcData;
  final double height;
  final bool showClimbRate;

  const FlightAltitudeChart({
    super.key,
    required this.flight,
    this.igcData,
    this.height = 200,
    this.showClimbRate = true,
  });

  @override
  State<FlightAltitudeChart> createState() => _FlightAltitudeChartState();
}

class _FlightAltitudeChartState extends State<FlightAltitudeChart> {
  bool _showAltitude = true;
  bool _showClimbRate = false;

  @override
  Widget build(BuildContext context) {
    if (widget.igcData?.trackPoints.isEmpty ?? true) {
      return Container(
        height: widget.height,
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.show_chart, size: 48, color: Colors.grey),
              SizedBox(height: 8),
              Text(
                'No altitude data available',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      height: widget.height,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Chart controls
          _buildChartControls(context),
          const SizedBox(height: 12),
          
          // Chart
          Expanded(
            child: LineChart(_buildChartData()),
          ),
        ],
      ),
    );
  }

  Widget _buildChartControls(BuildContext context) {
    return Row(
      children: [
        Text(
          'Flight Profile',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const Spacer(),
        if (widget.showClimbRate) ...[
          _buildToggleChip(
            context,
            'Altitude',
            _showAltitude,
            Colors.blue,
            () => setState(() => _showAltitude = !_showAltitude),
          ),
          const SizedBox(width: 8),
          _buildToggleChip(
            context,
            'Climb Rate',
            _showClimbRate,
            Colors.red,
            () => setState(() => _showClimbRate = !_showClimbRate),
          ),
        ],
      ],
    );
  }

  Widget _buildToggleChip(
    BuildContext context,
    String label,
    bool isSelected,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : Colors.grey[300]!,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isSelected ? color : Colors.grey[400],
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: isSelected ? color : Colors.grey[600],
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  LineChartData _buildChartData() {
    final trackPoints = widget.igcData!.trackPoints;
    final lineBarsData = <LineChartBarData>[];

    // Calculate time offsets from start
    final startTime = trackPoints.first.timestamp;
    final timeOffsets = trackPoints
        .map((point) => point.timestamp.difference(startTime).inMinutes.toDouble())
        .toList();

    // Altitude line
    if (_showAltitude) {
      final altitudeSpots = <FlSpot>[];
      for (int i = 0; i < trackPoints.length; i++) {
        final altitude = trackPoints[i].pressureAltitude > 0 
            ? trackPoints[i].pressureAltitude.toDouble() 
            : trackPoints[i].gpsAltitude.toDouble();
        altitudeSpots.add(FlSpot(timeOffsets[i], altitude));
      }

      lineBarsData.add(
        LineChartBarData(
          spots: altitudeSpots,
          color: Colors.blue,
          strokeWidth: 2,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            color: Colors.blue.withValues(alpha: 0.1),
          ),
        ),
      );
    }

    // Climb rate line
    if (_showClimbRate && widget.igcData!.hasClimbRateData) {
      final climbRateSpots = <FlSpot>[];
      for (int i = 0; i < trackPoints.length; i++) {
        final climbRate = trackPoints[i].climbRate ?? 0;
        climbRateSpots.add(FlSpot(timeOffsets[i], climbRate));
      }

      lineBarsData.add(
        LineChartBarData(
          spots: climbRateSpots,
          color: Colors.red,
          strokeWidth: 2,
          dotData: const FlDotData(show: false),
        ),
      );
    }

    final maxTime = timeOffsets.isNotEmpty ? timeOffsets.last : 60;
    final maxAltitude = _showAltitude 
        ? trackPoints.map((p) => p.altitude).reduce((a, b) => a > b ? a : b)
        : 1000;
    final minAltitude = _showAltitude 
        ? trackPoints.map((p) => p.altitude).reduce((a, b) => a < b ? a : b)
        : 0;

    return LineChartData(
      lineBarsData: lineBarsData,
      minX: 0,
      maxX: maxTime,
      minY: _showClimbRate && !_showAltitude 
          ? -10  // Show climb rate range
          : minAltitude - (maxAltitude - minAltitude) * 0.1,
      maxY: _showClimbRate && !_showAltitude 
          ? 10   // Show climb rate range
          : maxAltitude + (maxAltitude - minAltitude) * 0.1,
      backgroundColor: Theme.of(context).colorScheme.surface,
      gridData: FlGridData(
        show: true,
        drawVerticalLine: true,
        horizontalInterval: _showAltitude ? (maxAltitude - minAltitude) / 5 : 2,
        verticalInterval: maxTime / 6,
        getDrawingHorizontalLine: (value) => FlLine(
          color: Colors.grey[300],
          strokeWidth: 0.5,
        ),
        getDrawingVerticalLine: (value) => FlLine(
          color: Colors.grey[300],
          strokeWidth: 0.5,
        ),
      ),
      titlesData: FlTitlesData(
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 32,
            interval: maxTime / 6,
            getTitlesWidget: (value, meta) => Text(
              '${value.toInt()}min',
              style: const TextStyle(fontSize: 10),
            ),
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 50,
            getTitlesWidget: (value, meta) {
              if (_showAltitude && !_showClimbRate) {
                return Text(
                  '${value.toInt()}m',
                  style: const TextStyle(fontSize: 10),
                );
              } else if (_showClimbRate && !_showAltitude) {
                return Text(
                  value.toStringAsFixed(1),
                  style: const TextStyle(fontSize: 10),
                );
              } else {
                return Text(
                  '${value.toInt()}',
                  style: const TextStyle(fontSize: 10),
                );
              }
            },
          ),
        ),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      borderData: FlBorderData(
        show: true,
        border: Border(
          bottom: BorderSide(color: Colors.grey[300]!),
          left: BorderSide(color: Colors.grey[300]!),
        ),
      ),
      lineTouchData: LineTouchData(
        enabled: true,
        touchTooltipData: LineTouchTooltipData(
          getTooltipItems: (touchedSpots) {
            final items = <LineTooltipItem>[];
            
            for (final spot in touchedSpots) {
              final timeStr = '${spot.x.toInt()}min';
              
              if (spot.barIndex == 0 && _showAltitude) {
                items.add(LineTooltipItem(
                  'Altitude: ${spot.y.toInt()}m\nTime: $timeStr',
                  const TextStyle(color: Colors.blue, fontSize: 12),
                ));
              } else if (_showClimbRate) {
                items.add(LineTooltipItem(
                  'Climb: ${spot.y.toStringAsFixed(1)}m/s\nTime: $timeStr',
                  const TextStyle(color: Colors.red, fontSize: 12),
                ));
              }
            }
            
            return items;
          },
        ),
      ),
    );
  }
}
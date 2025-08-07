import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../data/models/flight.dart';
import '../../../data/models/igc_file.dart';

/// Simplified altitude chart widget
class FlightAltitudeChart extends StatelessWidget {
  final Flight flight;
  final IgcFile? igcData;
  final double height;

  const FlightAltitudeChart({
    super.key,
    required this.flight,
    this.igcData,
    this.height = 200,
  });

  @override
  Widget build(BuildContext context) {
    if (igcData?.trackPoints.isEmpty ?? true) {
      return Container(
        height: height,
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
      height: height,
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
          // Title
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Flight Altitude Profile',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 12),
          
          // Chart
          Expanded(
            child: LineChart(_buildChartData()),
          ),
        ],
      ),
    );
  }

  LineChartData _buildChartData() {
    final trackPoints = igcData!.trackPoints;
    final altitudeSpots = <FlSpot>[];

    // Calculate time offsets from start
    final startTime = trackPoints.first.timestamp;
    
    for (int i = 0; i < trackPoints.length; i++) {
      final timeOffset = trackPoints[i].timestamp.difference(startTime).inMinutes.toDouble();
      final altitude = trackPoints[i].pressureAltitude > 0 
          ? trackPoints[i].pressureAltitude.toDouble() 
          : trackPoints[i].gpsAltitude.toDouble();
      altitudeSpots.add(FlSpot(timeOffset, altitude));
    }

    final maxTime = altitudeSpots.isNotEmpty ? altitudeSpots.last.x : 60;
    final altitudes = altitudeSpots.map((s) => s.y).toList();
    final maxAltitude = altitudes.reduce((a, b) => a > b ? a : b);
    final minAltitude = altitudes.reduce((a, b) => a < b ? a : b);

    return LineChartData(
      lineBarsData: [
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
      ],
      minX: 0,
      maxX: maxTime,
      minY: minAltitude - (maxAltitude - minAltitude) * 0.1,
      maxY: maxAltitude + (maxAltitude - minAltitude) * 0.1,
      backgroundColor: Theme.of(context).colorScheme.surface,
      gridData: FlGridData(
        show: true,
        drawVerticalLine: true,
        horizontalInterval: (maxAltitude - minAltitude) / 5,
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
            getTitlesWidget: (value, meta) => Text(
              '${value.toInt()}m',
              style: const TextStyle(fontSize: 10),
            ),
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
    );
  }
}
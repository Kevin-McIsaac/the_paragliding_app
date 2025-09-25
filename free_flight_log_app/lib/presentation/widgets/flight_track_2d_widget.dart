import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../data/models/flight.dart';
import '../../data/models/igc_file.dart';
import '../../services/logging_service.dart';
import '../../services/flight_track_loader.dart';
import '../../utils/map_calculation_utils.dart';
import '../../utils/performance_monitor.dart';
import '../../utils/preferences_helper.dart';
import '../../utils/ui_utils.dart';
import 'flight_track_map.dart';


class FlightTrack2DWidget extends StatefulWidget {
  final Flight flight;
  final double? height;
  
  const FlightTrack2DWidget({
    super.key,
    required this.flight,
    this.height = 400,
  });

  @override
  State<FlightTrack2DWidget> createState() => _FlightTrack2DWidgetState();
}

class _FlightTrack2DWidgetState extends State<FlightTrack2DWidget> {
  // Constants
  static const double _chartHeight = 100.0;
  static const double _totalChartsHeight = 300.0; // 3 charts * 100px each
  static const double _altitudePaddingFactor = 0.1;
  static const int _chartIntervalMinutes = 15;
  static const int _chartIntervalMs = _chartIntervalMinutes * 60 * 1000;

  List<IgcPoint> _trackPoints = [];
  List<IgcPoint> _faiTrianglePoints = [];
  bool _isLoading = true;
  String? _error;
  final ValueNotifier<int?> _selectedTrackPointIndex = ValueNotifier<int?>(null);
  double _closingDistanceThreshold = 500.0; // Default value
  
  @override
  void initState() {
    super.initState();
    LoggingService.action('FlightTrack2D', 'Widget initialization started', {
      'flight_id': widget.flight.id,
      'has_track': widget.flight.trackLogPath != null,
    });
    _loadTrackData();
    _loadClosingDistanceThreshold();
  }

  @override
  void didUpdateWidget(FlightTrack2DWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Check if flight data that affects the map display has changed
    if (_shouldReloadTrackData(oldWidget.flight, widget.flight)) {
      LoggingService.ui('FlightTrack2D', 'Flight data changed, reloading track data');
      _loadTrackData();
    }
  }

  /// Check if track data should be reloaded based on flight changes
  bool _shouldReloadTrackData(Flight oldFlight, Flight newFlight) {
    // Compare key fields that affect track/triangle display
    return oldFlight.id != newFlight.id ||
           oldFlight.trackLogPath != newFlight.trackLogPath ||
           oldFlight.faiTrianglePoints != newFlight.faiTrianglePoints ||
           oldFlight.isClosed != newFlight.isClosed ||
           oldFlight.closingPointIndex != newFlight.closingPointIndex;
  }


  Future<void> _loadClosingDistanceThreshold() async {
    try {
      final threshold = await PreferencesHelper.getTriangleClosingDistance();
      setState(() {
        _closingDistanceThreshold = threshold;
      });
    } catch (e) {
      LoggingService.error('FlightTrack2DWidget: Error loading closing distance threshold', e);
    }
  }



  Future<void> _loadTrackData() async {
    if (widget.flight.trackLogPath == null) {
      setState(() {
        _error = 'No track data available for this flight';
        _isLoading = false;
      });
      return;
    }

    try {
      // Load trimmed flight track data (always consistent)
      final igcFile = await FlightTrackLoader.loadFlightTrack(
        widget.flight,
        logContext: 'FlightTrack2D',
      );
      
      if (igcFile.trackPoints.isEmpty) {
        setState(() {
          _error = 'No track points found';
          _isLoading = false;
        });
        return;
      }
      
      // Create track data structure with timezone from the loaded file
      final trackData = (
        points: igcFile.trackPoints,
        timezone: igcFile.timezone,
      );

      // Get triangle points from stored data or calculate if needed
      List<IgcPoint> faiTrianglePoints = [];
      
      try {
        // Try to use pre-calculated triangle points from database
        final storedTrianglePoints = widget.flight.getParsedTrianglePoints();
        if (storedTrianglePoints != null && storedTrianglePoints.length == 3) {
          // Convert stored coordinate maps to IgcPoint objects
          faiTrianglePoints = storedTrianglePoints.map((point) => IgcPoint(
            latitude: point['lat']!,
            longitude: point['lng']!,
            gpsAltitude: point['alt']!.toInt(),
            pressureAltitude: 0,
            timestamp: DateTime.now(), // Timestamp not needed for triangle display
            isValid: true, // Stored points are assumed valid
          )).toList();
        } else if (widget.flight.isClosed && widget.flight.closingPointIndex != null) {
          // Fallback: calculate from IGC file if no stored points
          final triangleSamplingInterval = await PreferencesHelper.getTriangleSamplingInterval();
          final closingDistance = await PreferencesHelper.getTriangleClosingDistance();
          final trimmedIgcFile = igcFile.copyWithTrimmedPoints(0, widget.flight.closingPointIndex!);
          final faiTriangle = trimmedIgcFile.calculateFaiTriangle(
            samplingIntervalSeconds: triangleSamplingInterval,
            closingDistanceMeters: closingDistance,
          );
          final rawTrianglePoints = faiTriangle['trianglePoints'] as List<dynamic>?;
          
          if (rawTrianglePoints != null && rawTrianglePoints.length == 3) {
            faiTrianglePoints = rawTrianglePoints.cast<IgcPoint>();
          }
        }
      } catch (e) {
        LoggingService.error('FlightTrack2D: Failed to get triangle points', e);
      }

      setState(() {
        _trackPoints = trackData.points;
        _faiTrianglePoints = faiTrianglePoints;
        _isLoading = false;
      });
      
      LoggingService.structured('TRACK_LOAD', {
        'track_points': _trackPoints.length,
        'triangle_points': _faiTrianglePoints.length,
        'flight_id': widget.flight.id,
      });
    } catch (e) {
      LoggingService.error('FlightTrack2DWidget: Error loading track data', e);
      setState(() {
        _error = 'Error loading track data: $e';
        _isLoading = false;
      });
    }
  }



  /// Calculate smoothed ground speed using 5-second time-based moving average
  /// Similar to the existing climbRate5s implementation but for ground speed
  double _getSmoothedGroundSpeed(IgcPoint point) {
    if (point.parentFile == null || point.pointIndex == null) {
      return point.groundSpeed;
    }
    
    final tracks = point.parentFile!.trackPoints;
    final currentIndex = point.pointIndex!;
    
    if (currentIndex >= tracks.length || currentIndex == 0) {
      return point.groundSpeed; // Fallback to instantaneous for first point
    }
    
    // Find the first point in the 5-second window (looking backwards from current point)
    IgcPoint? firstInWindow;
    for (int i = currentIndex - 1; i >= 0; i--) {
      final timeDiff = point.timestamp.difference(tracks[i].timestamp).inSeconds;
      if (timeDiff >= 5) {
        firstInWindow = tracks[i];
        break;
      }
    }
    
    // If we don't have enough points in the window, use instantaneous rate
    if (firstInWindow == null || firstInWindow == point) {
      return point.groundSpeed;
    }
    
    // Calculate the average ground speed over the 5-second window
    final timeDiffSeconds = point.timestamp.difference(firstInWindow.timestamp).inSeconds.toDouble();
    
    if (timeDiffSeconds <= 0) {
      return point.groundSpeed; // Fallback to instantaneous
    }
    
    // Calculate distance traveled over the time window using simple Pythagorean formula
    final distanceMeters = MapCalculationUtils.simpleDistance(
      firstInWindow.latitude, firstInWindow.longitude,
      point.latitude, point.longitude
    );
    
    // Convert to km/h: (meters/second) * 3.6
    return (distanceMeters / timeDiffSeconds) * 3.6;
  }

  /// Finds the closest track point index by timestamp
  int _findClosestTrackPointByTimestamp(int targetTimestamp) {
    if (_trackPoints.isEmpty) return -1;

    int closestIndex = 0;
    double minDifference = (targetTimestamp - _trackPoints[0].timestamp.millisecondsSinceEpoch).abs().toDouble();

    for (int i = 1; i < _trackPoints.length; i++) {
      final difference = (targetTimestamp - _trackPoints[i].timestamp.millisecondsSinceEpoch).abs().toDouble();
      if (difference < minDifference) {
        minDifference = difference;
        closestIndex = i;
      }
    }

    return closestIndex;
  }


  Widget _buildSynchronizedChart({
    required String title,
    required String unit,
    required Color color,
    required double Function(IgcPoint) dataExtractor,
    bool showTimeLabels = false,
    bool showGridLabels = false,
  }) {
    if (_trackPoints.length < 2) {
      return SizedBox(height: _chartHeight, child: Center(child: Text('Insufficient data for $title chart')));
    }

    // Calculate data points using actual timestamps
    final spots = _trackPoints.map((point) {
      return FlSpot(point.timestamp.millisecondsSinceEpoch.toDouble(), dataExtractor(point));
    }).toList();

    // Calculate bounds
    final values = spots.map((s) => s.y).toList();
    final minVal = values.reduce(math.min);
    final maxVal = values.reduce(math.max);
    final valRange = maxVal - minVal;
    final padding = valRange * _altitudePaddingFactor;

    return Container(
      height: _chartHeight,
      padding: const EdgeInsets.all(8),
      decoration: const BoxDecoration(
        color: Colors.white,
      ),
      child: ValueListenableBuilder<int?>(
        valueListenable: _selectedTrackPointIndex,
        builder: (context, selectedIndex, child) {
          // Create the line bar data inside the builder for proper spot references
          final lineBarData = LineChartBarData(
            spots: spots,
            isCurved: false,
            color: color,
            barWidth: 1,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: color.withValues(alpha: 0.15),
            ),
            showingIndicators: selectedIndex != null && selectedIndex < spots.length ? [selectedIndex] : [],
          );
          
          return LineChart(
            LineChartData(
          showingTooltipIndicators: selectedIndex != null && selectedIndex < spots.length ? [
            ShowingTooltipIndicators([
              LineBarSpot(
                lineBarData,
                0,
                spots[selectedIndex],
              ),
            ])
          ] : [],
          lineTouchData: LineTouchData(
            enabled: true,
            handleBuiltInTouches: false,
            touchCallback: (FlTouchEvent event, LineTouchResponse? touchResponse) {
              if (touchResponse != null && touchResponse.lineBarSpots != null && touchResponse.lineBarSpots!.isNotEmpty) {
                final spot = touchResponse.lineBarSpots!.first;
                final targetTimestamp = spot.x.toInt();
                final closestIndex = _findClosestTrackPointByTimestamp(targetTimestamp);
                
                if (closestIndex != -1) {
                  _selectedTrackPointIndex.value = closestIndex;
                }
              }
            },
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (touchedSpot) => color.withValues(alpha: 0.8),
              tooltipPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              getTooltipItems: (List<LineBarSpot> touchedBarSpots) {
                return touchedBarSpots.map((barSpot) {
                  final value = barSpot.y;
                  final displayValue = unit == 'm' ? value.toInt().toString() : value.toStringAsFixed(1);
                  return LineTooltipItem(
                    '$displayValue$unit',
                    const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  );
                }).toList();
              },
            ),
            getTouchedSpotIndicator: (LineChartBarData barData, List<int> spotIndexes) {
              return spotIndexes.map((spotIndex) {
                return TouchedSpotIndicatorData(
                  FlLine(
                    color: color.withValues(alpha: 0.5),
                    strokeWidth: 1,
                    dashArray: [3, 3],
                  ),
                  FlDotData(
                    show: true,
                    getDotPainter: (spot, percent, barData, index) {
                      return FlDotCirclePainter(
                        radius: 3,
                        color: color,
                        strokeWidth: 1,
                        strokeColor: Colors.white,
                      );
                    },
                  ),
                );
              }).toList();
            },
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: valRange / 4,
            getDrawingHorizontalLine: (value) {
              return FlLine(
                color: Colors.grey[350]!,
                strokeWidth: 0.5,
              );
            },
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: false,
                reservedSize: 0,
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: showTimeLabels,
                reservedSize: showTimeLabels ? 15 : 0,
                interval: _chartIntervalMs.toDouble(),
                getTitlesWidget: (value, meta) {
                  if (!showTimeLabels) return const SizedBox.shrink();
                  
                  final targetTimestamp = value.toInt();
                  final closestIndex = _findClosestTrackPointByTimestamp(targetTimestamp);
                  
                  if (closestIndex == -1) {
                    return const SizedBox.shrink();
                  }
                  
                  final closestPoint = _trackPoints[closestIndex];
                  final timeString = '${closestPoint.timestamp.hour.toString().padLeft(2, '0')}:${closestPoint.timestamp.minute.toString().padLeft(2, '0')}';
                  return Text(
                    timeString,
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          minX: spots.first.x,
          maxX: spots.last.x,
          minY: minVal - padding,
          maxY: maxVal + padding,
          extraLinesData: showGridLabels ? _buildGridLineLabels(minVal - padding, maxVal + padding, valRange / 4, unit) : null,
          lineBarsData: [
            lineBarData,
          ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildChartWithTitle(String title, Widget chart, {String? tooltip}) {
    return Stack(
      children: [
        chart,
        Positioned(
          top: 2,
          left: 0,
          right: 0,
          child: Center(
            child: tooltip != null
                ? AppTooltip(
                    message: tooltip,
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey,
                      ),
                    ),
                  )
                : Text(
                    title,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  ExtraLinesData _buildGridLineLabels(double minY, double maxY, double interval, String unit) {
    List<HorizontalLine> lines = [];
    
    // Calculate a small downward offset to float labels above grid lines
    double labelOffset = (maxY - minY) * -0.085; // 8.5% of the value range
    
    // Calculate grid line positions based on the interval
    // Use floor for negative values to ensure we include 0 when range crosses zero
    double currentY = minY < 0 ? (minY / interval).floor() * interval : (minY / interval).ceil() * interval;
    
    while (currentY <= maxY) {
      if (currentY >= minY && currentY <= maxY) {
        // Format the value for display based on unit
        String labelText;
        if (currentY.abs() < 0.1) {
          labelText = '0';
        } else if (unit == 'm/s') {
          // Climb rate: show decimal places
          labelText = currentY.toStringAsFixed(1);
        } else if (unit == 'm' || unit == 'km/h') {
          // Altitude (meters) and Speed (km/h): show as integers with thousand separators
          final formatter = NumberFormat('#,###');
          labelText = formatter.format(currentY.round());
        } else {
          // Fallback
          labelText = currentY.toStringAsFixed(1);
        }
        
        // Special styling for zero line
        bool isZeroLine = currentY.abs() < 0.1;
        
        // Add dotted zero line for climb rate charts
        if (isZeroLine && unit == 'm/s') {
          lines.add(HorizontalLine(
            y: currentY,
            color: Colors.grey[400]!,
            strokeWidth: 1,
            dashArray: [2, 4],
          ));
        }
        
        // Add transparent line with left label positioned above grid line
        lines.add(HorizontalLine(
          y: currentY + labelOffset,
          color: Colors.transparent,
          strokeWidth: 0,
          label: HorizontalLineLabel(
            show: true,
            labelResolver: (line) => labelText,
            style: TextStyle(
              fontSize: 9,
              color: isZeroLine ? Colors.grey[600] : Colors.grey[500],
              fontWeight: isZeroLine ? FontWeight.w500 : FontWeight.normal,
            ),
            alignment: Alignment.topLeft,
          ),
        ));
        
        // Add transparent line with right label positioned above grid line
        lines.add(HorizontalLine(
          y: currentY + labelOffset,
          color: Colors.transparent,
          strokeWidth: 0,
          label: HorizontalLineLabel(
            show: true,
            labelResolver: (line) => labelText,
            style: TextStyle(
              fontSize: 9,
              color: isZeroLine ? Colors.grey[600] : Colors.grey[500],
              fontWeight: isZeroLine ? FontWeight.w500 : FontWeight.normal,
            ),
            alignment: Alignment.topRight,
          ),
        ));
      }
      
      currentY += interval;
    }
    
    return ExtraLinesData(horizontalLines: lines);
  }

  @override
  void dispose() {
    _selectedTrackPointIndex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    PerformanceMonitor.trackWidgetRebuild('FlightTrack2D');

    if (_isLoading) {
      return SizedBox(
        height: widget.height,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return SizedBox(
        height: widget.height,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // Flight Track Map using the new refactored widget
        SizedBox(
          height: (widget.height ?? 400) - _totalChartsHeight - 20,
          child: FlightTrackMap(
            flight: widget.flight,
            trackPoints: _trackPoints,
            faiTrianglePoints: _faiTrianglePoints,
            selectedTrackPointIndex: _selectedTrackPointIndex,
            closingDistanceThreshold: _closingDistanceThreshold,
            onTrackPointSelected: (index) {
              _selectedTrackPointIndex.value = index;
            },
          ),
        ),
        // Three synchronized charts
        _buildChartWithTitle(
          'Altitude (m)',
          _buildSynchronizedChart(
            title: 'altitude',
            unit: 'm',
            color: Colors.blue,
            dataExtractor: (point) => point.gpsAltitude.toDouble(),
            showTimeLabels: false,
            showGridLabels: true,
          ),
          tooltip: 'GPS altitude above sea level in meters',
        ),
        _buildChartWithTitle(
          'Climb Rate (m/s)',
          _buildSynchronizedChart(
            title: 'climb rate',
            unit: 'm/s',
            color: Colors.green,
            dataExtractor: (point) => point.climbRate5s,
            showTimeLabels: false,
            showGridLabels: true,
          ),
          tooltip: '5 second average Climb Rate in meters per second ',
        ),
        _buildChartWithTitle(
          'Ground Speed (km/h)',
          _buildSynchronizedChart(
            title: 'ground speed',
            unit: 'km/h',
            color: Colors.orange,
            dataExtractor: (point) => _getSmoothedGroundSpeed(point),
            showTimeLabels: false,
            showGridLabels: true,
          ),
          tooltip: '5-second average GPS ground speed in km/h',
        ),
      ],
    );
  }
}
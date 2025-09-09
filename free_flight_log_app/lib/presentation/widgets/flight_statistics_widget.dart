import 'package:flutter/material.dart';
import '../../data/models/flight.dart';
import '../../data/models/igc_file.dart';
import '../../utils/date_time_utils.dart';
import '../../utils/preferences_helper.dart';
import '../../services/database_service.dart';
import '../../services/igc_parser.dart';
import '../../services/logging_service.dart';

class FlightStatisticsWidget extends StatefulWidget {
  final Flight flight;
  final VoidCallback? onFlightUpdated;

  const FlightStatisticsWidget({
    super.key,
    required this.flight,
    this.onFlightUpdated,
  });

  @override
  State<FlightStatisticsWidget> createState() => _FlightStatisticsWidgetState();
}

class _FlightStatisticsWidgetState extends State<FlightStatisticsWidget> {
  Flight? _updatedFlight;
  bool _isRecalculatingTriangle = false;
  final DatabaseService _databaseService = DatabaseService.instance;
  
  @override
  void initState() {
    super.initState();
    // Defer triangle recalculation until after first frame renders
    // This prevents blocking the UI when opening FlightDetailScreen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Run the check in a microtask to further defer execution
      Future.microtask(() => _checkAndRecalculateTriangle());
    });
  }
  
  Future<void> _checkAndRecalculateTriangle() async {
    // Get current triangle calculation version
    final currentVersion = await PreferencesHelper.getTriangleCalcVersion();
    
    LoggingService.info('FlightStatisticsWidget: Checking triangle recalculation for flight ${widget.flight.id} - currentVersion: $currentVersion, flightVersion: ${widget.flight.triangleCalcVersion}');
    
    // Check if recalculation is needed
    if (widget.flight.needsTriangleRecalculation(currentVersion) && 
        widget.flight.trackLogPath != null) {
      
      setState(() {
        _isRecalculatingTriangle = true;
      });
      
      try {
        LoggingService.info('FlightStatisticsWidget: Recalculating triangle for flight ${widget.flight.id}');
        
        // Parse IGC file and recalculate triangle
        final parser = IgcParser();
        final igcFile = await parser.parseFile(widget.flight.trackLogPath!);
        
        // Get current preferences
        final triangleSamplingInterval = await PreferencesHelper.getTriangleSamplingInterval();
        final closingDistance = await PreferencesHelper.getTriangleClosingDistance();
        
        // Recalculate closing point with new closing distance preference
        int? newClosingPointIndex = igcFile.getClosingPointIndex(maxDistanceMeters: closingDistance);
        double? actualClosingDistance;
        
        if (newClosingPointIndex != null) {
          final launchPoint = igcFile.trackPoints.first;
          final closingPoint = igcFile.trackPoints[newClosingPointIndex];
          actualClosingDistance = igcFile.calculateSimpleDistance(launchPoint, closingPoint);
          LoggingService.info('FlightStatisticsWidget: New closing point at index $newClosingPointIndex, distance: ${actualClosingDistance?.toStringAsFixed(1)}m');
        } else {
          LoggingService.info('FlightStatisticsWidget: Flight is now OPEN with closing distance ${closingDistance}m');
        }
        
        // Calculate triangle on trimmed data if closing point exists
        Map<String, dynamic> faiTriangle;
        if (newClosingPointIndex != null) {
          final trimmedIgcFile = igcFile.copyWithTrimmedPoints(0, newClosingPointIndex);
          faiTriangle = trimmedIgcFile.calculateFaiTriangle(
            samplingIntervalSeconds: triangleSamplingInterval,
            closingDistanceMeters: closingDistance,
          );
          
          // Check if triangle validation failed
          if (faiTriangle['trianglePoints'] != null && 
              (faiTriangle['trianglePoints'] as List).isEmpty) {
            // Triangle invalid - mark flight as open
            newClosingPointIndex = null;
            actualClosingDistance = null;
            faiTriangle = {'trianglePoints': null, 'triangleDistance': 0.0};
            LoggingService.info('FlightStatisticsWidget: Triangle validation failed - flight marked as OPEN');
          }
        } else {
          faiTriangle = {'trianglePoints': null, 'triangleDistance': 0.0};
        }
        
        // Convert triangle points to JSON
        String? faiTrianglePointsJson;
        if (faiTriangle['trianglePoints'] != null && 
            (faiTriangle['trianglePoints'] as List).isNotEmpty) {
          final trianglePoints = faiTriangle['trianglePoints'] as List<dynamic>;
          faiTrianglePointsJson = Flight.encodeTrianglePointsToJson(trianglePoints);
        }
        
        // Update flight with new closing point and triangle data
        final updatedFlight = widget.flight.copyWith(
          closingPointIndex: newClosingPointIndex,
          closingDistance: actualClosingDistance,
          faiTriangleDistance: faiTriangle['triangleDistance'],
          faiTrianglePoints: faiTrianglePointsJson,
          triangleCalcVersion: currentVersion,
        );
        
        // Save to database
        await _databaseService.updateFlight(updatedFlight);
        
        setState(() {
          _updatedFlight = updatedFlight;
          _isRecalculatingTriangle = false;
        });
        
        // Notify parent to refresh flight data
        widget.onFlightUpdated?.call();
        
        LoggingService.info('FlightStatisticsWidget: Triangle recalculated: ${faiTriangle['triangleDistance']} km, Closed: ${newClosingPointIndex != null}');
      } catch (e) {
        LoggingService.error('FlightStatisticsWidget: Error recalculating triangle', e);
        setState(() {
          _isRecalculatingTriangle = false;
        });
      }
    }
  }
  
  Flight get flight => _updatedFlight ?? widget.flight;

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
                  _isRecalculatingTriangle
                      ? 'Recalculating...'
                      : flight.isClosed 
                          ? '${flight.faiTriangleDistance?.toStringAsFixed(1) ?? 'N/A'} km'
                          : 'Open',
                  Icons.change_history,
                  context,
                  tooltip: _isRecalculatingTriangle
                      ? 'Recalculating triangle with updated preferences...'
                      : flight.isClosed 
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
          
          // Advanced Statistics
          if (_hasAdvancedStats()) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            _buildAdvancedStatistics(),
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

  Widget _buildAdvancedStatistics() {
    return Column(
      children: [
        // Row 1: Max Alt, Best L/D, Avg L/D, Climb % (4 items)
        if (widget.flight.maxAltitude != null || widget.flight.bestLD != null || widget.flight.avgLD != null || widget.flight.climbPercentage != null) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              if (widget.flight.maxAltitude != null)
                Expanded(
                  child: _buildStatItem(
                    'Max Alt',
                    '${widget.flight.maxAltitude!.toInt()} m',
                    Icons.height,
                    context,
                    tooltip: 'Maximum GPS altitude above sea level',
                  ),
                )
              else
                const Expanded(child: SizedBox()),
              if (widget.flight.bestLD != null)
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
              if (widget.flight.avgLD != null)
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
        
        // Row 2: Longest Glide, Thermals, Avg Thermal, Best Thermal (4 items)  
        if (widget.flight.longestGlide != null || widget.flight.thermalCount != null || widget.flight.avgThermalStrength != null || widget.flight.bestThermal != null) ...[
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
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
              if (widget.flight.thermalCount != null)
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
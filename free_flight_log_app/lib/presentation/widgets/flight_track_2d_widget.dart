import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_dragmarker/flutter_map_dragmarker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/flight.dart';
import '../../data/models/site.dart';
import '../../data/models/igc_file.dart';
import '../../services/database_service.dart';
import '../../services/logging_service.dart';
import '../../services/triangle_recalculation_service.dart';
import '../../services/flight_track_loader.dart';
import '../../utils/preferences_helper.dart';
import '../../utils/site_marker_utils.dart';
import '../../utils/ui_utils.dart';
import '../screens/flight_track_3d_fullscreen.dart';

enum MapProvider {
  openStreetMap('Street Map', 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', 18, '© OpenStreetMap contributors'),
  googleSatellite('Google Satellite', 'https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}', 18, '© Google'),
  esriWorldImagery('Esri Satellite', 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}', 18, '© Esri');

  const MapProvider(this.displayName, this.urlTemplate, this.maxZoom, this.attribution);
  
  final String displayName;
  final String urlTemplate;
  final int maxZoom;
  final String attribution;
}

class FlightTrack2DWidget extends StatefulWidget {
  final Flight flight;
  final double? height;
  final VoidCallback? onFlightUpdated;
  
  const FlightTrack2DWidget({
    super.key,
    required this.flight,
    this.height = 400,
    this.onFlightUpdated,
  });

  @override
  State<FlightTrack2DWidget> createState() => _FlightTrack2DWidgetState();
}

class _FlightTrack2DWidgetState extends State<FlightTrack2DWidget> {
  final DatabaseService _databaseService = DatabaseService.instance;
  final MapController _mapController = MapController();
  
  // Constants
  static const String _mapProviderKey = 'flight_track_2d_map_provider';
  static const String _legendExpandedKey = 'flight_track_2d_legend_expanded';
  static const double _chartHeight = 100.0;
  static const double _totalChartsHeight = 300.0; // 3 charts * 100px each
  static const double _mapPadding = 0.005;
  static const double _altitudePaddingFactor = 0.1;
  static const int _chartIntervalMinutes = 15;
  static const int _chartIntervalMs = _chartIntervalMinutes * 60 * 1000;
  
  List<IgcPoint> _trackPoints = [];
  List<IgcPoint> _faiTrianglePoints = [];
  bool _isLoading = true;
  String? _error;
  bool _mapReady = false;
  bool _hasPerformedInitialFit = false;
  MapProvider _selectedMapProvider = MapProvider.openStreetMap;
  int? _selectedTrackPointIndex;
  bool _isLegendExpanded = false; // Default to collapsed for cleaner initial view
  double _closingDistanceThreshold = 500.0; // Default value
  
  // Simplified site display state
  List<Site> _localSites = [];
  bool _isLoadingSites = true;
  
  @override
  void initState() {
    super.initState();
    _loadMapProvider();
    _loadTrackData();
    _loadClosingDistanceThreshold();
    _loadAllSites(); // Simple one-time load
  }

  @override
  void didUpdateWidget(FlightTrack2DWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Check if flight data that affects the map display has changed
    if (_shouldReloadTrackData(oldWidget.flight, widget.flight)) {
      LoggingService.ui('FlightTrack2D', 'Flight data changed, reloading track data');
      _hasPerformedInitialFit = false; // Reset fit flag for new flight data
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

  Future<void> _loadMapProvider() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final providerName = prefs.getString(_mapProviderKey);
      if (providerName != null) {
        final provider = MapProvider.values.firstWhere(
          (p) => p.name == providerName,
          orElse: () => MapProvider.openStreetMap,
        );
        setState(() {
          _selectedMapProvider = provider;
        });
      }
    } catch (e) {
      LoggingService.error('FlightTrack2DWidget: Error loading map provider', e);
    }
  }

  Future<void> _saveMapProvider(MapProvider provider) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_mapProviderKey, provider.name);
    } catch (e) {
      LoggingService.error('FlightTrack2DWidget: Error saving map provider', e);
    }
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


  Future<void> _saveLegendPreference(bool isExpanded) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_legendExpandedKey, isExpanded);
    } catch (e) {
      LoggingService.error('FlightTrack2DWidget: Error saving legend preference', e);
    }
  }

  void _toggleLegend() {
    setState(() {
      _isLegendExpanded = !_isLegendExpanded;
    });
    _saveLegendPreference(_isLegendExpanded);
  }

  Widget _buildCollapsibleLegend() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      decoration: const BoxDecoration(
        color: Color(0x80000000),
        borderRadius: BorderRadius.all(Radius.circular(4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Toggle button header
          InkWell(
            onTap: _toggleLegend,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Legend',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: _isLegendExpanded ? 0.25 : 0.0,
                    duration: const Duration(milliseconds: 300),
                    child: const Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Expandable content
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 300),
            crossFadeState: _isLegendExpanded 
                ? CrossFadeState.showFirst 
                : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Site legend items (always shown for consistent layout)
                  SiteMarkerUtils.buildLegendItem(context, Icons.location_on, SiteMarkerUtils.flownSiteColor, 'Flown Sites'),
                  const SizedBox(height: 4),
                  SiteMarkerUtils.buildLegendItem(context, Icons.location_on, SiteMarkerUtils.newSiteColor, 'New Sites'),
                  const SizedBox(height: 4),
                  // Launch and landing markers
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SiteMarkerUtils.buildLaunchMarkerIcon(
                              color: SiteMarkerUtils.launchColor,
                              size: 16,
                            ),
                            const Icon(
                              Icons.flight_takeoff,
                              color: Colors.white,
                              size: 8,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('Launch', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: Colors.white)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SiteMarkerUtils.buildLandingMarkerIcon(
                              color: SiteMarkerUtils.landingColor,
                              size: 16,
                            ),
                            const Icon(
                              Icons.flight_land,
                              color: Colors.white,
                              size: 8,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('Landing', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: Colors.white)),
                    ],
                  ),
                  
                  // Closing point legend (only for closed flights)
                  if (widget.flight.isClosed) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 16,
                          height: 16,
                          decoration: const BoxDecoration(
                            color: Colors.purple,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.change_history,
                            color: Colors.white,
                            size: 8,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('Close', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: Colors.white)),
                      ],
                    ),
                  ],
                  
                  // Closing threshold legend (only shown for closed flights)
                  if (widget.flight.isClosed && _trackPoints.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: Colors.transparent,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.purple,
                              width: 2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('Closing Threshold: ${_closingDistanceThreshold.toStringAsFixed(0)}m', 
                             style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: Colors.white)),
                      ],
                    ),
                  ],
                  
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 14, height: 3, decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(1.5))),
                      const SizedBox(width: 8),
                      Text('Climb', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: Colors.white)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 14, height: 3, decoration: BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.circular(1.5))),
                      const SizedBox(width: 8),
                      Text('Sink (<1.5m/s)', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: Colors.white)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 14, height: 3, decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(1.5))),
                      const SizedBox(width: 8),
                      Text('Sink (>1.5m/s)', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: Colors.white)),
                    ],
                  ),
                ],
              ),
            ),
            secondChild: const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  /// Simple site loading - load all sites once
  Future<void> _loadAllSites() async {
    try {
      LoggingService.debug('FlightTrack2D: Loading sites...');
      final localSites = await _databaseService.getAllSites();
      
      if (mounted) {
        setState(() {
          _localSites = localSites;
          _isLoadingSites = false;
        });
        LoggingService.debug('FlightTrack2D: Loaded ${localSites.length} sites');
      }
    } catch (e) {
      LoggingService.error('FlightTrack2DWidget: Error loading sites', e);
      if (mounted) {
        setState(() {
          _isLoadingSites = false;
        });
      }
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

      // Get triangle points (with lazy recalculation if needed)
      List<IgcPoint> faiTrianglePoints = [];
      
      try {
        final result = await TriangleRecalculationService.checkAndRecalculate(
          widget.flight,
          logContext: 'FlightTrack2D',
        );
        
        // Use triangle points from result
        faiTrianglePoints = result.trianglePoints ?? [];
        
        // Notify parent to refresh flight data if recalculation was performed
        if (result.recalculationPerformed) {
          widget.onFlightUpdated?.call();
        }
        
      } catch (e) {
        LoggingService.error('FlightTrack2D: Failed to get triangle points', e);
      }

      setState(() {
        _trackPoints = trackData.points;
        _faiTrianglePoints = faiTrianglePoints;
        _isLoading = false;
      });
      
      LoggingService.info('FlightTrack2DWidget: Loaded ${_trackPoints.length} track points, triangle: ${_faiTrianglePoints.length} points');
      
      // Try to fit map bounds now that track data is loaded
      _tryFitMapToBounds();
    } catch (e) {
      LoggingService.error('FlightTrack2DWidget: Error loading track data', e);
      setState(() {
        _error = 'Error loading track data: $e';
        _isLoading = false;
      });
    }
  }

  // Removed complex bounds-based site loading for simplicity

  double _calculateClimbRate(IgcPoint point1, IgcPoint point2) {
    final timeDiff = point2.timestamp.difference(point1.timestamp).inSeconds;
    if (timeDiff <= 0) return 0.0;
    
    final altitudeDiff = point2.gpsAltitude - point1.gpsAltitude;
    return altitudeDiff / timeDiff;
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
    final distanceMeters = _calculateSimpleDistance(
      firstInWindow.latitude, firstInWindow.longitude,
      point.latitude, point.longitude
    );
    
    // Convert to km/h: (meters/second) * 3.6
    return (distanceMeters / timeDiffSeconds) * 3.6;
  }
  
  /// Calculate distance between two lat/lng points using simple Pythagorean formula
  /// For small distances (GPS points), Earth curvature correction is negligible
  double _calculateSimpleDistance(double lat1, double lng1, double lat2, double lng2) {
    // Convert degrees to approximate meters using first point's latitude for longitude correction
    const metersPerDegreeLat = 111320.0; // Meters per degree latitude (constant)
    final metersPerDegreeLng = 111320.0 * math.cos(lat1 * math.pi / 180); // Adjust for longitude at first point's latitude
    
    final deltaLat = (lat2 - lat1) * metersPerDegreeLat;
    final deltaLng = (lng2 - lng1) * metersPerDegreeLng;
    
    return math.sqrt(deltaLat * deltaLat + deltaLng * deltaLng);
  }

  /// Format timestamp as HH:MM:SS for the time overlay
  String _formatTimeHMS(DateTime timestamp) {
    return '${timestamp.hour.toString().padLeft(2, '0')}:'
           '${timestamp.minute.toString().padLeft(2, '0')}:'
           '${timestamp.second.toString().padLeft(2, '0')}';
  }

  Color _getClimbRateColor(double climbRate) {
    if (climbRate >= 0) return Colors.green;
    if (climbRate > -1.5) return Colors.blue;
    return Colors.red;
  }

  List<Polyline> _buildColoredTrackLines() {
    if (_trackPoints.length < 2) return [];
    
    List<Polyline> lines = [];
    List<LatLng> currentSegment = [LatLng(_trackPoints[0].latitude, _trackPoints[0].longitude)];
    Color currentColor = Colors.blue; // Default for first point
    
    for (int i = 1; i < _trackPoints.length; i++) {
      final climbRate = _calculateClimbRate(_trackPoints[i-1], _trackPoints[i]);
      final color = _getClimbRateColor(climbRate);
      
      if (color != currentColor && currentSegment.length > 1) {
        // Finish current segment
        lines.add(Polyline(
          points: currentSegment,
          strokeWidth: 3.0,
          color: currentColor,
        ));
        
        // Start new segment with the last point of previous segment
        currentSegment = [currentSegment.last];
        currentColor = color;
      }
      
      currentSegment.add(LatLng(_trackPoints[i].latitude, _trackPoints[i].longitude));
      currentColor = color;
    }
    
    // Add final segment
    if (currentSegment.length > 1) {
      lines.add(Polyline(
        points: currentSegment,
        strokeWidth: 3.0,
        color: currentColor,
      ));
    }
    
    return lines;
  }

  List<Polyline> _buildFaiTriangleLines() {
    // Only show triangle for closed flights
    if (!widget.flight.isClosed || _faiTrianglePoints.length != Flight.expectedTrianglePoints) return [];
    
    // Convert IgcPoint to LatLng
    final p1 = LatLng(_faiTrianglePoints[0].latitude, _faiTrianglePoints[0].longitude);
    final p2 = LatLng(_faiTrianglePoints[1].latitude, _faiTrianglePoints[1].longitude);
    final p3 = LatLng(_faiTrianglePoints[2].latitude, _faiTrianglePoints[2].longitude);
    
    // Create triangle as dashed purple lines
    return [
      Polyline(
        points: [p1, p2],
        strokeWidth: 2.0,
        color: Colors.purple,
        pattern: StrokePattern.dashed(segments: [5, 5]),
      ),
      Polyline(
        points: [p2, p3],
        strokeWidth: 2.0,
        color: Colors.purple,
        pattern: StrokePattern.dashed(segments: [5, 5]),
      ),
      Polyline(
        points: [p3, p1],
        strokeWidth: 2.0,
        color: Colors.purple,
        pattern: StrokePattern.dashed(segments: [5, 5]),
      ),
    ];
  }

  List<Marker> _buildTriangleDistanceMarkers() {
    // Only show for closed flights with valid triangle
    if (!widget.flight.isClosed || _faiTrianglePoints.length != Flight.expectedTrianglePoints) return [];
    
    // Convert IgcPoint to LatLng
    final p1 = LatLng(_faiTrianglePoints[0].latitude, _faiTrianglePoints[0].longitude);
    final p2 = LatLng(_faiTrianglePoints[1].latitude, _faiTrianglePoints[1].longitude);
    final p3 = LatLng(_faiTrianglePoints[2].latitude, _faiTrianglePoints[2].longitude);
    
    // Calculate distances in meters and convert to km
    final side1Distance = _calculateDistance(p1, p2) / 1000.0; // P1-P2
    final side2Distance = _calculateDistance(p2, p3) / 1000.0; // P2-P3
    final side3Distance = _calculateDistance(p3, p1) / 1000.0; // P3-P1
    
    // Calculate midpoints for label placement
    final midpoint1 = LatLng((p1.latitude + p2.latitude) / 2, (p1.longitude + p2.longitude) / 2);
    final midpoint2 = LatLng((p2.latitude + p3.latitude) / 2, (p2.longitude + p3.longitude) / 2);
    final midpoint3 = LatLng((p3.latitude + p1.latitude) / 2, (p3.longitude + p1.longitude) / 2);
    
    return [
      // Side 1 distance label
      Marker(
        point: midpoint1,
        width: 60,
        height: 20,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(3),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Center(
            child: Text(
              '${side1Distance.toStringAsFixed(1)}km',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
      // Side 2 distance label
      Marker(
        point: midpoint2,
        width: 60,
        height: 20,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(3),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Center(
            child: Text(
              '${side2Distance.toStringAsFixed(1)}km',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
      // Side 3 distance label
      Marker(
        point: midpoint3,
        width: 60,
        height: 20,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(3),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Center(
            child: Text(
              '${side3Distance.toStringAsFixed(1)}km',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    ];
  }

  List<CircleMarker> _buildClosingDistanceCircle() {
    // Only show for closed flights
    if (!widget.flight.isClosed || _trackPoints.isEmpty) {
      return [];
    }
    
    final launchPoint = _trackPoints.first;
    
    return [
      CircleMarker(
        point: LatLng(launchPoint.latitude, launchPoint.longitude),
        radius: _closingDistanceThreshold,  // Use preference value
        useRadiusInMeter: true,
        color: Colors.transparent,  // No fill
        borderColor: Colors.purple,
        borderStrokeWidth: 2.0,
      ),
    ];
  }

  void _onMapTapped(LatLng position) {
    final closestIndex = _findClosestTrackPointByPosition(position);
    if (closestIndex == -1) return;
    
    setState(() {
      _selectedTrackPointIndex = closestIndex;
    });
  }
  
  double _calculateDistance(LatLng point1, LatLng point2) {
    // Simple distance calculation (Haversine would be more accurate but this is sufficient)
    final lat1Rad = point1.latitude * (math.pi / 180);
    final lat2Rad = point2.latitude * (math.pi / 180);
    final deltaLat = (point2.latitude - point1.latitude) * (math.pi / 180);
    final deltaLng = (point2.longitude - point1.longitude) * (math.pi / 180);
    
    final a = math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(lat1Rad) * math.cos(lat2Rad) *
        math.sin(deltaLng / 2) * math.sin(deltaLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    
    return 6371000 * c; // Earth radius in meters
  }

  /// Finds the closest track point index by geographic distance
  int _findClosestTrackPointByPosition(LatLng position) {
    if (_trackPoints.isEmpty) return -1;
    
    int closestIndex = 0;
    double minDistance = _calculateDistance(position, LatLng(_trackPoints[0].latitude, _trackPoints[0].longitude));
    
    for (int i = 1; i < _trackPoints.length; i++) {
      final distance = _calculateDistance(position, LatLng(_trackPoints[i].latitude, _trackPoints[i].longitude));
      if (distance < minDistance) {
        minDistance = distance;
        closestIndex = i;
      }
    }
    
    return closestIndex;
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

  List<Marker> _buildTrackPointMarker() {
    if (_selectedTrackPointIndex == null || _selectedTrackPointIndex! >= _trackPoints.length || _trackPoints.isEmpty) {
      return [];
    }
    
    final point = _trackPoints[_selectedTrackPointIndex!];
    
    // Calculate distance from launch point
    final launchPoint = _trackPoints.first;
    final distance = _calculateDistance(
      LatLng(launchPoint.latitude, launchPoint.longitude),
      LatLng(point.latitude, point.longitude)
    );
    
    return [
      Marker(
        point: LatLng(point.latitude, point.longitude),
        width: 80,  // Increased to accommodate label
        height: 40,  // Increased for label
        anchor: const AnchorPos.align(AnchorAlign.bottom), // Center the yellow circle on the track point
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Distance label above the marker
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                '${distance.toStringAsFixed(0)}m',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 2),
            // Existing yellow/amber circle
            Container(
              width: 12,
              height: 12,
              decoration: const BoxDecoration(
                color: SiteMarkerUtils.selectedPointColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ];
  }

  List<DragMarker> _buildFlightMarkers() {
    if (_trackPoints.isEmpty) return [];
    
    final firstPoint = _trackPoints.first;
    final lastPoint = _trackPoints.last;
    
    return [
      // Launch marker
      DragMarker(
        point: LatLng(firstPoint.latitude, firstPoint.longitude),
        size: const Size(32, 32),
        disableDrag: true, // Disable drag functionality
        builder: (ctx, point, isDragging) => Stack(
          alignment: Alignment.center,
          children: [
            SiteMarkerUtils.buildLaunchMarkerIcon(
              color: SiteMarkerUtils.launchColor,
              size: SiteMarkerUtils.launchMarkerSize,
            ),
            const Icon(
              Icons.flight_takeoff,
              color: Colors.white,
              size: 14,
            ),
          ],
        ),
      ),
      // Landing marker
      DragMarker(
        point: LatLng(lastPoint.latitude, lastPoint.longitude),
        size: const Size(32, 32),
        disableDrag: true, // Disable drag functionality
        builder: (ctx, point, isDragging) => AppTooltip(
          message: widget.flight.landingDescription ?? 'Landing Site',
          child: Stack(
            alignment: Alignment.center,
            children: [
              SiteMarkerUtils.buildLandingMarkerIcon(
                color: SiteMarkerUtils.landingColor,
                size: SiteMarkerUtils.launchMarkerSize,
              ),
              const Icon(
                Icons.flight_land,
                color: Colors.white,
                size: 14,
              ),
            ],
          ),
        ),
      ),
      
      // Closing point marker (debug feature)
      if (widget.flight.isClosed && 
          widget.flight.closingPointIndex != null &&
          _trackPoints.isNotEmpty) ..._buildClosingPointMarker(),
    ];
  }

  List<DragMarker> _buildClosingPointMarker() {
    // The closingPointIndex is already relative to trimmed data (index 0 = takeoff)
    // No adjustment needed since both stored index and display data are trimmed consistently
    int adjustedIndex = widget.flight.closingPointIndex!;
    
    // Ensure the adjusted index is within bounds
    if (adjustedIndex < 0 || adjustedIndex >= _trackPoints.length) {
      return [];
    }
    
    return [
      DragMarker(
        point: LatLng(_trackPoints[adjustedIndex].latitude, _trackPoints[adjustedIndex].longitude),
        size: const Size(60, 40),
        offset: const Offset(-30, -12), // Center the 24px circle on the closing point
        disableDrag: true,
        builder: (ctx, point, isDragging) => IgnorePointer(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            // Closing point marker icon
            Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(
                color: Colors.purple,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              child: const Icon(
                Icons.change_history,
                color: Colors.white,
                size: 14,
              ),
            ),
            const SizedBox(height: 2),
            // Distance label
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.purple.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(3),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Text(
                '${widget.flight.closingDistance?.toStringAsFixed(0) ?? 'N/A'}m',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        ),
      ),
    ];
  }

  /// Build simple site markers (local sites only for simplicity)
  List<DragMarker> _buildSiteMarkers() {
    return _localSites.map((site) => DragMarker(
      point: LatLng(site.latitude, site.longitude),
      size: const Size(100, 60),
      offset: const Offset(0, -SiteMarkerUtils.siteMarkerSize / 2),
      disableDrag: true,
      builder: (ctx, point, isDragging) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SiteMarkerUtils.buildSiteMarkerIcon(
            color: SiteMarkerUtils.flownSiteColor,
          ),
          SiteMarkerUtils.buildSiteLabel(
            siteName: site.name,
            flightCount: null, // Simplified - no flight counts
          ),
        ],
      ),
    )).toList();
  }

  LatLngBounds _calculateBounds() {
    if (_trackPoints.isEmpty) {
      return LatLngBounds(
        const LatLng(46.9480, 7.4474),
        const LatLng(46.9580, 7.4574),
      );
    }
    
    double minLat = _trackPoints.first.latitude;
    double maxLat = _trackPoints.first.latitude;
    double minLng = _trackPoints.first.longitude;
    double maxLng = _trackPoints.first.longitude;
    
    for (final point in _trackPoints) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLng = math.min(minLng, point.longitude);
      maxLng = math.max(maxLng, point.longitude);
    }
    
    // Add padding
    return LatLngBounds(
      LatLng(minLat - _mapPadding, minLng - _mapPadding),
      LatLng(maxLat + _mapPadding, maxLng + _mapPadding),
    );
  }

  void _onMapReady() {
    _mapReady = true;
    LoggingService.debug('FlightTrack2D: Map ready, attempting bounds fit');
    
    // Always try to fit bounds when map becomes ready
    if (_trackPoints.isNotEmpty && !_hasPerformedInitialFit) {
      // For initial load, delay fitCamera to allow tiles to load
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _tryFitMapToBounds();
        }
      });
    } else {
      _tryFitMapToBounds();
    }
  }

  void _tryFitMapToBounds() {
    // Only fit bounds when both map is ready AND track points are loaded
    if (_mapReady && _trackPoints.isNotEmpty && !_isLoading && !_hasPerformedInitialFit) {
      _fitCameraToBounds();
      _hasPerformedInitialFit = true;
      LoggingService.debug('FlightTrack2D: Initial map bounds fit completed');
    } else if (!_hasPerformedInitialFit) {
      LoggingService.debug('FlightTrack2D: Cannot fit bounds yet - mapReady: $_mapReady, trackPoints: ${_trackPoints.length}, loading: $_isLoading');
    }
  }

  void _fitCameraToBounds() {
    final bounds = _calculateBounds();
    _mapController.fitCamera(CameraFit.bounds(bounds: bounds));
    LoggingService.debug('FlightTrack2D: Fitted map to bounds with ${_trackPoints.length} track points');
  }

  void _openFullscreen3D() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FlightTrack3DFullscreenScreen(flight: widget.flight),
      ),
    );
  }

  IconData _getProviderIcon(MapProvider provider) {
    switch (provider) {
      case MapProvider.openStreetMap:
        return Icons.map;
      case MapProvider.googleSatellite:
        return Icons.satellite;
      case MapProvider.esriWorldImagery:
        return Icons.terrain;
    }
  }
  
  Widget _buildMapProviderButton() {
    return Container(
      decoration: BoxDecoration(
        color: Color(0x80000000),
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: PopupMenuButton<MapProvider>(
        tooltip: 'Change Maps',
        onSelected: (provider) async {
          setState(() {
            _selectedMapProvider = provider;
          });
          await _saveMapProvider(provider);
        },
        initialValue: _selectedMapProvider,
        itemBuilder: (context) => MapProvider.values.map((provider) {
          return PopupMenuItem<MapProvider>(
            value: provider,
            child: Row(
              children: [
                Icon(
                  _getProviderIcon(provider),
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(provider.displayName),
                ),
              ],
            ),
          );
        }).toList(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _getProviderIcon(_selectedMapProvider),
                size: 16,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              Icon(
                Icons.arrow_drop_down,
                size: 16,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _build3DViewButton() {
    return Container(
      decoration: BoxDecoration(
        color: Color(0x80000000),
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: AppTooltip(
        message: '3D Fly Through',
        child: InkWell(
          onTap: _openFullscreen3D,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Icon(
              Icons.threed_rotation,
              size: 16,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
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

    // Create the line bar data
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
      showingIndicators: _selectedTrackPointIndex != null 
        ? [_selectedTrackPointIndex!] 
        : [],
    );

    return Container(
      height: _chartHeight,
      padding: const EdgeInsets.all(8),
      decoration: const BoxDecoration(
        color: Colors.white,
      ),
      child: LineChart(
        LineChartData(
          showingTooltipIndicators: _selectedTrackPointIndex != null ? [
            ShowingTooltipIndicators([
              LineBarSpot(
                lineBarData,
                0,
                spots[_selectedTrackPointIndex!],
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
                  setState(() {
                    _selectedTrackPointIndex = closestIndex;
                  });
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
    // Simplified - no timers to cancel
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
        // Flight Track Map
        SizedBox(
          height: (widget.height ?? 400) - _totalChartsHeight - 20,
          child: Stack(
            children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _trackPoints.isNotEmpty
                  ? LatLng(_trackPoints.first.latitude, _trackPoints.first.longitude)
                  : const LatLng(46.9480, 7.4474),
              initialZoom: 13.0,
              minZoom: 1.0,
              maxZoom: _selectedMapProvider.maxZoom.toDouble(),
              onMapReady: _onMapReady,
              onTap: (tapPosition, point) => _onMapTapped(point),
            ),
            children: [
              TileLayer(
                urlTemplate: _selectedMapProvider.urlTemplate,
                maxZoom: _selectedMapProvider.maxZoom.toDouble(),
                userAgentPackageName: 'com.example.free_flight_log_app',
              ),
              PolylineLayer(
                polylines: [..._buildColoredTrackLines(), ..._buildFaiTriangleLines()],
              ),
              CircleLayer(
                circles: _buildClosingDistanceCircle(),
              ),
              DragMarkers(
                markers: [..._buildSiteMarkers(), ..._buildFlightMarkers()],
              ),
              // Keep track point marker as regular MarkerLayer since it's just a selection indicator
              MarkerLayer(
                markers: _buildTrackPointMarker(),
                rotate: false,
              ),
              // Triangle distance labels
              MarkerLayer(
                markers: _buildTriangleDistanceMarkers(),
                rotate: false,
              ),
            ],
          ),
          // Top right controls (map provider and 3D view)
          Positioned(
            top: 8,
            right: 8,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _build3DViewButton(),
                const SizedBox(width: 8),
                _buildMapProviderButton(),
              ],
            ),
          ),
          // Collapsible Legend for track colors and sites
          Positioned(
            top: 8,
            left: 8,
            child: _buildCollapsibleLegend(),
          ),
          // Attribution
          Positioned(
            bottom: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey[900]!.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                _selectedMapProvider.attribution,
                style: const TextStyle(fontSize: 8, color: Colors.white70),
              ),
            ),
          ),
          // Removed loading indicator for simplicity
          // Time display overlay for selected point
          if (_selectedTrackPointIndex != null && _selectedTrackPointIndex! < _trackPoints.length)
            Positioned(
              bottom: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  'Time: ${_formatTimeHMS(_trackPoints[_selectedTrackPointIndex!].timestamp)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            // Sites loading indicator
            if (_isLoadingSites && !_isLoading)
              Positioned(
                top: _isLegendExpanded ? 180 : 50,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Loading sites...',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Loading overlay
            if (_isLoading)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.7),
                  child: const Center(
                    child: CircularProgressIndicator(),
                  ),
                ),
              ),
            ],
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
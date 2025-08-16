import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../data/models/flight.dart';
import '../../data/models/igc_file.dart';
import '../../services/igc_import_service.dart';
import '../../services/logging_service.dart';
import '../controllers/flight_playback_controller.dart';

// FLUTTER_MAP TILE LOADING SOLUTION:
// This widget implements delayed TileLayer creation to solve a flutter_map race condition
// where tiles fail to load on the first widget creation. The solution:
// 1. Create FlutterMap immediately with stable preferences
// 2. Only add TileLayer after onMapReady callback fires (_tilesReady = true)
// 3. Sequential preference loading prevents tile URL instability
// 
// This approach is faster and cleaner than artificial delays or forced rebuilds.

/// Isolate-compatible polyline calculation to prevent main thread blocking
/// This function runs in a background isolate for heavy computational tasks
List<Polyline> _calculatePolylinesIsolate(Map<String, dynamic> data) {
  final List<Map<String, dynamic>> pointMaps = List<Map<String, dynamic>>.from(data['points']);
  final List<double> climbRates = List<double>.from(data['climbRates']);
  final bool showLabels = data['showLabels'] as bool;
  
  // Convert point maps back to coordinate objects
  final List<LatLng> trackCoordinates = pointMaps
      .map((pointMap) => LatLng(pointMap['lat'] as double, pointMap['lng'] as double))
      .toList();
  
  final polylines = <Polyline>[];
  
  if (climbRates.isEmpty) {
    // Simple red track for flights without climb rate data
    polylines.add(Polyline(
      points: trackCoordinates,
      color: const Color(0xFFFF0000), // Colors.red
      strokeWidth: 3.0,
    ));
    return polylines;
  }
  
  // Create colored segments between consecutive points
  for (int i = 0; i < trackCoordinates.length - 1; i++) {
    final currentPoint = trackCoordinates[i];
    final nextPoint = trackCoordinates[i + 1];
    
    // Get climb rate for current point (handle index bounds)
    final climbRate = i < climbRates.length ? climbRates[i] : 0.0;
    
    // Calculate color based on climb rate using helper function
    final color = _getClimbRateColorStatic(climbRate);
    
    polylines.add(
      Polyline(
        points: [currentPoint, nextPoint],
        color: color,
        strokeWidth: 3.0,
      ),
    );
  }
  
  // Add straight line polyline if enabled
  if (showLabels && trackCoordinates.length >= 2) {
    final launchPoint = trackCoordinates.first;
    final landingPoint = trackCoordinates.last;
    
    polylines.add(Polyline(
      points: [launchPoint, landingPoint],
      color: const Color(0xFF9E9E9E), // Colors.grey
      strokeWidth: 4.0,
      pattern: const StrokePattern.dotted(),
    ));
  }
  
  return polylines;
}

/// Helper function for climb rate color calculation (isolate-compatible)
Color _getClimbRateColorStatic(double climbRate) {
  // Simple 3-tier color scheme based on fixed thresholds
  // Red: Strong sink (rate <= -1.5 m/s)
  // Royal Blue: Weak sink (-1.5 < rate < 0 m/s)  
  // Green: Any climb (rate >= 0 m/s)
  
  if (climbRate <= -1.5) {
    return const Color(0xFFFF0000); // Colors.red
  } else if (climbRate < 0) {
    return const Color(0xFF1976D2); // Colors.blue[700]
  } else {
    return const Color(0xFF4CAF50); // Colors.green
  }
}

class FlightTrackConfig {
  final bool embedded;
  final bool showLegend;
  final bool showFAB;
  final bool interactive;
  final bool showStraightLine;
  final double? height;

  const FlightTrackConfig({
    this.embedded = false,
    this.showLegend = true,
    this.showFAB = true,
    this.interactive = true,
    this.showStraightLine = true,
    this.height,
  });

  FlightTrackConfig.embedded()
      : embedded = true,
        showLegend = false,
        showFAB = false,
        interactive = false,
        showStraightLine = true,
        height = 250;

  FlightTrackConfig.embeddedMap()
      : embedded = true,
        showLegend = true,
        showFAB = true,
        interactive = true,
        showStraightLine = true,
        height = 400;

  FlightTrackConfig.embeddedWithControls()
      : embedded = true,
        showLegend = true,
        showFAB = true,
        interactive = true,
        showStraightLine = true,
        height = 500;

  FlightTrackConfig.fullScreen()
      : embedded = false,
        showLegend = true,
        showFAB = true,
        interactive = true,
        showStraightLine = true,
        height = null;
}

class FlightTrackWidget extends StatefulWidget {
  final Flight flight;
  final FlightTrackConfig config;
  final Function(int)? onPointSelected;
  final bool showPlaybackPanel;

  const FlightTrackWidget({
    super.key,
    required this.flight,
    required this.config,
    this.onPointSelected,
    this.showPlaybackPanel = false,
  });

  @override
  State<FlightTrackWidget> createState() => _FlightTrackWidgetState();
}

class _FlightTrackWidgetState extends State<FlightTrackWidget> with WidgetsBindingObserver {
  MapController? _mapController;
  final IgcImportService _igcService = IgcImportService.instance;
  
  List<IgcPoint> _trackPoints = [];
  List<double> _instantaneousRates = [];
  List<double> _fifteenSecondRates = [];
  List<Polyline> _polylines = [];
  List<Marker> _markers = [];
  bool _isLoading = true;
  String? _error;
  
  // Map display options with persistent settings for full screen mode
  bool _showLabels = true;
  bool _showSatelliteView = false;
  bool _showLegend = true;
  bool _preferencesLoaded = false;
  bool _tilesReady = false; // Controls when TileLayer is added to prevent flutter_map race condition
  bool _isGeneratingPolylines = false; // Controls loading state during background polyline generation
  
  // Removed old hover system - now using unified playback controller linking
  
  // Playback controller for timeline scrubbing
  FlightPlaybackController? _playbackController;
  
  // Debounce timer for playback updates to reduce rebuild frequency
  Timer? _playbackUpdateTimer;
  
  // Static global cache for polylines to persist across widget rebuilds
  static final Map<String, List<Polyline>> _globalPolylineCache = <String, List<Polyline>>{};
  static const int _maxCacheSize = 10; // Limit cache size to prevent memory issues
  
  // Current playback position marker
  int? _playbackPointIndex;
  
  // Chart interaction key for accurate coordinate mapping
  final GlobalKey _chartKey = GlobalKey();
  
  // Cached chart data to avoid recalculation during playback
  List<FlSpot>? _cachedAltitudeData;
  Map<double, int> _timeToChartIndexMap = {}; // Maps x-axis time to chart spot index
  final ValueNotifier<int?> _chartIndicatorIndex = ValueNotifier<int?>(null);
  final ValueNotifier<double?> _chartVerticalLineTime = ValueNotifier<double?>(null);
  Timer? _verticalLineUpdateTimer; // For less frequent vertical line updates
  
  // Auto-follow throttling
  
  // Old label position variables removed - no longer needed without hover system

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeWidget();
  }

  Future<void> _initializeWidget() async {
    // Load preferences first to ensure stable tile URLs when TileLayer is created
    await _loadSavedPreferences();
    
    // Load track data
    _loadTrackData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _playbackController?.removeListener(_onPlaybackChanged);
    _playbackController?.dispose();
    // Cancel debounce timer
    _playbackUpdateTimer?.cancel();
    // Cancel vertical line update timer
    _verticalLineUpdateTimer?.cancel();
    // Dispose notifiers
    _chartIndicatorIndex.dispose();
    _chartVerticalLineTime.dispose();
    // Note: We don't clear the global cache on dispose to allow reuse
    super.dispose();
  }
  
  /// Clear global cache (for testing or memory management)
  static void clearGlobalCache() {
    _globalPolylineCache.clear();
    LoggingService.debug('FlightTrackWidget: Cleared global polylines cache');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Reload preferences when app comes back to foreground
      _loadSavedPreferences();
    }
  }

  @override
  void didUpdateWidget(FlightTrackWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload preferences when widget is updated (e.g., when navigating back to this screen)
    _loadSavedPreferences();
  }


  Future<void> _loadSavedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final newShowLabels = prefs.getBool('flight_track_show_labels') ?? 
          (prefs.getBool('flight_track_show_markers') ?? true); // Backward compatibility
      final newShowSatelliteView = prefs.getBool('flight_track_show_satellite') ?? false;
      final newShowLegend = prefs.getBool('flight_track_show_legend') ?? true;
      
      // Check if labels changed to recreate markers/polylines
      final labelsChanged = newShowLabels != _showLabels;
      
      if (mounted) {
        setState(() {
          _showLabels = newShowLabels;
          _showSatelliteView = newShowSatelliteView;
          _showLegend = newShowLegend;
          _preferencesLoaded = true;
        });
        
        // Recreate markers and polylines if labels changed and we have track data
        if (labelsChanged && _trackPoints.isNotEmpty) {
          _createMarkers();
          _createPolylinesAsync();
        }
      }
    } catch (e) {
      _preferencesLoaded = true; // Ensure we don't block forever on error
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
      final trackPoints = await _igcService.getTrackPoints(widget.flight.trackLogPath!);
      
      if (trackPoints.isEmpty) {
        setState(() {
          _error = 'No track points found';
          _isLoading = false;
        });
        return;
      }

      // Calculate climb rates from IGC data
      final igcFile = await _igcService.getIgcFile(widget.flight.trackLogPath!);
      final instantaneousRates = igcFile.calculateInstantaneousClimbRates();
      final fifteenSecondRates = _calculateGPS15SecondClimbRates(trackPoints);

      setState(() {
        _trackPoints = trackPoints;
        _instantaneousRates = instantaneousRates;
        _fifteenSecondRates = fifteenSecondRates;
        _isLoading = false;
      });
      
      // Prepare and cache altitude chart data
      _cachedAltitudeData = _prepareAltitudeChartData();
      
      // Build time-to-index mapping for quick lookups
      _timeToChartIndexMap.clear();
      if (_cachedAltitudeData != null) {
        for (int i = 0; i < _cachedAltitudeData!.length; i++) {
          _timeToChartIndexMap[_cachedAltitudeData![i].x] = i;
        }
      }
      
      // Initialize playback controller if needed
      if (widget.showPlaybackPanel) {
        _playbackController = FlightPlaybackController(
          trackPoints: trackPoints,
          instantaneousClimbRates: instantaneousRates,
          averagedClimbRates: fifteenSecondRates,
        );
        _playbackController!.addListener(_onPlaybackChanged);
      }
      
      await _createPolylinesAsync();
      _createMarkers();
      // Don't call _fitMapToBounds() here - it will be called in onMapReady
      
    } catch (e) {
      setState(() {
        _error = 'Error loading track data: $e';
        _isLoading = false;
      });
    }
  }

  /// Async polyline creation using background isolate to prevent main thread blocking
  Future<void> _createPolylinesAsync() async {
    if (_trackPoints.isEmpty) return;

    // Check global cache first
    final cacheKey = _createPolylineseCacheKey();
    if (_globalPolylineCache.containsKey(cacheKey)) {
      LoggingService.debug('FlightTrackWidget: Using cached polylines for key: ${cacheKey.substring(0, 16)}...');
      setState(() {
        _polylines = _globalPolylineCache[cacheKey]!;
      });
      return;
    }

    // Show loading state
    setState(() {
      _isGeneratingPolylines = true;
    });

    try {
      final startTime = DateTime.now();
      
      // Prepare data for isolate (must be serializable)
      final polylineData = {
        'points': _trackPoints.map((point) => {
          'lat': point.latitude,
          'lng': point.longitude,
        }).toList(),
        'climbRates': _fifteenSecondRates,
        'showLabels': _showLabels,
      };

      // Generate polylines in background isolate
      final polylines = await compute(_calculatePolylinesIsolate, polylineData);
      
      final duration = DateTime.now().difference(startTime);
      LoggingService.performance('Generate polylines (isolate)', duration, '${polylines.length} polylines created');

      // Cache and update UI
      if (mounted) {
        _cachePolylines(cacheKey, polylines);
        setState(() {
          _polylines = polylines;
          _isGeneratingPolylines = false;
        });
      }
      
    } catch (e) {
      LoggingService.error('FlightTrackWidget: Failed to generate polylines in background', e);
      
      // Fallback to synchronous generation
      if (mounted) {
        final fallbackPolylines = _createClimbRateColoredPolylinesFallback();
        setState(() {
          _polylines = fallbackPolylines;
          _isGeneratingPolylines = false;
        });
      }
    }
  }

  /// Fallback synchronous polyline generation for error cases
  List<Polyline> _createClimbRateColoredPolylinesFallback() {
    if (_trackPoints.length < 2) return [];
    
    final polylines = <Polyline>[];
    
    // Simple red track as fallback
    final trackCoordinates = _trackPoints
        .map((point) => LatLng(point.latitude, point.longitude))
        .toList();

    polylines.add(Polyline(
      points: trackCoordinates,
      color: Colors.red,
      strokeWidth: 3.0,
    ));
    
    return polylines;
  }

  List<Polyline> _createClimbRateColoredPolylines() {
    if (_trackPoints.length < 2) return [];
    
    // Create comprehensive cache key using flight ID + data fingerprint
    final cacheKey = _createPolylineseCacheKey();
    
    // Check global cache first
    if (_globalPolylineCache.containsKey(cacheKey)) {
      LoggingService.debug('FlightTrackWidget: Using cached polylines for key: ${cacheKey.substring(0, 16)}...');
      return _globalPolylineCache[cacheKey]!;
    }
    
    LoggingService.debug('FlightTrackWidget: Cache miss - creating polylines for key: ${cacheKey.substring(0, 16)}...');
    
    // If no climb rate data, create a simple red track
    if (_fifteenSecondRates.isEmpty) {
      LoggingService.debug('FlightTrackWidget: No climb rate data available, showing red track');
      final trackCoordinates = _trackPoints
          .map((point) => LatLng(point.latitude, point.longitude))
          .toList();

      final simplePolyline = [Polyline(
        points: trackCoordinates,
        color: Colors.red,
        strokeWidth: 3.0,
      )];
      
      // Cache the result globally
      _cachePolylines(cacheKey, simplePolyline);
      return simplePolyline;
    }

    LoggingService.debug('FlightTrackWidget: Creating climb rate colored track with ${_fifteenSecondRates.length} climb rate points');

    final polylines = <Polyline>[];

    // Create colored segments between consecutive points
    for (int i = 0; i < _trackPoints.length - 1; i++) {
      final currentPoint = _trackPoints[i];
      final nextPoint = _trackPoints[i + 1];
      
      // Get climb rate for current point (handle index bounds)
      final climbRate = i < _fifteenSecondRates.length ? _fifteenSecondRates[i] : 0.0;
      
      // Calculate color based on climb rate
      final color = _getClimbRateColor(climbRate);
      
      polylines.add(
        Polyline(
          points: [
            LatLng(currentPoint.latitude, currentPoint.longitude),
            LatLng(nextPoint.latitude, nextPoint.longitude),
          ],
          color: color,
          strokeWidth: 3.0,
        ),
      );
    }
    
    // Cache the result globally
    _cachePolylines(cacheKey, polylines);
    return polylines;
  }
  
  /// Create a comprehensive cache key based on flight ID and data fingerprint
  String _createPolylineseCacheKey() {
    // Use flight ID as primary key
    final flightId = widget.flight.id?.toString() ?? 'unknown';
    
    // Create data fingerprint using critical data points
    final dataPoints = <String>[];
    
    // Add basic metrics
    dataPoints.add('pts:${_trackPoints.length}');
    dataPoints.add('rates:${_fifteenSecondRates.length}');
    
    // Sample key points for fingerprint (first, middle, last + every 10th point)
    if (_trackPoints.isNotEmpty) {
      dataPoints.add('f:${_trackPoints.first.latitude.toStringAsFixed(6)},${_trackPoints.first.longitude.toStringAsFixed(6)},${_trackPoints.first.gpsAltitude}');
      
      if (_trackPoints.length > 1) {
        final mid = _trackPoints.length ~/ 2;
        dataPoints.add('m:${_trackPoints[mid].latitude.toStringAsFixed(6)},${_trackPoints[mid].longitude.toStringAsFixed(6)},${_trackPoints[mid].gpsAltitude}');
        dataPoints.add('l:${_trackPoints.last.latitude.toStringAsFixed(6)},${_trackPoints.last.longitude.toStringAsFixed(6)},${_trackPoints.last.gpsAltitude}');
      }
    }
    
    // Sample climb rates (first, middle, last)
    if (_fifteenSecondRates.isNotEmpty) {
      dataPoints.add('cr_f:${_fifteenSecondRates.first.toStringAsFixed(2)}');
      if (_fifteenSecondRates.length > 1) {
        final mid = _fifteenSecondRates.length ~/ 2;
        dataPoints.add('cr_m:${_fifteenSecondRates[mid].toStringAsFixed(2)}');
        dataPoints.add('cr_l:${_fifteenSecondRates.last.toStringAsFixed(2)}');
      }
    }
    
    // Create hash of the data fingerprint
    final fingerprint = dataPoints.join('|');
    final bytes = utf8.encode(fingerprint);
    final hash = sha256.convert(bytes).toString();
    
    return 'flight_${flightId}_$hash';
  }
  
  /// Cache polylines with size management
  void _cachePolylines(String key, List<Polyline> polylines) {
    // Manage cache size by removing oldest entries
    if (_globalPolylineCache.length >= _maxCacheSize) {
      final oldestKey = _globalPolylineCache.keys.first;
      _globalPolylineCache.remove(oldestKey);
      LoggingService.debug('FlightTrackWidget: Evicted old cache entry: ${oldestKey.substring(0, 16)}...');
    }
    
    _globalPolylineCache[key] = polylines;
    LoggingService.debug('FlightTrackWidget: Cached polylines for key: ${key.substring(0, 16)}... (cache size: ${_globalPolylineCache.length})');
  }

  Color _getClimbRateColor(double climbRate) {
    // Simple 3-tier color scheme based on fixed thresholds
    // Red: Strong sink (rate <= -1.5 m/s)
    // Royal Blue: Weak sink (-1.5 < rate < 0 m/s)  
    // Green: Any climb (rate >= 0 m/s)
    
    if (climbRate <= -1.5) {
      return Colors.red;
    } else if (climbRate < 0) {
      return Colors.blue[700]!;
    } else {
      return Colors.green;
    }
  }

  void _createMarkers() {
    if (_trackPoints.isEmpty) {
      setState(() {
        _markers = [];
      });
      return;
    }

    final markers = <Marker>[];

    // Add label markers if enabled
    if (_showLabels) {
      final startPoint = _trackPoints.first;
      final endPoint = _trackPoints.last;
      
      // Find highest point
      final highestPoint = _trackPoints.reduce(
        (a, b) => a.gpsAltitude > b.gpsAltitude ? a : b
      );

      // Position storage removed - no longer needed without hover system

      markers.addAll([
        Marker(
          point: LatLng(startPoint.latitude, startPoint.longitude),
          child: _buildCircleMarker(Colors.blue, 'Launch'),
          width: 18,
          height: 18,
        ),
        Marker(
          point: LatLng(endPoint.latitude, endPoint.longitude),
          child: _buildCircleMarker(Colors.red, 'Landing'),
          width: 18,
          height: 18,
        ),
        Marker(
          point: LatLng(highestPoint.latitude, highestPoint.longitude),
          child: _buildCircleMarker(Colors.green, 'High Point'),
          width: 18,
          height: 18,
        ),
      ]);
    }

    // Old hover crosshairs system removed - now using unified playback controller
    
    // Add playback position marker
    if (_playbackPointIndex != null && _playbackPointIndex! < _trackPoints.length) {
      final playbackPoint = _trackPoints[_playbackPointIndex!];
      
      markers.add(
        Marker(
          point: LatLng(playbackPoint.latitude, playbackPoint.longitude),
          child: _buildPlaybackMarker(),
          width: 24,
          height: 24,
        ),
      );
    }

    // Add straight distance marker at midpoint if showing labels
    if (_showLabels && _trackPoints.length >= 2 && widget.flight.straightDistance != null) {
      final startPoint = _trackPoints.first;
      final endPoint = _trackPoints.last;
      final midLat = (startPoint.latitude + endPoint.latitude) / 2;
      final midLng = (startPoint.longitude + endPoint.longitude) / 2;
      
      markers.add(
        Marker(
          point: LatLng(midLat, midLng),
          child: Center(
            child: Text(
              '${widget.flight.straightDistance!.toStringAsFixed(1)} km',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                shadows: [
                  Shadow(
                    offset: Offset(1, 1),
                    blurRadius: 2,
                    color: Colors.black,
                  ),
                ],
              ),
              textAlign: TextAlign.center,
            ),
          ),
          width: 60,
          height: 20,
        ),
      );
    }

    setState(() {
      _markers = markers;
    });
  }

  Widget _buildCircleMarker(Color color, String labelName) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
    );
  }

  // _buildCrosshairsIcon removed - no longer needed without hover system
  
  Widget _buildPlaybackMarker() {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: Colors.deepPurple[600],
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(
        Icons.play_arrow,
        color: Colors.white,
        size: 12,
      ),
    );
  }

  void _fitMapToBounds() {
    if (_trackPoints.isEmpty || _mapController == null) return;
    
    // Only fit bounds if map is ready to avoid MapController errors
    if (!mounted) return;

    final latitudes = _trackPoints.map((p) => p.latitude);
    final longitudes = _trackPoints.map((p) => p.longitude);
    
    final minLat = latitudes.reduce((a, b) => a < b ? a : b);
    final maxLat = latitudes.reduce((a, b) => a > b ? a : b);
    final minLng = longitudes.reduce((a, b) => a < b ? a : b);
    final maxLng = longitudes.reduce((a, b) => a > b ? a : b);

    final bounds = LatLngBounds(
      LatLng(minLat, minLng),
      LatLng(maxLat, maxLng),
    );

    _mapController!.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50.0)),
    );
  }


  // Old _handleMapHover method removed - now using unified click-based interaction

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371; // km
    final lat1Rad = lat1 * pi / 180;
    final lat2Rad = lat2 * pi / 180;
    final deltaLat = (lat2 - lat1) * pi / 180;
    final deltaLon = (lon2 - lon1) * pi / 180;

    final a = sin(deltaLat / 2) * sin(deltaLat / 2) +
        cos(lat1Rad) * cos(lat2Rad) *
        sin(deltaLon / 2) * sin(deltaLon / 2);
    
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    
    return earthRadius * c;
  }

  // _calculatePixelDistance removed - no longer needed without hover system

  // FAB Controls (only for full screen mode)
  void _toggleLabels() async {
    setState(() {
      _showLabels = !_showLabels;
    });
    _createMarkers();
    await _createPolylinesAsync();
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('flight_track_show_labels', _showLabels);
  }

  void _toggleSatelliteView() async {
    setState(() {
      _showSatelliteView = !_showSatelliteView;
    });
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('flight_track_show_satellite', _showSatelliteView);
  }

  void _toggleLegend() async {
    setState(() {
      _showLegend = !_showLegend;
    });
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('flight_track_show_legend', _showLegend);
  }

  Widget _buildClimbRateLegend() {
    if (!widget.config.showLegend || !_showLegend) return const SizedBox.shrink();
    
    return Positioned(
      bottom: 8,
      left: 8,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Climb Rate column
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Climb Rate',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 8),
                _buildLegendItem(Colors.green, '≥ 0 m/s', 'Climb'),
                const SizedBox(height: 4),
                _buildLegendItem(Colors.blue[700]!, '-1.5 to 0 m/s', 'Weak Sink'),
                const SizedBox(height: 4),
                _buildLegendItem(Colors.red, '≤ -1.5 m/s', 'Strong Sink'),
              ],
            ),
            const SizedBox(width: 24),
            // Flight Points column
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Flight Points',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 8),
                _buildMarkerLegendItem(Colors.green, 'High Point'),
                const SizedBox(height: 4),
                _buildMarkerLegendItem(Colors.blue, 'Launch'),
                const SizedBox(height: 4),
                _buildMarkerLegendItem(Colors.red, 'Landing'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMarkerLegendItem(Color color, String label) {
    return SizedBox(
      height: 32, // Match the height of climb rate legend items
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.only(top: 2), // Align with text baseline
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: Colors.grey[800],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String range, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(1.5),
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: Colors.grey[800],
              ),
            ),
            Text(
              range,
              style: TextStyle(
                fontSize: 9,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMapControls() {
    if (!widget.config.showFAB) return const SizedBox.shrink();
    
    return Positioned(
      top: 8,
      right: 8,
      child: FloatingActionButton(
        mini: true,
        onPressed: _showMenuBottomSheet,
        child: const Icon(Icons.layers),
      ),
    );
  }

  void _showMenuBottomSheet() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(_showSatelliteView ? Icons.map : Icons.satellite_alt),
              title: Text('${_showSatelliteView ? 'Street' : 'Satellite'} View'),
                onTap: () {
                  Navigator.pop(context);
                  _toggleSatelliteView();
                },
              ),
            ListTile(
              leading: Icon(_showLabels ? Icons.label_off : Icons.label),
              title: Text('${_showLabels ? 'Hide' : 'Show'} Labels'),
              onTap: () {
                Navigator.pop(context);
                _toggleLabels();
              },
            ),
            ListTile(
              leading: Icon(_showLegend ? Icons.visibility_off : Icons.visibility),
              title: Text('${_showLegend ? 'Hide' : 'Show'} Legend'),
              onTap: () {
                Navigator.pop(context);
                _toggleLegend();
              },
            ),
            ListTile(
              leading: const Icon(Icons.fit_screen),
              title: const Text('Fit to Track'),
              onTap: () {
                Navigator.pop(context);
                _fitMapToBounds();
              },
            ),
            ListTile(
              leading: const Icon(Icons.report_problem),
              title: const Text('Report Map Issue'),
              onTap: () {
                Navigator.pop(context);
                _openFixTheMap();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Only wait for preferences to be loaded before showing the map
    if (!_preferencesLoaded || _isLoading) {
      final loadingWidget = Container(
        height: widget.config.embedded ? (widget.config.height ?? 300) : null,
        decoration: BoxDecoration(
          borderRadius: widget.config.embedded ? BorderRadius.circular(8) : null,
          color: Colors.grey[100],
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading track data...'),
            ],
          ),
        ),
      );
      
      // For full screen mode, use SizedBox.expand to fill available space
      if (!widget.config.embedded) {
        return SizedBox.expand(child: loadingWidget);
      }
      return loadingWidget;
    }

    if (_error != null) {
      final errorWidget = Container(
        height: widget.config.embedded ? (widget.config.height ?? 300) : null,
        decoration: BoxDecoration(
          borderRadius: widget.config.embedded ? BorderRadius.circular(8) : null,
          color: Colors.grey[100],
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                'Track Not Available',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
      
      // For full screen mode, use SizedBox.expand to fill available space
      if (!widget.config.embedded) {
        return SizedBox.expand(child: errorWidget);
      }
      return errorWidget;
    }

    // Create 2D map widget
    Widget mapWidget;
    
    // 2D FlutterMap view
    _mapController ??= MapController();
    
    mapWidget = FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: _trackPoints.isNotEmpty
              ? LatLng(_trackPoints.first.latitude, _trackPoints.first.longitude)
              : const LatLng(46.8182, 8.2275), // Switzerland default for paragliding
          initialZoom: widget.config.embedded ? 12 : 14,
          onTap: widget.config.interactive ? (tapPosition, point) {
            _handleMapTrackClick(point);
          } : null,
          onMapReady: () {
            if (_trackPoints.isNotEmpty) {
              _fitMapToBounds();
            }
            
            // Add TileLayer once FlutterMap is fully initialized
            // This prevents the flutter_map tile loading race condition
            setState(() {
              _tilesReady = true;
            });
          },
        ),
        children: [
          // FLUTTER_MAP TILE LOADING FIX:
          // Only add TileLayer after onMapReady fires. This solves a flutter_map race condition
          // where tiles fail to load on first widget creation, particularly on ChromeOS/Linux containers.
          // Alternative approaches tested:
          // - Artificial delays (300ms): Works but slow and masks root cause
          // - Forced rebuilds (setState after onMapReady): Works but inefficient  
          // - This solution: Clean and fast - addresses the actual flutter_map initialization timing
          if (_tilesReady)
            TileLayer(
              urlTemplate: _showSatelliteView 
                ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.freeflightlog.free_flight_log_app',
            ),
          if (_polylines.isNotEmpty)
            PolylineLayer(
              polylines: _polylines,
            ),
          // Loading indicator for polyline generation
          if (_isGeneratingPolylines)
            Container(
              color: Colors.black.withValues(alpha: 0.3),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 8),
                    Text(
                      'Generating flight track...',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          if (_markers.isNotEmpty)
            MarkerLayer(
              markers: _markers,
            ),
          // Attribution overlay - required for OSM and satellite tiles
          Align(
            alignment: Alignment.bottomRight,
            child: Container(
              margin: const EdgeInsets.all(4),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_showSatelliteView) ...[
                    Text(
                      'Powered by Esri',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.black87,
                      ),
                    ),
                    const Text(' | ', style: TextStyle(fontSize: 10, color: Colors.black54)),
                  ],
                  GestureDetector(
                    onTap: () {
                      _openOSMCopyright();
                    },
                    child: Text(
                      '© OpenStreetMap contributors',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.blue[800],
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );

    // Remove individual styling since unified container handles it
    if (widget.config.height != null && !widget.config.embedded) {
      mapWidget = SizedBox(
        height: widget.config.height,
        child: mapWidget,
      );
    }

    // Create the main map widget with controls
    final stackWidget = Stack(
      children: [
        mapWidget,
        _buildMapControls(),
        _buildClimbRateLegend(),
      ],
    );

    // Unified container for seamless map and chart integration
    final unifiedWidget = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Map section
            widget.config.embedded 
                ? Expanded(child: stackWidget)
                : Flexible(child: stackWidget),
            // Chart section - seamlessly connected
            _buildAltitudeChart(),
          ],
        ),
      ),
    );

    // Add playback panel if enabled
    Widget finalWidget = unifiedWidget;
    if (widget.showPlaybackPanel && _playbackController != null) {
      // Playback panel removed - using native controls
      finalWidget = unifiedWidget;
    }
    
    // For embedded mode, provide bounded height
    if (widget.config.embedded) {
      return SizedBox(
        height: widget.config.height ?? 350,
        child: finalWidget,
      );
    } else {
      // Full screen mode
      return finalWidget;
    }
  }


  // Old floating stats system removed - now using unified playback controller

  /// Calculate 15-second averaged climb rates using GPS altitude specifically
  List<double> _calculateGPS15SecondClimbRates(List<IgcPoint> points) {
    if (points.length < 2) return [];

    final climbRates = <double>[];
    
    for (int i = 0; i < points.length; i++) {
      // Look for points within a 15-second window centered on current point
      final currentTime = points[i].timestamp;
      
      // Determine window bounds (±7.5 seconds)
      final windowStart = currentTime.subtract(const Duration(milliseconds: 7500));
      final windowEnd = currentTime.add(const Duration(milliseconds: 7500));
      
      // Find first and last points within window
      IgcPoint? firstInWindow;
      IgcPoint? lastInWindow;
      
      for (final point in points) {
        final pointTime = point.timestamp;
        
        // Check if point is within window
        if (!pointTime.isBefore(windowStart) && !pointTime.isAfter(windowEnd)) {
          firstInWindow ??= point;
          lastInWindow = point;
        }
      }
      
      // If we don't have at least 2 distinct points, use instantaneous rate as fallback
      if (firstInWindow == null || lastInWindow == null || firstInWindow == lastInWindow) {
        if (i > 0) {
          final timeDiff = (points[i].timestamp.millisecondsSinceEpoch - 
                           points[i-1].timestamp.millisecondsSinceEpoch) / 1000.0;
          if (timeDiff > 0) {
            // Force use of GPS altitude only
            final altDiff = (points[i].gpsAltitude - points[i-1].gpsAltitude).toDouble();
            climbRates.add(altDiff / timeDiff);
          } else {
            climbRates.add(0.0);
          }
        } else {
          climbRates.add(0.0);
        }
        continue;
      }
      
      // Calculate climb rate over the window using GPS altitude only
      final timeDiffSeconds = (lastInWindow.timestamp.millisecondsSinceEpoch - 
                              firstInWindow.timestamp.millisecondsSinceEpoch) / 1000.0;
      
      if (timeDiffSeconds > 0) {
        // Force use of GPS altitude only
        final altDiff = (lastInWindow.gpsAltitude - firstInWindow.gpsAltitude).toDouble();
        climbRates.add(altDiff / timeDiffSeconds);
      } else {
        climbRates.add(0.0);
      }
    }

    return climbRates;
  }

  /// Build altitude chart widget
  Widget _buildAltitudeChart() {
    if (_trackPoints.isEmpty || _cachedAltitudeData == null) {
      return const SizedBox.shrink();
    }

    // Use cached data instead of recalculating
    final altitudeData = _cachedAltitudeData!;
    if (altitudeData.isEmpty) return const SizedBox.shrink();

    // Calculate altitude range for Y-axis (only once)
    final altitudes = altitudeData.map((spot) => spot.y).toList();
    final minAlt = altitudes.reduce(min);
    final maxAlt = altitudes.reduce(max);
    final altRange = maxAlt - minAlt;
    final padding = altRange * 0.1; // 10% padding

    return Container(
      height: 120,
      padding: const EdgeInsets.all(16),
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: GestureDetector(
        onPanUpdate: widget.config.interactive ? (details) {
          LoggingService.debug('FlightTrackWidget: Pan update detected at ${details.localPosition}');
          _handleChartPanUpdate(details.localPosition, altitudeData);
        } : null,
        onTapDown: widget.config.interactive ? (details) {
          LoggingService.debug('FlightTrackWidget: Tap down detected at ${details.localPosition}');
          _handleChartPanUpdate(details.localPosition, altitudeData);
        } : null,
        child: ValueListenableBuilder<int?>(
          valueListenable: _chartIndicatorIndex,
          builder: (context, indicatorIndex, _) {
            return ValueListenableBuilder<double?>(
              valueListenable: _chartVerticalLineTime,
              builder: (context, verticalLineTime, _) {
                return LineChart(
                  key: _chartKey,
                  LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: true,
            drawHorizontalLine: true,
            horizontalInterval: _calculateYAxisInterval(altRange),
            verticalInterval: null, // Auto interval
            getDrawingHorizontalLine: (value) {
              // Make grid lines more prominent to act as tick marks
              return FlLine(
                color: Colors.grey[400]!,
                strokeWidth: 1.0,
              );
            },
            getDrawingVerticalLine: (value) {
              return FlLine(
                color: Colors.grey[300]!,
                strokeWidth: 0.5,
              );
            },
          ),
          titlesData: FlTitlesData(
            show: true,
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: null, // Auto interval
                getTitlesWidget: (value, meta) {
                  // Skip first and last labels to avoid crowding and overlap
                  if (meta.min == value || meta.max == value) {
                    return const SizedBox.shrink();
                  }
                  return Text(
                    _formatTimeOfDay(value),
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 10,
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 50,
                interval: _calculateYAxisInterval(altRange),
                getTitlesWidget: (value, meta) {
                  // Skip first and last labels to avoid crowding
                  if (meta.min == value || meta.max == value) {
                    return const SizedBox.shrink();
                  }
                  return Text(
                    '${value.toInt()}m',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 10,
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(
            show: true,
            border: Border.all(color: Colors.grey[300]!, width: 1),
          ),
          minX: altitudeData.first.x,
          maxX: altitudeData.last.x,
          minY: minAlt - padding,
          maxY: maxAlt + padding,
          lineBarsData: [
            LineChartBarData(
              spots: altitudeData,
              isCurved: true,
              curveSmoothness: 0.3,
              color: Colors.blue[600],
              barWidth: 2,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: Colors.blue[600]!.withValues(alpha: 0.2),
              ),
              // Native indicator for smooth 60fps updates
              showingIndicators: indicatorIndex != null ? [indicatorIndex] : [],
            ),
          ],
          // Optional faint vertical line for visual continuity (updates at 10fps)
          extraLinesData: ExtraLinesData(
            verticalLines: verticalLineTime != null ? [
              VerticalLine(
                x: verticalLineTime,
                color: Colors.deepPurple[600]!.withValues(alpha: 0.3),
                strokeWidth: 1,
                dashArray: [5, 3],
              ),
            ] : [],
          ),
          // Configure touch indicator appearance
          lineTouchData: LineTouchData(
            enabled: false, // Keep custom gesture handling
            getTouchedSpotIndicator: (LineChartBarData barData, List<int> indicators) {
              return indicators.map((index) {
                return TouchedSpotIndicatorData(
                  const FlLine(color: Colors.transparent, strokeWidth: 0), // Invisible line
                  FlDotData(
                    show: true,
                    getDotPainter: (spot, percent, barData, index) =>
                      FlDotCirclePainter(
                        radius: 6,
                        color: Colors.deepPurple[600]!,
                        strokeColor: Colors.white,
                        strokeWidth: 3,
                      ),
                  ),
                );
              }).toList();
            },
          ),
          backgroundColor: Colors.transparent,
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  /// Handle direct touch/pan on chart by converting screen coordinates to time
  void _handleChartPanUpdate(Offset localPosition, List<FlSpot> altitudeData) {
    if (altitudeData.isEmpty || _playbackController == null) return;
    
    // Get the chart widget's render box for precise coordinate mapping
    final RenderBox? chartBox = _chartKey.currentContext?.findRenderObject() as RenderBox?;
    if (chartBox == null) {
      LoggingService.debug('FlightTrackWidget: Chart RenderBox not available for touch coordinate conversion');
      return;
    }
    
    // Get actual chart dimensions and bounds
    final chartSize = chartBox.size;
    final chartPaintBounds = chartBox.paintBounds;
    
    LoggingService.debug('FlightTrackWidget: Chart touch - localPos: $localPosition, chartSize: $chartSize, paintBounds: $chartPaintBounds');
    
    // fl_chart reserves space for axes - estimate based on common patterns
    // These values are based on fl_chart's internal layout calculations
    const double leftAxisReserve = 50.0;   // reservedSize from leftTitles
    const double bottomAxisReserve = 22.0; // reservedSize from bottomTitles
    const double topPadding = 8.0;         // Default fl_chart top padding
    const double rightPadding = 8.0;       // Default fl_chart right padding
    
    // Calculate actual chart plot area
    final plotAreaWidth = chartSize.width - leftAxisReserve - rightPadding;
    final plotAreaHeight = chartSize.height - topPadding - bottomAxisReserve;
    
    // Adjust touch position relative to plot area origin
    final plotX = localPosition.dx - leftAxisReserve;
    final plotY = localPosition.dy - topPadding;
    
    LoggingService.debug('FlightTrackWidget: Plot area - width: $plotAreaWidth, height: $plotAreaHeight, plotX: $plotX, plotY: $plotY');
    
    // Validate touch is within plot bounds
    if (plotX < 0 || plotX > plotAreaWidth || plotY < 0 || plotY > plotAreaHeight) {
      LoggingService.debug('FlightTrackWidget: Touch outside plot area - ignoring');
      return;
    }
    
    // Convert screen X coordinate to chart data coordinate
    final minTime = altitudeData.first.x;
    final maxTime = altitudeData.last.x;
    final timeRange = maxTime - minTime;
    
    // Calculate normalized position (0.0 to 1.0) within plot area
    final normalizedX = plotX / plotAreaWidth;
    
    // Map to actual time value
    final timeMinutes = minTime + (normalizedX * timeRange);
    
    LoggingService.debug('FlightTrackWidget: Touch conversion - normalizedX: $normalizedX, timeMinutes: $timeMinutes, timeRange: $minTime-$maxTime');
    
    // Update playback controller - this syncs purple line, slider, and map
    _handleAltitudeChartInteraction(timeMinutes);
  }

  /// Calculate intelligent y-axis interval based on altitude range
  double _calculateYAxisInterval(double altRange) {
    if (altRange <= 50) return 10;
    if (altRange <= 100) return 20;
    if (altRange <= 200) return 50;
    if (altRange <= 500) return 100;
    if (altRange <= 1000) return 200;
    if (altRange <= 2000) return 500;
    return 1000;
  }

  /// Format time of day from minutes since midnight as hh:mm
  String _formatTimeOfDay(double minutesSinceMidnight) {
    final totalMinutes = minutesSinceMidnight.toInt();
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';
  }

  /// Format time from seconds with intelligent precision
  String _formatTimeFromSeconds(double seconds) {
    if (seconds < 60) {
      return '${seconds.toInt()}s';
    } else if (seconds < 3600) {
      final mins = seconds ~/ 60;
      final remainingSecs = (seconds % 60).toInt();
      return remainingSecs > 0 ? '${mins}m${remainingSecs}s' : '${mins}m';
    } else {
      final hours = seconds ~/ 3600;
      final remainingMins = ((seconds % 3600) ~/ 60).toInt();
      final remainingSecs = (seconds % 60).toInt();
      
      if (remainingMins > 0 && remainingSecs > 0) {
        return '${hours}h${remainingMins}m${remainingSecs}s';
      } else if (remainingMins > 0) {
        return '${hours}h${remainingMins}m';
      } else {
        return '${hours}h';
      }
    }
  }

  /// Prepare altitude chart data from track points with intelligent decimation
  List<FlSpot> _prepareAltitudeChartData() {
    if (_trackPoints.isEmpty) return [];

    final spots = <FlSpot>[];

    for (int i = 0; i < _trackPoints.length; i++) {
      final point = _trackPoints[i];
      // Use minutes since midnight as x-axis value
      final timeOfDay = point.timestamp.hour * 60.0 + point.timestamp.minute + point.timestamp.second / 60.0;
      final altitude = point.gpsAltitude.toDouble();
      spots.add(FlSpot(timeOfDay, altitude));
    }

    // Apply decimation for performance on large datasets
    return _decimateChartData(spots);
  }

  /// Intelligently reduce chart data points for smooth rendering performance
  /// Preserves important features while reducing density for large tracks
  List<FlSpot> _decimateChartData(List<FlSpot> data, {int maxPoints = 300}) {
    if (data.length <= maxPoints) {
      LoggingService.debug('FlightTrackWidget: Chart data within limits (${data.length} <= $maxPoints points) - no decimation needed');
      return data;
    }

    LoggingService.debug('FlightTrackWidget: Decimating chart data from ${data.length} to ~$maxPoints points for performance');

    final decimated = <FlSpot>[];
    
    // Always keep first and last points
    decimated.add(data.first);
    
    // Calculate step size for uniform sampling
    final step = (data.length - 2) / (maxPoints - 2);
    
    // Sample points with uniform distribution
    for (int i = 1; i < maxPoints - 1; i++) {
      final index = (1 + i * step).round().clamp(1, data.length - 2);
      if (index < data.length && !decimated.any((spot) => spot == data[index])) {
        decimated.add(data[index]);
      }
    }
    
    // Always keep last point
    if (data.length > 1) {
      decimated.add(data.last);
    }

    // Sort by x-value to maintain chronological order
    decimated.sort((a, b) => a.x.compareTo(b.x));
    
    LoggingService.performance('Chart data decimation', DateTime.now().difference(DateTime.now()), 
        '${data.length} -> ${decimated.length} points');

    return decimated;
  }

  // _getSelectedPointTime removed - now using unified playback controller only
  
  /// Get the X-coordinate (time) for the playback position
  double? _getPlaybackPointTime() {
    if (_playbackPointIndex == null || _playbackPointIndex! >= _trackPoints.length) {
      return null;
    }

    final playbackPoint = _trackPoints[_playbackPointIndex!];
    // Return minutes since midnight
    return playbackPoint.timestamp.hour * 60.0 + playbackPoint.timestamp.minute + playbackPoint.timestamp.second / 60.0;
  }

  // ========== NEW UNIFIED LINKING SYSTEM ==========
  
  /// Handle hover/interaction on altitude chart - updates playback controller for unified linking
  void _handleAltitudeChartInteraction(double timeMinutes) {
    if (_trackPoints.isEmpty || _playbackController == null) {
      LoggingService.debug('FlightTrackWidget: Chart interaction ignored - no track points or controller');
      return;
    }
    
    // Find the track point closest to the touched time-of-day
    int bestIndex = 0;
    double smallestDiff = double.infinity;
    
    for (int i = 0; i < _trackPoints.length; i++) {
      final point = _trackPoints[i];
      // Calculate time of day for this point (minutes since midnight)
      final pointTimeOfDay = point.timestamp.hour * 60.0 + 
                             point.timestamp.minute + 
                             point.timestamp.second / 60.0;
      
      final diff = (pointTimeOfDay - timeMinutes).abs();
      if (diff < smallestDiff) {
        smallestDiff = diff;
        bestIndex = i;
      }
    }
    
    LoggingService.debug('FlightTrackWidget: Chart interaction - timeMinutes: $timeMinutes -> bestIndex: $bestIndex (diff: ${smallestDiff.toStringAsFixed(2)} minutes)');
    
    // Update playback controller to the found index
    final oldIndex = _playbackController!.currentPointIndex;
    _playbackController!.seekToIndex(bestIndex);
    final newIndex = _playbackController!.currentPointIndex;
    
    LoggingService.debug('FlightTrackWidget: Playback controller updated - index: $oldIndex -> $newIndex');
  }
  
  /// Handle click on altitude chart - locks position for persistent display
  void _handleAltitudeChartClick(double timeMinutes) {
    if (_trackPoints.isEmpty || _playbackController == null) return;
    
    // Same logic as hover but with potential for additional click-specific behavior
    _handleAltitudeChartInteraction(timeMinutes);
    
    // Stop any currently playing animation to maintain clicked position
    if (_playbackController!.state == PlaybackState.playing) {
      _playbackController!.pause();
    }
  }
  
  /// Handle click on map track - finds closest point and updates playback controller
  void _handleMapTrackClick(LatLng clickedPosition) {
    if (_trackPoints.isEmpty || _playbackController == null) return;
    
    // Find closest track point to clicked position
    double minDistance = double.infinity;
    int closestIndex = 0;
    
    for (int i = 0; i < _trackPoints.length; i++) {
      final point = _trackPoints[i];
      final distance = _calculateDistance(
        clickedPosition.latitude,
        clickedPosition.longitude,
        point.latitude,
        point.longitude,
      );
      
      if (distance < minDistance) {
        minDistance = distance;
        closestIndex = i;
      }
    }
    
    // Only respond to clicks reasonably close to the track (within 1km)
    if (minDistance <= 1.0) {
      // Update playback controller - this automatically syncs chart indicator and timeline slider
      _playbackController!.seekToIndex(closestIndex);
      
      // Stop any currently playing animation to maintain clicked position
      if (_playbackController!.state == PlaybackState.playing) {
        _playbackController!.pause();
      }
    }
  }
  
  /// Map track point index to chart data index, handling decimated data
  int? _mapTrackIndexToChartIndex(int trackIndex) {
    if (_cachedAltitudeData == null || trackIndex >= _trackPoints.length) return null;
    
    final point = _trackPoints[trackIndex];
    final timeOfDay = point.timestamp.hour * 60.0 + 
                     point.timestamp.minute + 
                     point.timestamp.second / 60.0;
    
    // Try exact match first (common for non-decimated data)
    if (_timeToChartIndexMap.containsKey(timeOfDay)) {
      return _timeToChartIndexMap[timeOfDay];
    }
    
    // Find closest time in decimated data
    int closestIndex = 0;
    double smallestDiff = double.infinity;
    
    for (int i = 0; i < _cachedAltitudeData!.length; i++) {
      final diff = (_cachedAltitudeData![i].x - timeOfDay).abs();
      if (diff < smallestDiff) {
        smallestDiff = diff;
        closestIndex = i;
      }
    }
    
    return closestIndex;
  }
  
  /// Handle playback controller changes with debouncing
  void _onPlaybackChanged() {
    if (_playbackController == null) return;
    
    // Cancel any existing timer
    _playbackUpdateTimer?.cancel();
    
    // Debounce updates to reduce rebuild frequency (16ms = ~60fps)
    _playbackUpdateTimer = Timer(const Duration(milliseconds: 16), () {
      if (mounted && _playbackController != null) {
        final newIndex = _playbackController!.currentPointIndex;
        
        // Update chart indicator without setState
        final chartIndex = _mapTrackIndexToChartIndex(newIndex);
        _chartIndicatorIndex.value = chartIndex;
        
        // Update vertical line less frequently (100ms)
        _verticalLineUpdateTimer?.cancel();
        _verticalLineUpdateTimer = Timer(const Duration(milliseconds: 100), () {
          if (_cachedAltitudeData != null && chartIndex != null && 
              chartIndex < _cachedAltitudeData!.length) {
            _chartVerticalLineTime.value = _cachedAltitudeData![chartIndex].x;
          }
        });
        
        // Only setState for map marker updates if index actually changed
        if (_playbackPointIndex != newIndex) {
          LoggingService.debug('FlightTrackWidget: Playback position changed - index: $_playbackPointIndex -> $newIndex');
          
          setState(() {
            _playbackPointIndex = newIndex;
          });
          _createMarkers();
          _panIfNearEdge();
        }
      }
    });
  }

  /// Pan map if playback position is near the edge of the visible area
  void _panIfNearEdge() {
    final point = _playbackController?.currentPoint;
    final mapController = _mapController;
    
    if (point == null || mapController == null) return;
    
    final camera = mapController.camera;
    final bounds = camera.visibleBounds;
    final currentCenter = camera.center;
    
    // Define margin as percentage from edge (10% = 0.1)
    const double margin = 0.1;
    
    final latRange = bounds.north - bounds.south;
    final lngRange = bounds.east - bounds.west;
    
    // Calculate the safe zone boundaries
    final northLimit = bounds.north - (latRange * margin);
    final southLimit = bounds.south + (latRange * margin);
    final eastLimit = bounds.east - (lngRange * margin);
    final westLimit = bounds.west + (lngRange * margin);
    
    // Check if point is outside the safe zone and calculate minimal correction
    double newLat = currentCenter.latitude;
    double newLng = currentCenter.longitude;
    bool needsPan = false;
    
    if (point.latitude > northLimit) {
      // Point is too far north - move map north just enough
      newLat = currentCenter.latitude + (point.latitude - northLimit);
      needsPan = true;
    } else if (point.latitude < southLimit) {
      // Point is too far south - move map south just enough
      newLat = currentCenter.latitude + (point.latitude - southLimit);
      needsPan = true;
    }
    
    if (point.longitude > eastLimit) {
      // Point is too far east - move map east just enough
      newLng = currentCenter.longitude + (point.longitude - eastLimit);
      needsPan = true;
    } else if (point.longitude < westLimit) {
      // Point is too far west - move map west just enough
      newLng = currentCenter.longitude + (point.longitude - westLimit);
      needsPan = true;
    }
    
    if (needsPan) {
      mapController.move(
        LatLng(newLat, newLng),
        camera.zoom,
      );
    }
  }

  /// Open OpenStreetMap copyright page
  void _openOSMCopyright() async {
    final uri = Uri.parse('https://www.openstreetmap.org/copyright');
    try {
      await launchUrl(uri, mode: LaunchMode.platformDefault);
    } catch (e) {
      // Handle error silently or show a message
      LoggingService.error('FlightTrackWidget: Could not launch URL', e);
    }
  }

  /// Open OpenStreetMap fix the map reporting page
  void _openFixTheMap() async {
    final uri = Uri.parse('https://www.openstreetmap.org/fixthemap');
    try {
      await launchUrl(uri, mode: LaunchMode.platformDefault);
    } catch (e) {
      // Handle error silently or show a message
      LoggingService.error('FlightTrackWidget: Could not launch URL', e);
    }
  }
}

class CrosshairsPainter extends CustomPainter {
  final Color color;

  CrosshairsPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;
    final gapRadius = radius / 2; // 1/2 of the radius for the center gap

    // Draw white outline for better visibility
    final outlinePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.square;

    // Draw main crosshair lines
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.square;

    // Draw white outline horizontal lines (left and right segments)
    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx - gapRadius, center.dy),
      outlinePaint,
    );
    canvas.drawLine(
      Offset(center.dx + gapRadius, center.dy),
      Offset(center.dx + radius, center.dy),
      outlinePaint,
    );

    // Draw white outline vertical lines (top and bottom segments)
    canvas.drawLine(
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy - gapRadius),
      outlinePaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy + gapRadius),
      Offset(center.dx, center.dy + radius),
      outlinePaint,
    );

    // Draw colored horizontal lines (left and right segments)
    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx - gapRadius, center.dy),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx + gapRadius, center.dy),
      Offset(center.dx + radius, center.dy),
      paint,
    );

    // Draw colored vertical lines (top and bottom segments)
    canvas.drawLine(
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy - gapRadius),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy + gapRadius),
      Offset(center.dx, center.dy + radius),
      paint,
    );
  }

  @override
  bool shouldRepaint(CrosshairsPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
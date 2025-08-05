import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../data/models/flight.dart';
import '../../data/models/igc_file.dart';
import '../../services/igc_import_service.dart';

class FlightTrackConfig {
  final bool embedded;
  final bool showLegend;
  final bool showFAB;
  final bool showStats;
  final bool interactive;
  final bool showStraightLine;
  final bool showAltitudeChart;
  final double? height;

  const FlightTrackConfig({
    this.embedded = false,
    this.showLegend = true,
    this.showFAB = true,
    this.showStats = true,
    this.interactive = true,
    this.showStraightLine = true,
    this.showAltitudeChart = true,
    this.height,
  });

  FlightTrackConfig.embedded()
      : embedded = true,
        showLegend = false,
        showFAB = false,
        showStats = false,
        interactive = false,
        showStraightLine = true,
        showAltitudeChart = false,
        height = 250;

  FlightTrackConfig.embeddedWithControls()
      : embedded = true,
        showLegend = true,
        showFAB = true,
        showStats = true,
        interactive = true,
        showStraightLine = true,
        showAltitudeChart = true,
        height = 600;

  FlightTrackConfig.fullScreen()
      : embedded = false,
        showLegend = true,
        showFAB = true,
        showStats = true,
        interactive = true,
        showStraightLine = true,
        showAltitudeChart = true,
        height = null;
}

class FlightTrackWidget extends StatefulWidget {
  final Flight flight;
  final FlightTrackConfig config;
  final Function(int)? onPointSelected;

  const FlightTrackWidget({
    super.key,
    required this.flight,
    required this.config,
    this.onPointSelected,
  });

  @override
  State<FlightTrackWidget> createState() => _FlightTrackWidgetState();
}

class _FlightTrackWidgetState extends State<FlightTrackWidget> {
  MapController? _mapController;
  final IgcImportService _igcService = IgcImportService();
  
  List<IgcPoint> _trackPoints = [];
  List<double> _instantaneousRates = [];
  List<double> _fifteenSecondRates = [];
  List<Polyline> _polylines = [];
  List<Marker> _markers = [];
  bool _isLoading = true;
  String? _error;
  
  // Map display options with persistent settings for full screen mode
  bool _showMarkers = true;
  bool _showStraightLine = true;
  bool _showSatelliteView = false;
  
  // Currently hovered track point for real-time feedback
  int? _hoveredPointIndex;

  @override
  void initState() {
    super.initState();
    if (!widget.config.embedded) {
      _loadSavedPreferences();
    } else {
      // For embedded mode, use config defaults
      _showStraightLine = widget.config.showStraightLine;
    }
    _loadTrackData();
  }

  Future<void> _loadSavedPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _showMarkers = prefs.getBool('flight_track_show_markers') ?? true;
      _showStraightLine = prefs.getBool('flight_track_show_straight_line') ?? true;
      _showSatelliteView = prefs.getBool('flight_track_show_satellite') ?? false;
    });
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
      
      _createPolylines();
      _createMarkers();
      _fitMapToBounds();
      
    } catch (e) {
      setState(() {
        _error = 'Error loading track data: $e';
        _isLoading = false;
      });
    }
  }

  void _createPolylines() {
    if (_trackPoints.isEmpty) return;

    final polylines = <Polyline>[];

    // Create climb rate-based colored segments
    polylines.addAll(_createClimbRateColoredPolylines());

    // Create straight line polyline if enabled
    if (_showStraightLine && _trackPoints.length >= 2) {
      final launchPoint = LatLng(_trackPoints.first.latitude, _trackPoints.first.longitude);
      final landingPoint = LatLng(_trackPoints.last.latitude, _trackPoints.last.longitude);
      
      final straightLinePolyline = Polyline(
        points: [launchPoint, landingPoint],
        color: Colors.grey,
        strokeWidth: 4.0,
        isDotted: true,
      );
      polylines.add(straightLinePolyline);
    }

    setState(() {
      _polylines = polylines;
    });
  }

  List<Polyline> _createClimbRateColoredPolylines() {
    if (_trackPoints.length < 2) return [];
    
    // If no climb rate data, create a simple red track
    if (_fifteenSecondRates.isEmpty) {
      print('No climb rate data available, showing red track');
      final trackCoordinates = _trackPoints
          .map((point) => LatLng(point.latitude, point.longitude))
          .toList();

      return [Polyline(
        points: trackCoordinates,
        color: Colors.red,
        strokeWidth: 3.0,
      )];
    }

    print('Creating climb rate colored track with ${_fifteenSecondRates.length} climb rate points');

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

    return polylines;
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
    if (_trackPoints.isEmpty || !_showMarkers) {
      setState(() {
        _markers = [];
      });
      return;
    }

    final startPoint = _trackPoints.first;
    final endPoint = _trackPoints.last;
    
    // Find highest point
    final highestPoint = _trackPoints.reduce(
      (a, b) => a.gpsAltitude > b.gpsAltitude ? a : b
    );

    final markers = <Marker>[
      Marker(
        point: LatLng(startPoint.latitude, startPoint.longitude),
        child: _buildMarkerIcon(Colors.green, 'L'),
        width: 40,
        height: 40,
      ),
      Marker(
        point: LatLng(endPoint.latitude, endPoint.longitude),
        child: _buildMarkerIcon(Colors.red, 'X'),
        width: 40,
        height: 40,
      ),
      Marker(
        point: LatLng(highestPoint.latitude, highestPoint.longitude),
        child: _buildMarkerIcon(Colors.blue, 'H'),
        width: 40,
        height: 40,
      ),
    ];

    // Add crosshairs markers for interactive mode
    if (widget.config.interactive && _hoveredPointIndex != null) {
      if (_hoveredPointIndex! < _trackPoints.length) {
        final hoveredPoint = _trackPoints[_hoveredPointIndex!];
        
        // Use hover styling - matching altitude chart indicator
        final crosshairColor = Colors.orange[600]!;
        
        markers.add(
          Marker(
            point: LatLng(hoveredPoint.latitude, hoveredPoint.longitude),
            child: _buildCrosshairsIcon(crosshairColor),
            width: 40,
            height: 40,
          ),
        );
      }
    }

    // Add straight distance marker at midpoint if showing straight line
    if (_showStraightLine && _trackPoints.length >= 2 && widget.flight.straightDistance != null) {
      final startPoint = _trackPoints.first;
      final endPoint = _trackPoints.last;
      final midLat = (startPoint.latitude + endPoint.latitude) / 2;
      final midLng = (startPoint.longitude + endPoint.longitude) / 2;
      
      markers.add(
        Marker(
          point: LatLng(midLat, midLng),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.grey,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Text(
              '${widget.flight.straightDistance!.toStringAsFixed(1)} km',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          width: 80,
          height: 30,
        ),
      );
    }

    setState(() {
      _markers = markers;
    });
  }

  Widget _buildMarkerIcon(Color color, String label) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Center(
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildCrosshairsIcon(Color color) {
    return Container(
      width: 40,
      height: 40,
      child: CustomPaint(
        painter: CrosshairsPainter(color: color),
      ),
    );
  }

  void _fitMapToBounds() {
    if (_trackPoints.isEmpty || _mapController == null) return;

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


  void _handleMapHover(dynamic event, LatLng hoveredPoint) {
    if (_trackPoints.isEmpty || !widget.config.interactive) return;

    // Find the closest track point to the hovered location
    double minDistance = double.infinity;
    int closestIndex = 0;

    for (int i = 0; i < _trackPoints.length; i++) {
      final point = _trackPoints[i];
      final distance = _calculateDistance(
        hoveredPoint.latitude,
        hoveredPoint.longitude,
        point.latitude,
        point.longitude,
      );

      if (distance < minDistance) {
        minDistance = distance;
        closestIndex = i;
      }
    }

    // Only update if the hover is reasonably close to the track (within 0.5km for better responsiveness)
    // and if it's different from the current hovered point
    if (minDistance < 0.5 && _hoveredPointIndex != closestIndex) {
      setState(() {
        _hoveredPointIndex = closestIndex;
      });
      _createMarkers();
    } else if (minDistance >= 0.5 && _hoveredPointIndex != null) {
      // Clear hover state if mouse moves away from track
      setState(() {
        _hoveredPointIndex = null;
      });
      _createMarkers();
    }
  }

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

  // FAB Controls (only for full screen mode)
  void _toggleMarkers() async {
    setState(() {
      _showMarkers = !_showMarkers;
    });
    _createMarkers();
    
    if (!widget.config.embedded) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('flight_track_show_markers', _showMarkers);
    }
  }

  void _toggleStraightLine() async {
    setState(() {
      _showStraightLine = !_showStraightLine;
    });
    _createPolylines();
    _createMarkers();
    
    if (!widget.config.embedded) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('flight_track_show_straight_line', _showStraightLine);
    }
  }

  void _toggleSatelliteView() async {
    setState(() {
      _showSatelliteView = !_showSatelliteView;
    });
    
    if (!widget.config.embedded) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('flight_track_show_satellite', _showSatelliteView);
    }
  }

  Widget _buildClimbRateLegend() {
    if (!widget.config.showLegend) return const SizedBox.shrink();
    
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Climb Rate (15s avg)',
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
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: PopupMenuButton<String>(
          icon: const Icon(Icons.layers, size: 20),
          onSelected: (value) {
            switch (value) {
              case 'markers':
                _toggleMarkers();
                break;
              case 'straight_line':
                _toggleStraightLine();
                break;
              case 'satellite':
                _toggleSatelliteView();
                break;
              case 'fit':
                _fitMapToBounds();
                break;
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'markers',
              child: Row(
                children: [
                  Icon(_showMarkers ? Icons.visibility : Icons.visibility_off),
                  const SizedBox(width: 8),
                  Text('${_showMarkers ? 'Hide' : 'Show'} Markers'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'straight_line',
              child: Row(
                children: [
                  Icon(_showStraightLine ? Icons.timeline : Icons.timeline_outlined),
                  const SizedBox(width: 8),
                  Text('${_showStraightLine ? 'Hide' : 'Show'} Distance'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'satellite',
              child: Row(
                children: [
                  Icon(_showSatelliteView ? Icons.map : Icons.satellite_alt),
                  const SizedBox(width: 8),
                  Text('${_showSatelliteView ? 'Street' : 'Satellite'} View'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'fit',
              child: Row(
                children: [
                  Icon(Icons.fit_screen),
                  SizedBox(width: 8),
                  Text('Fit to Track'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
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

    _mapController ??= MapController();
    
    Widget mapWidget = FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _trackPoints.isNotEmpty
            ? LatLng(_trackPoints.first.latitude, _trackPoints.first.longitude)
            : const LatLng(0, 0),
        initialZoom: widget.config.embedded ? 12 : 14,
        onPointerHover: widget.config.interactive ? (event, point) {
          _handleMapHover(event, point);
        } : null,
        onMapReady: () {
          if (_trackPoints.isNotEmpty) {
            _fitMapToBounds();
          }
        },
      ),
      children: [
        TileLayer(
          urlTemplate: _showSatelliteView 
            ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
            : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.free_flight_log_app',
        ),
        if (_polylines.isNotEmpty)
          PolylineLayer(
            polylines: _polylines,
          ),
        if (_markers.isNotEmpty)
          MarkerLayer(
            markers: _markers,
          ),
        // Attribution overlay for satellite tiles
        if (_showSatelliteView)
          Align(
            alignment: Alignment.bottomRight,
            child: Container(
              margin: const EdgeInsets.all(4),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.8),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                'Powered by Esri',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.black87,
                ),
              ),
            ),
          ),
      ],
    );

    // Wrap in container with height constraint if specified (but not when stats are shown, as height is controlled by outer SizedBox)
    if (widget.config.height != null && !widget.config.showStats) {
      mapWidget = Container(
        height: widget.config.height,
        decoration: BoxDecoration(
          borderRadius: widget.config.embedded ? BorderRadius.circular(8) : null,
          border: widget.config.embedded ? Border.all(color: Colors.grey[300]!) : null,
        ),
        child: widget.config.embedded ? ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: mapWidget,
        ) : mapWidget,
      );
    } else if (widget.config.embedded) {
      // Apply embedded styling even when stats are shown
      mapWidget = Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: mapWidget,
        ),
      );
    }

    // If stats are enabled, wrap in a column with stats bar
    if (widget.config.showStats) {
      final stackWidget = Stack(
        children: [
          mapWidget,
          _buildMapControls(),
          _buildClimbRateLegend(),
          _buildFloatingStats(),
        ],
      );

      // For embedded mode, always provide bounded height
      if (widget.config.embedded) {
        return SizedBox(
          height: widget.config.height ?? 350, // Default height if not specified
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildStatsBar(),
              Expanded(child: stackWidget),
              _buildAltitudeChart(),
            ],
          ),
        );
      } else {
        // Full screen mode - use Flexible instead of Expanded for better constraint handling
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildStatsBar(),
            Flexible(child: stackWidget),
            _buildAltitudeChart(),
          ],
        );
      }
    }

    return Stack(
      children: [
        mapWidget,
        _buildMapControls(),
        _buildClimbRateLegend(),
        _buildFloatingStats(),
      ],
    );
  }

  // Statistics methods
  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  String _formatDuration(int minutes) {
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (hours > 0) {
      return '${hours}h ${mins}m';
    }
    return '${mins}m';
  }

  Widget _buildStatsBar() {
    if (_trackPoints.isEmpty) return const SizedBox.shrink();

    final duration = _formatDuration(widget.flight.duration);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
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
            children: [
              _buildStatItem(
                'Duration',
                duration,
                Icons.access_time,
              ),
              _buildStatItem(
                'Track Distance',
                widget.flight.distance != null 
                    ? '${widget.flight.distance!.toStringAsFixed(1)} km'
                    : 'N/A',
                Icons.timeline,
              ),
              _buildStatItem(
                'Max Alt',
                widget.flight.maxAltitude != null
                    ? '${widget.flight.maxAltitude!.toInt()} m'
                    : 'N/A',
                Icons.height,
              ),
            ],
          ),
          if (widget.flight.maxClimbRate != null || widget.flight.maxClimbRate5Sec != null) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                if (widget.flight.maxClimbRate != null)
                  _buildStatItem(
                    'Max Climb (Inst)',
                    '${widget.flight.maxClimbRate!.toStringAsFixed(1)} m/s',
                    Icons.trending_up,
                  ),
                if (widget.flight.maxSinkRate != null)
                  _buildStatItem(
                    'Max Sink (Inst)',
                    '${widget.flight.maxSinkRate!.toStringAsFixed(1)} m/s',
                    Icons.trending_down,
                  ),
                if (widget.flight.maxClimbRate5Sec != null)
                  _buildStatItem(
                    'Max Climb (15s)',
                    '${widget.flight.maxClimbRate5Sec!.toStringAsFixed(1)} m/s',
                    Icons.trending_up,
                  ),
                if (widget.flight.maxSinkRate5Sec != null)
                  _buildStatItem(
                    'Max Sink (15s)',
                    '${widget.flight.maxSinkRate5Sec!.toStringAsFixed(1)} m/s',
                    Icons.trending_down,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }



  Widget _buildStatItem(String label, String value, IconData icon) {
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

  Widget _buildFloatingStats() {
    // Only show stats for hovered point
    if (_hoveredPointIndex == null || 
        _hoveredPointIndex! >= _trackPoints.length ||
        _instantaneousRates.isEmpty ||
        _fifteenSecondRates.isEmpty) {
      return const SizedBox.shrink();
    }

    final point = _trackPoints[_hoveredPointIndex!];
    final instantRate = _hoveredPointIndex! < _instantaneousRates.length
        ? _instantaneousRates[_hoveredPointIndex!]
        : 0.0;
    final fifteenSecRate = _hoveredPointIndex! < _fifteenSecondRates.length
        ? _fifteenSecondRates[_hoveredPointIndex!]
        : 0.0;

    // Calculate screen position from the map coordinates
    final hoveredPoint = _trackPoints[_hoveredPointIndex!];
    final hoveredLatLng = LatLng(hoveredPoint.latitude, hoveredPoint.longitude);
    final screenPoint = _mapController?.camera.latLngToScreenPoint(hoveredLatLng);
    
    if (screenPoint == null) {
      return const SizedBox.shrink();
    }
    
    double left = screenPoint.x.toDouble();
    double top = screenPoint.y.toDouble() - 120; // Position above the point

    // Adjust if off-screen
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    
    if (left + 200 > screenWidth) left = screenWidth - 220;
    if (left < 20) left = 20;
    if (top < 20) top = screenPoint.y.toDouble() + 40; // Position below if no room above
    if (top + 100 > screenHeight) top = screenHeight - 120;

    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        onTap: () {
          // Close the floating stats when tapped
          setState(() {
            _hoveredPointIndex = null;
          });
          _createMarkers();
        },
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: 'Time: ',
                      style: TextStyle(color: Colors.grey[800], fontSize: 11),
                    ),
                    TextSpan(
                      text: '${point.timestamp.hour.toString().padLeft(2, '0')}:${point.timestamp.minute.toString().padLeft(2, '0')}:${point.timestamp.second.toString().padLeft(2, '0')}',
                      style: TextStyle(color: Colors.grey[800], fontSize: 11, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: 'Alt: ',
                      style: TextStyle(color: Colors.grey[800], fontSize: 11),
                    ),
                    TextSpan(
                      text: '${point.gpsAltitude.toInt()} m',
                      style: TextStyle(color: Colors.grey[800], fontSize: 11, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: 'Instant: ',
                      style: TextStyle(color: Colors.grey[800], fontSize: 11),
                    ),
                    TextSpan(
                      text: '${instantRate.toStringAsFixed(1)} m/s',
                      style: TextStyle(
                        color: _getClimbRateColor(instantRate),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: '15s Avg: ',
                      style: TextStyle(color: Colors.grey[800], fontSize: 11),
                    ),
                    TextSpan(
                      text: '${fifteenSecRate.toStringAsFixed(1)} m/s',
                      style: TextStyle(
                        color: _getClimbRateColor(fifteenSecRate),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
    if (!widget.config.showAltitudeChart || _trackPoints.isEmpty) {
      return const SizedBox.shrink();
    }

    final altitudeData = _prepareAltitudeChartData();
    if (altitudeData.isEmpty) return const SizedBox.shrink();

    // Calculate altitude range for Y-axis
    final altitudes = altitudeData.map((spot) => spot.y).toList();
    final minAlt = altitudes.reduce(min);
    final maxAlt = altitudes.reduce(max);
    final altRange = maxAlt - minAlt;
    final padding = altRange * 0.1; // 10% padding

    final selectedTime = _getSelectedPointTime();

    return Container(
      height: 120,
      margin: const EdgeInsets.all(8),
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
      child: MouseRegion(
        onHover: widget.config.interactive ? (PointerHoverEvent event) {
          _handleAltitudeChartMouseHover(event);
        } : null,
        onExit: widget.config.interactive ? (PointerExitEvent event) {
          _clearHoverState();
        } : null,
        child: LineChart(
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
            ),
          ],
          extraLinesData: selectedTime != null ? ExtraLinesData(
            verticalLines: [
              VerticalLine(
                x: selectedTime,
                color: Colors.orange[600]!,
                strokeWidth: 2,
                dashArray: [5, 5],
              ),
            ],
          ) : null,
          // Completely disable fl_chart's built-in touch system to prevent conflicting indicators
          lineTouchData: LineTouchData(enabled: false),
          ),
        ),
      ),
    );
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

  /// Prepare altitude chart data from track points
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

    return spots;
  }

  /// Get the X-coordinate (time) for the selected point
  double? _getSelectedPointTime() {
    // Only use hovered point
    if (_hoveredPointIndex == null || _hoveredPointIndex! >= _trackPoints.length) {
      return null;
    }

    final hoveredPoint = _trackPoints[_hoveredPointIndex!];
    // Return minutes since midnight
    return hoveredPoint.timestamp.hour * 60.0 + hoveredPoint.timestamp.minute + hoveredPoint.timestamp.second / 60.0;
  }

  /// Handle tap on altitude chart to set hover point
  void _handleAltitudeChartTap(double timeMinutes) {
    if (_trackPoints.isEmpty) return;
    
    // Find the closest point to the tapped time
    int closestIndex = 0;
    double minDiff = double.infinity;

    for (int i = 0; i < _trackPoints.length; i++) {
      final pointTime = _trackPoints[i].timestamp.hour * 60.0 + _trackPoints[i].timestamp.minute + _trackPoints[i].timestamp.second / 60.0;
      final diff = (pointTime - timeMinutes).abs();
      
      if (diff < minDiff) {
        minDiff = diff;
        closestIndex = i;
      }
    }

    setState(() {
      _hoveredPointIndex = closestIndex;
    });
    
    _createMarkers();
  }

  /// Handle hover on altitude chart to show real-time position
  void _handleAltitudeChartHover(double timeMinutes) {
    if (_trackPoints.isEmpty) return;
    
    // Find the closest point to the hovered time
    int closestIndex = 0;
    double minDiff = double.infinity;

    for (int i = 0; i < _trackPoints.length; i++) {
      final pointTime = _trackPoints[i].timestamp.hour * 60.0 + _trackPoints[i].timestamp.minute + _trackPoints[i].timestamp.second / 60.0;
      final diff = (pointTime - timeMinutes).abs();
      
      if (diff < minDiff) {
        minDiff = diff;
        closestIndex = i;
      }
    }

    if (_hoveredPointIndex != closestIndex) {
      setState(() {
        _hoveredPointIndex = closestIndex;
      });
      _createMarkers();
    }
  }

  /// Handle mouse hover on altitude chart by converting mouse position to time
  void _handleAltitudeChartMouseHover(PointerHoverEvent event) {
    if (_trackPoints.isEmpty) return;
    
    // Get the chart container bounds
    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    
    // Calculate the altitude chart area (120px height + margins/padding)
    // Chart is at the bottom, so we need to find its vertical position
    final chartHeight = 120.0;
    final chartMargin = 8.0;
    final chartPadding = 12.0;
    
    // Get mouse position relative to the chart area
    final mouseX = event.localPosition.dx - chartMargin - chartPadding;
    final chartWidth = renderBox.size.width - (2 * chartMargin) - (2 * chartPadding);
    
    if (mouseX < 0 || mouseX > chartWidth) return;
    
    // Calculate time range for the chart
    if (_trackPoints.isEmpty) return;
    final firstTime = _trackPoints.first.timestamp;
    final lastTime = _trackPoints.last.timestamp;
    final startMinutes = firstTime.hour * 60.0 + firstTime.minute + firstTime.second / 60.0;
    final endMinutes = lastTime.hour * 60.0 + lastTime.minute + lastTime.second / 60.0;
    
    // Convert mouse X position to time
    final timeRatio = mouseX / chartWidth;
    final hoveredTimeMinutes = startMinutes + (timeRatio * (endMinutes - startMinutes));
    
    // Use existing hover logic
    _handleAltitudeChartHover(hoveredTimeMinutes);
  }

  /// Clear hover state when mouse leaves altitude chart
  void _clearHoverState() {
    if (_hoveredPointIndex != null) {
      setState(() {
        _hoveredPointIndex = null;
      });
      _createMarkers();
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
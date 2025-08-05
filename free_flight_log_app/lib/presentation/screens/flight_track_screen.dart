import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/flight.dart';
import '../../data/models/igc_file.dart';
import '../../services/igc_import_service.dart';

class FlightTrackScreen extends StatefulWidget {
  final Flight flight;

  const FlightTrackScreen({super.key, required this.flight});

  @override
  State<FlightTrackScreen> createState() => _FlightTrackScreenState();
}

class _FlightTrackScreenState extends State<FlightTrackScreen> {
  MapController? _mapController;
  final IgcImportService _igcService = IgcImportService();
  
  List<IgcPoint> _trackPoints = [];
  List<double> _instantaneousRates = [];
  List<double> _fifteenSecondRates = [];
  List<Polyline> _polylines = [];
  List<Marker> _markers = [];
  bool _isLoading = true;
  String? _error;
  
  // Map display options
  bool _showMarkers = true;
  bool _showStraightLine = true;
  bool _showSatelliteView = false;
  
  // Currently selected track point for climb rate display
  int? _selectedPointIndex;

  @override
  void initState() {
    super.initState();
    _loadSavedPreferences();
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

    // Add selected point marker if one is selected
    if (_selectedPointIndex != null && _selectedPointIndex! < _trackPoints.length) {
      final selectedPoint = _trackPoints[_selectedPointIndex!];
      
      markers.add(
        Marker(
          point: LatLng(selectedPoint.latitude, selectedPoint.longitude),
          child: _buildCrosshairsIcon(Colors.black),
          width: 40,
          height: 40,
        ),
      );
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


  void _toggleMarkers() async {
    setState(() {
      _showMarkers = !_showMarkers;
    });
    _createMarkers();
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('flight_track_show_markers', _showMarkers);
  }

  void _toggleStraightLine() async {
    setState(() {
      _showStraightLine = !_showStraightLine;
    });
    _createPolylines();
    _createMarkers();
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('flight_track_show_straight_line', _showStraightLine);
  }

  void _toggleSatelliteView() async {
    setState(() {
      _showSatelliteView = !_showSatelliteView;
    });
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('flight_track_show_satellite', _showSatelliteView);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flight Track'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorState()
              : Stack(
                  children: [
                    Column(
                      children: [
                        _buildStatsBar(),
                        Expanded(
                          child: Stack(
                            children: [
                              _buildMap(),
                              _buildMapControls(),
                              _buildClimbRateLegend(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
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
    );
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
          if (_selectedPointIndex != null) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            _buildClimbRateDisplay(),
          ],
        ],
      ),
    );
  }

  Widget _buildClimbRateDisplay() {
    if (_selectedPointIndex == null || 
        _selectedPointIndex! >= _trackPoints.length ||
        _instantaneousRates.isEmpty ||
        _fifteenSecondRates.isEmpty) {
      return const SizedBox.shrink();
    }

    final point = _trackPoints[_selectedPointIndex!];
    final instantRate = _selectedPointIndex! < _instantaneousRates.length
        ? _instantaneousRates[_selectedPointIndex!]
        : 0.0;
    final fifteenSecRate = _selectedPointIndex! < _fifteenSecondRates.length
        ? _fifteenSecondRates[_selectedPointIndex!]
        : 0.0;

    return Column(
      children: [
        Text(
          'Point ${_selectedPointIndex! + 1} - ${_formatTime(point.timestamp)}',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildClimbRateItem(
              'Instant',
              '${instantRate.toStringAsFixed(1)} m/s',
              instantRate >= 0 ? Icons.trending_up : Icons.trending_down,
              instantRate >= 0 ? Colors.green : Colors.red,
            ),
            _buildClimbRateItem(
              '15-sec Avg',
              '${fifteenSecRate.toStringAsFixed(1)} m/s',
              fifteenSecRate >= 0 ? Icons.trending_up : Icons.trending_down,
              fifteenSecRate >= 0 ? Colors.green : Colors.red,
            ),
            _buildStatItem(
              'Altitude',
              '${point.gpsAltitude} m',
              Icons.height,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildClimbRateItem(String label, String value, IconData icon, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold, 
            fontSize: 12,
            color: color,
          ),
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

  Widget _buildMap() {
    _mapController ??= MapController();
    
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _trackPoints.isNotEmpty
            ? LatLng(_trackPoints.first.latitude, _trackPoints.first.longitude)
            : const LatLng(0, 0),
        initialZoom: 14,
        onTap: (tapPosition, point) {
          _handleMapTap(point);
        },
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
  }

  void _handleMapTap(LatLng tappedPoint) {
    if (_trackPoints.isEmpty) return;

    // Find the closest track point to the tapped location
    double minDistance = double.infinity;
    int closestIndex = 0;

    for (int i = 0; i < _trackPoints.length; i++) {
      final point = _trackPoints[i];
      final distance = _calculateDistance(
        tappedPoint.latitude,
        tappedPoint.longitude,
        point.latitude,
        point.longitude,
      );

      if (distance < minDistance) {
        minDistance = distance;
        closestIndex = i;
      }
    }

    // Only update if the tap is reasonably close to the track (within 1km)
    if (minDistance < 1.0) {
      setState(() {
        _selectedPointIndex = closestIndex;
      });

      // Update markers to show selected point
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

  Widget _buildMapControls() {
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

  Widget _buildClimbRateLegend() {
    return Positioned(
      bottom: 8,
      left: 8,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
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
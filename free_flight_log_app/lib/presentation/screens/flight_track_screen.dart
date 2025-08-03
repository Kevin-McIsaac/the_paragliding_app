import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
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
  bool _showAltitudeColors = true;
  bool _showMarkers = true;
  bool _showStraightLine = true;
  
  // Currently selected track point for climb rate display
  int? _selectedPointIndex;

  @override
  void initState() {
    super.initState();
    _loadTrackData();
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
      final fifteenSecondRates = igcFile.calculate15SecondClimbRates();

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

    // Create main track polyline
    final trackCoordinates = _trackPoints
        .map((point) => LatLng(point.latitude, point.longitude))
        .toList();

    final trackPolyline = Polyline(
      points: trackCoordinates,
      color: _showAltitudeColors ? Colors.blue : Colors.red,
      strokeWidth: 3.0,
    );
    polylines.add(trackPolyline);

    // Create straight line polyline if enabled
    if (_showStraightLine && _trackPoints.length >= 2) {
      final launchPoint = LatLng(_trackPoints.first.latitude, _trackPoints.first.longitude);
      final landingPoint = LatLng(_trackPoints.last.latitude, _trackPoints.last.longitude);
      
      final straightLinePolyline = Polyline(
        points: [launchPoint, landingPoint],
        color: Colors.orange,
        strokeWidth: 4.0,
        isDotted: true,
      );
      polylines.add(straightLinePolyline);
    }

    // TODO: Add altitude-based coloring in future update
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
          child: _buildMarkerIcon(Colors.orange, 'S'),
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
              color: Colors.orange,
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

  void _toggleAltitudeColors() {
    setState(() {
      _showAltitudeColors = !_showAltitudeColors;
    });
    _createPolylines();
  }

  void _toggleMarkers() {
    setState(() {
      _showMarkers = !_showMarkers;
    });
    _createMarkers();
  }

  void _toggleStraightLine() {
    setState(() {
      _showStraightLine = !_showStraightLine;
    });
    _createPolylines();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flight Track'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'markers':
                  _toggleMarkers();
                  break;
                case 'colors':
                  _toggleAltitudeColors();
                  break;
                case 'straight_line':
                  _toggleStraightLine();
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
                value: 'colors',
                child: Row(
                  children: [
                    Icon(_showAltitudeColors ? Icons.palette : Icons.palette_outlined),
                    const SizedBox(width: 8),
                    Text('${_showAltitudeColors ? 'Simple' : 'Altitude'} Colors'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'straight_line',
                child: Row(
                  children: [
                    Icon(_showStraightLine ? Icons.timeline : Icons.timeline_outlined),
                    const SizedBox(width: 8),
                    Text('${_showStraightLine ? 'Hide' : 'Show'} Straight Line'),
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
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorState()
              : Column(
                  children: [
                    _buildStatsBar(),
                    Expanded(child: _buildMap()),
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
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
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
}
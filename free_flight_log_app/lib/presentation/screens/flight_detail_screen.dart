import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../data/models/flight.dart';
import '../../data/models/site.dart';
import '../../data/models/wing.dart';
import '../../data/models/igc_file.dart';
import '../../data/repositories/flight_repository.dart';
import '../../data/repositories/site_repository.dart';
import '../../data/repositories/wing_repository.dart';
import '../../services/igc_import_service.dart';
import 'edit_flight_screen.dart';
import 'flight_track_screen.dart';

class FlightDetailScreen extends StatefulWidget {
  final Flight flight;

  const FlightDetailScreen({super.key, required this.flight});

  @override
  State<FlightDetailScreen> createState() => _FlightDetailScreenState();
}

class _FlightDetailScreenState extends State<FlightDetailScreen> {
  final FlightRepository _flightRepository = FlightRepository();
  final SiteRepository _siteRepository = SiteRepository();
  final WingRepository _wingRepository = WingRepository();
  final IgcImportService _igcService = IgcImportService();
  
  late Flight _flight;
  Site? _launchSite;
  Site? _landingSite;
  Wing? _wing;
  bool _isLoading = true;
  bool _flightModified = false;
  
  // Map-related state
  MapController? _mapController;
  List<IgcPoint> _trackPoints = [];
  List<Polyline> _polylines = [];
  List<Marker> _markers = [];
  bool _isTrackLoading = false;
  String? _trackError;

  @override
  void initState() {
    super.initState();
    _flight = widget.flight;
    _loadFlightDetails();
    _loadTrackData();
  }

  Future<void> _loadFlightDetails() async {
    try {
      if (_flight.launchSiteId != null) {
        _launchSite = await _siteRepository.getSite(_flight.launchSiteId!);
      }
      if (_flight.landingSiteId != null) {
        _landingSite = await _siteRepository.getSite(_flight.landingSiteId!);
      }
      if (_flight.wingId != null) {
        _wing = await _wingRepository.getWing(_flight.wingId!);
      }
    } catch (e) {
      print('Error loading flight details: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadTrackData() async {
    if (_flight.trackLogPath == null) {
      return;
    }

    setState(() {
      _isTrackLoading = true;
      _trackError = null;
    });

    try {
      final trackPoints = await _igcService.getTrackPoints(_flight.trackLogPath!);
      
      if (trackPoints.isEmpty) {
        setState(() {
          _trackError = 'No track points found';
          _isTrackLoading = false;
        });
        return;
      }

      setState(() {
        _trackPoints = trackPoints;
        _isTrackLoading = false;
      });
      
      _createPolylines();
      _createMarkers();
      
    } catch (e) {
      setState(() {
        _trackError = 'Error loading track data: $e';
        _isTrackLoading = false;
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
      color: Colors.blue,
      strokeWidth: 3.0,
    );
    polylines.add(trackPolyline);

    // Create straight line polyline if we have enough points
    if (_trackPoints.length >= 2 && _flight.straightDistance != null) {
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

    setState(() {
      _polylines = polylines;
    });
  }

  void _createMarkers() {
    if (_trackPoints.isEmpty) {
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

    // Add straight distance marker at midpoint if showing straight line
    if (_trackPoints.length >= 2 && _flight.straightDistance != null) {
      final startPoint = _trackPoints.first;
      final endPoint = _trackPoints.last;
      final midLat = (startPoint.latitude + endPoint.latitude) / 2;
      final midLng = (startPoint.longitude + endPoint.longitude) / 2;
      
      markers.add(
        Marker(
          point: LatLng(midLat, midLng),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.orange,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white, width: 1),
            ),
            child: Text(
              '${_flight.straightDistance!.toStringAsFixed(1)} km',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 8,
                fontWeight: FontWeight.bold,
              ),
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

  Future<void> _editFlight() async {
    final updatedFlight = await Navigator.of(context).push<Flight>(
      MaterialPageRoute(
        builder: (context) => EditFlightScreen(flight: _flight),
      ),
    );

    if (updatedFlight != null) {
      setState(() {
        _flight = updatedFlight;
        _flightModified = true;
      });
      _loadFlightDetails();
    }
  }

  Future<void> _deleteFlight() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Flight'),
        content: const Text('Are you sure you want to delete this flight? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _flightRepository.deleteFlight(_flight.id!);
        if (mounted) {
          Navigator.of(context).pop(true); // Return true to indicate deletion
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting flight: $e')),
          );
        }
      }
    }
  }

  String _formatDate(DateTime date) {
    return DateFormat('EEEE, MMMM d, y').format(date);
  }

  String _formatDuration(int minutes) {
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (hours > 0) {
      return '${hours}h ${mins}m';
    }
    return '${mins}m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Flight ${_formatDate(_flight.date)}'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(_flightModified),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: _editFlight,
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'delete') {
                _deleteFlight();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Delete Flight', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Flight Overview Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Flight Overview',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: _buildInfoTile(
                                  'Date',
                                  _formatDate(_flight.date),
                                  Icons.calendar_today,
                                ),
                              ),
                              Expanded(
                                child: _buildInfoTile(
                                  'Duration',
                                  _formatDuration(_flight.duration),
                                  Icons.access_time,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: _buildInfoTile(
                                  'Launch',
                                  _flight.launchTime,
                                  Icons.flight_takeoff,
                                ),
                              ),
                              Expanded(
                                child: _buildInfoTile(
                                  'Landing',
                                  _flight.landingTime,
                                  Icons.flight_land,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Flight Statistics Card
                  if (_flight.maxAltitude != null || _flight.distance != null || 
                      _flight.maxClimbRate != null || _flight.maxSinkRate != null ||
                      _flight.maxClimbRate5Sec != null || _flight.maxSinkRate5Sec != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Flight Statistics',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                if (_flight.maxAltitude != null)
                                  Expanded(
                                    child: _buildInfoTile(
                                      'Max Altitude',
                                      '${_flight.maxAltitude!.toStringAsFixed(0)} m',
                                      Icons.height,
                                    ),
                                  ),
                                if (_flight.distance != null)
                                  Expanded(
                                    child: _buildInfoTile(
                                      'Ground Track',
                                      '${_flight.distance!.toStringAsFixed(1)} km',
                                      Icons.timeline,
                                    ),
                                  ),
                                if (_flight.straightDistance != null)
                                  Expanded(
                                    child: _buildInfoTile(
                                      'Straight Distance',
                                      '${_flight.straightDistance!.toStringAsFixed(1)} km',
                                      Icons.straighten,
                                    ),
                                  ),
                              ],
                            ),
                            if (_flight.maxClimbRate != null || _flight.maxSinkRate != null ||
                                _flight.maxClimbRate5Sec != null || _flight.maxSinkRate5Sec != null) ...[
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  if (_flight.maxClimbRate != null)
                                    Expanded(
                                      child: _buildInfoTile(
                                        'Max Climb',
                                        '${_flight.maxClimbRate!.toStringAsFixed(1)} m/s',
                                        Icons.trending_up,
                                      ),
                                    ),
                                  if (_flight.maxSinkRate != null)
                                    Expanded(
                                      child: _buildInfoTile(
                                        'Max Sink',
                                        '${_flight.maxSinkRate!.toStringAsFixed(1)} m/s',
                                        Icons.trending_down,
                                      ),
                                    ),
                                  if (_flight.maxClimbRate5Sec != null)
                                    Expanded(
                                      child: _buildInfoTile(
                                        'Max Climb (15s)',
                                        '${_flight.maxClimbRate5Sec!.toStringAsFixed(1)} m/s',
                                        Icons.trending_up,
                                      ),
                                    ),
                                  if (_flight.maxSinkRate5Sec != null)
                                    Expanded(
                                      child: _buildInfoTile(
                                        'Max Sink (15s)',
                                        '${_flight.maxSinkRate5Sec!.toStringAsFixed(1)} m/s',
                                        Icons.trending_down,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 16),

                  // Sites Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Sites',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 16),
                          if (_launchSite != null)
                            ListTile(
                              leading: const Icon(Icons.flight_takeoff),
                              title: const Text('Launch Site'),
                              subtitle: Text(_launchSite!.name),
                              trailing: Text(
                                '${_launchSite!.latitude.toStringAsFixed(4)}, ${_launchSite!.longitude.toStringAsFixed(4)}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          if (_landingSite != null)
                            ListTile(
                              leading: const Icon(Icons.flight_land),
                              title: const Text('Landing Site'),
                              subtitle: Text(_landingSite!.name),
                              trailing: Text(
                                '${_landingSite!.latitude.toStringAsFixed(4)}, ${_landingSite!.longitude.toStringAsFixed(4)}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          if (_launchSite == null && _landingSite == null)
                            const ListTile(
                              leading: Icon(Icons.location_off),
                              title: Text('No site information'),
                              subtitle: Text('Sites were not recorded for this flight'),
                            ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Track Log Card with Embedded Map
                  if (_flight.trackLogPath != null && _flight.source == 'igc')
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Flight Track',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                TextButton.icon(
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (context) => FlightTrackScreen(flight: _flight),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.fullscreen),
                                  label: const Text('Full Screen'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _buildEmbeddedMap(),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 16),

                  // Equipment Card
                  if (_wing != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Equipment',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 16),
                            ListTile(
                              leading: const Icon(Icons.paragliding),
                              title: Text(_wing!.manufacturer ?? 'Unknown'),
                              subtitle: Text(_wing!.model ?? 'Unknown'),
                              trailing: Text(_wing!.size ?? ''),
                            ),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 16),

                  // Notes Card (Full Width)
                  if (_flight.notes?.isNotEmpty == true)
                    SizedBox(
                      width: double.infinity,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Notes',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _flight.notes!,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildEmbeddedMap() {
    if (_isTrackLoading) {
      return Container(
        height: 250,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Colors.grey[100],
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading track data...'),
            ],
          ),
        ),
      );
    }

    if (_trackError != null) {
      return Container(
        height: 250,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Colors.grey[100],
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'Track Not Available',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _trackError!,
                style: TextStyle(color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (_trackPoints.isEmpty) {
      return Container(
        height: 250,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Colors.grey[100],
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.map_outlined, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'No Track Data',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      );
    }

    _mapController ??= MapController();

    return Container(
      height: 250,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _trackPoints.isNotEmpty
                ? LatLng(_trackPoints.first.latitude, _trackPoints.first.longitude)
                : const LatLng(0, 0),
            initialZoom: 12,
            onMapReady: () {
              _fitMapToBounds();
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
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(20.0)),
    );
  }

  Widget _buildInfoTile(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
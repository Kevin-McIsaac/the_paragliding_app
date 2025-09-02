import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/flight.dart';
import '../../data/models/site.dart';
import '../../data/models/igc_file.dart';
import '../../services/igc_import_service.dart';
import '../../services/database_service.dart';
import '../../services/logging_service.dart';
import '../screens/flight_track_3d_fullscreen.dart';

enum MapProvider {
  openStreetMap('Street Map', 'OSM', 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', 18, '© OpenStreetMap contributors'),
  googleSatellite('Google Satellite', 'Google', 'https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}', 18, '© Google'),
  esriWorldImagery('Esri Satellite', 'Esri', 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}', 18, '© Esri');

  const MapProvider(this.displayName, this.shortName, this.urlTemplate, this.maxZoom, this.attribution);
  
  final String displayName;
  final String shortName;
  final String urlTemplate;
  final int maxZoom;
  final String attribution;
}

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
  final IgcImportService _igcService = IgcImportService.instance;
  final DatabaseService _databaseService = DatabaseService.instance;
  final MapController _mapController = MapController();
  
  static const String _mapProviderKey = 'flight_track_2d_map_provider';
  
  List<IgcPoint> _trackPoints = [];
  Site? _launchSite;
  bool _isLoading = true;
  String? _error;
  MapProvider _selectedMapProvider = MapProvider.openStreetMap;
  
  @override
  void initState() {
    super.initState();
    _loadMapProvider();
    _loadTrackData();
    _loadSiteData();
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

  Future<void> _loadSiteData() async {
    if (widget.flight.launchSiteId != null) {
      try {
        _launchSite = await _databaseService.getSite(widget.flight.launchSiteId!);
        setState(() {
          // Trigger rebuild to update markers with site name
        });
      } catch (e) {
        LoggingService.error('FlightTrack2DWidget: Error loading site data', e);
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
      final trackData = await _igcService.getTrackPointsWithTimezone(widget.flight.trackLogPath!);
      
      if (trackData.points.isEmpty) {
        setState(() {
          _error = 'No track points found';
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _trackPoints = trackData.points;
        _isLoading = false;
      });
      
      LoggingService.info('FlightTrack2DWidget: Loaded ${_trackPoints.length} track points');
    } catch (e) {
      LoggingService.error('FlightTrack2DWidget: Error loading track data', e);
      setState(() {
        _error = 'Error loading track data: $e';
        _isLoading = false;
      });
    }
  }

  double _calculateClimbRate(IgcPoint point1, IgcPoint point2) {
    final timeDiff = point2.timestamp.difference(point1.timestamp).inSeconds;
    if (timeDiff <= 0) return 0.0;
    
    final altitudeDiff = point2.gpsAltitude - point1.gpsAltitude;
    return altitudeDiff / timeDiff;
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

  List<Marker> _buildMarkers() {
    if (_trackPoints.isEmpty) return [];
    
    final firstPoint = _trackPoints.first;
    final lastPoint = _trackPoints.last;
    
    return [
      // Launch marker
      Marker(
        point: LatLng(firstPoint.latitude, firstPoint.longitude),
        width: 30,
        height: 30,
        child: Tooltip(
          message: _launchSite?.name ?? 'Launch Site',
          child: Container(
            decoration: BoxDecoration(
              color: Colors.green,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.flight_takeoff,
              color: Colors.white,
              size: 16,
            ),
          ),
        ),
      ),
      // Landing marker
      Marker(
        point: LatLng(lastPoint.latitude, lastPoint.longitude),
        width: 30,
        height: 30,
        child: Tooltip(
          message: widget.flight.landingDescription ?? 'Landing Site',
          child: Container(
            decoration: BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.flight_land,
              color: Colors.white,
              size: 16,
            ),
          ),
        ),
      ),
    ];
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
    const padding = 0.005;
    return LatLngBounds(
      LatLng(minLat - padding, minLng - padding),
      LatLng(maxLat + padding, maxLng + padding),
    );
  }

  void _fitMapToBounds() {
    if (_trackPoints.isNotEmpty) {
      final bounds = _calculateBounds();
      _mapController.fitCamera(CameraFit.bounds(bounds: bounds));
    }
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
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
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

  @override
  Widget build(BuildContext context) {
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

    return SizedBox(
      height: widget.height,
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
              onMapReady: _fitMapToBounds,
            ),
            children: [
              TileLayer(
                urlTemplate: _selectedMapProvider.urlTemplate,
                maxZoom: _selectedMapProvider.maxZoom.toDouble(),
                userAgentPackageName: 'com.example.free_flight_log_app',
              ),
              PolylineLayer(
                polylines: _buildColoredTrackLines(),
              ),
              MarkerLayer(
                markers: _buildMarkers(),
              ),
            ],
          ),
          // Map provider selector (top right, like Site Maps)
          Positioned(
            top: 8,
            right: 8,
            child: _buildMapProviderButton(),
          ),
          // 3D View button (bottom right)
          Positioned(
            bottom: 60,
            right: 8,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: TextButton.icon(
                onPressed: _openFullscreen3D,
                icon: const Icon(Icons.threed_rotation, color: Colors.white, size: 18),
                label: const Text('3D View', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
            ),
          ),
          // Legend
          Positioned(
            bottom: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(4),
                boxShadow: const [
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
                  const Text('Track Color:', style: TextStyle(fontSize: 10, fontWeight: FontWeight.normal, color: Colors.black87)),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 14, height: 3, decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(1.5))),
                      const SizedBox(width: 8),
                      const Text('Climbing', style: TextStyle(fontSize: 10, color: Colors.black87)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 14, height: 3, decoration: BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.circular(1.5))),
                      const SizedBox(width: 8),
                      const Text('Sink (<1.5m/s)', style: TextStyle(fontSize: 10, color: Colors.black87)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 14, height: 3, decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(1.5))),
                      const SizedBox(width: 8),
                      const Text('Sink (>1.5m/s)', style: TextStyle(fontSize: 10, color: Colors.black87)),
                    ],
                  ),
                ],
              ),
            ),
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
        ],
      ),
    );
  }
}
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../data/models/flight.dart';
import '../../../data/models/igc_file.dart';
import '../../../services/logging_service.dart';

/// Configuration for the flight track map display
class FlightMapConfig {
  final bool interactive;
  final bool showStraightLine;
  final double? height;
  final double? width;

  const FlightMapConfig({
    this.interactive = true,
    this.showStraightLine = true,
    this.height,
    this.width,
  });

  const FlightMapConfig.embedded({
    this.height = 250,
    this.width,
  }) : interactive = false,
       showStraightLine = true;
}

/// Widget responsible for displaying the flight track on a map
class FlightTrackMap extends StatefulWidget {
  final Flight flight;
  final IgcFile? igcData;
  final FlightMapConfig config;
  final VoidCallback? onMapReady;

  const FlightTrackMap({
    super.key,
    required this.flight,
    this.igcData,
    this.config = const FlightMapConfig(),
    this.onMapReady,
  });

  @override
  State<FlightTrackMap> createState() => _FlightTrackMapState();
}

class _FlightTrackMapState extends State<FlightTrackMap> {
  final MapController _mapController = MapController();
  bool _tilesReady = false;
  bool _preferencesLoaded = false;
  String _tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  
  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedTileUrl = prefs.getString('map_tile_url') ?? _tileUrl;
      
      if (mounted) {
        setState(() {
          _tileUrl = savedTileUrl;
          _preferencesLoaded = true;
        });
      }
      
      LoggingService.debug('FlightTrackMap: Loaded preferences, tile URL: $_tileUrl');
    } catch (e) {
      LoggingService.error('FlightTrackMap: Failed to load preferences', e);
      if (mounted) {
        setState(() {
          _preferencesLoaded = true;
        });
      }
    }
  }

  void _onMapReady() {
    LoggingService.debug('FlightTrackMap: Map ready, enabling tiles');
    if (mounted) {
      setState(() {
        _tilesReady = true;
      });
      widget.onMapReady?.call();
    }
  }

  List<LatLng> _buildTrackPoints() {
    if (widget.igcData?.trackPoints.isEmpty ?? true) {
      return [];
    }
    
    return widget.igcData!.trackPoints
        .map((point) => LatLng(point.latitude, point.longitude))
        .toList();
  }

  List<LatLng> _buildStraightLinePoints() {
    final trackPoints = _buildTrackPoints();
    if (trackPoints.isEmpty) return [];
    
    return [trackPoints.first, trackPoints.last];
  }

  LatLngBounds? _calculateBounds() {
    final trackPoints = _buildTrackPoints();
    if (trackPoints.isEmpty) return null;

    double minLat = trackPoints.first.latitude;
    double maxLat = trackPoints.first.latitude;
    double minLon = trackPoints.first.longitude;
    double maxLon = trackPoints.first.longitude;

    for (final point in trackPoints) {
      minLat = min(minLat, point.latitude);
      maxLat = max(maxLat, point.latitude);
      minLon = min(minLon, point.longitude);
      maxLon = max(maxLon, point.longitude);
    }

    // Add padding
    final latPadding = (maxLat - minLat) * 0.1;
    final lonPadding = (maxLon - minLon) * 0.1;

    return LatLngBounds(
      LatLng(minLat - latPadding, minLon - lonPadding),
      LatLng(maxLat + latPadding, maxLon + lonPadding),
    );
  }

  List<Marker> _buildMarkers() {
    final trackPoints = _buildTrackPoints();
    if (trackPoints.isEmpty) return [];

    final markers = <Marker>[];

    // Launch marker (green)
    markers.add(
      Marker(
        point: trackPoints.first,
        width: 24,
        height: 24,
        child: _buildCircleMarker(Colors.green, 'Launch'),
      ),
    );

    // Landing marker (red)
    if (trackPoints.length > 1) {
      markers.add(
        Marker(
          point: trackPoints.last,
          width: 24,
          height: 24,
          child: _buildCircleMarker(Colors.red, 'Landing'),
        ),
      );
    }

    return markers;
  }

  Widget _buildCircleMarker(Color color, String labelName) {
    return Container(
      decoration: BoxDecoration(
        color: color,
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
        Icons.place,
        color: Colors.white,
        size: 16,
      ),
    );
  }

  List<Polyline> _buildPolylines() {
    final trackPoints = _buildTrackPoints();
    if (trackPoints.isEmpty) return [];

    final polylines = <Polyline>[];

    // Flight track (blue)
    polylines.add(
      Polyline(
        points: trackPoints,
        strokeWidth: 3.0,
        color: Colors.blue,
      ),
    );

    // Straight line distance (red dashed - approximated with segments)
    if (widget.config.showStraightLine && trackPoints.length > 1) {
      polylines.add(
        Polyline(
          points: _buildStraightLinePoints(),
          strokeWidth: 2.0,
          color: Colors.red.withValues(alpha: 0.7),
        ),
      );
    }

    return polylines;
  }

  @override
  Widget build(BuildContext context) {
    if (!_preferencesLoaded) {
      return Container(
        height: widget.config.height ?? 400,
        width: widget.config.width,
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (widget.igcData?.trackPoints.isEmpty ?? true) {
      return Container(
        height: widget.config.height ?? 400,
        width: widget.config.width,
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.map_outlined, size: 48, color: Colors.grey),
              SizedBox(height: 8),
              Text(
                'No track data available',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    final bounds = _calculateBounds();
    
    return Container(
      height: widget.config.height ?? 400,
      width: widget.config.width,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCameraFit: bounds != null ? CameraFit.bounds(bounds: bounds) : null,
            interactionOptions: InteractionOptions(
              flags: widget.config.interactive 
                  ? InteractiveFlag.all 
                  : InteractiveFlag.none,
            ),
            onMapReady: _onMapReady,
          ),
          children: [
            // Only show tiles after map is ready to prevent loading issues
            if (_tilesReady)
              TileLayer(
                urlTemplate: _tileUrl,
                userAgentPackageName: 'com.freeflightlog.free_flight_log_app',
                maxZoom: 18,
                tileBuilder: (context, widget, tile) {
                  return ColorFiltered(
                    colorFilter: Theme.of(context).brightness == Brightness.dark
                        ? const ColorFilter.matrix([
                            -1, 0, 0, 0, 255,
                            0, -1, 0, 0, 255,
                            0, 0, -1, 0, 255,
                            0, 0, 0, 1, 0,
                          ])
                        : const ColorFilter.matrix([
                            1, 0, 0, 0, 0,
                            0, 1, 0, 0, 0,
                            0, 0, 1, 0, 0,
                            0, 0, 0, 1, 0,
                          ]),
                    child: widget,
                  );
                },
              ),
            
            // Flight track and markers
            PolylineLayer(polylines: _buildPolylines()),
            MarkerLayer(markers: _buildMarkers()),
            
            // Attribution
            RichAttributionWidget(
              attributions: [
                TextSourceAttribution(
                  'OpenStreetMap contributors',
                  onTap: () => launchUrl(
                    Uri.parse('https://openstreetmap.org/copyright'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
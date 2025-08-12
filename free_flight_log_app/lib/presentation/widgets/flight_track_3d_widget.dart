import 'dart:math';
import 'package:flutter/material.dart';
import '../../data/models/flight.dart';
import '../../data/models/igc_file.dart';
import '../../services/igc_import_service.dart';
import '../../services/logging_service.dart';
import 'cesium_3d_map_inappwebview.dart';
import 'cesium/cesium_webview_controller.dart';

/// Configuration for the 3D flight track visualization
class FlightTrack3DConfig {
  final bool embedded;
  final bool showControls;
  final bool showPlayback;
  final double? height;

  const FlightTrack3DConfig({
    this.embedded = false,
    this.showControls = true,
    this.showPlayback = true,
    this.height,
  });

  FlightTrack3DConfig.embedded()
      : embedded = true,
        showControls = true,
        showPlayback = true,
        height = 500;

  FlightTrack3DConfig.fullScreen()
      : embedded = false,
        showControls = true,
        showPlayback = true,
        height = null;
}

/// Widget to display a 3D visualization of a flight track using Cesium
class FlightTrack3DWidget extends StatefulWidget {
  final Flight flight;
  final FlightTrack3DConfig config;
  final bool showPlaybackPanel;
  
  const FlightTrack3DWidget({
    super.key,
    required this.flight,
    this.config = const FlightTrack3DConfig(),
    this.showPlaybackPanel = true,
  });

  @override
  State<FlightTrack3DWidget> createState() => _FlightTrack3DWidgetState();
}

class _FlightTrack3DWidgetState extends State<FlightTrack3DWidget> {
  final CesiumWebViewController _cesiumController = CesiumWebViewController();
  final IgcImportService _igcService = IgcImportService();
  
  List<IgcPoint> _trackPoints = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTrackData();
  }

  @override
  void dispose() {
    _cesiumController.dispose();
    super.dispose();
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

      setState(() {
        _trackPoints = trackPoints;
        _isLoading = false;
      });
      
    } catch (e) {
      setState(() {
        _error = 'Error loading track data: $e';
        _isLoading = false;
      });
    }
  }


  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        height: widget.config.height ?? 500,
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
              Text('Loading 3D track data...'),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return Container(
        height: widget.config.height ?? 500,
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
                '3D Track Not Available',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[500],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // Convert IgcPoints to format expected by Cesium widget with timestamps and climb rates
    final trackPointsForCesium = _trackPoints.map((point) {
      // Use the virtual properties if available, otherwise fall back to calculated values
      final climbRate = point.climbRate;
      
      // Debug log to verify climb rates are being passed
      if (point.pointIndex != null && point.pointIndex! % 30 == 0) {
        LoggingService.debug('FlightTrack3D: Point ${point.pointIndex} - climbRate: $climbRate, groundSpeed: ${point.groundSpeed}');
      }
      
      return {
        'latitude': point.latitude,
        'longitude': point.longitude,
        'altitude': point.gpsAltitude,  // Use GPS altitude to match terrain reference
        'gpsAltitude': point.gpsAltitude,
        'pressureAltitude': point.pressureAltitude,
        'timestamp': point.timestamp.toIso8601String(),
        'climbRate': climbRate,
        'groundSpeed': point.groundSpeed,
      };
    }).toList();

    // Calculate appropriate initial view based on track bounds
    double initialLat = 46.8182;
    double initialLon = 8.2275;
    double initialAltitude = 10000; // Default 10km
    
    if (_trackPoints.isNotEmpty) {
      // Calculate center of the track
      double minLat = _trackPoints.first.latitude;
      double maxLat = _trackPoints.first.latitude;
      double minLon = _trackPoints.first.longitude;
      double maxLon = _trackPoints.first.longitude;
      
      for (var point in _trackPoints) {
        minLat = minLat < point.latitude ? minLat : point.latitude;
        maxLat = maxLat > point.latitude ? maxLat : point.latitude;
        minLon = minLon < point.longitude ? minLon : point.longitude;
        maxLon = maxLon > point.longitude ? maxLon : point.longitude;
      }
      
      initialLat = (minLat + maxLat) / 2;
      initialLon = (minLon + maxLon) / 2;
      
      // Calculate altitude based on track extent for fullscreen mode
      if (!widget.config.embedded) {
        // Calculate the diagonal distance of the bounding box in meters
        double latDiff = maxLat - minLat;
        double lonDiff = maxLon - minLon;
        
        // Add padding to account for UI elements (stats box at bottom)
        // Shift center slightly up to compensate for bottom UI
        initialLat = minLat + (latDiff * 0.45); // Shift center up slightly
        
        // Rough conversion to meters (at mid-latitude)
        double latMeters = latDiff * 111000; // 1 degree latitude ≈ 111km
        double lonMeters = lonDiff * 111000 * cos(initialLat * pi / 180);
        double diagonal = sqrt(latMeters * latMeters + lonMeters * lonMeters);
        
        // Set altitude to roughly 4x the diagonal for better overview with UI padding
        // Minimum 8km, maximum 60km for fullscreen
        initialAltitude = (diagonal * 4).clamp(8000, 60000);
      }
    }

    // Build the 3D map widget
    Widget cesiumWidget = Cesium3DMapInAppWebView(
      initialLat: initialLat,
      initialLon: initialLon,
      initialAltitude: initialAltitude,
      trackPoints: trackPointsForCesium,
      onControllerCreated: (controller) {
        _cesiumController.setController(controller);
      },
    );

    // Playback is now handled by Cesium's native Animation and Timeline widgets

    // Apply container with height if embedded
    if (widget.config.embedded) {
      return Container(
        height: widget.config.height ?? 500,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: cesiumWidget,
      );
    }

    return cesiumWidget;
  }
}